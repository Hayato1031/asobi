// The 3D stage: one renderer, two worlds (Uyuni at dusk, the fog stage) and
// two things floating in them, frameless: the art, big, near and to the
// right, and the code, smaller, further back and to the left, turned a little
// toward you. The camera sits low over the water, looking slightly up, with
// the horizon in the lower third, and drifts slowly so the depth shows.
// Only the world on show is drawn; nothing is drawn while the page is flat.
//
// The art is the picture's EXTENT (extent.js): its paper and whatever the
// sketch drew past it, fitted whole into the art's place, so nothing drawn is
// cut. A Reel's extent is measured once, from a few of its frames, BEFORE its
// frames are drawn (meanwhile the Reel before goes on playing): every frame is
// drawn once, over the right extent. Drawing a Reel's frames twice (once over
// a guessed extent, again over the measured one) doubled the SVG documents
// made, and their garbage collection stopped the page for 0.2-0.5 s. When the
// extent differs from the one on show, the art eases to it over 0.4 s.
//
// The frames are drawn into bitmaps in a process of its own (far-raster.js),
// so the hundreds of svg documents a Reel's frames make, and their garbage
// collection, never stop this one. A new Reel pre-rolls in a second frame
// cache while the one on show goes on playing, and takes over once its frame
// for the moment is ready: the art never stops at a switch.
import * as THREE from "./vendor/three/build/three.module.js";
import { EffectComposer } from "./vendor/three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "./vendor/three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "./vendor/three/addons/postprocessing/UnrealBloomPass.js";
import { ShaderPass } from "./vendor/three/addons/postprocessing/ShaderPass.js";
import { Pieces } from "./pieces.js";
import { FrameCache, BUDGET } from "./frames.js";
import { CodeCanvas } from "./code.js";
import { measureExtent, plainExtent } from "./extent.js";
import { far } from "./far-raster.js";
import { Uyuni } from "./uyuni.js";
import { Fog } from "./fog.js";

const WORLDS = { uyuni: Uyuni, fog: Fog };

// The composition, in world units, for a 16:9 window (a narrower window
// moves the camera back). The water is y = 0.
// The camera is low, so a floating thing's mirror image lies just under the
// horizon: the art hangs only a hand above the water, so its image shows.
const CAM = { x: 0.2, y: 0.32, z: 8.6, fov: 40 };  // low, just above the water
const LOOK_Y = 1.38;                                // a little up: the horizon sits in the lower third
const ART = { left: 0.2, z: 0.9, lift: 0.1, h: 3.48, maxW: 4.4 };   // near, right, big
const SOLO = { x: 0.7, z: 1.5, h: 3.3, maxW: 4.6 };                  // the art alone (c): bigger, centre-right
// The code hangs high enough to stay above the bright band of the horizon.
const CODE = { x: -3.75, y: 2.85, z: -4.2, h: 2.7, aspect: 1.7, turn: 0.38 }; // back, left, turned

