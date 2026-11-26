// Flat mode: the picture alone, filling the window (contain), over its own
// background colour, like the live view.
//
// Two ways to get the picture:
//   play(reel): the stage's own player (lib/asobi/web/player.js, the same one
//     the playground uses), visible, full window: native SVG, crisp, nothing
//     drawn twice. The Reel was checked with AsobiSafeReel first, exactly as
//     the playground checks it. Pointer events never reach it, so reacting
//     parts rest; the song is left out (sound stays with the playground).
//   show(svg, background): a picture mirrored from the playground (a Reel
//     with reacting parts while the playground is visible, so a click there
//     shows here). Two <img> elements take turns: the new picture loads into
//     the hidden one and only becomes visible once decoded, so nothing
//     flickers. The svg is only ever an image (a blob: URL).
export class Flat {
  constructor(root, onShown) {
    this.root = root;
    this.onShown = onShown || (() => {});
    this.pics = root.querySelector(".pics");
    this.live = root.querySelector(".live");
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
    this.player.update(reel);
  }

  // Leaves the player (flat mode is off, or a mirrored picture takes over).
  stop() {
    if (this.observer) this.observer.disconnect();
    if (this.player) this.player.destroy();
    this.player = this.observer = null;
    this.live.hidden = true;
  }

  // Answers a promise that settles once the newest picture is on show.
  show(svg, background) {
    this.stop();
    this.pics.hidden = false;
    // backgroundColor only takes a colour, so an odd value is simply ignored.
    this.pics.style.backgroundColor = background || "#ffffff";
    this.next = svg;
    if (!this.loading) {
      const run = (this.loading = this.load());
      run.finally(() => { if (this.loading === run) this.loading = null; });
    }
    return this.loading;
  }

  async load() {
    while (this.next) {
      const svg = this.next;
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
