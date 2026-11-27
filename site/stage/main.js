// asobi stage window: the playground's code and picture, shown big for a
// projector: flat (0), or floating in a three.js world: Uyuni at dusk (1),
// the fog stage (2); or side by side (3): the code beside the picture, the
// whole window in the picture's own background colour.
//
// The playground keeps running Ruby, reactions and sound. It sends this window
// (BroadcastChannel "asobi-stage") the code as it is typed, the error, and the
// Reel it shows (without its song). This window plays that Reel by its own
// clock, with its own copy of the site's player (flat) or with frames drawn
// ahead of time (3D, see frames.js), so the picture moves at an even rhythm
// and never waits on the playground. Only a Reel with reacting parts (click,
// hover, key, sound...) is mirrored instead: the playground then also sends a
// snapshot of its player's <svg> whenever it changes, so a click there shows
// here. While the playground is hidden (its animation frames stop), or gone,
// such a Reel plays here too, its parts at rest.
//
// Stage -> playground: hello { seq } (at start, and whenever the playground
// has gone quiet; seq names the Reel this window has, so a big Reel is sent
// once, not on every hello), here (every 2 s), bye (pagehide).
// Playground -> stage: setup { hidden }, code, error, picture (Reels with
// parts only), visibility { hidden }, bye; and reel { seq, json, frames, fps,
// parts } on a channel of its own ("asobi-stage-reel"), which only this
// window's worker hears (reel-worker.js): a big Reel's text (tens of MB) never
// comes to this thread, where its copies and their garbage collection stopped
// the picture for a moment. The worker checks the Reel and keeps it; here
// there is its description, frames as svg Blobs on request (the 3D views),
// or the whole checked Reel when the flat and side views' player needs it.
//
// Trust: the code comes from a URL anyone can write. A Reel goes through
// AsobiSafeReel (the playground's own check: only the SVG asobi writes) before
// anything of it is drawn. The flat player then puts its frames on this page,
// exactly as the playground does, under the same CSP; in 3D a frame is only
// ever loaded as an image (blob: URL, image/svg+xml), as is a mirrored
// picture. Code and error text are drawn with canvas fillText or set with
// textContent. The side view's colours are read from the background with a
// canvas (fillStyle takes only a colour), never put into a style as written.
import { Raster } from "./raster.js";
import { Flat } from "./flat.js";
import { Subtitles } from "./subtitles.js";
import { SideCode } from "./side.js";
import { paletteOn } from "./code.js";
import { stripGrain, withoutBackground, withViewBox, withBackgroundBox } from "./svgframe.js";
import { ReelSource, localSource, unpack } from "./reel-tools.js";
import { plainExtent } from "./extent.js";

const MODES = ["flat", "uyuni", "fog", "side"];
const KEYS = { 0: "flat", 1: "uyuni", 2: "fog", 3: "side" };
// Flat and side both show the picture on this page (Flat: the player or the
// mirrored images); 1 and 2 are the three.js worlds.
const flatLike = (m) => m === "flat" || m === "side";
const HEARTBEAT_MS = 2000;
const QUIET_MS = 6000;       // no word from a playground for this long: waiting again
const PROBE_MS = 3900;       // quiet this long: ask again (a still picture sends nothing)
const MAX_SVG = 32 * 1024 * 1024;
const MAX_REEL = 96 * 1024 * 1024;
const MAX_CODE = 200000;

const TEXT = {
  en: {
    say: "Waiting for the playground",
    how: "Open this window from the playground’s “Stage window” button. Code and picture appear here as you write.",
    go: "Open the playground",
    flat: "Flat", uyuni: "Uyuni", fog: "Fog", side: "Side", code: "Code", bg: "Background", full: "Full screen",
    live: "Connected", wait: "Waiting", here: "Playing here",
  },
  ja: {
    say: "遊び場を待っています",
    how: "遊び場の「別ウィンドウ」ボタンから開いてください。書いたコードと絵がここに映ります。",
    go: "遊び場を開く",
    flat: "平面", uyuni: "ウユニ", fog: "霧", side: "並べる", code: "コード", bg: "背景", full: "全画面",
    live: "接続中", wait: "待機中", here: "ここで再生中",
  },
};

