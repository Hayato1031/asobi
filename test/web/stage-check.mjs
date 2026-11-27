// Checks the stage window's SVG tools (site/stage/svgframe.js) on real asobi
// output, and the side view's code palettes (code.js, beside it), in plain Node:
//
//   node test/web/stage-check.mjs <svgframe.js> <frames.json>
//
// frames.json: { "grain": "<a frame with grain: true>", "plain": "<a frame without>",
//                "parts": { "frame": "...<!--asobi:p1-->...", "parts": {...} } }
// Prints a JSON object; test/site_test.rb checks it.
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const [lib, data] = process.argv.slice(2);
const { stripGrain, restFrame, frameSvg, withoutBackground, grainAtEnd, withoutGrainAtEnd, reelWithoutGrain, withViewBox, withBackgroundBox } = await import(pathToFileURL(lib).href);
const { paletteOn, contrast, LIGHT, DARK } = await import(new URL("./code.js", pathToFileURL(lib)).href);
const X = await import(new URL("./extent.js", pathToFileURL(lib)).href);
const T = await import(new URL("./reel-tools.js", pathToFileURL(lib)).href);
const f = JSON.parse(fs.readFileSync(data, "utf8"));
const g = stripGrain(f.grain);
const p = stripGrain(f.plain);
const rest = restFrame(f.parts.frame, f.parts.parts);
const svg = frameSvg('<circle r="5" fill="white"/>', [-10, -10, 20, 20], "black", true, 64, 64);
const bare = withoutBackground(svg);
console.log(JSON.stringify({
  grain: { strength: g.grain, turbulenceLeft: g.markup.includes("feTurbulence"), keptRest: f.grain.startsWith(g.markup.slice(0, 40)) },
  plain: { strength: p.grain, same: p.markup === f.plain },
  rest: { markersLeft: rest.includes("<!--asobi:"), firstFrameIn: rest.includes(f.parts.parts.p1.frames[0]) },
  background: { withRect: svg.includes('fill="black"'), withoutRect: !bare.includes('fill="black"'), contentKept: bare.includes('<circle r="5" fill="white"/>') },
  palette: palettes(),
  tail: tailGrain(),
  pack: packCheck(),
  extent: extents()
}));

// The 3D art's extent (extent.js), from boxes of drawn pixels in a probe:
// nothing past the paper (or only edge smoothing) keeps the paper; a disc
// taller than its paper (the galaxy) widens it up and down only, padded, with
// fading bands there; a drawing at the probe's edge asks for a bigger probe,
// and the extent never passes CAP papers.
// The flat and side views' player gets the frames packed in one buffer,
// without grain, read one at a time (reel-tools.js playerPack / unpack).
function packCheck() {
  const reel = { frames: [f.grain, "<g>あ</g>"], fps: 30, view: [0, 0, 10, 10], parts: { p1: { frames: ["<g/>"] } }, code: "c" };
  const r = T.unpack(T.playerPack(reel));
  return {
    isArray: Array.isArray(r.frames), length: r.frames.length,
    first: r.frames[0] === stripGrain(f.grain).markup, second: r.frames[1], beyond: r.frames[2] === undefined,
    grain: r.grain, grainless: r.grainless, code: r.code, parts: r.parts.p1.frames.length, original: reel.frames[0] === f.grain,
  };
}

