// The code, drawn on a transparent canvas: only the glyphs, tinted like the
// site, and the error as a pink line under them. In the 3D world the glyphs
// float in the air on their own.
//
// The glow, the pink of changed lines, the blinking caret and the fading ends
// of a long code's window are drawn by the shader (pieces.js) from the numbers
// kept here (rows, flash, caret), so none of them redraws or re-uploads the canvas.
//
// Code and error text are drawn with fillText only. The tint (AsobiTint, the
// site's own tinting) returns HTML; it is parsed in an inert document and
// only its text and class names are read, never put into the page.

export const MAX_ROWS = 96;
export const FLASH_TIME = 1.2;
const LINE = 1.42;          // line height, in font sizes
export const COLORS = {
  "t-c": "#8f8f9c", "t-s": "#a6e3a1", "t-y": "#ffc58a", "t-n": "#ffd479",
  "t-k": "#ff8fab", "t-t": "#cdb4ff", "t-w": "#89d9ff",
};
export const INK = "#f1f1f4";
const SIGNAL = "#ff5470";
export const MONO = `ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, "Liberation Mono", "Hiragino Sans", monospace`;

// The code's colours on a plain background (the side view, where the window
// is the picture's own colour): the site's dark-background set above, or this
// set for light backgrounds. Same hues, darker, each at least 4.5:1 on white
// (contrast on white: c 5.25, s 5.33, y 5.30, n 5.51, k 5.87, t 6.49, w 5.84,
// ink 17.85, signal 5.50; on the site's paper #f7f5ef all stay above 4.7).
// The signal (flash, caret, error) is a deeper pink there.
export const DARK = { name: "dark", colors: COLORS, ink: INK, signal: SIGNAL };
export const LIGHT = {
  name: "light",
  colors: {
    "t-c": "#6b6b78", "t-s": "#2f7a2a", "t-y": "#b04f00", "t-n": "#896200",
    "t-k": "#c2185b", "t-t": "#6a3fd0", "t-w": "#0b6aa2",
  },
  ink: "#17171d",
  signal: "#d0103c",
};
// Below this against the background a tint is not worth its colour: that
// part of the code takes the ink instead (the code is big: WCAG's large text).
const LEGIBLE = 3;

// The palette for code on a background [r, g, b] (0..255): the set whose ink
// stands out more (so a mid-tone such as red gets the one that reads better),
// with any colour that would still be too faint there turned to ink.
export function paletteOn(rgb) {
  const base = contrast(DARK.ink, rgb) >= contrast(LIGHT.ink, rgb) ? DARK : LIGHT;
  const colors = {};
  for (const [kind, color] of Object.entries(base.colors)) colors[kind] = contrast(color, rgb) >= LEGIBLE ? color : base.ink;
  const signal = contrast(base.signal, rgb) >= LEGIBLE;
  return { name: base.name, ink: base.ink, colors, accent: signal ? base.signal : base.ink, signal };
}

// WCAG contrast ratio of two colours, each "#rrggbb" or [r, g, b].
export function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

export function luminance(color) {
  const rgb = typeof color === "string" ? hexRgb(color) : color;
  const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2]);
}

export function hexRgb(hex) { return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)); }

export class CodeCanvas {
  constructor(width, height) {
    this.canvas = document.createElement("canvas");
    this.canvas.width = width;
    this.canvas.height = height;
    this.g = this.canvas.getContext("2d");
    this.words = [];
    this.lines = null;       // the code, as lines (null: nothing yet)
    this.error = null;
    this.dirty = true;
    this.px = 0;             // the font size in use (kept steady while typing)
    this.start = 0;          // first line shown when the code is longer than the panel
    this.focus = -1;         // the line last edited (the caret's line)
    this.flashAt = new Float64Array(0); // per line: when it last changed (seconds)
    this.tints = new Map();  // line text -> coloured runs
    this.parser = new DOMParser();
    // For the shader (all in uv: 0..1, y up)
    this.rows = 0;
    this.rowTop = 0;
    this.rowH = 0;
    this.fadeTop = 0;
    this.fadeBottom = 0;
    this.caret = [0, 0, 0, 0];    // x, y, w, h
    this.flash = new Float32Array(MAX_ROWS);
    this.rowLines = new Int32Array(0); // row on show -> line
  }