// ---- state ------------------------------------------------------------------
const params = new URLSearchParams(location.search);
const urlLang = ["ja", "en"].includes(params.get("lang")) ? params.get("lang") : null;
let lang = urlLang || ((navigator.language || "").toLowerCase().startsWith("ja") ? "ja" : "en");
let playgroundUrl = null;
let words = [];
let code = null;
let error = null;
let latest = null;            // the newest mirrored picture { svg, view, background }
let connected = false;
let lastHeard = 0;
let probed = false;
let freshCode = true;         // the next code just appears (no flash): first after (re)connecting
let mode = null;
let codeOn = true;
let withBackground = true;    // the B key: the picture's own background, or none
let stage3d = null;
let loading3d = null;
let switchToken = 0;
// The Reel the playground shows: what came with it, and once checked its
// source (reel-tools.js; null when it did not pass) and, if the player asked,
// the whole checked Reel.
let reel = { have: false, seq: null, frames: 1, fps: 1, parts: false, source: undefined, full: null, fullPending: null, waiting: [] };
let playgroundHidden = false;
let lastPicture = 0;          // when the playground's last picture came
let reelAt = 0;               // when its last Reel came
let driving = false;          // playing the Reel here (else: mirroring the playground's pictures)
const stats = { reelBytes: 0, reelTransferMs: null, reelParseMs: null, reels: 0, driveStarts: 0, mirrored: 0 };

const el = {
  world: document.getElementById("world"),
  flat: document.getElementById("flat"),
  subs: document.getElementById("subs"),
  beside: document.getElementById("beside"),
  note: document.getElementById("note"),
  bar: document.getElementById("bar"),
  black: document.getElementById("black"),
};
const flatTimes = [];
const flat = new Flat(el.flat, () => { flatTimes.push(performance.now()); if (flatTimes.length > 4096) flatTimes.splice(0, 1024); });
const subs = new Subtitles(el.subs);
const beside = new SideCode(el.beside);
flat.onBackground = () => paintSide();
const raster = new Raster((source, info) => {
  if (!stage3d || flatLike(mode) || driving) return false;
  raster.spent(stage3d.setPicture(source, info));
  return true;
});

// ---- the channel ------------------------------------------------------------
let channel = null;
try { channel = new BroadcastChannel("asobi-stage"); } catch { channel = null; }
function post(message) { try { channel && channel.postMessage(message); } catch { /* closed: nothing to say */ } }

// hello says which Reel this window has, so the playground resends it only when it changed.
function hello() { post({ type: "hello", seq: reel.seq }); }

// The Reel's own channel, heard here only when there is no worker to hear it.
let reelChannel = null;
function hearReelsHere() {
  if (reelChannel) return;
  try { reelChannel = new BroadcastChannel("asobi-stage-reel"); reelChannel.onmessage = (e) => reelText(e.data); } catch { reelChannel = null; }
}

if (channel) {
  channel.onmessage = (e) => hear(e.data);
  hello();
  setInterval(heartbeat, HEARTBEAT_MS);
  addEventListener("pagehide", () => post({ type: "bye" }));
  addEventListener("pageshow", (e) => { if (e.persisted) hello(); });
  // A hidden window's timers slow right down; say hello as soon as it is back.
  document.addEventListener("visibilitychange", () => { if (!document.hidden) hello(); });
  setInterval(watchdog, 100);
}

function heartbeat() {
  const quiet = performance.now() - lastHeard;
  if (connected && quiet > QUIET_MS) setConnected(false);
  if (connected && quiet > PROBE_MS && !probed) { probed = true; hello(); return; }
  if (connected) post({ type: "here" }); else hello();
}

function hear(m) {
  if (!m || typeof m !== "object" || typeof m.type !== "string") return;
  if (m.type === "hello" || m.type === "here") return; // another stage window
  if (m.type === "bye") { setConnected(false); return; }
  lastHeard = performance.now();
  probed = false;
  if (!connected) setConnected(true);
  if (m.type === "setup") onSetup(m);
  else if (m.type === "code") onCode(m);
  else if (m.type === "error") onError(m);
  else if (m.type === "picture") onPicture(m);
  else if (m.type === "reel") reelText(m); // a playground without the Reel channel
  else if (m.type === "visibility") onVisibility(m.hidden);
}

