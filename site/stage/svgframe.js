// Small tools for the SVG the stage draws.
//
// A frame of a Reel is a fragment of asobi's own SVG (already checked by
// AsobiSafeReel). The stage turns it into a standalone <svg> the same way the
// player does (a background <rect>, then the frame), with two changes:
//   - the background can be left out (the B key): only that <rect> goes, so
//     nothing the sketch drew is ever removed, whatever its colour;
//   - asobi's grain (SVG.grain in lib/asobi/svg.rb: a noise filter on a rect
//     over the whole view, at the end of every frame) is taken out and drawn
//     by the GPU instead. feTurbulence at a few megapixels is the most
//     expensive thing an SVG can ask for, and it is the same in every frame.
// The flat and side views take the grain out too (grainAtEnd, reelWithoutGrain)
// and lay it once over the whole window (grain.js), so it has no edge.

const MAX_DEPTH = 32;

// The grain fragment: <defs><filter id=..>..feTurbulence..</filter></defs><rect .. filter="url(#id)" ../>
const GRAIN = /<defs><filter id="(asobi-[a-z0-9]+)"[^>]*>(?:(?!<\/filter>)[\s\S])*?<feTurbulence(?:(?!<\/filter>)[\s\S])*<\/filter><\/defs><rect [^>]*filter="url\(#\1\)"[^>]*?(?:\/>|><\/rect>)/;
// Its strength: the black specks' alpha row of the first feColorMatrix ("... K 0 0 0 -K/2").
const STRENGTH = /values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ([0-9.]+) 0 0 0 -/;

// The markup without the grain, and the grain's strength (0 when there is none).
export function stripGrain(markup) {
  const m = GRAIN.exec(markup);
  if (!m) return { markup, grain: 0 };
  const k = STRENGTH.exec(m[0]);
  return { markup: markup.slice(0, m.index) + markup.slice(m.index + m[0].length), grain: k ? Number(k[1]) / 4 : 0.12 };
}

// asobi's grain where SVG.grain puts it: at the very end of a frame (or, in a
// mirrored picture, followed only by closing tags). Found from the tail, so a
// big frame is never scanned. Answers { at, length, grain } or null.
const GRAIN_START = '<defs><filter id="asobi-';
const GRAIN_HERE = new RegExp(GRAIN.source, "y");
const ONLY_CLOSING = /^(?:\s*<\/[A-Za-z]+>)*\s*$/;
export function grainAtEnd(markup) {
  const at = markup.lastIndexOf(GRAIN_START);
  if (at < 0) return null;
  GRAIN_HERE.lastIndex = at;
  const m = GRAIN_HERE.exec(markup);
  if (!m || !ONLY_CLOSING.test(markup.slice(at + m[0].length))) return null;
  const k = STRENGTH.exec(m[0]);
  return { at, length: m[0].length, grain: k ? Number(k[1]) / 4 : 0.12 };
}

// The markup without the grain at its end (as it is when there is none).
export function withoutGrainAtEnd(markup) {
  const g = grainAtEnd(markup);
  return g ? { markup: markup.slice(0, g.at) + markup.slice(g.at + g.length), grain: g.grain } : { markup, grain: 0 };
}

// A Reel without its grain, and the grain's strength: a shallow copy whose
// frames end before the grain (the checked Reel itself is left as it is; others
// use it). Every frame ends with the same fragment, so it is found once, in
// the first frame, and each frame is only checked for that ending: the cost
// does not grow with the frames' size.
export function reelWithoutGrain(reel) {
  const frames = reel.frames;
  const first = frames.length ? grainAtEnd(frames[0]) : null;
  if (!first) return { reel, grain: 0 };
  const tail = frames[0].slice(first.at, first.at + first.length);
  const bare = frames.map((f) => (f.endsWith(tail) ? f.slice(0, f.length - tail.length) : withoutGrainAtEnd(f).markup));
  return { reel: { ...reel, frames: bare }, grain: first.grain };
}

// A frame with every reacting part at rest (its first frame), as the player
// shows it before anyone clicks, hovers, plays or speaks.
export function restFrame(frame, parts, depth = 0) {
  if (!parts || depth >= MAX_DEPTH) return frame;
  return frame.replace(/<!--asobi:(p[0-9]+)-->/g, (all, id) => {
    const d = parts[id];
    return d ? `<g>${restFrame(d.frames[0], parts, depth + 1)}</g>` : all;
  });
}

// A standalone <svg> of w x h pixels for one frame (already without grain).
// box: the rectangle drawn (user units), the paper (view) by default; a wider
// one shows what was drawn past the paper (extent.js). The background, when
// on, covers the whole box: the sheet is the whole picture, never a paper
// with the drawing running off it.
export function frameSvg(body, view, background, withBackground, w, h, box = view) {
  const v = box.join(" ");
  const bg = withBackground
    ? `<rect x="${box[0]}" y="${box[1]}" width="${box[2]}" height="${box[3]}" fill="${attr(background || "white")}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${v}" preserveAspectRatio="xMidYMid meet" stroke-linejoin="round" stroke-linecap="round">${bg}<g>${body}</g></svg>`;
}

// A picture's root <svg> with another viewBox (numbers only; nothing else in
// the markup changes). As it was when the root has no viewBox.
const ROOT_VIEWBOX = /^(\s*<svg\b[^>]*?\sviewBox=")[^"]*(")/;
export function withViewBox(svg, box) {
  const v = Array.isArray(box) ? box.map((n) => Math.round(n * 1000) / 1000).join(" ") : String(box);
  return svg.replace(ROOT_VIEWBOX, (all, head, tail) => head + v + tail);
}

// A mirrored picture whose background <rect> (the first element inside the
// root) covers box instead of the paper: x, y, width and height only, numbers
// made here. As it was when the root does not start with a <rect>.
const FIRST_RECT = /^(\s*<svg\b[^>]*>\s*)(<rect\b[^>]*?)(\/?>)/;
export function withBackgroundBox(svg, box) {
  const n = (v) => String(Math.round(v * 1000) / 1000);
  return svg.replace(FIRST_RECT, (all, head, rect, end) => {
    let r = rect;
    for (const [name, v] of [["x", box[0]], ["y", box[1]], ["width", box[2]], ["height", box[3]]]) {
      const re = new RegExp(`\\s${name}="[^"]*"`);
      r = re.test(r) ? r.replace(re, ` ${name}="${n(v)}"`) : `${r} ${name}="${n(v)}"`;
    }
    return head + r + end;
  });
}

// A mirrored picture (the playground player's whole <svg>) without its
// background: the first element inside the root is that <rect>.
export function withoutBackground(svg) {
  return svg.replace(/^(\s*<svg\b[^>]*>)\s*<rect\b[^>]*?(?:\/>|><\/rect>)/, "$1");
}

function attr(s) { return String(s).replace(/[&"<>]/g, (c) => ({ "&": "&amp;", '"': "&quot;", "<": "&lt;", ">": "&gt;" })[c]); }
