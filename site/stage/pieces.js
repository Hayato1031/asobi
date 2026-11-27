// What floats in both 3D worlds. No panels, frames or glass:
//   code: the tinted glyphs alone, with a faint glow (light around them, and
//         a very soft shade so they still read in front of a bright sky). A
//         changed line glows pink in the glyphs themselves; the caret blinks.
//   art : the picture as a plain sheet, with its own background (white paper,
//         a dark slab), or without it (the B key): only what the sketch drew.
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

// The picture as a plain sheet: exactly as drawn, with its own background
// (white paper, a dark slab), or without it (the B key: only what the sketch
// drew, with its own transparency). The texture holds premultiplied sRGB
// values; asobi's grain is drawn here (see svgframe.js), only where the
// picture is, never on the air around it. Lit a little by the world, and kept
// under the bloom threshold so white paper never blows out.
//
// The sheet is the picture's extent (extent.js): the paper and what was drawn
// past it. uMap takes the sheet's place (vUv) to the texture's (st): a texture
// keeps the extent it was drawn with while a new one eases in, and outside it
// nothing shows. Where the extent reaches past the paper, its outermost band
// fades (uBands: left, right, top, bottom, in the texture's units; 0: none),
// so a spill the measuring missed fades instead of being cut. For a picture
// that stays on its paper, uMap is (0, 0, 1, 1) and uBands 0: as before.
function artMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, {
      map: { value: null },
      uLight: { value: new THREE.Color(0.85, 0.85, 0.85) },
      uSheen: { value: new THREE.Color(0, 0, 0) },
      uGrain: { value: 0 },
      uCells: { value: new THREE.Vector2(540, 540) },
      uMap: { value: new THREE.Vector4(0, 0, 1, 1) },
      uGrainAt: { value: new THREE.Vector2(0, 0) },
      uBands: { value: new THREE.Vector4(0, 0, 0, 0) },
      uOpacity: { value: 0 },
    }]),
    vertexShader: VERT,
    fragmentShader: /* glsl */`
      #include <fog_pars_fragment>
      uniform sampler2D map;
      uniform vec3 uLight, uSheen;
      uniform float uGrain, uOpacity;
      uniform vec2 uCells, uGrainAt;
      uniform vec4 uMap, uBands;
      varying vec2 vUv;
      ${FOG_KEEP}
      vec3 toLinear(vec3 c) { return mix(c / 12.92, pow((c + .055) / 1.055, vec3(2.4)), step(.04045, c)); }
      float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
      float vnoise(vec2 p) {
        vec2 i = floor(p), f = fract(p);
        vec2 u = f * f * (3. - 2. * f);
        return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
      }
      void main() {
        vec2 st = uMap.xy + vUv * uMap.zw;
        vec4 t = texture2D(map, st);
        float a = t.a;
        if (a <= .002) discard;
        vec3 c = t.rgb / a;                                  // as the browser drew it (sRGB)
        // asobi's grain: fractal noise, dark specks where it is high, light where it is low.
        if (uGrain > 0.) {
          vec2 p = st * uCells + uGrainAt;               // held to the paper, whatever extent the texture has
          float n = .66 * vnoise(p) + .34 * vnoise(p * 2.03 + 17.);
          float k = uGrain * 4.;
          c *= 1. - clamp(k * (n - .5), 0., 1.);
          c += (1. - c) * clamp(k * (.5 - n), 0., 1.);
        }
        vec3 col = toLinear(c) * uLight;
        // A faint sheen from the sky above, so a dark sheet still reads as a sheet.
        col += uSheen * smoothstep(.15, 1., vUv.y) * (1. - dot(c, vec3(.3333)));
        // Smooth edges (there is no MSAA); nothing outside the texture's extent.
        vec2 px = fwidth(st) * 1.2;
        vec2 e = smoothstep(vec2(0.), px, st) * smoothstep(vec2(0.), px, 1. - st);
        // The outer band of an extent wider than the paper (y up: top is 1).
        float f = 1.;
        if (uBands.x > 0.) f *= smoothstep(0., uBands.x, st.x);
        if (uBands.y > 0.) f *= smoothstep(0., uBands.y, 1. - st.x);
        if (uBands.z > 0.) f *= smoothstep(0., uBands.z, 1. - st.y);
        if (uBands.w > 0.) f *= smoothstep(0., uBands.w, st.y);
        a *= e.x * e.y * f * uOpacity * fogKeep();
        gl_FragColor = vec4(col * a, a);
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
    this.look = {};
  }

  setCodeTexture(texture) { this.codeMesh.material.uniforms.map.value = texture; }
  setArtTexture(texture) { this.artMesh.material.uniforms.map.value = texture; }

  // Where the texture on show lies in the sheet (shown: the extent the sheet
  // stands for now; drawn: the extent the texture was drawn with; paper: the
  // picture's paper; bands: the fading widths, user units), and the grain's
  // cells (about 540 along the paper's longer side, wherever the sheet ends).
  setArtPlace(shown, drawn, paper, bands) {
    const u = this.artMesh.material.uniforms;
    const [dx, dy, dw, dh] = shown, [bx, by, bw, bh] = drawn;
    if (dx === bx && dy === by && dw === bw && dh === bh) u.uMap.value.set(0, 0, 1, 1);
    else u.uMap.value.set((dx - bx) / bw, 1 - (dy + dh - by) / bh, dw / bw, dh / bh);
    const b = bands || [0, 0, 0, 0];
    u.uBands.value.set(b[0] / bw, b[1] / bw, b[2] / bh, b[3] / bh);
    const long = Math.max(paper[2], paper[3]), k = 540 / long;
    u.uCells.value.set(k * bw, k * bh);
    u.uGrainAt.value.set(k * (bx - paper[0]), k * (paper[1] + paper[3] - by - bh));
  }

  setCodeSize(w, h) {
    this.codeSize.set(w, h);
    this.codeMesh.scale.set(w, h, 1);
  }

  setArtSize(w, h) {
    this.artSize.set(w, h);
    this.artMesh.scale.set(w, h, 1);
  }

  // The grain (0..1, asobi's strength; 0 for none), drawn by the shader, and
  // the picture's shape (so the grain's cells are square).
  setGrain(strength, aspect) {
    const u = this.artMesh.material.uniforms;
    u.uGrain.value = strength || 0;
    // asobi's grain has about 540 cells along the picture's longer side.
    u.uCells.value.set(aspect >= 1 ? 540 : 540 * aspect, aspect >= 1 ? 540 / aspect : 540);
  }

  // The world's look for both pieces.
  style(s) {
    this.look = s;
    const cu = this.codeMesh.material.uniforms;
    cu.uGlow.value = s.glow;
    cu.uShade.value = s.shade;
    cu.uGain.value = s.textGain;
    const u = this.artMesh.material.uniforms;
    if (s.sheetLight) u.uLight.value.copy(s.sheetLight);
    if (s.sheen) u.uSheen.value.copy(s.sheen);
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
