// Checks a Reel off the stage's main thread: JSON.parse and AsobiSafeReel
// (the playground's own check, site/assets/safe-reel.js) over every frame.
// A big Reel (tens of MB) takes a second or more; done here, the 3D world
// and the picture keep moving meanwhile.
//   in:  { id, json }     out: { id, reel (checked, without its song) | null, ms }
import "../safe-reel.js";

self.onmessage = (e) => {
  const { id, json } = e.data || {};
  const t0 = performance.now();
  let reel = null;
  try {
    const r = self.AsobiSafeReel.parse(json);
    if (r && !r.error && r.frames) {
      delete r.song; // sound stays with the playground
      reel = r;
    }
  } catch { reel = null; }
  self.postMessage({ id, reel, ms: performance.now() - t0 });
};
