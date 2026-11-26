// Flat mode: the picture alone, filling the window (contain), over its own
// background colour, like the live view.
//
// Two <img> elements take turns: the new picture loads into the hidden one
// and only becomes visible once it is decoded, so frames never flicker.
// The svg is only ever an image (a blob: URL), never part of the page.
export class Flat {
  constructor(root) {
    this.root = root;
    this.imgs = [...root.querySelectorAll("img")];
    this.urls = [null, null];
    this.front = 0;
    this.loading = null;     // the running load, if any
    this.next = null;
  }

  // Answers a promise that settles once the newest picture is on show.
  show(svg, background) {
    // backgroundColor only takes a colour, so an odd value is simply ignored.
    this.root.style.backgroundColor = background || "#ffffff";
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
      this.imgs[this.front].classList.remove("front");
      const old = this.urls[this.front];
      this.urls[back] = url;
      this.front = back;
      // The old picture is no longer shown; free it once this frame is painted.
      if (old) requestAnimationFrame(() => URL.revokeObjectURL(old));
    }
  }
}
