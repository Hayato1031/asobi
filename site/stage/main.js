// asobi stage window: a mirror of the playground, which drives the picture
// itself while the playground cannot.
//
// The playground keeps running Ruby, the player, reactions and sound. This
// window listens on the BroadcastChannel "asobi-stage" for the code text and
// snapshots of the player's <svg>, and draws them: flat (0), or floating in a
// three.js world: Uyuni at dusk (1), the fog stage (2).
//
// When the playground is hidden (minimised, covered, or this window full
// screen on the same display), the browser stops its animation frames and the
// snapshots stop. So the playground also sends the Reel it shows (without its
// song), and this window then plays it with a player of its own: motions go
// on, reacting parts rest at their first frame, sound stays with the
// playground. As soon as the visible playground sends a new picture, this
// window mirrors again. The same happens after the playground says bye or
// goes quiet: the last Reel keeps playing.
//
// Stage -> playground: hello { seq } (at start, and whenever the playground
// has gone quiet; seq names the Reel this window has, so a big Reel is sent
// once, not on every hello), here (every 2 s), bye (pagehide).
// Playground -> stage: setup { hidden }, code, error, picture,
// reel { seq, json, frames, fps }, visibility { hidden }, bye.
//
// Trust: the code comes from a URL anyone can write. A mirrored svg is only
// ever loaded as an image (blob: URL, image/svg+xml). A Reel goes through
// AsobiSafeReel (the playground's own check: only the SVG asobi writes) before
// the player here puts its frames on this page, exactly as the playground
// does, under the same CSP. Code and error text are drawn with canvas
// fillText or set with textContent.
import { Raster } from "./raster.js";
import { Flat } from "./flat.js";

const MODES = ["flat", "uyuni", "fog"];
const KEYS = { 0: "flat", 1: "uyuni", 2: "fog" };
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
    flat: "Flat", uyuni: "Uyuni", fog: "Fog", code: "Code", full: "Full screen",
    live: "Connected", wait: "Waiting", here: "Playing here",
  },
  ja: {
    say: "遊び場を待っています",
    how: "遊び場の「別ウィンドウ」ボタンから開いてください。書いたコードと絵がここに映ります。",
    go: "遊び場を開く",
    flat: "平面", uyuni: "ウユニ", fog: "霧", code: "コード", full: "全画面",
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
let latest = null;            // { svg, view, background, dark, rgb, grain }
let connected = false;
let lastHeard = 0;
let probed = false;
let freshCode = true;         // the next code just appears (no flash): first after (re)connecting
let mode = null;
let codeOn = true;
let stage3d = null;
let loading3d = null;
let switchToken = 0;
// The Reel the playground shows, kept as it came (parsed only when needed).
let reel = { json: null, seq: null, frames: 1, fps: 1 };
let playgroundHidden = false;
let lastPicture = 0;          // when the playground's last picture came
let reelAt = 0;               // when its last Reel came
let driving = false;          // playing the Reel here
let selfPlayer = null, selfObserver = null, selfQueued = false;
const stats = { reelBytes: 0, reelTransferMs: null, reelParseMs: null, reels: 0, driveStarts: 0, mirrored: 0, playedHere: 0 };

const el = {
  world: document.getElementById("world"),
  flat: document.getElementById("flat"),
  note: document.getElementById("note"),
  bar: document.getElementById("bar"),
  black: document.getElementById("black"),
};
const flat = new Flat(el.flat);
const raster = new Raster((source, info) => {
  if (!stage3d || mode === "flat") return false;
  raster.spent(stage3d.setPicture(source, info));
  return true;
});

// ---- the channel ------------------------------------------------------------
let channel = null;
try { channel = new BroadcastChannel("asobi-stage"); } catch { channel = null; }
function post(message) { try { channel && channel.postMessage(message); } catch { /* closed: nothing to say */ } }

// hello says which Reel this window has, so the playground resends it only when it changed.
function hello() { post({ type: "hello", seq: reel.seq }); }

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
  else if (m.type === "reel") onReel(m);
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
  freshCode = false;
}

function onError(m) {
  error = typeof m.error === "string" && m.error ? m.error.slice(0, 4000) : null;
  if (stage3d) stage3d.setError(error);
}