function extents() {
  const MIRROR = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-80 -45 160 90"><rect x="-80" y="-45" width="160" height="90" fill="#1b2a4a"></rect><g><rect rx="2" x="1" width="5"/></g></svg>';
  const paper = [-240, -135, 480, 270];
  const probe = X.probeOf(paper, 3, 384);
  const s = probe.pw / probe.view[2];
  const px = (x, y) => [(x - probe.view[0]) * s, (y - probe.view[1]) * s];
  const box = (x0, y0, x1, y1) => [...px(x0, y0), ...px(x1, y1)].map((v, i) => (i < 2 ? Math.floor(v) : Math.ceil(v)));
  const r = (a) => a.map((v) => Math.round(v * 100) / 100);
  const galaxy = X.extentOf(box(-240, -240, 240, 240), probe, paper);
  const big = X.probeOf(paper, 7, 512);
  const huge = X.extentOf([0, 0, big.pw, big.ph], big, paper);
  const buf = new Uint8ClampedArray(8 * 6 * 4);
  buf[(2 * 8 + 3) * 4 + 3] = 200; buf[(4 * 8 + 6) * 4 + 3] = 9; buf[(5 * 8 + 1) * 4 + 3] = 2;
  return {
    probe: { view: probe.view, pw: probe.pw, ph: probe.ph },
    none: X.extentOf(null, probe, paper).spills,
    inside: X.extentOf(box(-200, -100, 200, 100), probe, paper).spills,
    edge: X.extentOf([...px(-240, -135).map((v) => v - 1), ...px(240, 135).map((v) => v + 1)], probe, paper).spills,
    galaxy: { box: r(galaxy.box), bands: r(galaxy.bands), touches: galaxy.touches },
    touches: X.extentOf([0, 10, 50, 60], probe, paper).touches,
    capped: r(huge.box),
    alpha: X.alphaBox(buf, 8, 6),
    samples: [X.samples(240), X.samples(1), X.samples(5)],
    // With B on the background covers the whole extent: in a frame drawn
    // here, and in a mirrored picture (only its first <rect>, x/y/w/h only).
    sheet: frameSvg("<g/>", paper, "black", true, 8, 8, galaxy.box).includes(`<rect x="-240" y="${galaxy.box[1]}" width="480" height="${galaxy.box[3]}" fill="black"/>`),
    mirrored: withViewBox(withBackgroundBox(MIRROR, [-177.4, -45, 354.8, 108.65]), [-177.4, -45, 354.8, 108.65]),
  };
}

// The flat views' grain: found from the end of a frame (and of a mirrored
// picture), taken out of a Reel as a copy, and left alone when it is not at
// the end (then it is not asobi's grain where SVG.grain puts it).
function tailGrain() {
  const reel = { frames: [f.grain, f.grain], view: [0, 0, 10, 10] };
  const bare = reelWithoutGrain(reel);
  const mirrored = withoutGrainAtEnd(`<svg xmlns="http://www.w3.org/2000/svg"><rect/><g>${f.grain}</g></svg>`);
  return {
    strength: bare.grain,
    sameAsStrip: bare.reel.frames.every((x) => x === stripGrain(f.grain).markup),
    copied: bare.reel !== reel && reel.frames[0] === f.grain,
    mirrored: { strength: mirrored.grain, turbulenceLeft: mirrored.markup.includes("feTurbulence"), closed: mirrored.markup.endsWith("</g></svg>") },
    notAtEnd: grainAtEnd(f.grain + '<circle r="1"/>') === null,
    none: reelWithoutGrain({ frames: [f.plain] }).grain,
  };
}

// Which palette each background gets, the light set's worst contrast on
// white, and the worst contrast any colour keeps on a few mid-tones (where
// faint colours fall back to the ink).
function palettes() {
  const on = { white: [255, 255, 255], paper: [247, 245, 239], black: [0, 0, 0], night: [5, 6, 12], red: [255, 0, 0], blue: [47, 111, 214], grey: [128, 128, 128] };
  const pick = Object.fromEntries(Object.entries(on).map(([k, rgb]) => [k, paletteOn(rgb).name]));
  const light = [...Object.values(LIGHT.colors), LIGHT.ink, LIGHT.signal];
  const dark = [...Object.values(DARK.colors), DARK.ink, DARK.signal];
  const worst = (colors, rgb) => Math.min(...colors.map((c) => contrast(c, rgb)));
  const kept = Object.fromEntries(Object.entries(on).map(([k, rgb]) => {
    const p = paletteOn(rgb);
    return [k, +worst([...Object.values(p.colors), p.ink, p.accent], rgb).toFixed(2)];
  }));
  return { pick, lightOnWhite: +worst(light, on.white).toFixed(2), darkOnBlack: +worst(dark, on.black).toFixed(2), kept };
}
