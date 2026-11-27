// The stage's Reels, off its main thread. The playground posts each Reel's
// JSON on a channel of its own ("asobi-stage-reel"), which only this worker
// listens to: the text (tens of MB for a big Reel) never reaches the main
// thread, so neither do its copies or their garbage collection.
//
// Here the JSON is checked with AsobiSafeReel (the playground's own check,
// site/assets/safe-reel.js) and the checked Reel is kept (this one and the one
// before, which may still be playing while the new one is measured). The main
// thread gets a description and, on request, frames as svg Blobs
// (reel-tools.js); the flat and side views, whose player needs the frames as
// text, get them packed in one buffer (playerPack), handed over.
//
// To the main thread: { type: "ready" } once listening; { type: "reel", seq,
// frames, fps, parts, at, bytes } as a Reel comes; { type: "checked", seq,
// about | null, ms } once checked. From it: { id, type: "frame" | "probe" |
// "full", seq, ... } (answered { id, blob | reel | null }), and { type:
// "json", seq, json, ... } when it heard a Reel itself (no channel here).
import "../safe-reel.js";
import { describe, frameBlob, probeBlob, playerPack } from "./reel-tools.js";

const MAX_REEL = 96 * 1024 * 1024;
const kept = new Map(); // seq -> checked Reel (the newest two)

function take(m) {
  if (!m || m.type !== "reel" || typeof m.json !== "string" || m.json.length > MAX_REEL) return;
  const seq = typeof m.seq === "string" ? m.seq.slice(0, 80) : null;
  if (seq !== null && kept.has(seq)) return; // the same Reel again (a second stage said hello)
  self.postMessage({
    type: "reel", seq, bytes: m.json.length,
    frames: Number.isFinite(m.frames) ? m.frames : 1, fps: Number(m.fps) > 0 ? Number(m.fps) : 1,
    parts: m.parts === true, at: Number.isFinite(m.at) ? m.at : null,
  });
  const t0 = performance.now();
  let reel = null;
  try {
    const r = self.AsobiSafeReel.parse(m.json);
    if (r && !r.error && r.frames) {
      delete r.song; // sound stays with the playground
      reel = r;
    }
  } catch { reel = null; }
  if (reel) {
    kept.set(seq, reel);
    while (kept.size > 2) kept.delete(kept.keys().next().value);
  }
  self.postMessage({ type: "checked", seq, about: reel ? describe(reel) : null, ms: performance.now() - t0 });
}

let channel = null;
try {
  channel = new BroadcastChannel("asobi-stage-reel");
  channel.onmessage = (e) => take(e.data);
} catch { channel = null; }

self.onmessage = (e) => {
  const q = e.data || {};
  if (q.type === "json") { take({ ...q, type: "reel" }); return; }
  const reel = kept.get(q.seq);
  let answer = null;
  try {
    if (reel && q.type === "frame") answer = { blob: frameBlob(reel, q) };
    else if (reel && q.type === "probe") answer = { blob: probeBlob(reel, q) };
    else if (reel && q.type === "full") answer = { reel };
    else if (reel && q.type === "player") {
      const pack = playerPack(reel);
      self.postMessage({ id: q.id, pack }, [pack.bytes, pack.offsets]);
      return;
    }
  } catch { answer = null; }
  self.postMessage({ id: q.id, ...(answer || { blob: null, reel: null }) });
};

self.postMessage({ type: "ready", listening: !!channel });
