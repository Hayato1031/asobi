// Uyuni at dusk: a salt flat under a thin sheet of still water, so the whole
// sky is mirrored at your feet. Deep indigo overhead, violet and pink lower
// down, warm orange where the low sun sits on the horizon, a few thin clouds
// lit from below, the first faint stars, far mountains in the haze.
// The sky is worked out per pixel (no images); the water is three's
// Reflector, roughened (see WaterShader).
import * as THREE from "./vendor/three/build/three.module.js";
import { Reflector } from "./vendor/three/addons/objects/Reflector.js";

// sRGB colour -> linear (the shaders work in linear light).
const lin = (hex) => new THREE.Color(hex);

// Shared by the sky and the water: noise, and the colour of the haze along
// the horizon (warm toward the sun, rose away from it).
const COMMON = /* glsl */`
  uniform vec3 uSunDir;
  uniform vec3 uHazeSun, uHazeAway;
  float hash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
  float hash13(vec3 p3) { p3 = fract(p3 * .1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
  float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3. - 2. * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
  }
  float fbm3(vec2 p) {
    return .57 * vnoise(p) + .29 * vnoise(p * 2.03 + vec2(17.1, 3.7)) + .14 * vnoise(p * 4.1 + vec2(5.3, 9.1));
  }
  float towardSun(vec3 d) {
    vec2 a = normalize(d.xz + vec2(1e-5)), s = normalize(uSunDir.xz);
    return dot(a, s) * .5 + .5;
  }
  vec3 hazeColor(vec3 d) {
    float t = towardSun(d);
    return mix(uHazeAway, uHazeSun, t * t * (3. - 2. * t));
  }`;