// The last pass: tone mapping and sRGB (what three's OutputPass does), then
// corners a little darker and a very fine moving grain (film), all in one
// full-screen pass: at 4K every extra pass costs frames.
const FinishShader = {
  defines: { NEUTRAL_TONE_MAPPING: "", SRGB_TRANSFER: "" },
  uniforms: {
    tDiffuse: { value: null },
    toneMappingExposure: { value: 1 },
    uTime: { value: 0 },
    uRes: { value: new THREE.Vector2(1, 1) },
    uVignette: { value: 0.75 },
    uGrain: { value: 0.028 },
  },
  vertexShader: /* glsl */`
    precision highp float;
    uniform mat4 modelViewMatrix;
    uniform mat4 projectionMatrix;
    attribute vec3 position;
    attribute vec2 uv;
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: /* glsl */`
    precision highp float;
    uniform sampler2D tDiffuse;
    uniform float uTime, uVignette, uGrain;
    uniform vec2 uRes;
    #include <tonemapping_pars_fragment>
    #include <colorspace_pars_fragment>
    varying vec2 vUv;
    float h(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      c.rgb = NeutralToneMapping(c.rgb);
      c = sRGBTransferOETF(c);
      vec2 q = (vUv - .5) * vec2(1., .82);
      c.rgb *= mix(1., 1. - dot(q, q) * 1.15, uVignette);
      c.rgb += (h(vUv * uRes + fract(uTime * 7.13) * 431.) - .5) * uGrain;
      gl_FragColor = vec4(c.rgb, 1.);
    }`,
};

const ease = (k) => k * k * (3 - 2 * k);
const EXTENT_EASE = 0.4;  // s: the art growing (or shrinking) to a newly measured extent
const sameBox = (a, b) => !!a && !!b && a.length === b.length && a.every((n, i) => n === b[i]);

// When the art on screen changed (for checking its rhythm): the last 4096 times.
export const artTimes = [];
export function artShown() { artTimes.push(performance.now()); if (artTimes.length > 4096) artTimes.splice(0, 1024); }
const mix = (a, b, k) => a + (b - a) * k;

export class Stage3D {
  constructor(canvas) {
    this.canvas = canvas;
    const renderer = (this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: "high-performance", stencil: false }));
    this.maxRatio = Math.min(window.devicePixelRatio || 1, 2);
    this.ratio = this.maxRatio;
    renderer.setPixelRatio(this.ratio);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.anisotropy = Math.min(16, renderer.capabilities.getMaxAnisotropy());

    // The code: a big canvas (crisp glyphs), mipmapped (the mipmaps make its
    // glow), premultiplied for clean edges.
    this.code = new CodeCanvas(Math.round(1800 * CODE.aspect), 1800);
    this.codeTexture = new THREE.CanvasTexture(this.code.canvas);
    this.codeTexture.colorSpace = THREE.SRGBColorSpace;
    this.codeTexture.premultiplyAlpha = true;
    this.codeTexture.anisotropy = this.anisotropy;
    this.pieces = new Pieces();
    this.pieces.setCodeSize(CODE.h * CODE.aspect, CODE.h);
    this.pieces.setCodeTexture(this.codeTexture);
    this.artTexture = null;  // the picture on show
    this.mirrorTexture = null;
    this.artAspect = 1;
    this.hasCode = false;
    this.hasArt = false;
    this.codeOn = true;      // the `c` key
    this.layoutK = 1;        // 1: code and art, 0: the art alone
    this.dark = false;
    this.withBackground = true; // the `b` key turns it off
    this.source = "none";    // "reel": played here by its own clock; "mirror": pictures from the playground
    this.frames = new FrameCache(renderer, this.anisotropy);
    // A new Reel is drawn in a second cache while the one on show goes on
    // playing; it takes over once its frame for the moment is ready, so the
    // art never stops at a switch (startReel, swapFrames).
    this.nextFrames = new FrameCache(renderer, this.anisotropy);
    this.prerollSince = 0;
    far.start(); // the rasteriser's own process, ready before the first frame is drawn
    // The extent (extent.js) of what is on show, and the box the art stands
    // for now (user units), easing from one extent to the next.
    this.extent = null;
    this.shownBox = null;
    this.boxFrom = null;
    this.boxTo = null;
    this.boxK = 1;
    this.extents = new WeakMap();   // checked Reel -> its measured extent
    this.measuring = new WeakMap();  // checked Reel -> the measuring under way
    this.mirrorReel = null;          // the Reel behind mirrored pictures (it has reacting parts)
    this.onExtent = null;            // called when the mirrored Reel's extent arrives
    this.probing = 0;                // measurings under way
    this.pendingReel = null;         // a Reel being measured before it plays
    this.extentStats = { measured: 0, ms: 0, busyMs: 0, probes: 0, across: 0, spills: false, box: null, frames: 0, slowFrames: 0, worstMs: 0 };
    this.sizeArt();

    // No MSAA: every pass would pay for a resolve. Nothing here has hard edges anyway.
    const rt = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 0 });
    this.composer = new EffectComposer(renderer, rt);
    this.renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
    this.composer.addPass(this.renderPass);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.42, 0.42, 0.8);
    // The bloom is soft anyway: size it by CSS pixels, not device pixels (it
    // works from half that), so a dense screen does not pay four times for it.
    const bloomSize = this.bloom.setSize.bind(this.bloom);
    this.bloom.setSize = (w, h) => bloomSize(w / this.ratio, h / this.ratio);
    this.composer.addPass(this.bloom);
    this.finish = new ShaderPass(new THREE.RawShaderMaterial({ ...FinishShader, uniforms: THREE.UniformsUtils.clone(FinishShader.uniforms) }));
    this.composer.addPass(this.finish);

    this.worlds = {};
    this.world = null;
    this.time = 0;
    this.slow = 0;
    this.slowSeen = 0;
    this.since = 0;
    this.running = false;
    this.last = 0;
    this.still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.stats = { frames: 0, uploads: 0, uploadMs: 0, uploadMax: 0 };
    this.loop = this.loop.bind(this);
    addEventListener("resize", () => this.resize());
  }

  // Shows a world ("uyuni" or "fog"); builds it the first time.
  setWorld(name) {
    if (!WORLDS[name]) return;
    let w = this.worlds[name];
    if (!w) w = this.worlds[name] = new WORLDS[name](this.renderer);
    this.world = w;
    w.scene.add(this.pieces.root);
    this.pieces.style(w.style);
    this.renderPass.scene = w.scene;
    this.renderPass.camera = w.camera;
    this.bloom.strength = w.bloom.strength;
    this.bloom.radius = w.bloom.radius;
    this.bloom.threshold = w.bloom.threshold;
    this.finish.uniforms.uVignette.value = w.finish.vignette;
    this.finish.uniforms.uGrain.value = w.finish.grain;
    this.finish.uniforms.toneMappingExposure.value = w.exposure;
    this.resize();
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.since = this.time;
    this.slow = 0;
    this.canvas.classList.remove("off");
    this.last = performance.now();
    requestAnimationFrame(this.loop);
  }

  stop() {
    this.running = false;
    this.canvas.classList.add("off");
  }

  // The first frame of a world compiles its shaders; do it while the screen is black.
  warm() {
    if (!this.world) return;
    this.layoutK = this.hasCode && this.codeOn ? 1 : 0; // no glide on arrival
    this.layout(0);
    this.world.update(0, this.pieces, this.dark);
    this.light();
    this.renderer.compile(this.world.scene, this.world.camera);
    this.composer.render(0);
  }

  resize() {
    const w = innerWidth, h = innerHeight;
    this.renderer.setPixelRatio(this.ratio);
    this.renderer.setSize(w, h, false);
    this.composer.setPixelRatio(this.ratio);
    this.composer.setSize(w, h);
    this.finish.uniforms.uRes.value.set(w * this.ratio, h * this.ratio);
    for (const world of Object.values(this.worlds)) {
      world.camera.aspect = w / h;
      world.camera.updateProjectionMatrix();
      world.resize(w, h, this.ratio);
    }
  }

  // ---- what to show ---------------------------------------------------------

  // A Reel to play here, by this window's own clock (checked by AsobiSafeReel).
  playReel(reel) {
    this.hasArt = true;
    const known = this.extents.get(reel);
    if (known) { this.pendingReel = null; this.startReel(reel, known); return; }
    // Measured first; what is on show stays (and plays) until then.
    this.pendingReel = reel;
    this.measure(reel).then((e) => {
      if (this.pendingReel !== reel) return;
      if (!e && !this.running) return; // the 3D view was left: measured again when it is back
      this.pendingReel = null;
      this.startReel(reel, e || plainExtent(reel.view));
    });
  }

  // Plays a Reel whose extent is known: its frames are drawn over it. When
  // another Reel is playing, the new one pre-rolls (see nextFrames).
  startReel(reel, extent) {
    const now = this.frames;
    this.useExtent(extent);
    if (this.source === "reel" && now.reel && now.reel !== reel && now.textures.size > 0) {
      const next = this.nextFrames;
      next.setBackground(this.withBackground);
      next.setReel(reel);
      next.setExtent(extent);
      this.prerollSince = performance.now();
      return;
    }
    this.nextFrames.clear();
    this.source = "reel";
    now.setReel(reel);
    now.setExtent(extent);
    this.pieces.setGrain(now.grain, this.artAspect);
  }

  // The pre-rolled Reel takes over; the one before goes (its texture on show
  // stays until replaced).
  swapFrames() {
    const old = this.frames;
    this.frames = this.nextFrames;
    this.nextFrames = old;
    old.clear();
    this.pieces.setGrain(this.frames.grain, this.artAspect);
  }

  // Measures a Reel's extent (once; in idle time, between frames). Gives up
  // when the 3D view is left or another Reel came (then it is measured again
  // when it is played again). Answers the extent, or null.
  measure(reel) {
    if (this.extents.has(reel)) return Promise.resolve(this.extents.get(reel));
    let run = this.measuring.get(reel);
    if (run) return run;
    const stats = {};
    this.probing++;
    run = measureExtent(reel, () => this.running && (this.pendingReel === reel || this.frames.reel === reel || this.nextFrames.reel === reel || this.mirrorReel === reel), stats)
      .catch(() => null)
      .then((e) => {
        this.probing--;
        this.measuring.delete(reel);
        if (!e) return null;
        this.extents.set(reel, e);
        const s = this.extentStats;
        s.measured++; s.ms = stats.ms; s.busyMs = stats.busyMs; s.probes = stats.probes; s.across = stats.across;
        s.spills = e.spills; s.box = e.box;
        return e;
      });
    this.measuring.set(reel, run);
    return run;
  }

  // The Reel behind the mirrored pictures (a Reel with reacting parts: the
  // stage has it too): its extent widens the pictures once measured.
  watchMirrorReel(reel) {
    if (this.mirrorReel === reel) return;
    this.mirrorReel = reel;
    if (this.extents.has(reel)) return;
    this.measure(reel).then((e) => { if (e && this.mirrorReel === reel && this.onExtent) this.onExtent(); });
  }

  // The extent for a mirrored picture of this paper (the paper alone until measured).
  mirrorExtent(view) {
    const e = this.mirrorReel && this.extents.get(this.mirrorReel);
    return e && sameBox(e.paper, view) ? e : plainExtent(view);
  }

  // The art stands for this extent from now on: eased to it when the paper
  // is the same (a newly measured extent), at once for another paper.
  useExtent(e) {
    const same = this.extent && sameBox(this.extent.paper, e.paper);
    this.extent = e;
    if (!this.shownBox || !same) {
      this.shownBox = e.box.slice();
      this.boxTo = e.box.slice();
      this.boxK = 1;
      this.setAspect(e.box[2] / e.box[3]);
      return;
    }
    if (sameBox(e.box, this.boxTo)) return;
    this.boxFrom = this.shownBox.slice();
    this.boxTo = e.box.slice();
    this.boxK = 0;
  }

  // From now on the pictures come from the playground (setPicture).
  mirror() {
    this.pendingReel = null; // a Reel still being measured does not take over now
    if (this.source === "mirror") return;
    this.source = "mirror";
    this.mirrorReady = false; // what is on the art stays until the playground's next picture is drawn
    this.frames.clear();
    this.nextFrames.clear();
  }

  // A picture from the playground, drawn by Raster: an ImageBitmap (this
  // takes it over and closes it once replaced) or a canvas. Answers the ms
  // the upload took.
  setPicture(source, info) {
    let t = this.mirrorTexture;
    const bitmap = typeof ImageBitmap !== "undefined" && source instanceof ImageBitmap;
    if (!t || t.userData.w !== source.width || t.userData.h !== source.height || t.userData.bitmap !== bitmap) {
      // A new size needs a new texture (GPU storage is made once per texture).
      if (t) { t.dispose(); if (t.userData.bitmap) t.image.close(); }
      t = this.mirrorTexture = new THREE.Texture(source);
      t.colorSpace = THREE.NoColorSpace; // premultiplied sRGB, decoded in the shader
      t.anisotropy = Math.min(4, this.anisotropy);
      t.flipY = !bitmap;          // a bitmap comes upside down already (WebGL ignores flipY for it)
      t.premultiplyAlpha = !bitmap; // a canvas is premultiplied too (a bitmap was asked to be)
      t.userData = { w: source.width, h: source.height, bitmap };
    } else {
      const old = t.image;
      t.image = source;
      // The GPU keeps its own copy: the old bitmap can go now.
      if (bitmap && old && old !== source) old.close();
    }
    t.needsUpdate = true;
    const ext = info.extent || plainExtent([0, 0, info.aspect, 1]);
    t.userData.box = ext.box;
    t.userData.paper = ext.paper;
    t.userData.bands = ext.bands;
    this.mirrorReady = true;
    this.useExtent(ext);
    this.pieces.setGrain(info.grain, this.artAspect);
    this.hasArt = true;
    if (!this.running) return 0;
    // Upload now, between frames, and say how long it took.
    const t0 = performance.now();
    this.renderer.initTexture(t);
    const ms = performance.now() - t0;
    const s = this.stats;
    s.uploads++; s.uploadMs += ms; s.uploadMax = Math.max(s.uploadMax, ms);
    return ms;
  }

  setAspect(a) {
    if (a === this.artAspect) return;
    this.artAspect = a;
    this.sizeArt();
  }

  // Whether the picture's background is dark (for the fog's light).
  setDark(dark) { this.dark = dark; }

  // The picture with its background (true) or without (the B key).
  setBackgroundOn(on) {
    this.withBackground = on;
    this.frames.setBackground(on);
    this.nextFrames.setBackground(on);
  }

  setCode(code, fresh) {
    this.code.setCode(code, this.time, fresh);
    this.hasCode = true;
  }

  setError(error) { this.code.setError(error); }
  setWords(words) { this.code.setWords(words); }
  showCode(on) { this.codeOn = on; }

  // The art's size for its picture's shape: wide pictures get wider, not taller.
  sizeArt() {
    const a = this.artAspect;
    const fit = (h, maxW) => (h * a > maxW ? [maxW, maxW / a] : [h * a, h]);
    this.artWithCode = fit(ART.h, ART.maxW);
    this.artSolo = fit(SOLO.h, SOLO.maxW);
  }

  // ---- each frame -----------------------------------------------------------

  loop(now) {
    if (!this.running) return;
    requestAnimationFrame(this.loop);
    const gap = now - this.last;
    const dt = Math.min(0.1, Math.max(0, gap / 1000));
    this.last = now;
    // While an extent is measured: how many frames came late (for the stats).
    if (this.probing > 0) {
      const s = this.extentStats;
      s.frames++;
      if (gap > 25) s.slowFrames++;
      s.worstMs = Math.max(s.worstMs, gap);
    }
    this.frame(dt);
    this.watch(dt);
  }

  frame(dt) {
    const w = this.world;
    if (!w) return;
    this.time += dt;
    this.stats.frames++;
    if (this.code.draw()) this.codeTexture.needsUpdate = true;
    const p = this.pieces;
    p.codeWanted = this.hasCode && this.codeOn ? 1 : 0;
    p.artWanted = this.hasArt ? 1 : 0;
    p.update(dt, this.code, this.time);
    // Easing to a newly measured extent: the art's shape follows.
    if (this.boxK < 1) {
      this.boxK = Math.min(1, this.boxK + dt / EXTENT_EASE);
      const k = ease(this.boxK);
      this.shownBox = this.boxTo.map((b, i) => (this.boxK >= 1 ? b : mix(this.boxFrom[i], b, k)));
      this.setAspect(this.shownBox[2] / this.shownBox[3]);
    }
    this.layout(dt);
    // The art: this window's own frame for this moment, or the newest picture from the playground.
    if (this.source === "reel") {
      const aim = this.artPixels();
      this.frames.aim(aim);
      // A new Reel pre-rolling: it takes over once its frame for this moment
      // is drawn (or after 2 s, then it waits for its frames as before).
      const next = this.nextFrames;
      if (next.reel) {
        next.aim(aim);
        if (next.prepare(this.frames.time, dt) || performance.now() - this.prerollSince > 2000) this.swapFrames();
      }
      this.showArt(this.frames.tick(dt));
    } else if (this.source === "mirror" && this.mirrorReady) {
      this.showArt(this.mirrorTexture, this.mirrorTexture && this.mirrorTexture.version);
    }
    w.update(dt, p, this.dark);
    this.light();
    this.finish.uniforms.uTime.value = this.time;
    this.composer.render(dt);
  }

  // Puts a texture on the art; notes the moment the art changed. Each
  // texture is placed by the extent it was drawn with.
  showArt(texture, version) {
    if (!texture) return;
    const d = texture.userData || {};
    if (this.shownBox && d.box) {
      // A texture of another paper (the Reel before, until the new one's first
      // frame is ready) fills the art as it is.
      const here = this.extent && sameBox(d.paper, this.extent.paper) ? this.shownBox : d.box;
      // With its background (B on) the sheet is the whole picture, its edge
      // crisp; without, the outer band fades.
      this.pieces.setArtPlace(here, d.box, d.paper || d.box, this.withBackground ? null : d.bands);
    }
    if (texture !== this.artTexture) {
      this.pieces.setArtTexture(texture);
      // A frame left over from a Reel no longer played goes once replaced.
      const old = this.artTexture;
      if (old && old !== this.mirrorTexture && !this.frames.has(old) && old !== this.frames.showing) old.dispose();
    }
    const key = version === undefined ? texture : version;
    if (texture !== this.artTexture || key !== this.artKey) artShown();
    this.artTexture = texture;
    this.artKey = key;
  }

  // A world that lights things with the art (the fog's glow and pool) gets
  // the current picture. Before every draw: an older texture may be gone.
  light() {
    const w = this.world, p = this.pieces;
    if (w && w.light) w.light(p.art.position, p.artSize, this.dark, p.artOpacity, this.artTexture, this.withBackground);
  }

  // Places the art, the code and the camera. With the code hidden (c) the
  // art moves to the centre-right and grows; the code drifts back and fades.
  layout(dt) {
    const w = this.world, p = this.pieces;
    const goal = this.hasCode && this.codeOn ? 1 : 0;
    this.layoutK += (goal - this.layoutK) * (1 - Math.exp(-dt / 0.6));
    const k = ease(Math.min(1, Math.max(0, this.layoutK)));
    const t = this.still ? 0 : this.time;

    const [bw, bh] = this.artWithCode, [sw, sh] = this.artSolo;
    const aw = mix(sw, bw, k), ah = mix(sh, bh, k);
    p.setArtSize(aw, ah);
    // A wide picture reaches a little further left, so it stays clear of the right edge.
    const left = ART.left - Math.max(0, bw - 3.6) * 0.6;
    const ax = mix(SOLO.x, left + bw / 2, k), az = mix(SOLO.z, ART.z, k);
    p.art.position.set(ax, ART.lift + ah / 2 + Math.sin(t * 0.5) * 0.03, az);
    p.art.rotation.set(0, -0.05 * k + Math.sin(t * 0.21) * 0.01, 0);
    p.code.position.set(CODE.x - (1 - k) * 1.2, CODE.y + Math.sin(t * 0.43 + 1.9) * 0.03, CODE.z - (1 - k) * 2);
    p.code.rotation.set(0, CODE.turn + Math.sin(t * 0.17 + 1.2) * 0.01, 0);

    // The camera: a narrower window moves it back. A slow drift sideways and
    // in and out, aimed at a point that moves less, so near and far slide
    // past each other.
    const cam = w.camera;
    const back = Math.max(1, (16 / 9) / cam.aspect);
    const z = CAM.z * back;
    const drift = this.still ? 0 : 1, T = 2 * Math.PI;
    cam.fov = CAM.fov;
    cam.updateProjectionMatrix();
    cam.position.set(
      CAM.x + Math.sin(t * T / 34) * 0.55 * drift,
      CAM.y + Math.sin(t * T / 23 + 1) * 0.05 * drift,
      z + Math.sin(t * T / 41 + 1) * 0.45 * drift,
    );
    cam.lookAt(CAM.x + Math.sin(t * T / 34 + 0.4) * 0.22 * drift, LOOK_Y, 0);

    // The sun, low on the horizon: between the code and the art, or just
    // left of the art alone, so things are lit from behind but the art never
    // sits on top of it.
    if (w.sunAt) {
      // Seen from where the camera is now: the sun keeps its place in the gap
      // while the camera drifts (it moves a little against the far hills,
      // too slowly to notice; near and far still slide past each other).
      const angle = (x, zz) => Math.atan2(x - cam.position.x, cam.position.z - zz);
      const artLeft = angle(ax - aw / 2, az);
      const cw = p.codeSize.x;
      const codeRight = angle(CODE.x + (cw / 2) * Math.cos(CODE.turn), CODE.z - (cw / 2) * Math.sin(CODE.turn));
      w.sunAt(mix(artLeft - 0.07, mix(codeRight, artLeft, 0.5), k));
    }
  }

  // When frames are slow, draw fewer pixels (a little at a time), like the LT deck.
  watch(dt) {
    // Not in the first seconds: shaders compile and the GPU wakes up then.
    if (dt <= 0 || dt > 0.25 || this.time - this.since < 2.5) return;
    this.slow = this.slow * 0.97 + (dt > 1 / 50 ? 1 : 0) * 0.03;
    this.slowSeen = this.slowSeen * 0.98 + (dt > 1 / 50 ? 1 : 0) * 0.02;
    if (this.slow > 0.3 && this.ratio > 1) {
      this.ratio = Math.max(1, this.ratio - 0.25);
      this.slow = 0;
      this.resize();
      console.info(`asobi stage: frames are slow, drawing at pixel ratio ${this.ratio}`);
    }
  }

  get artTimes() { return artTimes; }

  // How the frames are kept and drawn (for the numbers in asobiStage.stats()).
  frameStats() {
    const f = this.frames, s = f.stats;
    return { source: this.source, side: s.side, ring: s.ring, whole: s.whole, cached: f.textures.size, budgetMB: BUDGET / 1048576,
      drawn: s.drawn, drawAvgMs: s.drawn ? s.drawMs / s.drawn : 0, drawMaxMs: s.drawMax, held: s.held, scale: f.scale,
      extent: { ...this.extentStats, shown: this.shownBox, paper: this.extent && this.extent.paper },
      raster: { far: far.ready, drawn: far.stats.drawn, here: far.stats.fallback, avgMs: far.stats.drawn ? far.stats.ms / far.stats.drawn : 0 } };
  }

  // How often frames are slow lately (0..1): the raster draws smaller then.
  pressure() { return this.slowSeen; }

  // The art's longer side on screen, in device pixels (to size the raster).
  // For the extent being shown (its shape, not the one easing on screen now:
  // frames drawn while the art eases would otherwise be drawn again after).
  artPixels() {
    const w = this.world;
    const tanV = Math.tan(THREE.MathUtils.degToRad(CAM.fov / 2));
    const dist = w ? Math.max(3, w.camera.position.distanceTo(this.pieces.art.position)) : 8;
    const a = this.extent ? this.extent.box[2] / this.extent.box[3] : this.artAspect;
    const tall = (h, maxW) => (h * a > maxW ? maxW / a : h);
    const h = Math.max(tall(ART.h, ART.maxW), tall(SOLO.h, SOLO.maxW));
    const frac = h / (2 * tanV * dist);
    return frac * innerHeight * this.ratio * Math.max(1, a);
  }
}