function setConnected(on) {
  connected = on;
  if (!on) freshCode = true;
  // Gone or silent: the last Reel goes on playing here instead of freezing.
  if (!on) startDriving();
  // With a picture still on show, the note steps aside to the top.
  el.note.classList.toggle("small", !!(latest || code !== null));
  el.note.hidden = on;
  renderBar();
}

// setup comes again with every hello; only what changed is redone.
function onSetup(m) {
  if (Array.isArray(m.words)) {
    const next = m.words.filter((w) => typeof w === "string" && /^[A-Za-z_][\w?!]{0,40}$/.test(w)).slice(0, 1000);
    if (next.join(" ") !== words.join(" ")) {
      words = next;
      if (stage3d) stage3d.setWords(words);
      subs.setWords(words);
      beside.setWords(words);
    }
  }
  let changed = false;
  if (!urlLang && (m.lang === "ja" || m.lang === "en") && m.lang !== lang) { lang = m.lang; changed = true; }
  // Only a page of this site may be linked (never javascript: or elsewhere).
  if (typeof m.playground === "string") {
    try {
      const u = new URL(m.playground, location.href);
      if (u.origin === location.origin && /^https?:$/.test(u.protocol) && u.href !== playgroundUrl) { playgroundUrl = u.href; changed = true; }
    } catch { /* not a URL: keep the default link */ }
  }
  if (changed) renderText();
  if (typeof m.hidden === "boolean") onVisibility(m.hidden);
}

function onCode(m) {
  if (typeof m.code !== "string") return;
  code = m.code.slice(0, MAX_CODE);
  if (stage3d) stage3d.setCode(code, freshCode);
  subs.setCode(code, freshCode);
  beside.setCode(code, freshCode);
  freshCode = false;
}

function onError(m) {
  error = typeof m.error === "string" && m.error ? m.error.slice(0, 4000) : null;
  if (stage3d) stage3d.setError(error);
  subs.setError(error);
  beside.setError(error);
}

// A picture from the playground (sent for a Reel with reacting parts only).
// While this window plays the Reel itself, a hidden playground's picture is
// out of date (it answers a hello with what it last drew): only a visible
// playground's new picture takes over again.
function onPicture(m) {
  lastPicture = performance.now();
  if (reel.have && !reel.parts) return; // a Reel without parts always plays here
  if (driving) {
    if (playgroundHidden || !connected) return;
    stopDriving();
  }
  stats.mirrored++;
  const svg = m.svg, v = m.view;
  if (typeof svg !== "string" || svg.length > MAX_SVG) return;
  if (!Array.isArray(v) || v.length !== 4 || !v.every(Number.isFinite) || v[2] <= 0 || v[3] <= 0) return;
  if (latest && latest.svg === svg) return;
  const background = typeof m.background === "string" ? m.background.slice(0, 80) : "";
  latest = { svg, view: v.slice(), background };
  showMirrored();
}

// The newest mirrored picture, flat (or side) or into 3D.
function showMirrored() {
  if (!latest || driving) return;
  if (flatLike(mode)) { flat.show(latest.svg, latest.background, latest.view); return; }
  if (!stage3d) return;
  stage3d.mirror();
  stage3d.setDark(isDark(latest.background));
  // The Reel behind these pictures (it has reacting parts): its extent, once
  // measured, widens them, so what was drawn past the paper shows.
  if (reel.have && reel.parts) withChecked((r) => stage3d.watchMirrorReel(r));
  const ext = stage3d.mirrorExtent(latest.view) || plainExtent(latest.view);
  // A little more than on screen (mipmaps keep it crisp); on a dense screen as much as on screen.
  raster.aim(stage3d.artPixels() * (stage3d.ratio >= 1.5 ? 1.05 : 1.5));
  raster.pressure = stage3d.pressure();
  // The grain goes to the GPU; without the background (B) only the background <rect> goes.
  const g = stripGrain(latest.svg);
  let svg = withBackground ? g.markup : withoutBackground(g.markup);
  // Over the extent; its background (B on) covers all of it, as in the frames drawn here.
  if (ext.spills) svg = withViewBox(withBackground ? withBackgroundBox(svg, ext.box) : svg, ext.box);
  raster.push(svg, ext.box, g.grain, ext);
}

