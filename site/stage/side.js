// The side view's code: beside the picture (left of it; under it in a tall
// window), on the window's plain colour, which is the picture's own
// background. Only the glyphs: no backing, panel, frame or line numbers.
// Otherwise it behaves like the subtitles (subtitles.js): a changed line
// flashes, a caret blinks after the last change, the error is a line under
// the code, and long code shows a window of lines around the edited one
// with fading ends.
//
// The colours come from a palette picked for the background (paletteOn in
// code.js). The font is as big as the code allows: short, narrow code gets
// big type, wide code smaller type, down to a floor below which long lines
// wrap (later rows indented) and long code shows a window. Sizes go in steps,
// so typing does not make the code breathe.
//
// Text goes in with textContent only (the code comes from a URL anyone can write).
import { Subtitles } from "./subtitles.js";
import { tintRuns, paletteOn, hexRgb, DARK, MONO, FLASH_TIME } from "./code.js";

const LINE = 1.5;           // line height, in font sizes (as in stage.css)
// Where a long line may wrap besides its spaces: between the calls of a
// chain, after ")." or "]." (never inside a name such as Planet.new or a
// number such as 0.25).
const SOFT = /[)\]]\.(?=[A-Za-z_])/g;
const STEP = 0.93;          // one step down the font size ladder
const MARGIN_LINES = 3;     // lines kept around the edited one in a window

export class SideCode extends Subtitles {
  constructor(root) {
    super(root);
    this.shown = false;
    this.palette = paletteOn([255, 255, 255]);
    this.px = 0;
    this.runs = new Map();   // line text -> [text, kind] runs (the tint, whatever the palette)
    this.widths = new Map(); // line text -> width in font sizes
    this.measure = document.createElement("canvas").getContext("2d");
    this.measure.font = `500 100px ${MONO}`;
  }

  // Drawn only while on show (it measures the window); drawn at once when it shows.
  show(on) {
    if (on === this.shown) return;
    this.shown = on;
    if (on) this.render();
  }

  setPalette(palette) {
    const p = palette || paletteOn([255, 255, 255]);
    const same = this.palette.accent === p.accent && this.palette.ink === p.ink &&
      Object.keys(p.colors).every((k) => this.palette.colors[k] === p.colors[k]);
    this.palette = p;
    if (!same) this.render();
  }

  setWords(words) { this.runs.clear(); super.setWords(words); }

  render() {
    if (!this.shown) return;
    // Blank lines at the end take no room (unless the caret is on one).
    const all = this.lines || [];
    let n = all.length;
    while (n > 1 && !all[n - 1].trim() && n - 1 > this.focus) n--;
    const lines = all.slice(0, n);
    const root = this.root, box = this.box, p = this.palette;
    root.dataset.palette = p.name;
    root.style.setProperty("--accent", p.accent);
    this.err.style.color = p.accent;

    // The room the code has (its box less the padding).
    const cs = getComputedStyle(root);
    const roomW = root.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
    const roomH = root.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
    const unit = Math.min(innerWidth, innerHeight);
    const maxPx = unit * 0.031, minPx = unit * 0.0245; // the floor: a little over the subtitles' size
    const wide = lines.reduce((w, l) => Math.max(w, this.width(l)), 0.01);

    // The biggest step at which every line fits across and the whole code
    // fits top to bottom; failing that, the floor (lines wrap, a window shows).
    const errLines = this.error ? this.err.textContent.split("\n").length : 0;
    let px = minPx;
    for (let s = maxPx; s > minPx; s *= STEP) {
      const errAt = errLines ? s * (0.8 + errLines * LINE) : 0;
      if (wide * s <= roomW && this.rowsAt(lines, s, roomW).total * s * LINE + errAt <= roomH) { px = s; break; }
    }
    px = Math.round(px * 10) / 10;
    if (px !== this.px) { this.px = px; root.style.fontSize = px + "px"; }
    const lh = px * LINE;

    // The error first (measured at this size), so the code makes room for it.
    const errH = this.error ? this.err.offsetHeight + px * 0.8 : 0;
    const fitH = Math.max(lh * 3, roomH - errH);
    const rows = this.rowsAt(lines, px, roomW).each;

    // Which lines show: all, or a window that keeps the edited line in view.
    let [start, end] = this.windowOf(rows, fitH / lh);
    for (let tries = 0; tries < 4; tries++) {
      this.draw(lines, start, end);
      // Wrapping at spaces can take a row more than the estimate: then a line less.
      if (box.offsetHeight <= fitH + 1 || end - start <= 3) break;
      if (this.focus >= 0 && this.focus - start > end - 1 - this.focus) start++;
      else end--;
    }
    this.start = start;
  }