// A picture from the playground. While this window plays the Reel itself, a
// hidden playground's picture is out of date (it answers a hello with what it
// last drew): only a visible playground's new picture takes over again.
function onPicture(m) {
  lastPicture = performance.now();
  if (driving) {
    if (playgroundHidden || !connected) return;
    stopDriving();
  }
  stats.mirrored++;
  takePicture(m.svg, m.view, m.background);
}

function takePicture(svg, v, bg) {
  if (typeof svg !== "string" || svg.length > MAX_SVG) return;
  if (!Array.isArray(v) || v.length !== 4 || !v.every(Number.isFinite) || v[2] <= 0 || v[3] <= 0) return;
  if (latest && latest.svg === svg) return;
  const m = { svg };
  const background = typeof bg === "string" ? bg.slice(0, 80) : "";
  const look = latest && latest.background === background ? latest : lookOf(background);
  // asobi's grain is a noise filter over the whole picture: the key must ignore it.
  const grain = m.svg.includes("feTurbulence");
  latest = { svg: m.svg, view: v.slice(), background, dark: look.dark, rgb: look.rgb, grain };
  showPicture();
}

function showPicture() {
  if (!latest) return;
  if (mode === "flat") { flat.show(latest.svg, latest.background); return; }
  if (!stage3d) return;
  stage3d.setBackground(latest.rgb, latest.dark, latest.grain);
  // A little more than on screen (mipmaps keep it crisp); on a dense screen as much as on screen.
  raster.aim(stage3d.artPixels() * (stage3d.ratio >= 1.5 ? 1.05 : 1.5));
  raster.pressure = stage3d.pressure();
  raster.push(latest.svg, latest.view);
}

// The background colour, keyed out in 3D: a dark one leaves light, a light
// one leaves ink. No background (or one we cannot read) counts as white,
// asobi's default.
const probe = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
function lookOf(background) {
  let rgb = [255, 255, 255];
  if (background && background !== "none" && background !== "transparent") {
    probe.clearRect(0, 0, 1, 1);
    probe.fillStyle = "#ffffff";
    probe.fillStyle = background; // an invalid colour is ignored and white stays
    probe.fillRect(0, 0, 1, 1);
    const d = probe.getImageData(0, 0, 1, 1).data;
    if (d[3] > 0) rgb = [d[0], d[1], d[2]];
  }
  const luma = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255;
  return { dark: luma < 0.25, rgb };
}

// ---- playing the Reel here ----------------------------------------------------
// A player of this window's own, out of sight (#self), plays the Reel; its
// <svg> is taken the same way the playground's is (at most once a frame) and
// goes down the same road as a mirrored picture: flat, or into 3D.
const selfBox = document.getElementById("self");

function onReel(m) {
  if (typeof m.json !== "string" || m.json.length > MAX_REEL) return;
  reel = {
    json: m.json,
    seq: typeof m.seq === "string" ? m.seq.slice(0, 80) : null,
    frames: Number.isFinite(m.frames) ? m.frames : 1,
    fps: Number(m.fps) > 0 ? Number(m.fps) : 1,
  };
  stats.reels++;
  stats.reelBytes = m.json.length;
  stats.reelTransferMs = Number.isFinite(m.at) ? Date.now() - m.at : null;
  lastPicture = reelAt = performance.now(); // a new Reel: give its pictures a moment to start
  // While mirroring nothing else happens: the json waits until it is needed.
  if (driving) playHere();
  else if (playgroundHidden || !connected) startDriving();
}

function onVisibility(hidden) {
  playgroundHidden = !!hidden;
  // Hidden: play here at once. Visible again: the next new picture takes over (onPicture).
  if (playgroundHidden) startDriving();
}

// The playground's pictures stopped although its Reel moves (a hidden window
// that never said so): play here. A still Reel, or one whose parts only
// react, sends nothing while nobody touches it, and that is fine.
function watchdog() {
  if (driving || !connected || !reel.json || reel.frames < 2) return;
  const now = performance.now();
  // Just after a new Reel the playground may be busy (a big one takes a moment
  // to start), so wait longer then.
  const limit = Math.max(now - reelAt < 3000 ? 2000 : 400, 2500 / reel.fps);
  if (now - lastPicture > limit) startDriving();
}