// Whether a background colour is dark (for the light around the art). None
// (or one we cannot read) counts as white, asobi's default.
const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
const darkness = new Map();
const papers = new Map();
function isDark(background) {
  if (darkness.has(background)) return darkness.get(background);
  let rgb = [255, 255, 255];
  if (background && background !== "none" && background !== "transparent") {
    probe.clearRect(0, 0, 1, 1);
    probe.fillStyle = "#ffffff";
    probe.fillStyle = background; // an invalid colour is ignored and white stays
    probe.fillRect(0, 0, 1, 1);
    const d = probe.getImageData(0, 0, 1, 1).data;
    if (d[3] > 0) rgb = [d[0], d[1], d[2]];
  }
  const dark = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255 < 0.25;
  darkness.set(background, dark);
  return dark;
}

// The colour a background makes on the window, [r, g, b]: drawn over white,
// so a see-through one gives what it looks like over asobi's default white.
// None, transparent, currentcolor (no fixed colour here) or anything that is
// not a colour: white.
function paperOf(background) {
  if (papers.has(background)) return papers.get(background);
  probe.clearRect(0, 0, 1, 1);
  probe.fillStyle = "#ffffff";
  probe.fillRect(0, 0, 1, 1);
  if (background && !/^\s*currentcolor\s*$/i.test(background)) {
    probe.fillStyle = background; // an invalid colour is ignored and white stays
    probe.fillRect(0, 0, 1, 1);
  }
  const d = probe.getImageData(0, 0, 1, 1).data;
  const rgb = [d[0], d[1], d[2]];
  if (papers.size > 200) papers.clear();
  papers.set(background, rgb);
  return rgb;
}

// The side view: the whole window in the colour of the picture on show
// (its art boxes are see-through there, see stage.css), and the code's
// palette picked for that colour. Other modes: as before.
function paintSide() {
  const on = mode === "side";
  el.flat.classList.toggle("side", on);
  if (on) {
    const rgb = paperOf(flat.background);
    el.flat.style.backgroundColor = `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`;
    el.flat.style.setProperty("--ground", el.flat.style.backgroundColor); // the fade toward the code
    beside.setPalette(paletteOn(rgb));
  } else {
    el.flat.style.backgroundColor = "";
  }
  beside.show(on);
  flat.layout(); // the art's boxes changed: the grain's specks and a mirrored picture follow
}

// ---- playing the Reel here ----------------------------------------------------
// A new Reel (told by the worker, which has its text).
function onReel(m) {
  reel = {
    have: true,
    seq: typeof m.seq === "string" ? m.seq.slice(0, 80) : null,
    frames: Number.isFinite(m.frames) ? m.frames : 1,
    fps: Number(m.fps) > 0 ? Number(m.fps) : 1,
    parts: m.parts === true,
    source: undefined,    // once checked: its source, or null when it did not pass
    full: null,           // the whole checked Reel, once the player asked for it
    fullPending: null,
    waiting: [],          // what waits for the check
  };
  stats.reels++;
  stats.reelBytes = Number(m.bytes) || 0;
  stats.reelTransferMs = Number.isFinite(m.at) ? Date.now() - m.at : null;
  lastPicture = reelAt = performance.now(); // a new Reel: give its pictures a moment to start
  // A Reel without parts always plays here; one with parts only while the playground cannot show it.
  if (driving) playHere();
  else if (!reel.parts || playgroundHidden || !connected) startDriving();
}

// The checked Reel (the worker checked it, as the playground does, without
// its song): its source, for the 3D views.
function onChecked(m, here) {
  if (m.seq !== reel.seq) return;
  const r = reel;
  stats.reelParseMs = Number(m.ms) || 0;
  if (here) { r.source = here ? localSource(r.seq, here) : null; r.full = here; }
  else r.source = m.about ? new ReelSource(r.seq, m.about, (q) => ask(q).then((a) => (a && a.blob) || null)) : null;
  const fns = r.waiting;
  r.waiting = [];
  if (r.source) for (const fn of fns) fn(r.source);
}

