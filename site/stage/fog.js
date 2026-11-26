// The fog stage: the dark world of the asobi LT deck (docs/lt-3d/deck/world.js).
// Fog, a black wet floor whose reflection smears downward, a faint glow and
// ridge on the horizon, dust drifting in the air. The light comes from the
// pictures; the world itself stays dark and quiet.
import * as THREE from "./vendor/three/build/three.module.js";
import { Reflector } from "./vendor/three/addons/objects/Reflector.js";
import { makePool, makeGlow } from "./pieces.js";

const FOG_COLOR = "#111118";
const FOG_DENSITY = 0.042;

// The floor: the Reflector's image, smeared downward, with patchy wetness.
const FloorShader = {
  name: "AsobiFogFloor",
  uniforms: {
    color: { value: null },
    tDiffuse: { value: null },
    textureMatrix: { value: null },
    uFogColor: { value: new THREE.Color(FOG_COLOR) },
    uFogDensity: { value: FOG_DENSITY },
    uCam: { value: new THREE.Vector3() },
    uStrength: { value: 0.55 },
    uSmear: { value: 0.055 },
    uTexel: { value: new THREE.Vector2(1 / 512, 1 / 512) },
    uNoise: { value: null },
  },
  vertexShader: /* glsl */`
    uniform mat4 textureMatrix;
    varying vec4 vUv;
    varying vec3 vWorld;
    void main() {
      vUv = textureMatrix * vec4(position, 1.0);
      vec4 w = modelMatrix * vec4(position, 1.0);
      vWorld = w.xyz;
      gl_Position = projectionMatrix * viewMatrix * w;
    }`,
  fragmentShader: /* glsl */`
    uniform vec3 color;
    uniform sampler2D tDiffuse;
    uniform vec3 uFogColor;
    uniform float uFogDensity;
    uniform vec3 uCam;
    uniform float uStrength;
    uniform float uSmear;
    uniform vec2 uTexel;
    uniform sampler2D uNoise;
    varying vec4 vUv;
    varying vec3 vWorld;
    void main() {
      vec2 uv = vUv.xy / vUv.w;
      float d = length(vWorld - uCam);
      float n = texture2D(uNoise, vWorld.xz * .08).r;
      float fine = texture2D(uNoise, vWorld.xz * .9).g;
      // Wet patches mirror clearly, dry ones blur.
      float wet = smoothstep(.38, .62, n);
      float smear = uSmear * mix(1.6, .55, wet);
      vec2 jit = vec2((fine - .5) * 5.0 * uTexel.x * (1. + d * .05), 0.);
      vec3 acc = vec3(0.); float ws = 0.;
      for (int i = 0; i < 8; i++) {
        float k = float(i) / 7.;
        float w = exp(-k * 2.4);
        acc += texture2D(tDiffuse, uv + jit + vec2((fine - .5) * k * 6. * uTexel.x, -k * smear)).rgb * w;
        ws += w;
      }
      vec3 refl = acc / ws;
      vec3 V = normalize(uCam - vWorld);
      float fres = mix(.22, 1., pow(1. - clamp(V.y, 0., 1.), 5.));
      vec3 base = color * (.65 + .7 * n) + .004 * fine;
      vec3 col = base + refl * uStrength * fres * mix(.55, 1., wet);
      float f = 1. - exp(-uFogDensity * uFogDensity * d * d);
      col = mix(col, uFogColor, f);
      gl_FragColor = vec4(col, 1.);
    }`,
};

// The sky: dark overhead, a faint band of light just above the horizon, a far ridge.
const SkyShader = {
  uniforms: {
    uZenith: { value: new THREE.Color("#060609") },
    uHorizon: { value: new THREE.Color(FOG_COLOR) },
    uGlow: { value: new THREE.Color("#1a1a24") },
    uRidge: { value: new THREE.Color("#0c0c11") },
  },
  vertexShader: /* glsl */`
    varying vec3 vDir;
    void main() {
      vDir = position;
      vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      gl_Position = p.xyww;
    }`,
  fragmentShader: /* glsl */`
    uniform vec3 uZenith, uHorizon, uGlow, uRidge;
    varying vec3 vDir;
    void main() {
      vec3 d = normalize(vDir);
      float h = d.y;
      vec3 col = mix(uHorizon, uZenith, smoothstep(0., .5, h));
      col += uGlow * exp(-max(h, 0.) * 22.) * step(0., h);
      float a = atan(d.z, d.x);
      float hill = (.5 + .5 * sin(a * 3. + 1.3)) * (.5 + .5 * sin(a * 5. + .4)) + .35 * (.5 + .5 * sin(a * 11. + 2.1));
      float r = .01 + .022 * hill + .003 * sin(a * 37. + 1.);
      float ridge = smoothstep(r + .0015, r - .0015, h) * step(0., h);
      col = mix(col, uRidge, ridge * .9);
      if (h < 0.) col = uHorizon;
      gl_FragColor = vec4(col, 1.);
    }`,
};