  // Rows each line takes at font size px in width w (estimated: it wraps at
  // the width, later rows indented, see stage.css), and their sum.
  rowsAt(lines, px, w) {
    const ch = this.width("0") * px;
    let total = 0;
    const each = lines.map((l) => {
      const lw = this.width(l) * px;
      const n = lw <= w ? 1 : 1 + Math.ceil((lw - w) / Math.max(ch, w - (lead(l) + 4) * ch));
      total += n;
      return n;
    });
    return { each, total };
  }

  // [start, end) of the lines that fit +fit+ rows, keeping the edited line
  // (the caret's) a few lines from either end, and moving as little as it can.
  windowOf(rows, fit) {
    const n = rows.length;
    const sum = (a, b) => { let s = 0; for (let i = a; i < b; i++) s += rows[i]; return s; };
    if (sum(0, n) <= fit) return [0, n];
    const endFrom = (a) => { let b = a, s = 0; while (b < n && s + rows[b] <= fit) s += rows[b++]; return Math.max(b, a + 1); };
    let start = Math.min(this.start, n - 1);
    // Not past the end: fill the window back from the last line.
    if (endFrom(start) >= n) while (start > 0 && sum(start - 1, n) <= fit) start--;
    const f = this.focus;
    if (f >= 0) {
      const margin = Math.min(MARGIN_LINES, Math.floor(fit / 4));
      if (f < start + margin) start = Math.max(0, f - margin);
      while (start < f && endFrom(start) < n && endFrom(start) - 1 - margin < f) start++;
    }
    return [start, endFrom(start)];
  }

  draw(lines, start, end) {
    const p = this.palette, now = performance.now() / 1000;
    const out = [];
    for (let i = start; i < end; i++) {
      // A line (block) holding the text (inline), so the flash hugs each row of a wrapped line.
      const row = document.createElement("div");
      row.className = "line";
      row.style.setProperty("--lead", String(lead(lines[i])));
      const text = document.createElement("span");
      text.className = "text";
      // Soft wrap points (<wbr>), found in the whole line: a chain's ")." and
      // the name after it are often in runs of their own.
      const soft = new Set([...lines[i].matchAll(SOFT)].map((m) => m.index + 2));
      let at = 0;
      for (const [t, kind] of this.tint(lines[i])) {
        if (soft.has(at)) text.append(document.createElement("wbr"));
        const span = document.createElement("span");
        let from = 0;
        for (let k = 1; k < t.length; k++) {
          if (!soft.has(at + k)) continue;
          span.append(t.slice(from, k), document.createElement("wbr"));
          from = k;
        }
        span.append(t.slice(from));
        span.style.color = p.colors[kind] || p.ink;
        if (kind === "t-c") span.className = "c";
        text.append(span);
        at += t.length;
      }
      if (i === this.focus) {
        const caret = document.createElement("span");
        caret.className = "caret";
        text.append(caret);
      }
      row.append(text);
      // A changed line: a band of the accent that fades (picking up where it
      // was if redrawn mid-fade); on a dark background it glows as well.
      const since = now - this.flashAt[i];
      if (since >= 0 && since < FLASH_TIME && text.animate) {
        const [r, g, b] = hexRgb(p.accent);
        const glow = p.name === DARK.name && p.signal;
        const from = { backgroundColor: `rgba(${r}, ${g}, ${b}, ${p.name === DARK.name ? 0.4 : 0.2})` };
        const to = { backgroundColor: `rgba(${r}, ${g}, ${b}, 0)` };
        if (glow) {
          from.textShadow = `0 0 0.5em ${p.accent}, 0 0 1.2em rgba(${r}, ${g}, ${b}, 0.6)`;
          to.textShadow = "0 0 0 transparent";
        }
        const anim = text.animate([from, to], { duration: FLASH_TIME * 1000, easing: "ease-in" });
        anim.currentTime = since * 1000;
      }
      out.push(row);
    }
    this.box.replaceChildren(...out);
    // The ends of a window of lines dissolve into the background.
    this.box.classList.toggle("cut-top", start > 0);
    this.box.classList.toggle("cut-bottom", end < lines.length);
  }

  // A line's coloured runs as [text, kind] (cached by line text).
  tint(line) {
    let runs = this.runs.get(line);
    if (runs) return runs;
    runs = tintRuns(line, this.words, this.parser).map(([t, , kind]) => [t, kind]);
    if (this.runs.size > 4000) this.runs.clear();
    this.runs.set(line, runs);
    return runs;
  }

  // A line's width in font sizes (cached by line text).
  width(line) {
    let w = this.widths.get(line);
    if (w !== undefined) return w;
    w = this.measure.measureText(line).width / 100;
    if (this.widths.size > 4000) this.widths.clear();
    this.widths.set(line, w);
    return w;
  }
}

// The spaces a line starts with (its indent), at most 24.
function lead(line) { return Math.min(24, line.length - line.trimStart().length); }
