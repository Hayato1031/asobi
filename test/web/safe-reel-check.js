// Checks the playground's checker for what an engine sends
// (site/assets/safe-reel.js), in plain Node.
//
//   node test/web/safe-reel-check.js _site/assets/safe-reel.js _site/reels
//
// Every Reel the site built from its own examples must pass, with the same
// frames and parts; a list of attacks must not. Prints a JSON object with
// the answers (test/site_test.rb checks them); exits 1 with a message when
// the script itself cannot run.
"use strict";
const fs = require("fs");
const path = require("path");

const [safeJs, reelsDir] = process.argv.slice(2);
const Safe = require(path.resolve(safeJs));

const result = {};

// (a) the site's own Reels
result.reels = { count: 0, rejected: [], changed: [] };
for (const file of fs.readdirSync(reelsDir).filter((f) => f.endsWith(".js")).sort()) {
  const text = fs.readFileSync(path.join(reelsDir, file), "utf8");
  const m = /^asobiReel\("([^"]+)",\s*([\s\S]*)\);\s*$/.exec(text);
  if (!m) { console.error("not a reel file: " + file); process.exit(1); }
  const value = JSON.parse(m[2]);
  const safe = Safe.reel(value);
  result.reels.count++;
  if (!safe) {
    const bad = (value.frames || []).find((f) => !Safe.markup(f));
    result.reels.rejected.push({ file, frame: bad === undefined ? null : String(bad).slice(0, 300) });
    continue;
  }
  const partsIn = Object.keys(value.parts || {}), partsOut = Object.keys(safe.parts || {});
  const same = safe.frames.length === value.frames.length && partsIn.length === partsOut.length &&
    partsIn.every((id) => safe.parts[id] && safe.parts[id].frames.length === value.parts[id].frames.length);
  if (!same) result.reels.changed.push(file);
}

// (b) markup that is not asobi's own
const attacks = [
  '<image href="x:" onerror="alert(1)"/>',
  "<script>alert(1)</script>",
  '<g onclick="alert(1)">',
  "<foreignObject><img src=x onerror=alert(1)></foreignObject>",
  '<a href="javascript:alert(1)">',
  '<use href="#x"/>',
  '<animate attributeName="href"/>',
  "<set/>",
  "<style>*{}</style>",
  '<svg onload="alert(1)">',
  '<G ONCLICK="alert(1)">',
  '<g\tonclick="alert(1)">',
  "<g onclick=alert(1)>",
  "<g fill='red'>",
  '<rect fill="url(https://example.com/x.svg#a)"/>',
  '<rect fill="u\\72l(https://example.com/x)"/>',
  "<rect mask=\"image-set('https://example.com/x.png' 1x)\"/>",
  '<g style="background:url(https://example.com/x)">',
  '<g id="code">',
  "<!-- x -->",
  "<!--asobi:__proto__-->",
  "<![CDATA[x]]>",
  "<?xml?>",
  "<g ",
  "a > b",
  '<circle r="1"//>',
  '<g  fill="red">',
  // entities that would spell "(" or "\" once the page reads them
  '<rect fill="url&#40;https://example.com/x)"/>',
  '<rect fill="url&lpar;https://example.com/x)"/>',
  '<rect fill="u&#92;72l(https://example.com/x)"/>',
  // a "(" after a name that only ends like an allowed one
  '<rect fill="xrgb(1,2,3)"/>',
  '<rect fill="-rgb(1,2,3)"/>',
  '<g transform="aaaaaaaaaaaaaaaatranslate(1 2)">',
  '<g style="mix-blend-mode:url(x)">',
  '<g mask="url(#asobi-a) url(https://example.com/x)">'
];
result.attacks = attacks.length;
result.attacksPassed = attacks.filter((a) => Safe.markup(a) !== false);

// markup asobi does write
const fine = [
  "",
  '<g fill="gold"><circle r="10"/></g>',
  '<g transform="matrix(0.999 0.052 -0.052 0.999 20 0)"><rect x="-1" y="-1" width="2" height="2"/></g>',
  '<g fill="hsl(200, 80%, 50%)"><text text-anchor="middle" dominant-baseline="central" xml:space="preserve" font-family="&quot;a&quot; &amp; b" font-size="12">1 &lt; 2 &amp; 3</text></g>',
  '<defs><mask id="asobi-1x2y" maskUnits="userSpaceOnUse" style="mask-type:alpha" x="0" y="0" width="1" height="1"></mask></defs><rect fill="url(#asobi-ab12)" mask="url(#asobi-1x2y)"/>',
  '<g style="mix-blend-mode:screen"><!--asobi:p12--></g>'
];
result.fineRejected = fine.filter((f) => Safe.markup(f) !== true);

// (c) Reels that are not
const ok = { frames: ['<circle r="1"/>'], fps: 30, view: [0, 0, 1, 1], background: "white", code: "show circle", error: null };
const withBad = (extra) => Object.assign({}, ok, extra);
result.reelRejects = {
  notObject: Safe.reel("frames") === null && Safe.reel(null) === null && Safe.reel([ok]) === null,
  noFrames: Safe.reel(withBad({ frames: undefined })) === null && Safe.reel(withBad({ frames: [] })) === null,
  badFrame: Safe.reel(withBad({ frames: ['<g onclick="x">'] })) === null,
  protoPart: Safe.parse('{"frames":["<g/>"],"fps":30,"view":[0,0,1,1],"parts":{"__proto__":{"frames":["<g/>"]}}}') === null,
  badPartFrame: Safe.reel(withBad({ parts: { p1: { frames: ["<script>x</script>"] } } })) === null,
  urlBackground: Safe.reel(withBad({ background: "url(https://example.com/x)" })) === null,
  stringInView: Safe.reel(withBad({ view: [0, "0", 1, 1] })) === null,
  badFps: Safe.reel(withBad({ fps: 0 })) === null,
  notJson: Safe.parse("{") === null && Safe.parse(42) === null,
  throwing: (() => {
    const evil = {};
    Object.defineProperty(evil, "frames", { get() { throw new Error("no"); }, enumerable: true });
    try { return Safe.reel(evil) === null; } catch (e) { return false; }
  })()
};
const proto = Object.prototype.frames;
result.prototypeClean = proto === undefined && ({}).p1 === undefined;

// (d) songs: only the site's own
const foreign = Safe.reel(withBad({ song: { id: "x", src: "https://example.com/a.mp3" } }));
result.foreignSong = foreign ? { kept: true, song: foreign.song || null } : { kept: false };
const own = Safe.reel(withBad({ song: { id: "3ff79180f05b", src: "assets/beat.wav", volume: 0.5 } }));
result.ownSong = own ? own.song || null : null;

// (e) an error Reel keeps only error and code
result.errorReel = Safe.reel({ error: "boom", code: "show x", frames: ["<script>x</script>"], song: { src: "assets/a.wav" }, extra: 1 });

// a Reel that passes keeps only known fields
const parts = Safe.reel(withBad({ parts: { p1: { frames: ["<g/>"], turn: "click", sound: "pop", fps: 30, nope: "x", what: { a: 1 } } }, extra: "x", controls: false, pending: "yes" }));
result.partsCopy = parts ? { keys: Object.keys(parts).sort(), p1: parts.parts.p1 } : null;

console.log(JSON.stringify(result));