// Dust: points in a box around the camera, wrapping from side to side.
const DustShader = {
  uniforms: {
    uTime: { value: 0 },
    uCam: { value: new THREE.Vector3() },
    uBox: { value: new THREE.Vector3(24, 9, 24) },
    uSize: { value: 26 },
    uFogDensity: { value: FOG_DENSITY },
    uScale: { value: 1 },
  },
  vertexShader: /* glsl */`
    uniform float uTime, uSize, uFogDensity, uScale;
    uniform vec3 uCam, uBox;
    attribute float aSeed;
    varying float vA;
    void main() {
      vec3 drift = vec3(.011, .006, -.008) * (0.5 + aSeed) + vec3(0., -.003, 0.);
      vec3 p = fract(position + drift * uTime + vec3(sin(uTime * .21 + aSeed * 40.) * .004, 0., 0.));
      vec3 world = uCam + (p - .5) * uBox;
      world.y = .1 + p.y * uBox.y;
      vec3 q = abs(p - .5) * 2.;
      float edge = (1. - smoothstep(.75, 1., q.x)) * (1. - smoothstep(.75, 1., q.y)) * (1. - smoothstep(.75, 1., q.z));
      vec4 mv = viewMatrix * vec4(world, 1.);
      float depth = -mv.z;
      float fog = exp(-uFogDensity * uFogDensity * depth * depth);
      vA = edge * fog * (.25 + .75 * aSeed) * smoothstep(.4, 2.0, depth);
      gl_PointSize = uSize * uScale * (.35 + aSeed) / max(depth, .1);
      gl_Position = projectionMatrix * mv;
    }`,
  fragmentShader: /* glsl */`
    varying float vA;
    void main() {
      vec2 c = gl_PointCoord - .5;
      float a = smoothstep(.5, .0, length(c)) * vA;
      gl_FragColor = vec4(vec3(1., .96, .9) * a * .55, 1.);
    }`,
};

export class Fog {
  constructor() {
    this.name = "fog";
    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.FogExp2(new THREE.Color(FOG_COLOR), FOG_DENSITY);
    this.camera = new THREE.PerspectiveCamera(32, 16 / 9, 0.05, 1500);
    this.time = 0;

    this.sky = new THREE.Mesh(
      new THREE.SphereGeometry(700, 64, 32),
      new THREE.ShaderMaterial({ ...SkyShader, uniforms: THREE.UniformsUtils.clone(SkyShader.uniforms), side: THREE.BackSide, depthWrite: false, fog: false }),
    );
    this.sky.renderOrder = -10;
    this.sky.frustumCulled = false;
    this.scene.add(this.sky);

    this.floor = new Reflector(new THREE.PlaneGeometry(1400, 1400), {
      shader: FloorShader, color: 0x0a0a0e, textureWidth: 512, textureHeight: 512, clipBias: 0.002, multisample: 0,
    });
    this.floor.material.uniforms.uNoise.value = noiseTexture();
    this.floor.rotation.x = -Math.PI / 2;
    this.floor.renderOrder = -5;
    this.scene.add(this.floor);

    const N = 1400;
    const g = new THREE.BufferGeometry();
    const pos = new Float32Array(N * 3), seed = new Float32Array(N);
    for (let i = 0; i < N; i++) { pos[i * 3] = Math.random(); pos[i * 3 + 1] = Math.random(); pos[i * 3 + 2] = Math.random(); seed[i] = Math.random(); }
    g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    g.setAttribute("aSeed", new THREE.BufferAttribute(seed, 1));
    this.dust = new THREE.Points(g, new THREE.ShaderMaterial({
      ...DustShader, uniforms: THREE.UniformsUtils.clone(DustShader.uniforms),
      transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    }));
    this.dust.frustumCulled = false;
    this.scene.add(this.dust);

    // The art lights the fog around it and the floor under it (see light()).
    this.halo = makeGlow({ radius: 4.6, intensity: 0 });
    this.pool = makePool({ width: 6, depth: 3.6, intensity: 0 });
    this.scene.add(this.halo, this.pool);

    this.style = {
      glow: 0.6, shade: 0.12, textGain: 1.0,
      sheetLight: new THREE.Color(0.8, 0.8, 0.79), sheen: new THREE.Color(0.018, 0.018, 0.024),
    };
    this.bloom = { strength: 0.42, radius: 0.42, threshold: 0.88 };
    this.finish = { vignette: 0.75, grain: 0.028 };
    this.exposure = 1.0;
  }

