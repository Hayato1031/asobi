// How far a Reel's drawing reaches past its paper, for the 3D art.
//
// A sketch may draw past its paper (the galaxy's disc above and below its
// 480 x 270, seigaiha's rows on every side); the playground and the flat
// views show that, so the 3D sheet must not cut it. The sheet is drawn with
// its viewBox widened to the EXTENT: the paper and everything drawn around it.
//
// Measured by pixels, not by getBBox, so glows and stroke widths count: a few
// frames (the first and up to 11 more spread over the loop; reacting parts at
// rest; no grain, no background) are drawn small into a probe three papers
// wide and tall (the paper in the middle), and the box of their visible
// pixels is taken. If the drawing reaches the probe's edge, the probe grows
// to seven papers once. Then the box is padded a little and joined with the
// paper, and kept within CAP papers in each direction.
//
// Each probe waits for idle time and draws one small image, so the 3D frames
// keep their pace. An svg drawn as an image is a whole document of its own
// (page, frame, DOM), and tearing those down is what the garbage collector
// spends long pauses on: so several sample frames are drawn into one probe
// (overlaid: the union is what is measured), and a heavy Reel samples fewer
// frames (about MAX_MARKUP of markup in all, never fewer than MIN_SAMPLES).
// The pure part (extentOf) has no DOM and is checked in Node
// (test/web/stage-check.mjs).

export const SAMPLES = 12;       // frames looked at: the first, then spread over the loop
const MIN_SAMPLES = 4;           // ... at least this many, however heavy the frames
const MAX_MARKUP = 1 << 20;      // ... and about this much markup in all (characters)
const PER_PROBE = 200 * 1024;    // markup drawn in one probe image (one document): its load is one task
export const PROBE = [3, 7];     // the probe, in papers across (paper centred); the second only if needed
const PROBE_PX = [384, 512];     // its longer side, in pixels
export const CAP = 6;            // the extent is at most this many papers wide and tall (paper centred)
const ALPHA = 4;                 // a pixel counts as drawn from this alpha (of 255)
const SNAP_PX = 1.5;             // a drawing that leaves the paper by less (probe px: edge smoothing) does not spill
const PAD_PX = 2;                // padding beyond the measured box, in probe px ...
const BAND = 0.03;               // ... plus this share of the drawing's size: the outer band that fades

// The paper as an extent (nothing past it).
export function plainExtent(view) {
  return { paper: view.slice(), box: view.slice(), bands: [0, 0, 0, 0], spills: false };
}

// The probe for a paper: `across` papers wide and tall, the paper in the
// middle, drawn `long` pixels along its longer side.
export function probeOf(view, across, long) {
  const [x, y, w, h] = view;
  const pw = w >= h ? long : Math.max(1, Math.round(long * w / h));
  const ph = w >= h ? Math.max(1, Math.round(long * h / w)) : long;
  const k = (across - 1) / 2;
  return { view: [x - k * w, y - k * h, w * across, h * across], pw, ph, across };
}

// The extent from the box of drawn pixels in a probe (bbox: [x0, y0, x1, y1]
// in probe pixels, x1/y1 exclusive; null when nothing was drawn).
// Answers { paper, box (user units), bands ([left, right, top, bottom], the
// widths that fade, user units; 0 where the extent is the paper's edge),
// spills, touches (the drawing reached the probe's edge) }.
export function extentOf(bbox, probe, view) {
  const out = plainExtent(view);
  if (!bbox) return { ...out, touches: false };
  const [px, py, pw] = probe.view, s = probe.pw / pw; // pixels per user unit
  const touches = bbox[0] <= 0 || bbox[1] <= 0 || bbox[2] >= probe.pw || bbox[3] >= probe.ph;
  // The drawing, in user units.
  const d = [px + bbox[0] / s, py + bbox[1] / s, px + bbox[2] / s, py + bbox[3] / s];
  const [x, y, w, h] = view;
  const paper = [x, y, x + w, y + h];
  const snap = SNAP_PX / s;
  const band = BAND * Math.max(d[2] - d[0], d[3] - d[1]);
  const pad = band + PAD_PX / s;
  const lim = [x - (CAP - 1) / 2 * w, y - (CAP - 1) / 2 * h, x + (CAP + 1) / 2 * w, y + (CAP + 1) / 2 * h];
  // Per side: past the paper by more than the smoothing of an edge, padded, within the cap.
  const e = [
    d[0] < paper[0] - snap ? Math.max(lim[0], d[0] - pad) : paper[0],
    d[1] < paper[1] - snap ? Math.max(lim[1], d[1] - pad) : paper[1],
    d[2] > paper[2] + snap ? Math.min(lim[2], d[2] + pad) : paper[2],
    d[3] > paper[3] + snap ? Math.min(lim[3], d[3] + pad) : paper[3],
  ];
  // The band that fades: never wider than what lies past the paper on that side.
  const bands = [
    Math.min(band, paper[0] - e[0]), Math.min(band, e[2] - paper[2]),
    Math.min(band, paper[1] - e[1]), Math.min(band, e[3] - paper[3]),
  ];
  const spills = bands.some((b) => b > 0) || e[0] < paper[0] || e[1] < paper[1] || e[2] > paper[2] || e[3] > paper[3];
  if (!spills) return { ...out, touches };
  return { paper: view.slice(), box: [e[0], e[1], e[2] - e[0], e[3] - e[1]], bands, spills: true, touches };
}

