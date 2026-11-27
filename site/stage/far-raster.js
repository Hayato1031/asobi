// Rasterising svg frames in another process. An svg drawn as an image is a
// whole document of its own (page, frame, DOM): the 3D frame cache makes one
// per frame (240 for a galaxy), and Chrome tears them down in garbage
// collections that stopped the stage for 0.1-0.4 s now and then, whatever
// the pace of drawing. So the frames are drawn in a sandboxed iframe
// (raster-frame.html: scripts only, an opaque origin), which Chrome runs in a
// process of its own; it hands back ImageBitmaps. The svg goes there as a Blob
// (made by the stage's worker) and only ever becomes an image there.
// bitmap(blob, flip) answers an ImageBitmap, or null when the rasteriser is not
// there (not ready yet, gone, too slow): then the caller draws it here.
const TIMEOUT_MS = 4000;

class FarRaster {
  constructor() {
    this.frame = null;
    this.ready = false;
    this.failed = false;
    this.asks = 0;
    this.waiting = new Map();
    this.stats = { drawn: 0, fallback: 0, ms: 0 };
    this.whenReady = new Promise((r) => { this.isReady = r; });
  }

  start() {
    if (this.frame || this.failed || typeof document === "undefined") return;
    const f = (this.frame = document.createElement("iframe"));
    f.setAttribute("sandbox", "allow-scripts");
    f.setAttribute("aria-hidden", "true");
    f.tabIndex = -1;
    f.style.cssText = "position:fixed;left:-4px;top:-4px;width:1px;height:1px;border:0;opacity:0;pointer-events:none";
    f.src = new URL("./raster-frame.html", import.meta.url).href;
    addEventListener("message", (e) => {
      if (!this.frame || e.source !== this.frame.contentWindow) return;
      const d = e.data || {};
      if (d.ready) { this.ready = true; this.isReady(); return; }
      const w = this.waiting.get(d.id);
      if (!w) { if (d.bitmap) d.bitmap.close(); return; }
      this.waiting.delete(d.id);
      clearTimeout(w.timer);
      w.done(d.bitmap || null);
    });
    document.body.append(f);
  }

  async bitmap(blob, flip) {
    this.start();
    if (!this.ready) await Promise.race([this.whenReady, new Promise((r) => setTimeout(r, 1500))]);
    if (!this.ready || !this.frame || !this.frame.contentWindow) { this.stats.fallback++; return null; }
    const id = ++this.asks, t0 = performance.now();
    return new Promise((done) => {
      const timer = setTimeout(() => { this.waiting.delete(id); this.stats.fallback++; done(null); }, TIMEOUT_MS);
      this.waiting.set(id, { timer, done: (b) => { if (b) { this.stats.drawn++; this.stats.ms += performance.now() - t0; } done(b); } });
      this.frame.contentWindow.postMessage({ id, blob, flip: !!flip }, "*");
    });
  }
}

export const far = new FarRaster();

// An svg Blob drawn on this thread: an ImageBitmap (or null).
export async function drawHere(blob, flip) {
  const url = URL.createObjectURL(blob);
  const img = new Image();
  try {
    img.decoding = "async";
    img.src = url;
    await img.decode();
    return await createImageBitmap(img, { imageOrientation: flip ? "flipY" : "from-image", premultiplyAlpha: "premultiply" });
  } catch {
    return null;
  } finally {
    URL.revokeObjectURL(url);
    img.src = ""; // its document goes now, not when the element is collected
  }
}
