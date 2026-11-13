// Checks the plain parts of the player (lib/asobi/web/player.js) in plain
// Node, without a browser: markers and copy numbers, value -> frame, the
// sound levels and the beat detector on made-up series.
//
//   node test/web/player-check.js lib/asobi/web/player.js
//
// Prints a JSON object; test/site_test.rb runs it and checks the answers.
"use strict";
const fs = require("fs");
const vm = require("vm");

const sandbox = {};
sandbox.window = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(process.argv[2], "utf8"), sandbox);
const P = sandbox.AsobiPlayer._internals;
const out = {};

// ---- composing a frame ------------------------------------------------------
// Top frame: two copies of p1, then one p2 that holds a p1 inside (nesting).
const reel = {
  frames: ["<a/><!--asobi:p1--><!--asobi:p1--><!--asobi:p2--><!--asobi:p9--><b/>"],
  parts: {
    p1: { frames: ["<i0/>", "<i1/>", "<i2/>"], fps: 30, turn: "click" },
    p2: { frames: ["<o0><!--asobi:p1--></o0>", "<o1><!--asobi:p1--></o1>"], turn: "value", from: "mic", what: "low" }
  }
};
const prep = P.prepare(reel);
// Copy k of p1 shows frame k; p2 shows frame 1.
const c = P.compose(prep, 0, (id, k) => (id === "p1" ? k : 1));
out.compose = {
  html: c.pieces.join(""),
  copies: c.copies.map((x) => [x.id, x.k, x.idx, x.parent]),
  inner: c.copies.map((x) => c.pieces.slice(x.from + 1, x.to - 1).join("")),
  // a frame index out of range shows frame 0
  outOfRange: P.compose(prep, 0, () => 7).pieces.join(""),
  has: prep.has,
  noParts: P.prepare({ frames: ["<g/>"] }),
  sameShape: P.sameShape(c, P.compose(prep, 0, () => 0)),
  // a cycle (p1 holds p1) stops at the depth limit instead of hanging
  cycle: P.compose(P.prepare({ frames: ["<!--asobi:p1-->"], parts: { p1: { frames: ["x<!--asobi:p1-->"], turn: "click" } } }), 0, () => 0).copies.length
};

// ---- numbers -> frames ------------------------------------------------------
out.valueIndex = [-1, 0, 0.24, 0.26, 0.5, 0.99, 1, 2, NaN].map((v) => P.valueIndex(v, 5));
out.onceIndex = [0, 33, 66, 99, 100, 140].map((ms) => P.onceIndex(1000, 1000 + ms, 30, 3));

// ---- beats on an onset series (dB the low bins rose, 60 frames a second, 10 s) --
function beats(onset) {
  const detect = P.makeBeat();
  let n = 0;
  for (let i = 0; i < 600; i++) if (detect(onset(i / 60, i), i / 60)) n++;
  return n;
}
let seed = 1;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const jitter = () => (rnd() - 0.5) * 0.06;
const kickAt = (i, every) => i % every === 0; // a kick on this frame
out.beats = {
  kicks120: beats((t, i) => (kickAt(i, 30) ? 28 : kickAt(i - 1, 30) ? 10 : 1)),
  // kicks with hats between them (onset 7) and small wobbles
  withHats: beats((t, i) => (kickAt(i, 30) ? 25 : kickAt(i - 15, 30) ? 7 : rnd() * 3)),
  silence: beats(() => 0),
  noise: beats(() => rnd() * 8),        // busy noise: wobbles only, no beats
  fast: beats((t, i) => (kickAt(i, 6) ? 30 : 0)) // 600 BPM: never closer than 0.2 s
};