// The box of pixels with alpha in an RGBA buffer of w x h, or null.
export function alphaBox(data, w, h, min = ALPHA) {
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) {
    const row = y * w * 4;
    let first = -1, last = -1;
    for (let x = 0; x < w; x++) if (data[row + x * 4 + 3] >= min) { if (first < 0) first = x; last = x; }
    if (first < 0) continue;
    if (first < x0) x0 = first;
    if (last > x1) x1 = last;
    if (y < y0) y0 = y;
    y1 = y;
  }
  return x1 < 0 ? null : [x0, y0, x1 + 1, y1 + 1];
}

function union(a, b) {
  if (!a) return b;
  if (!b) return a;
  return [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];
}

// The frames looked at: the first, and up to count - 1 more spread evenly.
export function samples(n, count = SAMPLES) {
  const out = [0];
  const more = Math.min(count - 1, n - 1);
  for (let k = 1; k <= more; k++) out.push(Math.round((k * n) / (more + 1)) % n);
  return [...new Set(out)];
}

// ---- in the browser ---------------------------------------------------------
import { far, drawHere } from "./far-raster.js";

const idle = () => new Promise((done) => {
  if (typeof requestIdleCallback === "function") requestIdleCallback(() => done(), { timeout: 250 });
  else setTimeout(done, 16);
});

let canvas = null;

// Measures a checked Reel's extent (see the top), from its source
// (reel-tools.js: the worker makes each probe's svg). stillWanted() is asked
// between probes: answer false to give up (another Reel, the 3D view left).
// Answers the extent, or null when given up. stats gets the costs.
export async function measureExtent(reel, stillWanted, stats = {}) {
  const t0 = performance.now();
  stats.busyMs = 0; stats.probes = 0;
  const view = reel.view, bytes = Math.max(1, reel.frameBytes);
  // Fewer samples for heavy frames (frame 0's size stands for all).
  const count = Math.max(MIN_SAMPLES, Math.min(SAMPLES, Math.floor(MAX_MARKUP / bytes)));
  const picks = samples(reel.n, count);
  // Sample frames grouped into probes of about PER_PROBE markup each.
  const per = Math.max(1, Math.floor(PER_PROBE / bytes));
  const groups = [];
  for (let k = 0; k < picks.length; k += per) groups.push(picks.slice(k, k + per));
  stats.samples = picks.length;
  for (let pass = 0; pass < PROBE.length; pass++) {
    const probe = probeOf(view, PROBE[pass], PROBE_PX[pass]);
    let box = null;
    for (const group of groups) {
      await idle();
      if (!stillWanted()) return null;
      const blob = await reel.probeBlob(group, probe.view, probe.pw, probe.ph);
      if (!stillWanted()) return null;
      if (!blob) continue;
      // Drawn in the rasteriser's own process (far-raster.js), here when it is not there.
      const bitmap = (await far.bitmap(blob, false)) || (await drawHere(blob, false));
      if (!bitmap) continue; // a frame that does not draw tells nothing: the others decide
      try {
        await idle();
        if (!stillWanted()) return null;
        const b0 = performance.now();
        if (!canvas) canvas = document.createElement("canvas");
        if (canvas.width !== probe.pw || canvas.height !== probe.ph) { canvas.width = probe.pw; canvas.height = probe.ph; }
        const g = canvas.getContext("2d", { willReadFrequently: true });
        g.clearRect(0, 0, probe.pw, probe.ph);
        g.drawImage(bitmap, 0, 0, probe.pw, probe.ph);
        box = union(box, alphaBox(g.getImageData(0, 0, probe.pw, probe.ph).data, probe.pw, probe.ph));
        stats.busyMs += performance.now() - b0;
        stats.probes++;
      } finally {
        bitmap.close();
      }
    }
    const ext = extentOf(box, probe, view);
    stats.across = probe.across;
    if (!ext.touches || pass === PROBE.length - 1) {
      stats.ms = performance.now() - t0;
      return ext;
    }
  }
  return null;
}