  setWords(words) {
    this.words = words;
    this.tints.clear();
    this.dirty = true;
  }

  // New code. Lines that differ from the last code flash; the caret goes to
  // the end of the last changed line. The first code after a quiet time
  // (fresh = true) just appears.
  setCode(code, now, fresh) {
    const lines = splitCode(code);
    const d = diffCode(this.lines, lines, this.flashAt, now, fresh);
    if (!d) return;
    this.focus = d.focus;
    if (d.focus < 0) this.start = 0;
    this.lines = lines;
    this.flashAt = d.flashAt;
    this.typedAt = now;
    this.dirty = true;
  }

  setError(error) {
    const e = error ? String(error) : null;
    if (e === this.error) return;
    this.error = e;
    this.dirty = true;
  }

  // Per frame: the flash strengths of the rows on show.
  tick(now) {
    this.flash.fill(0);
    if (!this.lines) return;
    for (let r = 0; r < this.rows; r++) {
      const at = this.flashAt[this.rowLines[r]];
      const k = (now - at) / FLASH_TIME;
      if (k >= 0 && k < 1) this.flash[r] = 1 - k * k * (3 - 2 * k); // holds, then fades
    }
  }

  // Redraws the canvas if something changed. Answers true when it did.
  // Only glyphs: no box, no header, no line numbers. The block of code is
  // centred top to bottom; the error, if any, is a pink line under it.
  draw() {
    if (!this.dirty) return false;
    this.dirty = false;
    const { g, canvas } = this;
    const W = canvas.width, H = canvas.height;
    g.clearRect(0, 0, W, H);
    // A margin all round, so the glow (taken from the blurred mipmaps) has room.
    const pad = Math.round(H * 0.06);
    const lines = this.lines || [];

    // The error: first line or two, measured first so the code makes room.
    const epx = Math.round(H * 0.046);
    g.font = `500 ${epx}px ${MONO}`;
    const errRows = this.error ? wrap(g, this.error, W - pad * 2, 2) : [];
    const errH = errRows.length ? epx * 0.9 + errRows.length * epx * 1.4 : 0;
    const bodyH = Math.max(1, H - pad * 2 - errH);

    // The font size: big enough to read on a projector, small enough that the
    // code fits. Long lines wrap (rather than shrinking everything) once the
    // font would get smaller than WRAP; below MIN only a window of lines shows.
    g.font = `500 100px ${MONO}`;
    let widest = 1;
    for (const l of lines) widest = Math.max(widest, g.measureText(l).width / 100);
    const textW = W - pad * 2;
    const maxPx = H * 0.07, wrapPx = H * 0.056, minPx = H * 0.044;
    const n = Math.max(lines.length, 1);
    const fitH = bodyH / (n * LINE);
    const fitW = textW / widest;
    let px = Math.min(maxPx, fitH, fitW);
    if (px < wrapPx && fitW < fitH) {
      px = Math.min(wrapPx, fitH);
      while (px > minPx && this.layoutRows(lines, px, textW).length * px * LINE > bodyH) px *= 0.96;
    }
    px = Math.max(minPx, px);
    if (this.px && px > this.px && px < this.px * 1.06) px = this.px; // no jitter while it grows
    this.px = px;
    const lh = px * LINE;
    g.font = `500 ${px}px ${MONO}`;
    const all = this.layoutRows(lines, px, textW);
    const fit = Math.max(1, Math.min(MAX_ROWS, Math.floor(bodyH / lh)));

    // Long code: a window of rows that keeps the edited line in view.
    let focusRow = -1;
    if (this.focus >= 0) for (let r = all.length - 1; r >= 0; r--) if (all[r].line === this.focus) { focusRow = r; break; }
    let start = Math.min(this.start, Math.max(0, all.length - fit));
    if (all.length <= fit) start = 0;
    else if (focusRow >= 0) {
      const margin = Math.min(3, Math.floor(fit / 4));
      if (focusRow < start + margin) start = Math.max(0, focusRow - margin);
      if (focusRow > start + fit - 1 - margin) start = Math.min(all.length - fit, focusRow - fit + 1 + margin);
    }
    this.start = start;
    const shown = Math.min(fit, all.length - start);
    const blockH = shown * lh + errH;
    const y0 = Math.max(pad, (H - blockH) / 2);

    g.textBaseline = "middle";
    const indent = g.measureText("00").width;
    let caretX = pad, caretRow = -1;
    this.rowLines = new Int32Array(shown);
    for (let r = 0; r < shown; r++) {
      const row = all[start + r];
      this.rowLines[r] = row.line;
      const y = y0 + lh * (r + 0.5);
      let x = pad + (row.first ? 0 : indent);
      for (const [text, color] of row.runs) {
        g.fillStyle = color;
        g.fillText(text, x, y);
        x += g.measureText(text).width;
      }
      if (row.line === this.focus && start + r === focusRow) { caretX = x; caretRow = r; }
    }
    if (errRows.length) {
      g.font = `500 ${epx}px ${MONO}`;
      g.fillStyle = SIGNAL;
      const top = y0 + shown * lh + epx * 0.9;
      errRows.forEach((row, i) => g.fillText(row, pad, top + epx * 1.4 * (i + 0.5)));
    }

    // Numbers for the shader (uv, y up). The ends of a window fade out there.
    this.rows = shown;
    this.rowTop = 1 - y0 / H;
    this.rowH = lh / H;
    this.fadeTop = start > 0 ? 1 : 0;
    this.fadeBottom = start + shown < all.length ? 1 : 0;
    if (caretRow >= 0) {
      const cw = Math.max(4, px * 0.11);
      this.caret = [(caretX + px * 0.14) / W, 1 - (y0 + lh * (caretRow + 0.5) + px * 0.6) / H, cw / W, (px * 1.2) / H];
    } else {
      this.caret = [0, 0, 0, 0];
    }
    return true;
  }

