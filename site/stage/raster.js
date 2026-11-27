// Turns the newest mirrored picture (svg markup from the playground, for a
// Reel with reacting parts) into pixels for the 3D art: an ImageBitmap (or,
// where that is missing, a canvas). Reels without parts are drawn ahead of
// time instead (frames.js).
//
// The markup is untrusted: it is only ever loaded as an IMAGE (a blob: URL of
// type image/svg+xml), never put into the page. An svg image runs no scripts
// and loads nothing, and a blob: URL made here is same-origin, so its pixels
// are clean for WebGL (no SecurityError on upload).
//
// Why an ImageBitmap: drawing a heavy svg (hundreds of letters with glow) into
// a canvas can stall the page for a quarter of a second when WebGL reads it;
// createImageBitmap does the same work without holding up animation frames.
//
// Latest wins: while one picture is being drawn, a newer one only replaces
// the one waiting. Nothing queues up and nothing waits inside a frame.
// If drawing gets slow (a heavy picture), the next ones are drawn smaller.

import { far } from "./far-raster.js";

const MIN_SIDE = 768;
const MAX_SIDE = 1800;

export class Raster {
  constructor(onDraw) {
    // onDraw(source, info) after each picture: source is an ImageBitmap (the
    // callee owns it and must close it; answer false to hand it back) or the
    // fallback canvas.
    this.onDraw = onDraw;
    this.bitmaps = typeof createImageBitmap === "function";
    this.canvas = null;
    this.next = null;
    this.busy = false;
    this.side = 1024;              // the long side we aim for (set by the stage from the window size)
    this.scale = 1;                // drops below 1 while drawing is slow
    this.cost = 0;                 // smoothed ms of one picture, start to upload
    this.last = 0;                 // ms the latest upload held the page
    this.pressure = 0;             // how often the 3D world misses frames (0..1)
    this.stats = { drawn: 0, skipped: 0, failed: 0, max: 0, sum: 0 };
  }

  // The long side of the drawn picture for the panel's size on screen.
  aim(px) { this.side = Math.max(MIN_SIDE, Math.min(MAX_SIDE, Math.round(px))); }

  // grain: asobi's grain strength, taken out of svg (drawn by the GPU instead).
  // view: the rectangle the svg's viewBox shows (its extent's box: extent.js);
  // extent: handed on with the picture.
  push(svg, view, grain = 0, extent = null) {
    if (this.next) this.stats.skipped++;
    this.next = { svg, view, grain, extent };
    if (!this.busy) this.run();
  }

  // The stage reports how long its upload held the page.
  spent(ms) { this.last = ms; }

  async run() {
    this.busy = true;
    while (this.next) {
      const { svg, view, grain, extent } = this.next;
      this.next = null;
      const aspect = view[2] / view[3];
      const long = Math.max(MIN_SIDE * 0.5, this.side * this.scale);
      const w = Math.max(1, Math.round(aspect >= 1 ? long : long * aspect));
      const h = Math.max(1, Math.round(aspect >= 1 ? long / aspect : long));
      const markup = sized(svg, w, h);
      if (!markup) { this.stats.failed++; continue; }
      const t0 = performance.now();
      const blob = new Blob([markup], { type: "image/svg+xml" });
      // Drawn in the rasteriser's own process (far-raster.js: every picture is
      // a document of its own, and their garbage collection stays there).
      let source = await far.bitmap(blob, true);
      if (source && this.next) { source.close(); this.stats.skipped++; continue; } // a newer picture came: skip to it
      if (!source) {
        const url = URL.createObjectURL(blob);
        const img = new Image();
        img.decoding = "async";
        img.src = url;
        try {
          await img.decode();
          // A newer picture came while this one loaded: skip straight to it.
          if (this.next) { this.stats.skipped++; continue; }
          source = await this.draw(img, w, h);
        } catch {
          this.stats.failed++;
          continue;
        } finally {
          URL.revokeObjectURL(url);
          img.src = ""; // its document goes now, not when the element is collected
        }
      }
      this.last = 0;
      const kept = this.onDraw(source, { width: w, height: h, aspect, grain, extent });
      if (kept === false && source.close) source.close();
      const ms = performance.now() - t0;
      const s = this.stats;
      s.drawn++; s.sum += ms; s.max = Math.max(s.max, ms);
      this.adapt(ms);
      // A slow upload held the page: rest twice as long, so the 3D world keeps
      // most of the frames and the picture updates a little less often.
      const rest = Math.min(300, this.last * 2);
      if (rest > 8) await sleep(rest);
      if (this.next) await frame();
    }
    this.busy = false;
  }

  // The pixels of the decoded image at w x h: an ImageBitmap (upside down,
  // as WebGL wants it), or the fallback canvas.
  async draw(img, w, h) {
    if (this.bitmaps) {
      try {
        return await createImageBitmap(img, { imageOrientation: "flipY", premultiplyAlpha: "premultiply" });
      } catch {
        this.bitmaps = false; // not for svg here: use a canvas from now on
      }
    }
    if (!this.canvas) this.canvas = document.createElement("canvas");
    const c = this.canvas;
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    const g = c.getContext("2d");
    g.clearRect(0, 0, w, h);
    g.drawImage(img, 0, 0, w, h);
    return c;
  }

  // Slow pictures are drawn smaller (down to half), fast ones grow back. So
  // are all pictures while the 3D world is missing frames (pressure, 0..1,
  // set by the stage): drawing svg shares the GPU with it.
  adapt(ms) {
    this.cost = this.cost ? this.cost * 0.8 + ms * 0.2 : ms;
    const strained = this.cost > 25 || this.pressure > 0.25;
    if (strained && this.scale > 0.5) this.scale = Math.max(0.5, this.scale * 0.9);
    else if (!strained && this.cost < 12 && this.scale < 1) this.scale = Math.min(1, this.scale * 1.03);
  }
}

// The markup with width and height set on the root <svg>, so the image is
// drawn at exactly that many pixels. null when it does not start with <svg.
export function sized(svg, w, h) {
  if (typeof svg !== "string") return null;
  const s = svg.trimStart();
  const m = /^<svg\b[^>]*>/.exec(s);
  if (!m) return null;
  const tag = m[0]
    .replace(/\s(?:width|height)\s*=\s*(?:"[^"]*"|'[^']*')/g, "")
    .replace(/^<svg\b/, `<svg width="${w}" height="${h}"`);
  return tag + s.slice(m[0].length);
}

function frame() { return new Promise((r) => requestAnimationFrame(() => r())); }
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