const SKY_FRAG = /* glsl */`
  uniform vec3 uZenith, uHigh, uMid, uLow, uLowSun;
  uniform vec3 uSun, uCloudLit, uCloudGold, uCloudShade, uMountFar, uMountNear;
  uniform float uTime, uStars;
  varying vec3 vDir;
  ${COMMON}

  vec3 skyBase(vec3 d, float ts) {
    float h = max(d.y, 0.);
    // Within the 20-odd degrees the camera sees: haze, then rose and coral,
    // violet, indigo, and deep night blue overhead.
    vec3 low = mix(uLow, uLowSun, ts * ts);
    vec3 c = mix(hazeColor(d), low, smoothstep(0., .05, h));
    c = mix(c, uMid, smoothstep(.03, .15, h));
    c = mix(c, uHigh, smoothstep(.1, .27, h));
    c = mix(c, uZenith, smoothstep(.2, .5, h));
    // Away from the sun the low sky is a little dimmer.
    c *= mix(.8, 1., ts);
    return c;
  }

  // A mountain range's height along the horizon: ridged noise, sharp peaks.
  float range(float az, float seed) {
    float s = 0., a = .55, f = 1.;
    for (int i = 0; i < 4; i++) {
      float n = 1. - abs(vnoise(vec2(az * f + seed, seed * 1.7 + float(i) * 5.3)) * 2. - 1.);
      s += a * n * n;
      f *= 2.3; a *= .45;
    }
    return s;
  }

  void main() {
    vec3 d = normalize(vDir);
    float h = d.y;
    // One pixel, in h. Taken here, before any branch: derivatives are only
    // defined where every pixel runs the same code.
    float px = max(fwidth(h), 1e-4);
    float ts = towardSun(d);
    vec3 col = skyBase(d, ts);

    // The first stars, only high up and very faint.
    if (h > .11) {
      vec3 q = d * 380.;
      vec3 id = floor(q);
      float r = hash13(id);
      if (r > .975) {
        vec3 off = vec3(hash13(id + 7.1), hash13(id + 3.3), hash13(id + 9.7)) - .5;
        float dist = length(fract(q) - .5 - off * .6);
        float b = (r - .975) / .025;
        float tw = .7 + .3 * sin(uTime * (1.3 + 2. * b) + r * 90.);
        col += vec3(.85, .88, 1.) * exp(-dist * dist * 90.) * b * b * tw * uStars * smoothstep(.11, .3, h);
      }
    }

    // A few thin clouds lit from below: streaks lying along the horizon at
    // set heights, broken into pieces, wavy, frayed at the edges.
    float az = atan(d.x, -d.z);
    if (h > .02 && h < .3) {
      float dens = 0., under = 0.;
      for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float e = .042 + fi * .043 + fi * fi * .004;          // 2.4 to 15 degrees
        float w = .0035 + fi * .0016;
        // Far from this layer's height nothing of it shows: skip the noise.
        if (abs(h - e) > 5.5 * w) continue;
        float seed = 3.7 + fi * 11.3;
        float x = az + uTime * .0015 * (1. + fi * .3);
        float piece = smoothstep(.5, .72, fbm3(vec2(x * 2.1 + seed, seed)));
        if (piece <= 0.) continue;
        float wob = (fbm3(vec2(x * 4.7 + seed * 2., 3.)) - .5) * w * 3.;
        float thick = w * (.3 + fbm3(vec2(x * 8.3 + seed, 7.)));
        float y = (h - e - wob) / thick;
        float body = exp(-y * y * 1.6) * piece;
        float fray = vnoise(vec2(x * 46. + seed, y * 1.3 + seed)) * .6 + vnoise(vec2(x * 120. + seed, y * 2.1)) * .4;
        float c = body * smoothstep(.3, .75, fray + .35 * body);
        dens += c * (1. - dens);
        under += c * smoothstep(.4, -1.2, y);
      }
      // Low clouds are already in shadow; higher ones still catch the sun.
      float lit = smoothstep(.05, .15, h);
      vec3 litCol = mix(uCloudLit, uCloudGold, pow(ts, 3.)) * (.8 + 1.1 * pow(max(dot(d, uSunDir), 0.), 10.));
      vec3 cc = mix(uCloudShade, litCol, clamp(lit * .7 + under * .5, 0., 1.));
      col = mix(col, cc, clamp(dens, 0., 1.) * .85);
    }

    // The sun: a soft disc with a warm glow, low over the horizon.
    float cs = dot(d, uSunDir);
    float disc = smoothstep(.99993, .99996, cs);
    col += uSun * (disc * 6. + pow(max(cs, 0.), 2400.) * 1.2 + pow(max(cs, 0.), 260.) * .3 + pow(max(cs, 0.), 18.) * .12 * exp(-max(h, 0.) * 8.));

    // Far mountains on the horizon: a long pale range far away, and nearer,
    // darker ranges in places. All low, all softened by the haze.
    vec3 haze = hazeColor(d);
    if (h < .04 && h > -px) {
      float far = .005 + .013 * range(az * 1.6, 3.1);
      float mask = smoothstep(-1.4, -1.0, az) * (1. - smoothstep(-.5, -.18, az)) + smoothstep(.12, .5, az) * (1. - smoothstep(1.1, 1.5, az));
      float near = (.003 + .026 * range(az * 2.4, 11.7)) * mask;
      col = mix(col, mix(uMountFar, haze, .45), smoothstep(far + px, far - px, h));
      col = mix(col, mix(uMountNear, haze, .3 * exp(-h * 220.)), smoothstep(near + px, near - px, h));
    }

    // Haze on the horizon, over everything, so sky and water meet softly.
    col += haze * .22 * exp(-abs(h) * 70.);
    if (h < 0.) col = haze * 1.1;
    gl_FragColor = vec4(col, 1.);
  }`;

const SKY_VERT = /* glsl */`
  varying vec3 vDir;
  void main() {
    vDir = position;
    vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    gl_Position = p.xyww;
  }`;