// ---- the listener: dB series in, 0..1 out ------------------------------------
function listen(series, seconds) {
  const L = P.makeListener();
  const trace = [];
  for (let i = 0; i < seconds * 60; i++) {
    const t = i / 60;
    L.step(series(t), t, 1 / 60);
    trace.push({ volume: L.volume, low: L.low, mid: L.mid, high: L.high, pitch: L.pitch, beats: L.beats });
  }
  return trace;
}
const last = (trace) => trace[trace.length - 1];
const silent = { volume: -Infinity, low: -Infinity, mid: -Infinity, high: -Infinity, centre: 0, onset: 0 };
const loud = { volume: -12, low: -14, mid: -20, high: -30, centre: 300, onset: 1 };
out.listener = {
  silence: last(listen(() => silent, 3)),
  // music for 3 s, then silence: everything settles at exactly 0 except pitch,
  // which holds 2 s and then eases back to 0
  afterMusic: last(listen((t) => (t < 3 ? loud : silent), 3.5)),
  afterMusicLong: last(listen((t) => (t < 3 ? loud : silent), 8)),
  // a quiet room: noise around -62 dBFS with wobbles
  room: last(listen(() => { const n = -62 + jitter() * 60; return { volume: n, low: n - 3, mid: n - 4, high: n - 6, centre: 900, onset: rnd() * 8 }; }, 10)),
  // steady music: the volume sits high, the high band is weak but not 0
  steady: last(listen(() => loud, 3)),
  // attack is fast, release slower: frames to go from 0 to 0.9 and back to 0.1
  attack: (() => { const tr = listen((t) => (t < 1 ? silent : loud), 2); return tr.findIndex((x) => x.volume > 0.9) - 60; })(),
  release: (() => {
    const tr = listen((t) => (t < 2 ? loud : { volume: -40, low: -42, mid: -48, high: -58, centre: 300 }), 3);
    return tr.slice(120).findIndex((x) => x.volume < 0.1);
  })(),
  // a sweep 100 Hz -> 3000 Hz: pitch rises from near 0 to near 1
  sweep: (() => {
    const tr = listen((t) => ({ volume: -12, low: -12, mid: -12, high: -12, centre: 100 * Math.pow(30, t / 10) }), 10);
    return [0, 2, 4, 6, 8, 10].map((s) => +tr[Math.min(599, s * 60)].pitch.toFixed(2));
  })(),
  // 120 BPM kicks in the low band
  kickBeats: last(listen((t) => {
    const k = Math.exp(-((t % 0.5) / 0.12)), first = t % 0.5 < 1 / 60;
    const db = -10 + 20 * Math.log10(k);
    return { volume: db, low: db, mid: db - 15, high: -Infinity, centre: 60, onset: first ? 28 : 0 };
  }, 10)).beats,
  // the same kicks while the volume is below the room's noise: no beats
  quietKicks: last(listen((t) => ({ volume: -95, low: -95, mid: -99, high: -Infinity, centre: 60, onset: t % 0.5 < 1 / 60 ? 28 : 0 }), 10)).beats
};

// ---- asobi's own sound: which parts sound, which song a Reel plays -----------
out.sound = {
  partSound: [
    { turn: "click", sound: "pop" }, { turn: "key", note: 60 }, { turn: "beat", from: "music", sound: "bell" },
    { turn: "value", from: "mic", sound: "pop" },      // value parts never sound
    { turn: "click", sound: "boom" },                  // not one of the six: silent
    { turn: "click", note: 200 }, { turn: "hover" }
  ].map((d) => P.partSound(d)),
  hasSound: [
    P.prepare({ frames: ["x"], parts: { p1: { frames: ["a"], turn: "click", sound: "kick" } } }).has.sound,
    P.prepare({ frames: ["x"], parts: { p1: { frames: ["a"], turn: "click" } } }).has.sound
  ],
  songOf: [
    { song: { id: "3f9a0c2b7d1e", src: "/song/3f9a0c2b7d1e", volume: 0.5 } },
    { song: { id: "3f9a0c2b7d1e", src: "data:audio/mpeg;base64,AAAA" } }, // volume absent: 1
    { song: { id: "a", src: "x.mp3", volume: 7 } },                       // clamped
    { song: { id: "a" } }, {}
  ].map((r) => P.songOf(r))
};

console.log(JSON.stringify(out));