// fn(source) once the Reel is checked (at once if it is).
function withChecked(fn) {
  const r = reel;
  if (!r.have) return;
  if (r.source !== undefined) { if (r.source) fn(r.source); return; }
  r.waiting.push((x) => { if (r === reel) fn(x); });
}

// fn(reel) with the whole checked Reel, for the player (flat and side): it
// needs the frames as text, so they come over from the worker (once per
// Reel), packed in one buffer (reel-tools.js unpack): the text stays off this
// thread's JavaScript heap, so a big Reel being replaced costs no long pause.
function withFull(fn) {
  const r = reel;
  withChecked(() => {
    if (r.full) { fn(r.full); return; }
    if (!r.fullPending) r.fullPending = ask({ type: "player", seq: r.seq }).then((a) => { r.full = a && a.pack ? unpack(a.pack) : null; return r.full; });
    r.fullPending.then((x) => { if (x && r === reel) fn(x); });
  });
}

// A Reel's text heard on this thread (no worker, or a playground without the
// Reel channel): to the worker if there is one, else checked here.
function reelText(m) {
  if (!m || typeof m.json !== "string" || m.json.length > MAX_REEL) return;
  if (checker) { checker.postMessage({ ...m, type: "json" }); return; }
  const seq = typeof m.seq === "string" ? m.seq.slice(0, 80) : null;
  if (seq !== null && seq === reel.seq) return;
  onReel({ ...m, seq, bytes: m.json.length });
  const t0 = performance.now();
  let x = null;
  try { x = window.AsobiSafeReel ? AsobiSafeReel.parse(m.json) : null; } catch { x = null; }
  if (x && !x.error && x.frames) delete x.song; else x = null; // sound stays with the playground
  onChecked({ seq, ms: performance.now() - t0 }, x);
  if (!x) reel.source = null;
}

// The worker (reel-worker.js): it hears the Reels, checks and keeps them, and
// answers asks for frames ({ id, ... } -> { id, blob | reel }).
let checker = null, asks = 0;
const asking = new Map();
function ask(q) {
  if (!checker) return Promise.resolve(null);
  const id = ++asks;
  return new Promise((done) => { asking.set(id, done); checker.postMessage({ ...q, id }); });
}
try {
  checker = new Worker(new URL("./reel-worker.js", import.meta.url), { type: "module" });
  checker.onmessage = (e) => {
    const d = e.data || {};
    if (d.type === "ready") {
      if (!d.listening) hearReelsHere(); // no channel in the worker: hear here, hand over
      hello(); // a Reel sent before the worker listened comes again
    } else if (d.type === "reel") onReel(d);
    else if (d.type === "checked") onChecked(d);
    else { const w = asking.get(d.id); asking.delete(d.id); if (w) w(d); }
  };
  checker.onerror = () => {
    checker = null;
    for (const w of asking.values()) w(null);
    asking.clear();
    hearReelsHere();
  };
} catch { checker = null; }
if (!checker) hearReelsHere();

function onVisibility(hidden) {
  playgroundHidden = !!hidden;
  // Hidden: play here at once. Visible again: the next new picture takes over (onPicture).
  if (playgroundHidden) startDriving();
}

// A Reel with parts whose pictures stopped although it moves (a hidden
// window that never said so): play here. A still Reel, or one whose parts
// only react, sends nothing while nobody touches it, and that is fine.
function watchdog() {
  if (driving || !connected || !reel.have || !reel.parts || reel.frames < 2) return;
  const now = performance.now();
  // Just after a new Reel the playground may be busy (a big one takes a moment
  // to start), so wait longer then.
  const limit = Math.max(now - reelAt < 3000 ? 2000 : 400, 2500 / reel.fps);
  if (now - lastPicture > limit) startDriving();
}

function startDriving() {
  if (driving || !reel.have) return;
  driving = true;
  stats.driveStarts++;
  playHere();
  renderBar();
}

