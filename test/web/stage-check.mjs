// Checks the stage window's SVG tools (site/stage/svgframe.js) on real asobi
// output, in plain Node:
//
//   node test/web/stage-check.mjs <svgframe.js> <frames.json>
//
// frames.json: { "grain": "<a frame with grain: true>", "plain": "<a frame without>",
//                "parts": { "frame": "...<!--asobi:p1-->...", "parts": {...} } }
// Prints a JSON object; test/site_test.rb checks it.
import fs from "node:fs";
import { pathToFileURL } from "node:url";
const [lib, data] = process.argv.slice(2);
const { stripGrain, restFrame, frameSvg, withoutBackground } = await import(pathToFileURL(lib).href);
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
  background: { withRect: svg.includes('fill="black"'), withoutRect: !bare.includes('fill="black"'), contentKept: bare.includes('<circle r="5" fill="white"/>') }
}));
