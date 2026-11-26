// The code over the flat picture, like subtitles (as the live view's code
// overlay: line by line, each line on its own tight dark backing), tinted
// like the site. A changed line glows pink and fades; a caret blinks after
// the last change; the error is a pink line under the code. Long code shows
// the lines around the edited one, and the ends fade.
//
// Text goes in with textContent only (the code comes from a URL anyone can write).
import { splitCode, diffCode, tintRuns, FLASH_TIME } from "./code.js";

const SIGNAL = "#ff5470";

export class Subtitles {
  constructor(root) {
    this.root = root;
    this.box = root.querySelector(".lines");
    this.err = root.querySelector(".err");
    this.parser = new DOMParser();
    this.words = [];
    this.lines = null;
    this.flashAt = new Float64Array(0);
    this.focus = -1;
    this.start = 0;
    this.error = null;
    addEventListener("resize", () => this.render());
  }

  setWords(words) { this.words = words; if (this.lines) this.render(); }

  setCode(code, fresh) {
    const now = performance.now() / 1000;
    const lines = splitCode(code);
    const d = diffCode(this.lines, lines, this.flashAt, now, fresh);
    if (!d) return;
    this.lines = lines;
    this.flashAt = d.flashAt;
    this.focus = d.focus;
    if (d.focus < 0) this.start = 0;
    this.render();
  }

  setError(error) {
    const e = error ? String(error) : null;
    if (e === this.error) return;
    this.error = e;
    this.err.textContent = e ? e.split("\n").filter((l) => l.trim()).slice(0, 2).join("\n") : "";
    this.err.hidden = !e;
    this.render();
  }

  render() {
    const lines = this.lines || [];
    const now = performance.now() / 1000;
    // How many lines fit: the window's height, less the error and the margins.
    const lh = parseFloat(getComputedStyle(this.box).lineHeight) || 24;
    const room = innerHeight * 0.9 - (this.error ? this.err.offsetHeight + lh * 0.6 : 0);
    const fit = Math.max(3, Math.floor(room / (lh + 2)));
    let start = Math.min(this.start, Math.max(0, lines.length - fit));
    if (lines.length <= fit) start = 0;
    else if (this.focus >= 0) {
      const margin = Math.min(3, Math.floor(fit / 4));
      if (this.focus < start + margin) start = Math.max(0, this.focus - margin);
      if (this.focus > start + fit - 1 - margin) start = Math.min(lines.length - fit, this.focus - fit + 1 + margin);
    }
    this.start = start;
    const end = Math.min(lines.length, start + fit);
    const out = [];
    for (let i = start; i < end; i++) {
      // A line (block) holding the text (inline): the backing hugs each row of a wrapped line.
      const row = document.createElement("div");
      row.className = "line";
      const text = document.createElement("span");
      text.className = "text" + (lines[i].trim() === "" ? " blank" : "");
      for (const [t, color] of tintRuns(lines[i], this.words, this.parser)) {
        const span = document.createElement("span");
        span.textContent = t;
        span.style.color = color;
        text.append(span);
      }
      if (i === this.focus) {
        const caret = document.createElement("span");
        caret.className = "caret";
        text.append(caret);
      }
      row.append(text);
      // A changed line: a pink glow that fades (picking up where it was if redrawn mid-fade).
      const since = now - this.flashAt[i];
      if (since >= 0 && since < FLASH_TIME && text.animate) {
        const anim = text.animate([
          { backgroundColor: "rgba(255, 84, 112, 0.42)", textShadow: `0 0 0.5em ${SIGNAL}, 0 0 1.2em rgba(255, 84, 112, 0.6)` },
          { backgroundColor: "rgba(11, 11, 15, 0.72)", textShadow: "0 0 0 transparent" },
        ], { duration: FLASH_TIME * 1000, easing: "ease-in" });
        anim.currentTime = since * 1000;
      }
      out.push(row);
    }
    this.box.replaceChildren(...out);
    // The ends of a window of lines dissolve.
    this.box.classList.toggle("cut-top", start > 0);
    this.box.classList.toggle("cut-bottom", end < lines.length);
  }
}