// The Reel into this window's player (flat, side: the whole checked Reel) or
// the frames of the 3D art (its source). Until then what is on show stays.
function playHere() {
  if (flatLike(mode)) {
    withFull((r) => { if (driving && flatLike(mode)) flat.play(r, lang); });
    return;
  }
  withChecked((src) => {
    if (!driving || flatLike(mode) || !stage3d || !mode) return;
    stage3d.setDark(isDark(src.background));
    stage3d.playReel(src);
  });
}

function stopDriving() {
  if (!driving) return;
  driving = false;
  renderBar();
}

// ---- modes ------------------------------------------------------------------
// The address keeps the mode and, after "&", the background: #uyuni, #fog&bg=off.
function modeFromHash() {
  const h = location.hash.replace(/^#/, "").split("&")[0];
  return MODES.includes(h) ? h : "uyuni";
}
function backgroundFromHash() { return !/(^|&)bg=off\b/.test(location.hash.replace(/^#/, "")); }
function writeHash() {
  history.replaceState(null, "", `${location.pathname}${location.search}#${mode}${withBackground ? "" : "&bg=off"}`);
}

async function get3d() {
  if (stage3d) return stage3d;
  if (!loading3d) {
    loading3d = import("./stage3d.js").then(({ Stage3D }) => {
      const s = new Stage3D(el.world);
      s.setWords(words);
      if (code !== null) s.setCode(code, true);
      s.setError(error);
      s.showCode(codeOn);
      s.setBackgroundOn(withBackground);
      s.onExtent = () => showMirrored(); // the mirrored Reel's extent arrived: draw the picture over it
      stage3d = s;
      return s;
    });
  }
  return loading3d;
}

async function setMode(next, instant = false) {
  if (next === mode) return;
  const token = ++switchToken;
  el.black.classList.remove("clear");
  if (!instant) await wait(190);
  if (token !== switchToken) return;
  mode = next;
  renderBar();
  if (flatLike(next)) {
    if (stage3d) stage3d.stop();
    // Laid out for this mode at once (no glide while the screen is black).
    el.flat.classList.add("still");
    el.flat.hidden = false;
    paintSide();
    if (driving) playHere();
    // Wait (a little) for a mirrored picture, so the black lifts onto it.
    else if (latest) await Promise.race([flat.show(latest.svg, latest.background, latest.view), wait(400)]);
    if (token !== switchToken) return;
  } else {
    let s;
    try {
      s = await get3d();
    } catch (err) {
      // No WebGL (or the module failed): fall back to the flat picture.
      console.error("asobi stage: 3D is not available here", err);
      mode = null;
      setMode("flat", true);
      return;
    }
    if (token !== switchToken) return;
    el.flat.hidden = true;
    paintSide();
    flat.stop();
    s.setWorld(next);
    if (driving) playHere(); else showMirrored();
    s.warm();
    s.start();
  }
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (token !== switchToken) return;
    el.flat.classList.remove("still");
    el.black.classList.add("clear");
  }));
}

function go(next) {
  if (!MODES.includes(next)) return;
  history.replaceState(null, "", `${location.pathname}${location.search}#${next}${withBackground ? "" : "&bg=off"}`);
  setMode(next);
}

addEventListener("hashchange", () => {
  if (backgroundFromHash() !== withBackground) toggleBackground();
  setMode(modeFromHash());
});

// ---- keys, mouse, the bar ---------------------------------------------------
function toggleCode() {
  codeOn = !codeOn;
  if (stage3d) stage3d.showCode(codeOn);
  el.subs.classList.toggle("off", !codeOn);
  el.flat.classList.toggle("nocode", !codeOn); // side: the art glides to the middle
  renderBar();
}

// B: the picture with its own background (as written), or without it: only
// the background <rect> goes, never anything the sketch drew. In 3D only;
// flat always shows the picture as the live view does, and in side the whole
// window is the picture's background already.
function toggleBackground() {
  withBackground = !withBackground;
  if (stage3d) stage3d.setBackgroundOn(withBackground);
  if (!driving) showMirrored();
  if (mode) writeHash();
  renderBar();
}

function toggleFull() {
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  else document.documentElement.requestFullscreen().catch(() => {});
}

// Caught first (capture) and kept from going further: the flat player must
// not take these keys as reactions (its parts rest).
addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
  const k = e.key.toLowerCase();
  if (KEYS[k]) go(KEYS[k]);
  else if (k === "c") toggleCode();
  else if (k === "b" && !flatLike(mode)) toggleBackground();
  else if (k === "f") toggleFull();
  else return;
  e.preventDefault();
  wake();
}, true);