  resize(w, h, ratio) {
    // The reflection is blurred anyway: draw it at half the CSS pixels.
    const rw = Math.round(w * 0.5), rh = Math.round(h * 0.5);
    this.floor.getRenderTarget().setSize(rw, rh);
    this.floor.material.uniforms.uTexel.value.set(1 / rw, 1 / rh);
    this.dust.material.uniforms.uScale.value = ratio * (h / 1080);
  }

  // Where the art floats and how big it is, whether its picture is dark,
  // whether its background is shown, and the picture itself. A dark picture
  // tints the fog and the floor with its own light. Without its background, a
  // light picture leaves dark ink in the air, so the fog behind it is lit
  // instead, a pale glow the ink stands against. A sheet of paper lights the
  // floor a little, like paper does.
  light(artPos, artSize, dark, opacity, texture, withBackground) {
    const ink = !dark && !withBackground;
    this.halo.position.set(artPos.x, artPos.y, artPos.z - (ink ? 1.4 : 0.6));
    const hu = this.halo.material.uniforms, pu = this.pool.material.uniforms;
    hu.uRadius.value = Math.max(artSize.x, artSize.y) * (ink ? 1.55 : 1.5);
    hu.uSquash.value = artSize.y / Math.max(artSize.x, artSize.y) * 0.8;
    this.pool.position.set(artPos.x, 0.004, artPos.z + 1.0);
    // The picture's own average colour when its texture has mipmaps (a mirrored
    // picture); frames drawn ahead have none, then a warm light.
    const average = dark && texture && texture.generateMipmaps !== false;
    for (const u of [hu, pu]) {
      u.uColor.value.set(dark ? "#ffd9a8" : "#e9e4f0");
      u.uArt.value = texture;
      u.uUseArt.value = average ? 1 : 0;
    }
    hu.uIntensity.value = (ink ? 0.26 : dark ? 0.07 : 0.02) * opacity;
    pu.uIntensity.value = (ink ? 0.07 : dark ? 0.08 : 0.05) * opacity;
  }

  update(dt) {
    this.time += dt;
    const cam = this.camera;
    const fu = this.floor.material.uniforms;
    fu.uCam.value.copy(cam.position);
    this.floor.position.set(Math.round(cam.position.x), 0, Math.round(cam.position.z));
    this.sky.position.copy(cam.position);
    const du = this.dust.material.uniforms;
    du.uTime.value = this.time;
    du.uCam.value.copy(cam.position);
  }
}

// The floor's patches (R: large wet/dry patches, G: fine grain). Made once.
function noiseTexture(size = 256) {
  const data = new Uint8Array(size * size * 4);
  const lattice = (g, seed) => { const a = new Float32Array(g * g); let x = seed; for (let i = 0; i < a.length; i++) { x = (x * 1664525 + 1013904223) >>> 0; a[i] = x / 4294967296; } return a; };
  const sample = (lat, g, u, v) => {
    const x = u * g, y = v * g, i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j;
    const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    const at = (a, b) => lat[((b % g) + g) % g * g + ((a % g) + g) % g];
    return (at(i, j) * (1 - sx) + at(i + 1, j) * sx) * (1 - sy) + (at(i, j + 1) * (1 - sx) + at(i + 1, j + 1) * sx) * sy;
  };
  const octaves = [4, 8, 16, 32, 64].map((g, k) => ({ g, lat: lattice(g, 17 + k * 101), amp: 0.5 / 2 ** k }));
  const fine = { g: 64, lat: lattice(64, 9001) };
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const u = x / size, v = y / size;
    let f = 0; for (const o of octaves) f += o.amp * sample(o.lat, o.g, u, v);
    const i = (y * size + x) * 4;
    data[i] = Math.round(Math.min(1, f) * 255);
    data[i + 1] = Math.round(sample(fine.lat, fine.g, u, v) * 255);
    data[i + 2] = 0; data[i + 3] = 255;
  }
  const t = new THREE.DataTexture(data, size, size);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.magFilter = THREE.LinearFilter;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  t.generateMipmaps = true;
  t.needsUpdate = true;
  return t;
}
