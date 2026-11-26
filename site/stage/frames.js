// The art in 3D, played by the stage's own clock: every frame of the Reel is
// turned into a texture AHEAD of the moment it is shown, and kept.
//
// Why: drawing an SVG frame takes from a few ms to tens of ms. Drawing each
// one when it is due (or when a picture arrives) makes the art change at an
// uneven rhythm, which reads as stutter. Here a frame is drawn well before
// its turn; on its turn it is only a texture switch, so the art changes
// exactly every 1/fps, in order. If a frame is not ready in time (a very
// heavy picture), the art waits on the frame before it (it never skips ahead
// or goes out of order), and the next frames are drawn smaller.
//
// Memory: textures live on the GPU (the bitmap is closed once uploaded). A
// frame costs w * h * 4 bytes (no mipmaps: a frame is drawn at about the size
// it is shown, and leaving them out saves a quarter of the memory and their
// making). When the whole loop fits in BUDGET it is all kept (after one pass
// nothing is drawn again); otherwise a ring of the frames coming next is kept.
import * as THREE from "./vendor/three/build/three.module.js";
import { stripGrain, restFrame, frameSvg } from "./svgframe.js";

export const BUDGET = 256 * 1024 * 1024;
const MAX_SIDE = 1600;     // the longest side drawn, in pixels
const MIN_SIDE = 384;
const IN_FLIGHT = 2;       // frames being drawn at once

export class FrameCache {
  constructor(renderer, anisotropy) {
    this.renderer = renderer;
    this.anisotropy = anisotropy;
    this.reel = null;
    this.n = 0;                // frames in the Reel
    this.grain = 0;
    this.withBackground = true;
    this.side = 1024;          // the long side wanted (from the art's size on screen)
    this.scale = 1;            // below 1 while drawing cannot keep up
    this.textures = new Map(); // frame index -> { texture, w, h, bytes }
    this.busy = new Set();     // frame indices being drawn
    this.gen = 0;              // bumps when what is drawn changes (another Reel, the background)
    this.time = 0;             // the Reel's clock (s)
    this.shown = -1;           // the frame index on show
    this.waiting = -1;         // the frame index the clock waits for
    this.showing = null;       // its texture (kept on screen across a change of Reel)
    this.stats = { drawn: 0, drawMs: 0, drawMax: 0, held: 0, ring: 0, whole: false, side: 0 };
  }

  // A checked Reel (AsobiSafeReel) to play. Its clock starts at 0. Each
  // frame's body (parts at rest, grain out) is made when it is first drawn.
  setReel(reel) {
    this.reel = reel;
    this.n = reel.frames.length;
    this.grain = stripGrain(reel.frames[0]).grain;
    this.restart();
    this.time = 0;
  }

  // A frame's body, made when it is drawn and not kept (a big Reel's frames
  // are tens of MB; a second copy would only be more to collect later).
  body(i) {
    return stripGrain(restFrame(this.reel.frames[i], this.reel.parts)).markup;
  }

  // With the picture's own background (true), or without it (the B key).
  setBackground(on) {
    if (on === this.withBackground) return;
    this.withBackground = on;
    if (this.reel) this.restart();
  }

  // The art's longer side on screen, in device pixels.
  aim(px) { this.side = Math.max(MIN_SIDE, Math.min(MAX_SIDE, Math.round(px))); }

  // Stop playing. The texture on show is left to the stage, which lets it go
  // once something else is on the art.
  clear() {
    this.reel = null;
    this.n = 0;
    this.restart();
    this.showing = null;
  }

  // Forget every texture (the one on show stays until a new one is ready).
  restart() {
    this.gen++;
    for (const [i, t] of this.textures) if (t.texture !== this.showing) t.texture.dispose();
    this.textures.clear();
    this.busy.clear();
    this.shown = -1;
    this.waiting = -1;
  }

  // The size to draw at. If the whole loop would fit the budget at no less
  // than 70% of the size wanted, it is drawn that much smaller and kept
  // whole: then after one pass nothing is drawn again. (Drawing on and on
  // makes thousands of SVG documents a minute, and their garbage collection
  // stops the page for a few hundred ms now and then.)
  size() {
    const v = this.reel.view, a = v[2] / v[3];
    let long = Math.max(MIN_SIDE, this.side * this.scale);
    const dims = (l) => (a >= 1 ? [Math.round(l), Math.max(1, Math.round(l / a))] : [Math.max(1, Math.round(l * a)), Math.round(l)]);
    const [w, h] = dims(long);
    const whole = this.n * w * h * 4;
    if (whole > BUDGET) {
      const k = Math.sqrt(BUDGET / whole) * 0.99;
      if (k >= 0.7) long = Math.max(MIN_SIDE * 0.7, long * k);
    }
    return dims(long);
  }

