// What floats in both 3D worlds. No panels, frames or glass:
//   code: the tinted glyphs alone, with a faint glow (light around them, and
//         a very soft shade so they still read in front of a bright sky). A
//         changed line glows pink in the glyphs themselves; the caret blinks.
//   art : the picture with its own background colour keyed out, so only its
//         lines and light are left. A dark picture's light floats and blooms;
//         a white picture leaves its ink drawn on the sky.
// Each world sets the look through pieces.style(...).
import * as THREE from "./vendor/three/build/three.module.js";
import { MAX_ROWS } from "./code.js";

const VERT = /* glsl */`
  #include <fog_pars_vertex>
  varying vec2 vUv;
  void main() {
    vUv = uv;
    vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
    gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
  }`;

// How much of the colour is left after the fog (1 near, 0 far). 1 without fog.
const FOG_KEEP = /* glsl */`
  float fogKeep() {
    #ifdef USE_FOG
      #ifdef FOG_EXP2
        return exp(-fogDensity * fogDensity * vFogDepth * vFogDepth);
      #else
        return 1.0 - smoothstep(fogNear, fogFar, vFogDepth);
      #endif
    #else
      return 1.0;
    #endif
  }`;

function glyphMaterial() {
  return new THREE.ShaderMaterial({
    defines: { MAX_ROWS },
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      map: { value: null },
      uOpacity: { value: 0 },
      uGain: { value: 1 },
      uGlow: { value: 0.5 },        // light around the glyphs
      uShade: { value: 0.25 },      // soft dark behind them
      uAccent: { value: new THREE.Color("#ff5470") },
      uFlash: { value: new Float32Array(MAX_ROWS) },
      uRows: { value: 0 },
      uRowTop: { value: 0 },
      uRowH: { value: 0.05 },
      uFadeTop: { value: 0 },
      uFadeBottom: { value: 0 },
      uCaret: { value: new THREE.Vector4() },
      uCaretOn: { value: 0 },
    }]),
    vertexShader: VERT,
    fragmentShader: /* glsl */`
      #include <fog_pars_fragment>
      uniform sampler2D map;
      uniform float uOpacity, uGain, uGlow, uShade, uRowTop, uRowH, uFadeTop, uFadeBottom, uCaretOn;
      uniform vec3 uAccent;
      uniform float uFlash[MAX_ROWS];
      uniform int uRows;
      uniform vec4 uCaret;
      varying vec2 vUv;
      ${FOG_KEEP}
      void main() {
        vec4 t = texture2D(map, vUv);                 // premultiplied glyphs
        vec4 near = textureLod(map, vUv, 3.2);         // the glyphs blurred: their glow
        vec4 far = textureLod(map, vUv, 5.);           // blurred more: the soft shade
        float row = (uRowTop - vUv.y) / uRowH;
        int ri = int(floor(row));
        float f = row >= 0. && ri < uRows ? uFlash[ri] : 0.;
        // A changed line: the glyphs themselves turn pink and glow, then fade back.
        vec3 glyph = mix(t.rgb * uGain, uAccent * t.a * 2.2, f);
        vec3 glow = mix(near.rgb, uAccent * near.a * 1.8, f) * (uGlow + f * 2.2);
        // The error line under the code gets more shade: pink is hard to read on a dusk sky.
        float shade = clamp(far.a * 2.2, 0., 1.) * uShade * (row > float(uRows) ? 2.2 : 1.);
        vec3 col = glyph + glow;                       // the glow only adds light
        float a = t.a + shade * (1. - t.a);
        // The caret.
        vec2 c = (vUv - uCaret.xy) / uCaret.zw;
        if (uCaretOn > 0. && c.x >= 0. && c.x <= 1. && c.y >= 0. && c.y <= 1.) { col = uAccent * 1.6 * uCaretOn + col * (1. - uCaretOn); a = max(a, uCaretOn); }
        // The ends of a long code's window dissolve (the error line below stays).
        float fade = 1.;
        if (uFadeTop > .5) fade *= smoothstep(-.2, 2.2, row);
        if (uFadeBottom > .5 && row < float(uRows)) fade *= smoothstep(-.2, 2.2, float(uRows) - row);
        float k = fade * uOpacity * fogKeep();
        gl_FragColor = vec4(col * k, a * k);
      }`,
    transparent: true, depthWrite: false, premultipliedAlpha: true, fog: true, side: THREE.DoubleSide,
  });
}

