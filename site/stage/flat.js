// Flat mode: the picture alone, filling the window (contain), over its own
// background colour, like the live view.
//
// Two ways to get the picture:
//   play(reel): the stage's own player (lib/asobi/web/player.js, the same one
//     the playground uses), visible, full window: native SVG, crisp, nothing
//     drawn twice. The Reel was checked with AsobiSafeReel first, exactly as
//     the playground checks it. Pointer events never reach it, so reacting
//     parts rest; the song is left out (sound stays with the playground).
//   show(svg, background, view): a picture mirrored from the playground (a Reel
//     with reacting parts while the playground is visible, so a click there
//     shows here). Two <img> elements take turns: the new picture loads into
//     the hidden one and only becomes visible once decoded, so nothing
//     flickers. The svg is only ever an image (a blob: URL).
//
// Whatever a sketch drew past its paper shows, as in the playground, out to
// the window's edges. The player's svg lets it out by itself; an image never
// paints past its box, so the mirrored picture's root viewBox (only that
// attribute, numbers made here) is widened to the image's whole box, the
// paper landing exactly where the player puts it.
//
// The side view (main.js) uses this same machinery, its art box moved to one
// side; it colours the whole window with the background of the picture on
// show (background, as written; onBackground says when it changes).
//
// asobi's grain comes out of the picture on both ways (svgframe.js) and is
// laid once over the whole window instead (grain.js), so the paper never shows
// an edge where its grain stops.
import { reelWithoutGrain, withoutGrainAtEnd, withViewBox } from "./svgframe.js";
import { WindowGrain } from "./grain.js";

export class Flat {
  constructor(root, onShown) {
    this.root = root;
    this.onShown = onShown || (() => {});
    this.onBackground = () => {};
    this.background = null;  // the background of the picture on show, as written (null: none)
    this.art = root.querySelector(".art");
    this.pics = root.querySelector(".pics");
    this.live = root.querySelector(".live");
    this.grain = new WindowGrain(root.querySelector(".grain"));
    this.strength = 0;       // the grain of the picture on show (0: none)
    this.view = null;        // its view, for the grain's speck size
    this.bare = new WeakMap(); // checked Reel -> { reel: a copy without grain, grain }
    this.stripMs = null;     // how long taking the grain out of the last new Reel took
    this.markup = null;      // the newest mirrored picture, without grain (as it came otherwise)
    this.fitBox = null;      // the viewBox that fills the image's box (null: leave the picture's own)
    addEventListener("resize", () => this.layout());
    this.imgs = [...this.pics.querySelectorAll("img")];
    this.urls = [null, null];
    this.front = 0;
    this.loading = null;     // the running image load, if any
    this.next = null;
    this.player = null;
    this.observer = null;
  }