// The water: a thin sheet over salt. It mirrors the sky, but not like glass:
//  - fine ripples, moving slowly, shift the image a little;
//  - the image softens the further the reflected ray travels before it meets
//    something, against how far away the water is: sharp where a thing
//    touches the water, soft higher up (so mirrored code can't be read);
//  - it is darker and greyer than what it mirrors, and less of a mirror
//    where you look down into it (fresnel);
//  - near you, the salt crust shows through: low ridges between polygon
//    cells brighten and break the mirror a little, gone well before the horizon.
const WaterShader = {
  name: "AsobiUyuniWater",
  uniforms: {
    color: { value: null },
    tDiffuse: { value: null },
    textureMatrix: { value: null },
    uNoise: { value: null },
    uTime: { value: 0 },
    uCam: { value: new THREE.Vector3() },
    uSize: { value: new THREE.Vector2(512, 512) },
    uRipple: { value: 0.0032 },
    uBlur: { value: 0.011 },
    uTint: { value: new THREE.Color(0.8, 0.77, 0.83) },
    uSalt: { value: lin("#2e2436") },
    uRidge: { value: lin("#b9a6b8") },
    uHazeDensity: { value: 0.0045 },
    uArtInv: { value: new THREE.Matrix4() },
    uCodeInv: { value: new THREE.Matrix4() },
    uArtOn: { value: 0 },
    uCodeOn: { value: 0 },
    uSunDir: { value: new THREE.Vector3() },
    uHazeSun: { value: new THREE.Color() },
    uHazeAway: { value: new THREE.Color() },
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
    uniform sampler2D tDiffuse, uNoise;
    uniform vec3 color, uCam, uTint, uSalt, uRidge;
    uniform vec2 uSize;
    uniform float uTime, uRipple, uBlur, uHazeDensity, uArtOn, uCodeOn;
    uniform mat4 uArtInv, uCodeInv;
    varying vec4 vUv;
    varying vec3 vWorld;
    ${COMMON}

    // How far the ray p + t r goes before it meets a floating piece (a unit
    // square in its own space), or -1.
    float meet(mat4 inv, vec3 p, vec3 r) {
      vec3 o = (inv * vec4(p, 1.)).xyz;
      vec3 d = (inv * vec4(r, 0.)).xyz;
      if (abs(d.z) < 1e-6) return -1.;
      float t = -o.z / d.z;
      vec2 h = o.xy + d.xy * t;
      return t > 0. && abs(h.x) < .6 && abs(h.y) < .6 ? t : -1.;
    }

    // Salt crust: polygons around points on a staggered lattice (so mostly
    // hexagons with straight sides), each point nudged a little. Cells are
    // one unit apart. x: the distance to the nearest cell wall, y: a number per cell.
    vec2 crustPoint(vec2 c) {
      return vec2(c.x + .5 * mod(c.y, 2.), c.y * .866) + (vec2(hash12(c), hash12(c + 19.7)) - .5) * .34;
    }
    vec2 crust(vec2 p) {
      vec2 n = floor(vec2(p.x, p.y / .866));
      vec2 mr = vec2(9.), mc = n;
      float md = 99.;
      for (int j = -1; j <= 1; j++) for (int i = -2; i <= 2; i++) {
        vec2 c = n + vec2(float(i), float(j));
        vec2 r = crustPoint(c) - p;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mc = c; }
      }
      // The exact distance to the cell's wall (the nearest bisector).
      float edge = 9.;
      for (int j = -2; j <= 2; j++) for (int i = -2; i <= 2; i++) {
        vec2 c = mc + vec2(float(i), float(j));
        vec2 r = crustPoint(c) - p;
        vec2 e = r - mr;
        if (dot(e, e) > 1e-6) edge = min(edge, dot(.5 * (mr + r), normalize(e)));
      }
      return vec2(edge, hash12(mc + 7.3));
    }

    void main() {
      vec3 v = vWorld - uCam;
      float dist = length(v);
      vec3 dir = v / dist;
      vec3 r = vec3(dir.x, -dir.y, dir.z);
      float travel = 200.;
      if (uArtOn > .5) { float t = meet(uArtInv, vWorld, r); if (t > 0.) travel = min(travel, t); }
      if (uCodeOn > .5) { float t = meet(uCodeInv, vWorld, r); if (t > 0.) travel = min(travel, t); }

      // The salt crust, only in the near water: cells about 1.3 units across,
      // their low ridges brightening and breaking the mirror a little.
      vec2 w = vWorld.xz;
      float aaw = length(fwidth(w));                 // one pixel, in world units
      float crustOn = 1. - smoothstep(1.8, 4.2, dist);
      vec2 cr = vec2(9., .5);
      if (crustOn > 0.) cr = crust(w / 1.3);
      float wall = cr.x * 1.3;                       // in world units
      float ridge = (1. - smoothstep(.015, .05 + aaw * 1.5, wall)) * crustOn;

      // Fine ripples, slowly moving; rougher on the ridges.
      vec2 n1 = texture2D(uNoise, w * vec2(.23, .41) + uTime * vec2(.006, .004)).rg;
      vec2 n2 = texture2D(uNoise, w * vec2(.9, 1.4) - uTime * vec2(.009, -.007)).rg;
      vec2 rip = ((n1 - .5) * .5 + (n2 - .5)) * uRipple * (1. + ridge * 5.) / (1. + dist * .05);
      vec2 uv = vUv.xy / vUv.w + rip;

      // Softer the further the reflected ray travels, mostly up and down.
      float blur = uBlur * travel / (dist + travel) + ridge * .006;
      float lod = clamp(log2(1. + blur * uSize.y * .3), 0., 6.);
      vec3 refl = vec3(0.);
      float ws = 0.;
      for (int i = 0; i < 5; i++) {
        float k = float(i) / 4. - .5;
        float wt = 1.15 - abs(k) * 1.6;
        refl += textureLod(tDiffuse, uv + vec2(0., k * blur * 2.), lod).rgb * wt;
        ws += wt;
      }
      refl /= ws;

      // Darker and greyer than what it mirrors; less of a mirror looking down.
      float l = dot(refl, vec3(.2126, .7152, .0722));
      refl = mix(vec3(l), refl, .74) * uTint;
      float down = clamp(-dir.y, 0., 1.);
      float fres = mix(.95, .5, smoothstep(.03, .45, down));
      vec3 col = refl * fres + uSalt * (1. - fres);
      // The ridges catch a little light; each cell is a shade different.
      col = mix(col, col * 1.14 + uRidge * .035, ridge * .7);
      col *= 1. - crustOn * (cr.y - .5) * .05;
      // Haze between you and the far water, the same colour as the sky's.
      float f = 1. - exp(-dist * uHazeDensity);
      col = mix(col, hazeColor(dir) * 1.05, f * .55);
      gl_FragColor = vec4(col, 1.);
    }`,
};

export class Uyuni {
  constructor(renderer) {
    this.name = "uyuni";
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(32, 16 / 9, 0.05, 2000);
    this.time = 0;

    // The sun sits low on the horizon. Where along it is art direction, not
    // physics: the stage asks for a place (sunAt), and it glides there.
    this.sunEl = 0.03;
    this.sunAz = 0;
    this.sunGoal = 0;
    this.sunDir = new THREE.Vector3(0, this.sunEl, -1).normalize();
    const common = {
      uSunDir: { value: this.sunDir },
      uHazeSun: { value: lin("#ffb27a") },
      uHazeAway: { value: lin("#c98aa6") },
    };
    this.common = common;

    this.sky = new THREE.Mesh(
      new THREE.SphereGeometry(900, 64, 32),
      new THREE.ShaderMaterial({
        uniforms: {
          ...common,
          uZenith: { value: lin("#0b0e30") },
          uHigh: { value: lin("#2a2563") },
          uMid: { value: lin("#6c3a7c") },
          uLow: { value: lin("#c25a84") },
          uLowSun: { value: lin("#ef7a62") },
          uSun: { value: lin("#ffc890") },
          uCloudLit: { value: lin("#ff7fa0") },
          uCloudGold: { value: lin("#ffb37a") },
          uCloudShade: { value: lin("#43305f") },
          uMountFar: { value: lin("#7d5a8c") },
          uMountNear: { value: lin("#3b2c55") },
          uTime: { value: 0 },
          uStars: { value: 0.9 },
        },
        vertexShader: SKY_VERT,
        fragmentShader: SKY_FRAG,
        side: THREE.BackSide, depthWrite: false,
      }),
    );
    this.sky.renderOrder = -10;
    this.sky.frustumCulled = false;
    this.scene.add(this.sky);

    this.water = new Reflector(new THREE.PlaneGeometry(2400, 2400), {
      shader: WaterShader, color: 0x000000, textureWidth: 512, textureHeight: 512, clipBias: 0.001, multisample: 0,
    });
    // Mipmaps of the reflection: the water's blur reads them.
    const rt = this.water.getRenderTarget();
    rt.texture.generateMipmaps = true;
    rt.texture.minFilter = THREE.LinearMipmapLinearFilter;
    const wu = this.water.material.uniforms;
    wu.uNoise.value = noiseTexture();
    wu.uSunDir = common.uSunDir;
    wu.uHazeSun = common.uHazeSun;
    wu.uHazeAway = common.uHazeAway;
    this.water.rotation.x = -Math.PI / 2;
    this.water.renderOrder = -5;
    this.scene.add(this.water);

    // How the floating pieces look here: glyphs with a soft shade so they
    // read on the bright sky; the sheet a little warmed and dimmed by the
    // dusk (white paper stays under the bloom threshold), with a faint sheen
    // of violet sky on a dark one.
    this.style = {
      glow: 0.36, shade: 0.3, textGain: 0.96,
      sheetLight: new THREE.Color(0.86, 0.8, 0.82), sheen: lin("#2a1e3e"),
    };
    this.bloom = { strength: 0.55, radius: 0.55, threshold: 0.92 };
    this.finish = { vignette: 0.5, grain: 0.02 };
    this.exposure = 1.0;
  }

  resize(w, h) {
    // Drawn smaller than the screen: the water softens it anyway.
    const rw = Math.round(w * 0.6), rh = Math.round(h * 0.6);
    this.water.getRenderTarget().setSize(rw, rh);
    this.water.material.uniforms.uSize.value.set(rw, rh);
  }

  // Where along the horizon the sun sits (radians; 0 is straight ahead).
  sunAt(az) { this.sunGoal = az; }

  update(dt, pieces) {
    this.time += dt;
    this.sunAz += (this.sunGoal - this.sunAz) * (dt > 0 ? 1 - Math.exp(-dt / 0.8) : 1);
    this.sunDir.set(Math.sin(this.sunAz), this.sunEl, -Math.cos(this.sunAz)).normalize();
    const cam = this.camera;
    this.sky.position.copy(cam.position);
    this.sky.material.uniforms.uTime.value = this.time;
    const wu = this.water.material.uniforms;
    wu.uTime.value = this.time;
    wu.uCam.value.copy(cam.position);
    this.water.position.set(Math.round(cam.position.x), 0, Math.round(cam.position.z));
    // Where the pieces float, for the water's blur.
    if (pieces) {
      pieces.root.updateMatrixWorld(true);
      wu.uArtInv.value.copy(pieces.artMesh.matrixWorld).invert();
      wu.uCodeInv.value.copy(pieces.codeMesh.matrixWorld).invert();
      wu.uArtOn.value = pieces.art.visible ? 1 : 0;
      wu.uCodeOn.value = pieces.code.visible ? 1 : 0;
    }
  }
}

// Ripple noise: two smooth random fields (R and G), tiling. Made once.
function noiseTexture(size = 256) {
  const data = new Uint8Array(size * size * 4);
  const lattice = (g, seed) => { const a = new Float32Array(g * g); let x = seed; for (let i = 0; i < a.length; i++) { x = (x * 1664525 + 1013904223) >>> 0; a[i] = x / 4294967296; } return a; };
  const sample = (lat, g, u, v) => {
    const x = u * g, y = v * g, i = Math.floor(x), j = Math.floor(y), fx = x - i, fy = y - j;
    const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
    const at = (a, b) => lat[((b % g) + g) % g * g + ((a % g) + g) % g];
    return (at(i, j) * (1 - sx) + at(i + 1, j) * sx) * (1 - sy) + (at(i, j + 1) * (1 - sx) + at(i + 1, j + 1) * sx) * sy;
  };
  const r = [8, 16, 32].map((g, k) => ({ g, lat: lattice(g, 31 + k * 7), amp: [0.55, 0.3, 0.15][k] }));
  const gg = [8, 16, 32].map((g, k) => ({ g, lat: lattice(g, 911 + k * 13), amp: [0.55, 0.3, 0.15][k] }));
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    const u = x / size, v = y / size;
    let a = 0, b = 0;
    for (const o of r) a += o.amp * sample(o.lat, o.g, u, v);
    for (const o of gg) b += o.amp * sample(o.lat, o.g, u, v);
    const i = (y * size + x) * 4;
    data[i] = Math.round(a * 255);
    data[i + 1] = Math.round(b * 255);
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