  // The rows the lines make at font size px when each row may be +width+
  // wide: long lines wrap (at a space or after punctuation when one is near
  // the end, else anywhere), their later rows indented by two characters.
  layoutRows(lines, px, width) {
    const g = this.g;
    g.font = `500 ${px}px ${MONO}`;
    const indent = g.measureText("00").width;
    const rows = [];
    lines.forEach((line, i) => {
      let runs = this.tint(line);
      let first = true;
      for (let guard = 0; guard < 200; guard++) {
        const room = width - (first ? 0 : indent);
        const text = runs.map((r) => r[0]).join("");
        if (g.measureText(text).width <= room || text.length <= 1) { rows.push({ line: i, first, runs }); break; }
        // The longest start of the text that fits.
        let lo = 1, hi = text.length;
        while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (g.measureText(text.slice(0, mid)).width <= room) lo = mid; else hi = mid - 1; }
        let cut = lo;
        const soft = Math.max(text.lastIndexOf(" ", lo), ...[".", ",", "(", "+"].map((c) => text.lastIndexOf(c, lo - 1) + 1));
        if (soft > lo * 0.6) cut = soft;
        const [head, tail] = splitRuns(runs, cut);
        rows.push({ line: i, first, runs: head });
        runs = trimRuns(tail);
        first = false;
        if (!runs.length) break;
      }
    });
    return rows;
  }

  // Coloured runs of one line, from the site's tint (cached by line text).
  tint(line) {
    let runs = this.tints.get(line);
    if (runs) return runs;
    runs = tintRuns(line, this.words, this.parser);
    if (this.tints.size > 4000) this.tints.clear();
    this.tints.set(line, runs);
    return runs;
  }

}

// The code as lines (tabs as two spaces).
export function splitCode(code) {
  return String(code).replace(/\r\n?/g, "\n").replace(/\t/g, "  ").split("\n");
}