  play(reel, lang) {
    this.pics.hidden = true;
    this.live.hidden = false;
    if (!this.player) {
      this.player = AsobiPlayer.mount(this.live, { controls: false, keys: false, language: lang });
      // Only to note when the picture changed (asobiStage.artTimes): one note per animation frame.
      let queued = false;
      this.observer = new MutationObserver(() => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => { queued = false; this.onShown(); });
      });
      this.observer.observe(this.live, { subtree: true, childList: true });
    }
    // The player gets a copy without the grain (made once per Reel).
    let bare = this.bare.get(reel);
    if (!bare) {
      const t0 = performance.now();
      // A Reel from the worker comes without grain already (reel-tools.js).
      bare = reel.grainless ? { reel, grain: reel.grain || 0 } : reelWithoutGrain(reel);
      this.stripMs = performance.now() - t0;
      this.bare.set(reel, bare);
    }
    this.player.update(bare.reel);
    // The picture's shape, for the side view, which sizes the art to its
    // paper (stage.css): set once per Reel, never per frame.
    const v = reel.view;
    const shape = Array.isArray(v) && v[2] > 0 && v[3] > 0 ? v[2] / v[3] : 1;
    this.live.style.setProperty("--shape", String(shape));
    this.strength = bare.grain;
    this.view = v;
    this.setBackground(reel.background);
    this.placeGrain();
  }

  // After the art's boxes changed (a resize, flat <-> side): the grain's
  // speck size, and the mirrored picture's widened viewBox (redrawn if it changed).
  layout() {
    this.placeGrain();
    const box = this.pics.hidden ? null : this.mirrorView();
    if (box === this.fitBox) return;
    this.fitBox = box;
    if (this.markup && !this.pics.hidden && !this.root.hidden) { this.next = this.markup; this.kick(); }
  }

  // The rectangle, in the picture's user units, that the image's box (.pics)
  // covers when the paper sits where the player puts it. The player's svg
  // fills the art box (flat) or is the paper's shape in whole pixels, centred
  // in it (side: the same sums as stage.css); the paper is contained in the
  // svg. Both boxes move together (the glide), so only where one is in the
  // other counts. Answers a viewBox, or null.
  mirrorView() {
    const v = this.view;
    if (!Array.isArray(v) || !(v[2] > 0) || !(v[3] > 0)) return null;
    const a = this.art.getBoundingClientRect(), p = this.pics.getBoundingClientRect();
    if (!a.width || !a.height || !p.width || !p.height) return null;
    let sw = a.width, sh = a.height, sx = 0, sy = 0;
    if (this.root.classList.contains("side")) {
      const shape = v[2] / v[3];
      sw = Math.round(Math.min(a.width, a.height * shape));
      sh = Math.round(Math.min(a.height, a.width / shape));
      sx = Math.floor((a.width - sw) / 2);
      sy = Math.floor((a.height - sh) / 2);
    }
    const s = Math.min(sw / v[2], sh / v[3]);
    const x = v[0] + (p.left - a.left - sx - (sw - v[2] * s) / 2) / s;
    const y = v[1] + (p.top - a.top - sy - (sh - v[3] * s) / 2) / s;
    const r = (n) => Math.round(n * 1000) / 1000;
    return `${r(x)} ${r(y)} ${r(p.width / s)} ${r(p.height / s)}`;
  }

  // The window's grain for the picture on show, its specks the size they
  // are in the picture: the paper's longer side as shown (contain, in the art box).
  placeGrain() {
    const v = this.view, w = this.art.offsetWidth, h = this.art.offsetHeight;
    const ok = this.strength > 0 && Array.isArray(v) && v[2] > 0 && v[3] > 0 && w > 0 && h > 0;
    this.grain.set(ok ? this.strength : 0, ok ? Math.max(v[2], v[3]) * Math.min(w / v[2], h / v[3]) : 0);
  }

  setBackground(background) {
    const b = typeof background === "string" && background ? background : null;
    if (b === this.background) return;
    this.background = b;
    this.onBackground(b);
  }

  // Leaves the player (flat mode is off, or a mirrored picture takes over).
  stop() {
    if (this.observer) this.observer.disconnect();
    if (this.player) this.player.destroy();
    this.player = this.observer = null;
    this.live.hidden = true;
  }

  // Answers a promise that settles once the newest picture is on show.
  show(svg, background, view) {
    this.stop();
    this.pics.hidden = false;
    // backgroundColor only takes a colour, so an odd value is simply ignored.
    this.pics.style.backgroundColor = background || "#ffffff";
    const bare = withoutGrainAtEnd(svg);
    this.strength = bare.grain;
    this.markup = this.next = bare.markup;
    // The widened viewBox depends on the view only (and on the boxes: layout()).
    if (!this.fitBox || !sameView(view, this.view)) { this.view = view; this.fitBox = this.mirrorView(); }
    this.setBackground(background);
    this.placeGrain();
    return this.kick();
  }

  kick() {
    if (!this.loading) {
      const run = (this.loading = this.load());
      run.finally(() => { if (this.loading === run) this.loading = null; });
    }
    return this.loading;
  }

  async load() {
    while (this.next) {
      const svg = this.fitBox ? withViewBox(this.next, this.fitBox) : this.next;
      this.next = null;
      const back = 1 - this.front;
      const img = this.imgs[back];
      const url = URL.createObjectURL(new Blob([svg], { type: "image/svg+xml" }));
      img.src = url;
      try {
        await img.decode();
      } catch {
        URL.revokeObjectURL(url);
        continue;
      }
      if (this.next) { URL.revokeObjectURL(url); continue; } // a newer one is waiting
      img.classList.add("front");
      this.onShown();
      this.imgs[this.front].classList.remove("front");
      const old = this.urls[this.front];
      this.urls[back] = url;
      this.front = back;
      // The old picture is no longer shown; free it once this frame is painted.
      if (old) requestAnimationFrame(() => URL.revokeObjectURL(old));
    }
  }
}

function sameView(a, b) {
  return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((n, i) => n === b[i]);
}