// The picture with its background keyed out ("colour to alpha"): for each
// pixel, how far it is from the background colour gives its alpha, and the
// colour it would have had alone. Fine grain (asobi's grain: true) stays
// under a soft threshold and so disappears with the background.
function artMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      map: { value: null },
      uBg: { value: new THREE.Vector3(1, 1, 1) },   // the background, sRGB 0..1
      uCut: { value: 0.02 },
      uSoft: { value: 0.06 },
      uGain: { value: 1 },
      uOcclude: { value: 1 },       // 1: covers what is behind; lower: adds light to it
      uTint: { value: new THREE.Color(1, 1, 1) },
      uEdge: { value: 0.015 },
      uOpacity: { value: 0 },
    }]),
    vertexShader: VERT,
    fragmentShader: /* glsl */`
      #include <fog_pars_fragment>
      uniform sampler2D map;
      uniform vec3 uBg, uTint;
      uniform float uCut, uSoft, uGain, uOcclude, uEdge, uOpacity;
      varying vec2 vUv;
      ${FOG_KEEP}
      vec3 toLinear(vec3 c) { return mix(c / 12.92, pow((c + .055) / 1.055, vec3(2.4)), step(.04045, c)); }
      void main() {
        vec3 c = texture2D(map, vUv).rgb;              // sRGB values, as the browser drew them
        vec3 d = c - uBg;
        vec3 room = mix(uBg, 1. - uBg, step(0., d));   // how far each channel could move that way
        vec3 ac = abs(d) / max(room, vec3(1e-3));
        float a0 = clamp(max(ac.r, max(ac.g, ac.b)), 0., 1.);
        vec3 ink = clamp(uBg + d / max(a0, 1e-3), 0., 1.);
        float a = a0 * smoothstep(uCut, uCut + uSoft, a0);
        vec2 e = smoothstep(vec2(0.), vec2(uEdge), vUv) * smoothstep(vec2(0.), vec2(uEdge), 1. - vUv);
        a *= e.x * e.y * uOpacity;
        float k = fogKeep();
        gl_FragColor = vec4(toLinear(ink) * uTint * uGain * a * k, a * uOcclude * k);
      }`,
    transparent: true, depthWrite: false, premultipliedAlpha: true, fog: true, side: THREE.DoubleSide,
  });
}

export class Pieces {
  constructor() {
    this.root = new THREE.Group();
    this.code = new THREE.Group();
    this.codeMesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), glyphMaterial());
    this.codeMesh.renderOrder = 3;
    this.code.add(this.codeMesh);
    this.art = new THREE.Group();
    this.artMesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), artMaterial());
    this.artMesh.renderOrder = 2;
    this.art.add(this.artMesh);
    this.root.add(this.code, this.art);
    this.codeSize = new THREE.Vector2(1, 1);
    this.artSize = new THREE.Vector2(1, 1);
    this.codeOpacity = 0;   // shown
    this.artOpacity = 0;
    this.codeWanted = 0;    // aimed for
    this.artWanted = 0;
    this.dark = false;
    this.grain = false;
    this.look = {};
  }

  setCodeTexture(texture) { this.codeMesh.material.uniforms.map.value = texture; }
  setArtTexture(texture) { this.artMesh.material.uniforms.map.value = texture; }

  setCodeSize(w, h) {
    this.codeSize.set(w, h);
    this.codeMesh.scale.set(w, h, 1);
  }

  setArtSize(w, h) {
    this.artSize.set(w, h);
    this.artMesh.scale.set(w, h, 1);
  }

  // The picture's background (sRGB, 0..255), whether it is dark, whether it has grain.
  setBackground(rgb, dark, grain) {
    this.artMesh.material.uniforms.uBg.value.set(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
    this.dark = dark;
    this.grain = grain;
    this.applyArt();
  }

  // The world's look for both pieces.
  style(s) {
    this.look = s;
    const cu = this.codeMesh.material.uniforms;
    cu.uGlow.value = s.glow;
    cu.uShade.value = s.shade;
    cu.uGain.value = s.textGain;
    this.applyArt();
  }

  applyArt() {
    const u = this.artMesh.material.uniforms, s = this.look;
    // Grain is a faint speckle all over: a higher threshold keeps it out.
    u.uCut.value = this.grain ? 0.1 : 0.02;
    u.uSoft.value = this.grain ? 0.14 : 0.06;
    if (this.dark) {
      u.uGain.value = s.lightGain ?? 1.3;
      u.uOcclude.value = s.lightOcclude ?? 0.7;
      u.uTint.value.setRGB(1, 1, 1);
    } else {
      u.uGain.value = 1;
      u.uOcclude.value = 1;
      if (s.inkTint) u.uTint.value.copy(s.inkTint);
    }
  }

  // Per frame: fades, and the code's flash and caret.
  update(dt, codeCanvas, now) {
    const a = 1 - Math.exp(-dt / 0.35);
    this.codeOpacity += (this.codeWanted - this.codeOpacity) * a;
    this.artOpacity += (this.artWanted - this.artOpacity) * a;
    const cu = this.codeMesh.material.uniforms;
    cu.uOpacity.value = this.codeOpacity;
    this.code.visible = this.codeOpacity > 0.003;
    if (codeCanvas) {
      codeCanvas.tick(now);
      cu.uFlash.value.set(codeCanvas.flash);
      cu.uRows.value = codeCanvas.rows;
      cu.uRowTop.value = codeCanvas.rowTop;
      cu.uRowH.value = codeCanvas.rowH;
      cu.uFadeTop.value = codeCanvas.fadeTop;
      cu.uFadeBottom.value = codeCanvas.fadeBottom;
      cu.uCaret.value.fromArray(codeCanvas.caret);
      // Solid while typing, then a 1 s blink (on half, off half), like the site's caret.
      const since = now - (codeCanvas.typedAt ?? -10);
      cu.uCaretOn.value = since < 0.6 ? 1 : (Math.floor((since - 0.6) * 2) % 2 === 0 ? 0 : 1);
    }
    this.artMesh.material.uniforms.uOpacity.value = this.artOpacity;
    this.art.visible = this.artOpacity > 0.003;
  }
}