function startDriving() {
  if (driving || !reel.json || !selfBox || !window.AsobiPlayer || !window.AsobiSafeReel) return;
  driving = true;
  stats.driveStarts++;
  selfPlayer = AsobiPlayer.mount(selfBox, { controls: false, keys: false, language: lang });
  if (!playHere()) { stopDriving(); return; }
  const svg = selfBox.querySelector("svg.asobi-svg");
  selfObserver = new MutationObserver(queueSelf);
  selfObserver.observe(svg, { subtree: true, childList: true, attributes: true, characterData: true });
  renderBar();
}

// The Reel, checked the way the playground checks it, into this window's player.
function playHere() {
  const t0 = performance.now();
  const r = AsobiSafeReel.parse(reel.json);
  stats.reelParseMs = performance.now() - t0;
  if (!r || r.error || !r.frames) return false;
  delete r.song; // sound stays with the playground
  selfPlayer.update(r);
  return true;
}

function stopDriving() {
  if (!driving) return;
  driving = false;
  if (selfObserver) selfObserver.disconnect();
  if (selfPlayer) selfPlayer.destroy();
  selfObserver = selfPlayer = null;
  selfQueued = false;
  renderBar();
}

function queueSelf() {
  if (selfQueued) return;
  selfQueued = true;
  requestAnimationFrame(() => {
    selfQueued = false;
    if (!driving) return;
    const svg = selfBox.querySelector("svg.asobi-svg");
    const box = svg && svg.getAttribute("viewBox");
    if (!box) return;
    const view = box.trim().split(/[\s,]+/).map(Number);
    const copy = svg.cloneNode(true);
    copy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    copy.removeAttribute("class");
    const rect = svg.querySelector("rect");
    stats.playedHere++;
    takePicture(new XMLSerializer().serializeToString(copy), view, (rect && rect.getAttribute("fill")) || "");
  });
}

// ---- modes ------------------------------------------------------------------
function modeFromHash() {
  const h = location.hash.replace(/^#/, "");
  return MODES.includes(h) ? h : "uyuni";
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
  if (next === "flat") {
    if (stage3d) stage3d.stop();
    el.flat.hidden = false;
    // Wait (a little) for the picture, so the black lifts onto it.
    if (latest) await Promise.race([flat.show(latest.svg, latest.background), wait(400)]);
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
    s.setWorld(next);
    s.warm();
    s.start();
    showPicture();
  }
  requestAnimationFrame(() => requestAnimationFrame(() => { if (token === switchToken) el.black.classList.add("clear"); }));
}

function go(next) {
  if (!MODES.includes(next)) return;
  history.replaceState(null, "", `${location.pathname}${location.search}#${next}`);
  setMode(next);
}

addEventListener("hashchange", () => setMode(modeFromHash()));

// ---- keys, mouse, the bar ---------------------------------------------------
function toggleCode() {
  codeOn = !codeOn;
  if (stage3d) stage3d.showCode(codeOn);
  renderBar();
}

function toggleFull() {
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  else document.documentElement.requestFullscreen().catch(() => {});
}

// Caught first (capture) and kept from going further: the player that plays
// the Reel here must not take these keys as reactions (its parts rest).
addEventListener("keydown", (e) => {
  e.stopPropagation();
  if (e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
  const k = e.key.toLowerCase();
  if (KEYS[k]) go(KEYS[k]);
  else if (k === "c") toggleCode();
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
  sep();
  key("C", t.code, mode !== "flat" && codeOn, toggleCode);
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
renderText();
// A playground answers hello within a moment; only then is it worth saying we wait.
setTimeout(() => { if (!connected) el.note.hidden = false; }, 900);
setMode(modeFromHash(), true);

// For checks from the outside (the test harness): numbers only, nothing to change.
window.asobiStage = {
  get mode() { return mode; },
  get connected() { return connected; },
  stats() {
    const r = raster.stats;
    const s = stage3d ? stage3d.stats : null;
    return {
      raster: { drawn: r.drawn, skipped: r.skipped, failed: r.failed, avgMs: r.drawn ? r.sum / r.drawn : 0, maxMs: r.max, scale: raster.scale, side: raster.side },
      upload: s ? { count: s.uploads, avgMs: s.uploads ? s.uploadMs / s.uploads : 0, maxMs: s.uploadMax } : null,
      driving, playgroundHidden, reel: { ...stats, seq: reel.seq, frames: reel.frames },
      ratio: stage3d ? stage3d.ratio : null,
      frames: s ? s.frames : 0,
    };
  },
};