// What changed between two versions of the code: same lines at the start and
// at the end are kept, what is between changed. Answers null when nothing
// changed, else { flashAt (per new line: when it last changed), focus (the
// last changed line, the caret's; -1 when the code is shown fresh) }. Most of
// it new (another example opened, say), or fresh: shown from the top, quietly.
export function diffCode(old, lines, oldFlashAt, now, fresh) {
  if (old && old.length === lines.length && old.every((l, i) => l === lines[i])) return null;
  const flashAt = new Float64Array(lines.length).fill(-1e9);
  let a = 0, b = 0;
  if (old) {
    while (a < old.length && a < lines.length && old[a] === lines[a]) a++;
    while (b < old.length - a && b < lines.length - a && old[old.length - 1 - b] === lines[lines.length - 1 - b]) b++;
  }
  const whole = !old || (lines.length - a - b) > Math.max(3, lines.length * 0.6);
  if (fresh || whole) return { flashAt, focus: -1 };
  for (let i = 0; i < lines.length; i++) {
    if (i < a) flashAt[i] = oldFlashAt[i] ?? -1e9;
    else if (i >= lines.length - b) flashAt[i] = oldFlashAt[i - lines.length + old.length] ?? -1e9;
    else flashAt[i] = now;
  }
  const last = lines.length - b - 1;
  return { flashAt, focus: last >= a ? last : Math.max(0, Math.min(lines.length - 1, a - 1)) };
}

// The site's tint (AsobiTint) of one line as coloured runs [text, colour,
// kind] (kind: the tint's class, such as "t-c", or "" for plain text).
// AsobiTint answers HTML: it is parsed in an inert document and only its
// text and class names are read, never put into a page.
export function tintRuns(line, words, parser) {
  const runs = [];
  if (self.AsobiTint) {
    const doc = parser.parseFromString(`<p>${self.AsobiTint(line, words)}</p>`, "text/html");
    const p = doc.body.firstChild;
    for (const node of p ? p.childNodes : []) {
      const text = node.textContent;
      if (!text) continue;
      const kind = node.nodeType === 1 && COLORS[node.getAttribute("class")] ? node.getAttribute("class") : "";
      runs.push([text, COLORS[kind] || INK, kind]);
    }
  } else {
    runs.push([line, INK, ""]);
  }
  return runs;
}

// Runs split after +at+ characters.
function splitRuns(runs, at) {
  const head = [], tail = [];
  let n = 0;
  for (const [text, color] of runs) {
    if (n + text.length <= at) head.push([text, color]);
    else if (n >= at) tail.push([text, color]);
    else { head.push([text.slice(0, at - n), color]); tail.push([text.slice(at - n), color]); }
    n += text.length;
  }
  return [head, tail];
}

// Runs without the spaces they start with (a wrapped row starts at a word).
function trimRuns(runs) {
  const out = runs.slice();
  while (out.length && !out[0][0].trimStart()) out.shift();
  if (out.length) out[0] = [out[0][0].trimStart(), out[0][1]];
  return out;
}

// At most +max+ rows of text that fit +width+; the last ends with … when cut.
function wrap(g, text, width, max) {
  const out = [];
  const lines = text.split("\n").filter((l) => l.trim());
  let used = 0;
  for (const line of lines) {
    let rest = line;
    while (rest && out.length < max) {
      if (g.measureText(rest).width <= width) { out.push(rest); used += rest.length; rest = ""; break; }
      // The longest start that fits, ending at a space when there is one.
      let n = 1;
      while (n < rest.length && g.measureText(rest.slice(0, n + 1)).width <= width) n++;
      const space = rest.lastIndexOf(" ", n);
      if (space > n * 0.5) n = space + 1;
      out.push(rest.slice(0, n).trimEnd());
      used += n;
      rest = rest.slice(n);
    }
    if (out.length === max) break;
  }
  const total = lines.reduce((sum, l) => sum + l.length, 0);
  if (used < total && out.length) {
    let last = out[out.length - 1];
    while (last && g.measureText(last + "…").width > width) last = last.slice(0, -1);
    out[out.length - 1] = last + "…";
  }
  return out;
}