// The colour a light comes in: the picture's average colour (the texture's
// smallest mipmap), brought up to full strength, or a set colour.
const ART_LIGHT = /* glsl */`
  uniform sampler2D uArt;
  uniform float uUseArt;
  uniform vec3 uColor;
  vec3 lightColor() {
    if (uUseArt < .5) return uColor;
    vec3 a = textureLod(uArt, vec2(.5), 14.).rgb;
    return mix(vec3(.5), a / max(max(a.r, a.g), max(a.b, 1e-3)), .85);
  }`;

// A soft light lying on the floor (added). From the LT deck.
export function makePool({ color = "#ffffff", width = 4, depth = 3, intensity = 0.25 } = {}) {
  const m = new THREE.Mesh(
    new THREE.PlaneGeometry(width, depth),
    new THREE.ShaderMaterial({
      uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
        uColor: { value: new THREE.Color(color) }, uIntensity: { value: intensity }, uArt: { value: null }, uUseArt: { value: 0 },
      }]),
      vertexShader: VERT,
      fragmentShader: /* glsl */`
        #include <fog_pars_fragment>
        uniform float uIntensity;
        varying vec2 vUv;
        ${FOG_KEEP}
        ${ART_LIGHT}
        void main() {
          vec2 p = vUv * 2. - 1.;
          float a = exp(-dot(p, p) * 3.2) * uIntensity;
          gl_FragColor = vec4(lightColor() * a * fogKeep(), 1.);
        }`,
      fog: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    }),
  );
  m.rotation.x = -Math.PI / 2;
  m.position.y = 0.004;
  m.renderOrder = 1;
  return m;
}

// Fog lit from inside: a soft glow that always faces the camera. From the LT deck.
export function makeGlow({ color = "#ffffff", radius = 4, intensity = 0.06, squash = 0.75 } = {}) {
  const m = new THREE.Mesh(
    new THREE.PlaneGeometry(2, 2),
    new THREE.ShaderMaterial({
      uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
        uColor: { value: new THREE.Color(color) }, uIntensity: { value: intensity }, uRadius: { value: radius }, uSquash: { value: squash },
        uArt: { value: null }, uUseArt: { value: 0 },
      }]),
      vertexShader: /* glsl */`
        #include <fog_pars_vertex>
        uniform float uRadius, uSquash;
        varying vec2 vUv;
        void main() {
          vUv = uv;
          vec4 mvPosition = modelViewMatrix * vec4(0., 0., 0., 1.);
          mvPosition.xy += position.xy * vec2(uRadius, uRadius * uSquash);
          gl_Position = projectionMatrix * mvPosition;
          #include <fog_vertex>
        }`,
      fragmentShader: /* glsl */`
        #include <fog_pars_fragment>
        uniform float uIntensity;
        varying vec2 vUv;
        ${FOG_KEEP}
        ${ART_LIGHT}
        void main() {
          vec2 p = vUv * 2. - 1.;
          float r2 = dot(p, p);
          float a = (exp(-r2 * 3.2) * .75 + exp(-r2 * 12.) * .35) * uIntensity * (1. - smoothstep(.6, 1., sqrt(r2)));
          gl_FragColor = vec4(lightColor() * a * mix(1., fogKeep(), .8), 1.);
        }`,
      // Light in the fog is in the air, in front of the floor too: no depth test.
      fog: true, transparent: true, depthWrite: false, depthTest: false, blending: THREE.AdditiveBlending,
    }),
  );
  m.frustumCulled = false;
  m.renderOrder = 0;
  return m;
}
