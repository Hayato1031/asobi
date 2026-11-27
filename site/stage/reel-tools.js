// A checked Reel, kept where it was checked (the stage's worker, reel-worker.js),
// and what the stage's main thread gets of it: a short description, and on
// request one frame (or a few, for measuring its extent) as a standalone svg
// Blob. A big Reel's frames are tens of MB of text; on the main thread they
// cost a long pause each time a Reel is replaced (the garbage collector), so
// they stay in the worker: Blob bytes live outside the JavaScript heap, and the
// main thread only ever turns them into an image (a blob: URL of type
// image/svg+xml). No DOM here: the worker and the main thread both use it.
import { stripGrain, restFrame, frameSvg, reelWithoutGrain } from "./svgframe.js";

// What the main thread needs to know about a checked Reel.
export function describe(reel) {
  return {
    view: reel.view.slice(),
    background: typeof reel.background === "string" ? reel.background : null,
    fps: Number(reel.fps) > 0 ? Number(reel.fps) : 1,
    n: reel.frames.length,
    parts: !!reel.parts,
    grain: stripGrain(reel.frames[0]).grain,
    frameBytes: reel.frames[0].length,
  };
}

// Frame i, reacting parts at rest, grain out, drawn over box at w x h, with
// its background (covering the box) or without.
export function frameBlob(reel, { i, box, withBackground, w, h }) {
  if (!(i >= 0 && i < reel.frames.length)) return null;
  const body = stripGrain(restFrame(reel.frames[i], reel.parts)).markup;
  const svg = frameSvg(body, reel.view, reel.background, withBackground, w, h, box);
  return new Blob([svg], { type: "image/svg+xml" });
}

// Frames overlaid in one picture without background, for measuring (extent.js).
export function probeBlob(reel, { indices, view, pw, ph }) {
  const body = indices.filter((i) => i >= 0 && i < reel.frames.length)
    .map((i) => `<g>${stripGrain(restFrame(reel.frames[i], reel.parts)).markup}</g>`).join("");
  return new Blob([frameSvg(body, reel.view, null, false, pw, ph, view)], { type: "image/svg+xml" });
}

// The Reel for the flat and side views' player, which wants its frames as
// text: without grain (the window lays it, grain.js), every frame as UTF-8
// in one buffer (offsets: where each starts; the last is the end), and the
// rest of the Reel as it is. The buffer is handed over (transferred), so the
// frames' text never lives on the main thread's JavaScript heap, where a big
// Reel's tens of MB of strings cost a long garbage-collection pause when the
// Reel is replaced; framesOf below reads a frame when the player asks for it.
export function playerPack(reel) {
  const { reel: bare, grain } = reelWithoutGrain(reel);
  const enc = new TextEncoder();
  const parts = bare.frames.map((f) => enc.encode(f));
  const offsets = new Uint32Array(parts.length + 1);
  for (let i = 0; i < parts.length; i++) offsets[i + 1] = offsets[i] + parts[i].length;
  const bytes = new Uint8Array(offsets[parts.length]);
  parts.forEach((p, i) => bytes.set(p, offsets[i]));
  const rest = { ...bare };
  delete rest.frames;
  return { rest, grain, bytes: bytes.buffer, offsets: offsets.buffer };
}

// A Reel for the player from a pack: its frames an array (Array.isArray holds)
// whose items are read from the buffer when asked for, one at a time (the
// strings are short-lived). Only length and indexing are used by the player
// (lib/asobi/web/player.js); nothing walks the whole array.
export function unpack(pack) {
  const bytes = new Uint8Array(pack.bytes), offsets = new Uint32Array(pack.offsets), dec = new TextDecoder();
  const n = offsets.length - 1;
  const frames = new Proxy([], {
    get(target, key) {
      if (key === "length") return n;
      if (typeof key === "string") {
        const i = Number(key);
        if (Number.isInteger(i) && i >= 0 && i < n && String(i) === key) return dec.decode(bytes.subarray(offsets[i], offsets[i + 1]));
      }
      return Reflect.get(target, key);
    },
    has(target, key) {
      if (typeof key === "string") { const i = Number(key); if (Number.isInteger(i) && i >= 0 && i < n && String(i) === key) return true; }
      return Reflect.has(target, key);
    },
  });
  return { ...pack.rest, frames, grainless: true, grain: pack.grain };
}

// The Reel as the main thread holds it: its description, and frames on request.
// ask(request) answers a promise of the Blob (null when the Reel is gone).
export class ReelSource {
  constructor(seq, about, ask) {
    Object.assign(this, about);
    this.seq = seq;
    this.ask = ask;
  }
  frameBlob(i, box, withBackground, w, h) { return this.ask({ type: "frame", seq: this.seq, i, box, withBackground, w, h }); }
  probeBlob(indices, view, pw, ph) { return this.ask({ type: "probe", seq: this.seq, indices, view, pw, ph }); }
}

// Without a worker: the same, the Reel held on the main thread.
export function localSource(seq, reel) {
  return new ReelSource(seq, describe(reel), (q) => Promise.resolve(q.type === "frame" ? frameBlob(reel, q) : probeBlob(reel, q)));
}
