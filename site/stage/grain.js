// asobi's grain over the whole window, for the flat and side views.
//
// In a picture the grain (SVG.grain in lib/asobi/svg.rb) covers the paper
// only, so where the window shows the picture's colour around the paper (side,
// or letterbox bars), the paper's edge showed as a textured rectangle. Here
// the grain is taken out of the picture (svgframe.js) and this layer, above
// the art and below the code, draws it once over the whole window.
//
// It is the same recipe as asobi's (fractal noise, two octaves, seed 7; dark
// specks where the noise is high, light where it is low, at the same
// strength), drawn by the browser's own feTurbulence into a tile ONCE, then
// repeated as a plain image: no filter runs while the picture plays, and the
// layer is never redrawn (it has a compositor layer of its own). The specks
// are the size they are in the picture on screen: asobi asks for 540 cells
// along the view's longer side, so here 540 along the paper's longer side as
// shown (the tile is remade when that changes: another Reel, a resize, flat
// <-> side). The tile is only ever an image (blob: URL); it is built from
// numbers alone, never from the picture's markup.
const TILE = 512;          // CSS px: big enough that the repeat never shows in fine noise
const CELLS = 540;         // asobi: baseFrequency = 0.9 * 600 / the view's longer side

const KEEP = 4;             // tiles kept (flat and side differ in scale: switching back costs nothing)
const SETTLE_MS = 150;      // a new scale while a tile is on show (a resize drag): wait for it to settle

export class WindowGrain {
  constructor(el) {
    this.el = el;
    this.key = "";            // the tile wanted
    this.tiles = new Map();   // key -> { url, size } (most recent last)
    this.timer = 0;
    this.stats = { tiles: 0, lastMs: 0, drawMs: 0, bitmap: false };
  }

  // strength: asobi's (0..1; 0 for none). long: the paper's longer side on screen, CSS px.
  set(strength, long) {
    if (!(strength > 0) || !(long > 0)) {
      this.el.hidden = true;
      return;
    }
    const ratio = window.devicePixelRatio || 1;
    const freq = Number((CELLS / long).toPrecision(3)); // per CSS px; small changes keep the tile
    const key = `${strength}|${freq}|${ratio}`;
    const first = this.el.hidden || !this.key;
    this.el.hidden = false;
    if (key === this.key) return;
    this.key = key;
    clearTimeout(this.timer);
    if (this.tiles.has(key)) { this.apply(key); return; }
    if (first) this.make(strength, freq, ratio, key);
    else this.timer = setTimeout(() => this.make(strength, freq, ratio, key), SETTLE_MS);
  }

  apply(key) {
    const t = this.tiles.get(key);
    this.tiles.delete(key);
    this.tiles.set(key, t); // most recent last
    this.el.style.backgroundImage = `url("${t.url}")`;
    this.el.style.backgroundSize = `${t.size}px ${t.size}px`;
  }

  async make(strength, freq, ratio, key) {
    if (key !== this.key || this.tiles.has(key)) return;
    const t0 = performance.now();
    const px = Math.round(TILE * ratio);
    const k = strength * 4;
    const n = (x) => String(Math.round(x * 1e4) / 1e4);
    // The tile's user units are CSS px, so freq is per CSS px; drawn at the
    // screen's own pixel density (px device pixels across).
    const svg =
      `<svg xmlns="http://www.w3.org/2000/svg" width="${px}" height="${px}" viewBox="0 0 ${TILE} ${TILE}">` +
      `<filter id="g" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">` +
      `<feTurbulence type="fractalNoise" baseFrequency="${n(freq)}" numOctaves="2" seed="7" stitchTiles="stitch" result="n"/>` +
      `<feColorMatrix in="n" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ${n(k)} 0 0 0 -${n(k / 2)}" result="d"/>` +
      `<feColorMatrix in="n" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 -${n(k)} 0 0 0 ${n(k / 2)}" result="l"/>` +
      `<feMerge><feMergeNode in="d"/><feMergeNode in="l"/></feMerge></filter>` +
      `<rect width="${TILE}" height="${TILE}" filter="url(#g)"/></svg>`;
    const source = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
    let url = source, bitmap = false;
    try {
      const img = new Image();
      img.src = source;
      await img.decode();
      // Into a bitmap once, so the filter never runs again (an SVG background
      // could be re-filtered whenever the layer is painted).
      const c = document.createElement("canvas");
      c.width = c.height = px;
      const d0 = performance.now();
      c.getContext("2d").drawImage(img, 0, 0, px, px);
      this.stats.drawMs = performance.now() - d0;
      const blob = await new Promise((done) => c.toBlob(done, "image/png"));
      if (blob) { url = URL.createObjectURL(blob); bitmap = true; URL.revokeObjectURL(source); }
    } catch {
      // Keep the SVG itself as the tile: the same specks, only drawn by the filter.
    }
    this.tiles.set(key, { url, size: px / ratio });
    // Only a few kept; never the one on show.
    for (const [old, t] of this.tiles) {
      if (this.tiles.size <= KEEP) break;
      if (old === this.key) continue;
      this.tiles.delete(old);
      requestAnimationFrame(() => URL.revokeObjectURL(t.url));
    }
    this.stats.tiles++;
    this.stats.lastMs = performance.now() - t0;
    this.stats.bitmap = bitmap;
    if (key === this.key) this.apply(key);
  }
}