  // How many frames to keep: the whole loop when it fits the budget.
  ring() {
    const [w, h] = this.size();
    const n = this.n;
    const fit = Math.floor(BUDGET / (w * h * 4));
    return Math.max(2, Math.min(n, fit));
  }

  // Per animation frame: advance the clock by dt (s) and answer the texture
  // to show (or null before the first is ready).
  tick(dt) {
    const r = this.reel;
    if (!r) return this.showing;
    const n = this.n, fps = r.fps;
    const want = this.time + dt;
    const cur = Math.floor(this.time * fps), next = Math.floor(want * fps);
    if (next === cur && this.shown === cur % n) {
      this.time = want; // the same frame goes on
    } else {
      const idx = next % n;
      const t = this.textures.get(idx);
      if (t) {
        this.time = want;
        this.show(idx, t.texture);
        this.waiting = -1;
      } else if (this.waiting !== idx) {
        // Not drawn yet: the clock waits (the frame on show stays) until it is.
        this.waiting = idx;
        if (this.shown >= 0) this.stats.held++;
      }
    }
    this.produce(Math.floor(this.time * fps) % n);
    return this.showing;
  }

  show(idx, texture) {
    const before = this.showing;
    this.shown = idx;
    this.showing = texture;
    // A texture kept from the Reel before (no longer in the map) goes once replaced.
    if (before && before !== texture && !this.has(before)) before.dispose();
    this.dropOld();
  }

  has(texture) {
    for (const t of this.textures.values()) if (t.texture === texture) return true;
    return false;
  }

  // Draw the frames coming next (and keep at most IN_FLIGHT going).
  produce(from) {
    const n = this.n, ring = this.ring();
    this.stats.ring = ring;
    this.stats.whole = ring === n;
    const [w, h] = this.size();
    this.stats.side = Math.max(w, h);
    for (let k = 0; k < ring && this.busy.size < IN_FLIGHT; k++) {
      const i = (from + k) % n;
      if (this.busy.has(i)) continue;
      const have = this.textures.get(i);
      // Drawn, and at about the size wanted now: nothing to do.
      if (have && have.gen === this.gen && Math.abs(have.w / w - 1) < 0.2) continue;
      this.draw(i, w, h);
    }
  }

  // Textures outside the ring (only when the whole loop does not fit) go.
  dropOld() {
    const n = this.n, ring = this.ring();
    if (ring >= n) return;
    for (const [i, t] of this.textures) {
      const ahead = (i - this.shown + n) % n;
      if (ahead >= ring && t.texture !== this.showing) { t.texture.dispose(); this.textures.delete(i); }
    }
  }

  async draw(i, w, h) {
    const gen = this.gen;
    this.busy.add(i);
    const t0 = performance.now();
    const svg = frameSvg(this.body(i), this.reel.view, this.reel.background, this.withBackground, w, h);
    const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
    let bitmap = null;
    try {
      const img = new Image();
      img.decoding = "async";
      img.src = url;
      await img.decode();
      if (gen !== this.gen) return;
      // Upside down, as WebGL wants it; premultiplied, so the mipmaps blend edges right.
      bitmap = await createImageBitmap(img, { imageOrientation: "flipY", premultiplyAlpha: "premultiply" });
    } catch {
      return;
    } finally {
      URL.revokeObjectURL(url);
      if (gen === this.gen) this.busy.delete(i);
    }
    if (gen !== this.gen) { bitmap.close(); return; }
    const texture = new THREE.Texture(bitmap);
    texture.colorSpace = THREE.NoColorSpace; // sRGB values, decoded in the shader (premultiplied)
    texture.flipY = false;
    texture.premultiplyAlpha = false;
    texture.generateMipmaps = false;
    texture.minFilter = THREE.LinearFilter;
    texture.needsUpdate = true;
    this.renderer.initTexture(texture); // to the GPU now, between frames
    bitmap.close();
    const old = this.textures.get(i);
    if (old && old.texture !== this.showing) old.texture.dispose();
    this.textures.set(i, { texture, w, h, gen, bytes: w * h * 4 });
    const ms = performance.now() - t0;
    const s = this.stats;
    s.drawn++; s.drawMs += ms; s.drawMax = Math.max(s.drawMax, ms);
    // Falling behind (the clock had to wait): draw smaller from now on.
    if (s.held > (this.heldSeen || 0)) {
      this.heldSeen = s.held;
      this.scale = Math.max(0.5, this.scale * 0.85);
    }
  }
}
