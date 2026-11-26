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
export function frameSvg(body, view, background, withBackground, w, h) {
  const v = view.join(" ");
  const bg = withBackground
    ? `<rect x="${view[0]}" y="${view[1]}" width="${view[2]}" height="${view[3]}" fill="${attr(background || "white")}"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${v}" preserveAspectRatio="xMidYMid meet" stroke-linejoin="round" stroke-linecap="round">${bg}<g>${body}</g></svg>`;
}

// A mirrored picture (the playground player's whole <svg>) without its
// background: the first element inside the root is that <rect>.
export function withoutBackground(svg) {
  return svg.replace(/^(\s*<svg\b[^>]*>)\s*<rect\b[^>]*?(?:\/>|><\/rect>)/, "$1");
}

function attr(s) { return String(s).replace(/[&"<>]/g, (c) => ({ "&": "&amp;", '"': "&quot;", "<": "&lt;", ">": "&gt;" })[c]); }