let idleTimer = 0;
function wake() {
  el.bar.classList.add("on");
  document.body.classList.remove("idle");
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    el.bar.classList.remove("on");
    document.body.classList.add("idle");
  }, 2500);
}
addEventListener("pointermove", wake);
addEventListener("pointerdown", wake);

function renderBar() {
  const t = TEXT[lang];
  const bar = el.bar;
  bar.replaceChildren();
  const key = (k, label, now, act) => {
    const s = document.createElement("span");
    s.className = "k" + (now ? " now" : "");
    const b = document.createElement("b");
    b.textContent = k;
    s.append(b, label);
    s.addEventListener("click", act);
    bar.append(s);
  };
  const sep = () => { const s = document.createElement("span"); s.className = "sep"; bar.append(s); };
  key("0", t.flat, mode === "flat", () => go("flat"));
  key("1", t.uyuni, mode === "uyuni", () => go("uyuni"));
  key("2", t.fog, mode === "fog", () => go("fog"));
  key("3", t.side, mode === "side", () => go("side"));
  sep();
  key("C", t.code, codeOn, toggleCode);
  if (!flatLike(mode)) key("B", t.bg, withBackground, toggleBackground);
  key("F", t.full, false, toggleFull);
  sep();
  const state = document.createElement("span");
  state.className = "state" + (connected ? " live" : "");
  state.textContent = (connected ? t.live : t.wait) + (driving ? " · " + t.here : "");
  bar.append(state);
}

function renderText() {
  const t = TEXT[lang];
  document.documentElement.lang = lang;
  el.note.querySelector(".say").textContent = t.say;
  el.note.querySelector(".how").textContent = t.how;
  const a = el.note.querySelector(".go");
  a.textContent = t.go;
  a.href = playgroundUrl || (lang === "ja" ? "ja/playground" : "playground");
  renderBar();
}

function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }

// ---- start --------------------------------------------------------------------
withBackground = backgroundFromHash();
renderText();
// A playground answers hello within a moment; only then is it worth saying we wait.
setTimeout(() => { if (!connected) el.note.hidden = false; }, 900);
setMode(modeFromHash(), true);

// For checks from the outside (the test harness): numbers only, nothing to change.
window.asobiStage = {
  get mode() { return mode; },
  get connected() { return connected; },
  // When the art on screen changed (since a performance.now() time).
  artTimes(since) { return (stage3d && !flatLike(mode) ? stage3d.artTimes : flatTimes).filter((t) => t >= since); },
  stats() {
    const r = raster.stats;
    const s = stage3d ? stage3d.stats : null;
    return {
      raster: { drawn: r.drawn, skipped: r.skipped, failed: r.failed, avgMs: r.drawn ? r.sum / r.drawn : 0, maxMs: r.max, scale: raster.scale, side: raster.side },
      upload: s ? { count: s.uploads, avgMs: s.uploads ? s.uploadMs / s.uploads : 0, maxMs: s.uploadMax } : null,
      frames3d: stage3d ? stage3d.frameStats() : null,
      driving, playgroundHidden, withBackground,
      grain: { strength: flat.strength, stripMs: flat.stripMs, tiles: flat.grain.stats.tiles, tileMs: flat.grain.stats.lastMs, drawMs: flat.grain.stats.drawMs, bitmap: flat.grain.stats.bitmap, shown: !flat.grain.el.hidden },
      reel: { ...stats, seq: reel.seq, frames: reel.frames, fps: reel.fps, parts: reel.parts },
      ratio: stage3d ? stage3d.ratio : null,
      frames: s ? s.frames : 0,
    };
  },
};
