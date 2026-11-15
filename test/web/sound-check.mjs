// Checks asobi's own sound in the player (lib/asobi/web/player.js) in headless
// Chrome: the song, the effect sounds, the "music" analysis, mute, recording.
// Node 24 (no packages) and Google Chrome are needed; real input events are
// sent over the DevTools protocol, so the browser's "sound only after a click"
// rule is the real one.
//
//   node test/web/sound-check.mjs lib/asobi/web/player.js          (about a minute)
//   node test/web/sound-check.mjs lib/asobi/web/player.js --slow   (+ 70 s: the context is kept and closed)
//
// CHROME=/path/to/chrome overrides where Chrome is. Temporary files (the Chrome
// profile, removed at the end) go in TMPDIR. Prints the measurements as JSON,
// then one line per expectation; exits 1 if any expectation fails.
import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const PLAYER = path.resolve(process.argv[2] || "lib/asobi/web/player.js");
const SLOW = process.argv.includes("--slow");
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- test sounds (48 kHz, mono, 16-bit WAV), made here -----------------------
function wav(seconds, fn) {
  const RATE = 48000, n = Math.round(seconds * RATE), buf = Buffer.alloc(44 + n * 2);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * 2, 4); buf.write("WAVE", 8); buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(1, 22); buf.writeUInt32LE(RATE, 24);
  buf.writeUInt32LE(RATE * 2, 28); buf.writeUInt16LE(2, 32); buf.writeUInt16LE(16, 34); buf.write("data", 36); buf.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) buf.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(fn(i / RATE) * 32767))), 44 + i * 2);
  return buf;
}
let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;
const kick = (t) => (t < 0 ? 0 : Math.sin(2 * Math.PI * (50 * t + 4 * (1 - Math.exp(-t / 0.04)))) * Math.exp(-t / 0.15));
let lastN = 0;
const hat = (t) => { if (t < 0 || t > 0.15) return 0; const x = rnd(), y = x - lastN; lastN = x; return y * Math.exp(-t / 0.03); };
const SONGS = {
  kick: wav(4, (t) => 0.8 * kick(t % 0.5) + 0.25 * hat((t % 0.5) - 0.25)), // 120 BPM kicks, a hat between
  tone: wav(3, (t) => 0.3 * Math.sin(2 * Math.PI * 220 * t)),                 // another song, no beats
  silence: wav(2, () => 0)
};

// ---- the page --------------------------------------------------------------
const PAGE = `<!doctype html><meta charset="utf-8"><title>asobi sound check</title>
<style>html,body{margin:0;height:100%;overflow:hidden}#stage,#stage2{position:fixed;top:0;bottom:0;left:0;right:0}#stage2{left:50%}</style>
<div id="stage"></div><div id="stage2" hidden></div>
<script>
  // Count audio contexts; find the node that feeds the speakers; keep what the recorder makes.
  window.contexts = 0;
  var AC0 = window.AudioContext;
  window.AudioContext = class extends AC0 { constructor(o) { super(o); window.contexts++; } };
  var connect0 = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (d) { if (d instanceof AudioDestinationNode) window.speakers = this; return connect0.apply(this, arguments); };
  var url0 = URL.createObjectURL;
  URL.createObjectURL = function (b) { window.lastBlob = b; return url0.call(URL, b); };
  // ?deny=1: the person refuses the microphone.
  if (/deny=1/.test(location.search)) navigator.mediaDevices.getUserMedia = function () { return Promise.reject(new DOMException("refused", "NotAllowedError")); };
  window.errs = [];
  addEventListener("error", function (e) { errs.push(String(e.message)); });
  addEventListener("unhandledrejection", function (e) { errs.push("rejection: " + (e.reason && e.reason.message || e.reason)); });
</script>
<script src="/player.js"></script>
<script>
  var I = AsobiPlayer._internals;
  window.S = function () { return I.sound(); };
  var seq = function (n, f) { var o = []; for (var i = 0; i < n; i++) o.push(f(i, n)); return o; };
  // n copies of a part in a ring
  window.ring = function (id, n) {
    var s = "";
    for (var i = 0; i < n; i++) { var a = i / n * 2 * Math.PI; s += '<g transform="translate(' + (60 * Math.cos(a)).toFixed(1) + ',' + (60 * Math.sin(a)).toFixed(1) + ')"><!--asobi:' + id + '--></g>'; }
    return s;
  };
  window.part = function (turn, extra, inner) {
    var d = { frames: seq(10, function (i, n) { return '<circle r="' + (11 + 3 * Math.sin(Math.PI * i / n)).toFixed(2) + '" fill="tomato"/>' + (inner || ""); }), fps: 30, turn: turn };
    for (var k in extra) d[k] = extra[k];
    return d;
  };
  window.valuePart = function (from, what) { return { frames: seq(11, function (i) { return '<rect x="-95" y="85" height="5" width="' + i * 5 + '"/>'; }), turn: "value", from: from, what: what }; };
  window.reel = function (o) {
    o = o || {};
    var r = { frames: seq(30, function (i) { return '<rect x="-98" y="-98" width="6" height="6" fill="#999" transform="rotate(' + i * 12 + ')"/>' + (o.top || ""); }),
              fps: 30, view: [-100, -100, 200, 200], background: "white", code: "# sound check", error: null };
    if (o.parts) r.parts = o.parts;
    if (o.song) r.song = o.song;
    if (o.pending) { r.pending = true; r.frames = [r.frames[0].replace(/<!--asobi:[^>]*-->/g, "")]; delete r.parts; }
    return r;
  };
  window.mount = function (r, where) {
    var p = AsobiPlayer.mount(document.getElementById(where || "stage"), { language: "en" });
    p.update(r);
    return p;
  };
  window.centre = function (id, n) {
    var e = document.querySelector('#stage [data-asobi-part="' + id + '"][data-asobi-n="' + n + '"]').getBoundingClientRect();
    return [Math.round(e.x + e.width / 2), Math.round(e.y + e.height / 2)];
  };
  window.hint = function () { var h = document.querySelector("#stage .asobi-listen.asobi-on"); return h ? h.textContent : ""; };
  window.playedBy = function (since) {
    var c = {};
    S().played.forEach(function (p) { if (p.at >= since) c[p.part] = (c[p.part] || 0) + 1; });
    return c;
  };
  // Sample the sound state every ms for a while.
  window.watch = function (ms, every) {
    return new Promise(function (done) {
      var out = [], t0 = performance.now();
      var id = setInterval(function () {
        var s = S();
        out.push({ t: Math.round(performance.now() - t0), id: s.song && s.song.id, playing: s.song && s.song.playing,
                   time: s.song ? +s.song.time.toFixed(3) : null, volume: s.song && s.song.volume,
                   low: +s.music.low.toFixed(3), vol: +s.music.volume.toFixed(3), beats: s.music.beats,
                   micBeats: s.mic.beats, micVol: +s.mic.volume.toFixed(3) });
        if (performance.now() - t0 >= ms) { clearInterval(id); done(out); }
      }, every || 50);
    });
  };
  // How loud the speakers path is (RMS and peak over ms), measured after the mute gain.
  window.speakerLevel = function (ms) {
    var ctx = window.speakers.context, an = ctx.createAnalyser();
    an.fftSize = 2048; window.speakers.connect(an);
    var buf = new Float32Array(an.fftSize), peak = 0, sq = 0, n = 0, t0 = performance.now();
    return new Promise(function (done) {
      (function tick() {
        an.getFloatTimeDomainData(buf);
        for (var i = 0; i < buf.length; i++) { var a = Math.abs(buf[i]); if (a > peak) peak = a; sq += buf[i] * buf[i]; n++; }
        if (performance.now() - t0 < ms) requestAnimationFrame(tick);
        else { window.speakers.disconnect(an); done({ rms: +Math.sqrt(sq / n).toFixed(4), peak: +peak.toFixed(4) }); }
      })();
    });
  };
  // One effect sound (or count of them at once) rendered offline; what it looks like.
  function fftMag(x) {
    var n = x.length, re = Float64Array.from(x), im = new Float64Array(n);
    for (var i = 1, j = 0; i < n; i++) { var bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { var t = re[i]; re[i] = re[j]; re[j] = t; } }
    for (var len = 2; len <= n; len <<= 1) {
      var ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
      for (i = 0; i < n; i += len) {
        var cr = 1, ci = 0;
        for (var k = 0; k < len / 2; k++) {
          var ar = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci, ai = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
          re[i + k + len / 2] = re[i + k] - ar; im[i + k + len / 2] = im[i + k] - ai; re[i + k] += ar; im[i + k] += ai;
          var nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
        }
      }
    }
    var m = new Float64Array(n / 2); for (i = 0; i < n / 2; i++) m[i] = Math.hypot(re[i], im[i]); return m;
  }
  window.offline = async function (whats, bus) {
    var sr = 48000, ctx = new OfflineAudioContext(1, sr * 2, sr);
    var dest = bus ? I.fxBus(ctx, ctx.destination) : ctx.destination, made = 0;
    whats.forEach(function (w) { if (I.synth(ctx, dest, 0.01, w)) made++; });
    var d = (await ctx.startRendering()).getChannelData(0);
    var peak = 0, sq = 0, last = 0;
    for (var i = 0; i < d.length; i++) { var a = Math.abs(d[i]); if (a > peak) peak = a; sq += d[i] * d[i]; if (a > 0.001) last = i; }
    var w = d.slice(480, 480 + 8192), hann = w.map(function (v, i) { return v * (0.5 - 0.5 * Math.cos(2 * Math.PI * i / 8191)); });
    var m = fftMag(hann), hz = sr / 8192, num = 0, den = 0, top = 1;
    for (i = 1; i < m.length; i++) { num += i * hz * m[i]; den += m[i]; if (m[i] > m[top]) top = i; }
    return { made: made, peak: +peak.toFixed(3), length: +((last - 480) / sr).toFixed(3), rms: +Math.sqrt(sq / d.length).toFixed(4),
             centroidHz: den ? Math.round(num / den) : 0, strongestHz: Math.round(top * hz) };
  };
  // What the recorder made: its type, whether it carries sound, and how loud that is.
  window.inspectBlob = async function () {
    var b = window.lastBlob, bytes = new Uint8Array(await b.arrayBuffer()), text = "";
    for (var i = 0; i < bytes.length; i += 65536) text += String.fromCharCode.apply(null, bytes.subarray(i, i + 65536));
    var audio;
    try {
      var buf = await new OfflineAudioContext(1, 1, 48000).decodeAudioData(bytes.buffer.slice(0));
      var d = buf.getChannelData(0), peak = 0;
      for (i = 0; i < d.length; i++) if (Math.abs(d[i]) > peak) peak = Math.abs(d[i]);
      audio = { seconds: +buf.duration.toFixed(2), peak: +peak.toFixed(3) };
    } catch (e) { audio = null; }
    return { type: b.type, bytes: b.size, soundTrack: /soun|A_OPUS|A_AAC|mp4a|Opus/.test(text), audio: audio };
  };
  window.oldMime = function () { // the player's choice before asobi made sound
    var list = ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];
    for (var i = 0; i < list.length; i++) if (MediaRecorder.isTypeSupported(list[i])) return list[i].split(";")[0];
    return null;
  };
</script>`;

// ---- a server: the page, the player, songs with Range (as the live server) ----
const served = [];
const server = http.createServer((req, res) => {
  const url = req.url.split("?")[0];
  if (url === "/" || url === "/page.html") { res.writeHead(200, { "content-type": "text/html; charset=utf-8" }); res.end(PAGE); return; }
  if (url === "/player.js") { res.writeHead(200, { "content-type": "text/javascript", "cache-control": "no-store" }); res.end(fs.readFileSync(PLAYER)); return; }
  const m = url.match(/^\/song\/(\w+)$/);
  if (!m || !SONGS[m[1]]) { res.writeHead(404); res.end(); return; }
  const body = SONGS[m[1]], range = /bytes=(\d*)-(\d*)/.exec(req.headers.range || "");
  served.push({ song: m[1], range: req.headers.range || null });
  if (range) {
    const a = range[1] ? +range[1] : 0, b = range[2] ? Math.min(+range[2], body.length - 1) : body.length - 1;
    res.writeHead(206, { "content-type": "audio/wav", "content-length": b - a + 1, "accept-ranges": "bytes", "content-range": `bytes ${a}-${b}/${body.length}` });
    res.end(body.subarray(a, b + 1));
  } else {
    res.writeHead(200, { "content-type": "audio/wav", "content-length": body.length, "accept-ranges": "bytes" });
    res.end(body);
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const ORIGIN = `http://127.0.0.1:${server.address().port}`;
const dataUri = (name) => "data:audio/wav;base64," + SONGS[name].toString("base64");

// ---- Chrome over the DevTools protocol ------------------------------------
const work = fs.mkdtempSync(path.join(os.tmpdir(), "asobi-sound-"));
const chrome = spawn(CHROME, ["--headless=new", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check",
  "--remote-debugging-port=0", `--user-data-dir=${work}`, "--window-size=1000,800",
  "--use-fake-device-for-media-stream", "--use-fake-ui-for-media-stream", "--disable-features=AudioServiceOutOfProcess",
  "about:blank"], { stdio: "ignore" });
const socks = [];
function cleanup() {
  for (const w of socks) { try { w.close(); } catch {} }
  try { chrome.kill("SIGKILL"); } catch {}
  try { server.close(); } catch {}
  for (let i = 0; i < 20; i++) { try { fs.rmSync(work, { recursive: true, force: true }); break; } catch {} }
}
process.on("exit", cleanup);
process.on("SIGINT", () => process.exit(130));

function connect(wsUrl) {
  return new Promise((resolve) => {
    const ws = new WebSocket(wsUrl); socks.push(ws);
    let id = 0; const waiting = {}; const listeners = [];
    ws.addEventListener("message", (e) => { const m = JSON.parse(e.data); if (m.id && waiting[m.id]) { waiting[m.id](m); delete waiting[m.id]; } else for (const l of listeners) l(m); });
    const send = (method, params = {}) => new Promise((res, rej) => { const i = ++id; waiting[i] = (r) => (r.error ? rej(new Error(method + ": " + r.error.message)) : res(r.result)); ws.send(JSON.stringify({ id: i, method, params })); });
    ws.addEventListener("open", () => resolve({ send, on: (l) => listeners.push(l) }));
  });
}
let devPort;
for (let i = 0; i < 100 && !devPort; i++) {
  try { devPort = fs.readFileSync(path.join(work, "DevToolsActivePort"), "utf8").split("\n")[0]; } catch { await sleep(100); }
}
if (!devPort) { console.error("Chrome did not start (" + CHROME + ")"); process.exit(2); }
let target;
for (let i = 0; i < 50 && !target; i++) { try { target = (await (await fetch(`http://127.0.0.1:${devPort}/json`)).json()).find((t) => t.type === "page"); } catch {} if (!target) await sleep(100); }
const version = await (await fetch(`http://127.0.0.1:${devPort}/json/version`)).json();
const browser = await connect(version.webSocketDebuggerUrl);
const page = await connect(target.webSocketDebuggerUrl);
const consoleErrors = [];
page.on((m) => {
  if (m.method === "Runtime.exceptionThrown") consoleErrors.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
  if (m.method === "Runtime.consoleAPICalled" && (m.params.type === "error" || m.params.type === "warning")) consoleErrors.push(m.params.type + ": " + JSON.stringify(m.params.args.map((a) => a.value ?? a.description)));
  if (m.method === "Log.entryAdded" && m.params.entry.level === "error" && !/favicon/.test(m.params.entry.url || "")) consoleErrors.push("log: " + m.params.entry.text);
});
await page.send("Page.enable"); await page.send("Runtime.enable"); await page.send("Log.enable");
await browser.send("Browser.setDownloadBehavior", { behavior: "deny" });
const ev = async (expression) => {
  const r = await page.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 600));
  return r.result.value;
};
async function open(mic = "granted") {
  const loaded = new Promise((r) => page.on((m) => { if (m.method === "Page.loadEventFired") r(); }));
  await page.send("Page.navigate", { url: ORIGIN + "/page.html" + (mic === "denied" ? "?deny=1" : "") });
  await loaded; await sleep(150);
}
const mouse = (type, x, y) => page.send("Input.dispatchMouseEvent", { type, x, y, button: type === "mouseMoved" ? "none" : "left", clickCount: type === "mouseMoved" ? 0 : 1 });
const click = async (x, y) => { await mouse("mouseMoved", x, y); await mouse("mousePressed", x, y); await mouse("mouseReleased", x, y); };
const key = async (k, repeat = false) => {
  const p = { key: k, text: k, code: "Key" + k.toUpperCase(), windowsVirtualKeyCode: k.toUpperCase().charCodeAt(0), autoRepeat: repeat };
  await page.send("Input.dispatchKeyEvent", { type: "keyDown", ...p });
  await page.send("Input.dispatchKeyEvent", { type: "keyUp", ...p });
};
const pageErrors = async () => (await ev("errs")).concat(consoleErrors.splice(0));

// ---- the checks -------------------------------------------------------------
const out = {}, results = [];
const expect = (name, ok, detail) => results.push({ name, ok: !!ok, detail });
const beatsPerSecond = (w, field = "beats") => +((w[w.length - 1][field] - w[0][field]) / ((w[w.length - 1].t - w[0].t) / 1000)).toFixed(2);
const looped = (w) => w.some((x, i) => i > 0 && x.time !== null && w[i - 1].time !== null && x.time < w[i - 1].time - 1);
const errorsSeen = [];

try {
  // 1. A Reel without sound: no audio context, recording as before.
  await open();
  await ev(`window.p = mount(reel({ top: ring("p1", 12) + '<!--asobi:p2-->', parts: { p1: part("click"), p2: part("key", { key: "a" }) } }))`);
  await sleep(200);
  const [x1, y1] = await ev("centre('p1', 3)");
  await click(x1, y1); await key("a"); await key("r"); await sleep(1500); await key("r"); await sleep(800);
  out.noSound = { contexts: await ev("contexts"), state: await ev("S()"), hint: await ev("hint()"), recording: await ev("inspectBlob()"), oldMime: await ev("oldMime()") };
  expect("no sound: no audio context", out.noSound.contexts === 0 && out.noSound.state.context === null, out.noSound.contexts);
  expect("no sound: no hint", out.noSound.hint === "", out.noSound.hint);
  expect("no sound: recording is video only, MIME as before", out.noSound.recording.type === out.noSound.oldMime && !out.noSound.recording.soundTrack && !out.noSound.recording.audio, out.noSound.recording);
  errorsSeen.push(...(await pageErrors()).map((e) => "noSound: " + e));

  // 2. The song, as a data URI and as a URL: starts on a click, loops, "music" hears it.
  for (const [name, src] of [["dataUri", dataUri("kick")], ["url", "/song/kick"]]) {
    await open();
    await ev(`window.p = mount(reel({ top: '<!--asobi:p1--><!--asobi:p2-->', song: { id: "kick00000000", src: ${JSON.stringify(src)} },
      parts: { p1: valuePart("music", "low"), p2: part("beat", { from: "music" }) } }))`);
    await sleep(300);
    const before = { hint: await ev("hint()"), song: (await ev("S()")).song, contexts: await ev("contexts") };
    await click(500, 400);
    const w = await ev("watch(9000, 50)");
    const after = await ev("S()");
    const lows = w.filter((x) => x.t >= 1000).map((x) => x.low);
    out["song_" + name] = { before, hintAfter: await ev("hint()"), running: after.running, song: after.song,
      timeAt: [0, 2000, 4000, 6000, 8500].map((t) => w.find((x) => x.t >= t).time),
      looped: looped(w), beatsPerSecond: beatsPerSecond(w.filter((x) => x.t >= 1000)),
      lowMin: Math.min(...lows), lowMax: Math.max(...lows),
      lowEvery50ms: w.filter((x) => x.t >= 2000 && x.t < 3000).map((x) => x.low) };
    const o = out["song_" + name];
    expect(`song (${name}): waits for a click with "click for sound"`, before.hint === "click for sound" && before.contexts === 0 && before.song && !before.song.playing, before);
    expect(`song (${name}): plays after the click and loops`, after.song.playing && o.looped && o.hintAfter === "", o.timeAt);
    expect(`song (${name}): "music" beats about twice a second`, o.beatsPerSecond >= 1.7 && o.beatsPerSecond <= 2.3, o.beatsPerSecond);
    expect(`song (${name}): by(:music, :low) moves`, o.lowMax > 0.8 && o.lowMin < 0.5, [o.lowMin, o.lowMax]);
    errorsSeen.push(...(await pageErrors()).map((e) => name + ": " + e));
  }
  out.rangeRequests = served.filter((s) => s.song === "kick").slice(0, 6);

  // 3. update(): same id goes on, error keeps it, another id switches, none stops it.
  await open();
  const songReel = (id, src, vol, extra = "") => `reel({ top: '<!--asobi:p1-->${extra}', song: { id: "${id}", src: "${src}"${vol ? ", volume: " + vol : ""} }, parts: { p1: valuePart("music") } })`;
  await ev(`window.p = mount(reel({ pending: true, song: { id: "kick00000000", src: "/song/kick" } }))`); // a preview first
  await sleep(200); await click(500, 400); await sleep(1200);
  const u = {};
  const at = async () => { const s = (await ev("S()")).song; return s && { id: s.id, time: +s.time.toFixed(3), playing: s.playing, volume: s.volume }; };
  u.preview = await at();
  await ev(`p.update(${songReel("kick00000000", "/song/kick")})`); await sleep(500); u.sameAfterPreview = await at();
  await ev(`p.update(${songReel("kick00000000", "/song/kick", 0.5, "<circle r=\\'5\\'/>")})`); await sleep(500); u.sameNewCode = await at();
  await ev(`p.update({ error: "sketch.rb:3: typo", code: "x" })`); await sleep(700); u.error = await at();
  await ev(`p.update(${songReel("tone00000000", "/song/tone")})`); await sleep(300); u.other = await at();
  await ev(`p.update(reel())`); await sleep(300); u.none = await at();
  u.contextAfterNone = (await ev("S()")).context;
  out.update = u;
  expect("update: a preview Reel starts the song", u.preview && u.preview.playing && u.preview.time > 0.8, u.preview);
  expect("update: the same id goes on (time keeps rising)", u.sameAfterPreview.time > u.preview.time && u.sameNewCode.time > u.sameAfterPreview.time && u.sameNewCode.playing, [u.preview.time, u.sameAfterPreview.time, u.sameNewCode.time]);
  expect("update: a changed volume is applied", u.sameNewCode.volume === 0.5, u.sameNewCode.volume);
  expect("update: an error Reel keeps the song", u.error.id === "kick00000000" && u.error.playing && u.error.time > u.sameNewCode.time, u.error);
  expect("update: another id switches and starts from its start", u.other.id === "tone00000000" && u.other.time < 0.5 && u.other.playing, u.other);
  expect("update: a Reel without a song stops it", u.none === null, u.none);

  // Two players that want the same song share it; destroy stops only what no one else wants.
  await ev(`document.getElementById("stage2").hidden = false; p.update(${songReel("kick00000000", "/song/kick")}); window.q = mount(${songReel("kick00000000", "/song/kick")}, "stage2")`);
  await sleep(200); await click(200, 400); await sleep(800);
  const sh = { both: await at(), audioElements: null };
  await ev("p.destroy()"); await sleep(500); sh.afterOne = await at();
  await ev("q.destroy()"); await sleep(300); sh.afterBoth = await at(); sh.contextAfterBoth = (await ev("S()")).context;
  out.shared = sh;
  expect("two players share one song; destroy() stops it only when no one wants it", sh.afterOne && sh.afterOne.playing && sh.afterOne.time > sh.both.time && sh.afterBoth === null, sh);
  errorsSeen.push(...(await pageErrors()).map((e) => "update: " + e));

  // 4. How many sounds each kind of part plays (the microphone refused: beats only come from feed()).
  await open("denied");
  // 12 click copies, a hover part, 12 copies of a key part (small, in the middle), a beat part,
  // and a click part (bell) holding a click part (note c4).
  await ev(`window.p = mount(reel({ top: ring("p1", 12) + '<g transform="translate(0,0)"><!--asobi:p3--></g>' + ring("p2", 12).replace(/translate\\(/g, "scale(0.4) translate(") + '<g transform="translate(-80,80)"><!--asobi:p4--></g><g transform="translate(80,80)"><!--asobi:p6--></g>',
    parts: { p1: part("click", { sound: "pop" }), p2: part("key", { key: "a", sound: "kick" }),
             p3: part("hover", { sound: "hat" }), p4: part("beat", { from: "mic", sound: "snare" }),
             p5: part("click", { note: 60 }), p6: part("click", { sound: "bell" }, '<g transform="scale(0.5)"><!--asobi:p5--></g>') } }))`);
  await sleep(300);
  const cnt = {};
  cnt.copies = await ev("({ p1: document.querySelectorAll('#stage [data-asobi-part=p1]').length, p2: document.querySelectorAll('#stage [data-asobi-part=p2]').length })");
  let t = await ev("performance.now()");
  const [cx, cy] = await ev("centre('p1', 4)");
  await click(cx, cy); await sleep(600);
  cnt.oneClick = await ev(`playedBy(${t})`);
  cnt.hintAfterClick = await ev("hint()");
  t = await ev("performance.now()");
  await key("a"); await sleep(300); await key("a", true); await key("a", true); await sleep(300);
  cnt.keyPressPlusTwoRepeats = await ev(`playedBy(${t})`);
  t = await ev("performance.now()");
  await mouse("mouseMoved", 10, 10); await sleep(200);
  const [hx, hy] = await ev("centre('p3', 0)");
  await mouse("mouseMoved", hx, hy); await sleep(2000); // the hover part loops 6 times
  cnt.hover2s = await ev(`playedBy(${t})`);
  await mouse("mouseMoved", 10, 10); await sleep(300); await mouse("mouseMoved", hx, hy); await sleep(300);
  cnt.hoverLeaveAndBack = await ev(`playedBy(${t})`);
  await mouse("mouseMoved", 10, 10);
  t = await ev("performance.now()");
  await ev("I.feed('mic', { volume: 0.5, beat: true })"); await sleep(400);
  cnt.oneBeat = await ev(`playedBy(${t})`);
  await ev("I.feed('mic', null)");
  t = await ev("performance.now()");
  const [nx, ny] = await ev("centre('p5', 0)");
  await click(nx, ny); await sleep(300);
  cnt.nestedClick = await ev(`playedBy(${t})`);
  cnt.lastPlayed = (await ev("S()")).played.slice(-2).map((p) => ({ sound: p.sound, note: p.note, part: p.part }));
  // Twenty parts on one key: twenty sounds started, at most sixteen sounding.
  const twenty = Array.from({ length: 20 }, (_, i) => `p${i + 1}: part("key", { key: "b", sound: "${["kick", "snare", "clap", "bell"][i % 4]}" })`).join(",");
  await ev(`p.update(reel({ top: '${Array.from({ length: 20 }, (_, i) => `<!--asobi:p${i + 1}-->`).join("")}', parts: { ${twenty} } }))`);
  await sleep(200);
  t = await ev("performance.now()");
  await key("b"); await sleep(30);
  cnt.twentyAtOnce = { started: Object.keys(await ev(`playedBy(${t})`)).length, sounding: (await ev("S()")).voices };
  out.counts = cnt;
  expect("one click on one of 12 copies: 1 sound", cnt.copies.p1 === 12 && JSON.stringify(cnt.oneClick) === '{"p1":1}', cnt.oneClick);
  expect("a key press with 12 copies: 1 sound; auto-repeat: none", cnt.copies.p2 === 12 && JSON.stringify(cnt.keyPressPlusTwoRepeats) === '{"p2":1}', cnt.keyPressPlusTwoRepeats);
  expect("hover: 1 on entering, not per loop; again after leaving", JSON.stringify(cnt.hover2s) === '{"p3":1}' && JSON.stringify(cnt.hoverLeaveAndBack) === '{"p3":2}', [cnt.hover2s, cnt.hoverLeaveAndBack]);
  expect("a beat: 1 sound", JSON.stringify(cnt.oneBeat) === '{"p4":1}', cnt.oneBeat);
  expect("nested click parts: each plays its own once", JSON.stringify(cnt.nestedClick) === '{"p5":1,"p6":1}', cnt.nestedClick);
  expect("twenty at once: all start, at most 16 sound", cnt.twentyAtOnce.started === 20 && cnt.twentyAtOnce.sounding <= 16, cnt.twentyAtOnce);
  errorsSeen.push(...(await pageErrors()).map((e) => "counts: " + e));

  // 5. on_beat(:music).sounding(:kick) does not trigger itself.
  await open();
  await ev(`window.p = mount(reel({ top: '<!--asobi:p1--><g transform="translate(60,0)"><!--asobi:p2--></g>', song: { id: "silence00000", src: "/song/silence" },
    parts: { p1: part("beat", { from: "music", sound: "kick" }), p2: part("click", { sound: "kick" }) } }))`);
  await sleep(300);
  await click(500, 400); await sleep(1000); // start the sound (the silent song)
  t = await ev("performance.now()");
  const [kx, ky] = await ev("centre('p2', 0)");
  await click(kx, ky); await sleep(3000);
  out.selfTrigger = { in3s: await ev(`playedBy(${t})`), musicBeats: (await ev("S()")).music.beats };
  const st = out.selfTrigger.in3s;
  expect("on_beat(:music).sounding(:kick) does not trigger itself", st.p2 === 1 && (st.p1 || 0) <= 1, out.selfTrigger);
  errorsSeen.push(...(await pageErrors()).map((e) => "selfTrigger: " + e));

  // 6. The sounds themselves (rendered offline).
  const kinds = [["pop", { sound: "pop" }], ["kick", { sound: "kick" }], ["snare", { sound: "snare" }], ["hat", { sound: "hat" }],
                 ["clap", { sound: "clap" }], ["bell", { sound: "bell" }], ["c4", { note: 60 }], ["a4", { note: 69 }], ["unknown", { sound: "boom" }]];
  out.sounds = {};
  for (const [name, what] of kinds) out.sounds[name] = await ev(`offline([${JSON.stringify(what)}], true)`);
  out.sixteenKicks = await ev(`offline(Array(16).fill({ sound: "kick" }), true)`);
  out.sixteenMixed = await ev(`offline(${JSON.stringify(kinds.slice(0, 8).map((k) => k[1]).concat(kinds.slice(0, 8).map((k) => k[1])))}, true)`);
  const six = ["pop", "kick", "snare", "hat", "clap", "bell"];
  expect("each sound and a note make signal", six.concat(["c4", "a4"]).every((n) => out.sounds[n].peak > 0.1), six.map((n) => out.sounds[n].peak));
  expect("an unknown name is silent", out.sounds.unknown.made === 0 && out.sounds.unknown.peak === 0, out.sounds.unknown);
  expect("bell rings about a second, note about half", out.sounds.bell.length > 0.8 && out.sounds.bell.length < 1.6 && out.sounds.c4.length > 0.35 && out.sounds.c4.length < 0.7, [out.sounds.bell.length, out.sounds.c4.length]);
  expect("a4 sounds at 440 Hz, c4 at 262 Hz", Math.abs(out.sounds.a4.strongestHz - 440) < 8 && Math.abs(out.sounds.c4.strongestHz - 262) < 8, [out.sounds.a4.strongestHz, out.sounds.c4.strongestHz]);
  const distinct = six.every((a, i) => six.every((b, j) => j <= i || (() => {
    const A = out.sounds[a], B = out.sounds[b], diff = (x, y) => Math.abs(x - y) / Math.max(x, y);
    return diff(A.length, B.length) > 0.3 || diff(A.centroidHz, B.centroidHz) > 0.3 || diff(A.strongestHz, B.strongestHz) > 0.3;
  })()));
  expect("the six sounds are clearly different (length, centre or strongest frequency differ by 30%+)", distinct, six.map((n) => [n, out.sounds[n].length, out.sounds[n].centroidHz, out.sounds[n].strongestHz]));
  expect("sixteen at once do not clip", out.sixteenKicks.peak < 1 && out.sixteenMixed.peak < 1, [out.sixteenKicks.peak, out.sixteenMixed.peak]);

  // 7 + 8. Mute, recording with sound, and the recording while muted.
  await open();
  await ev(`window.p = mount(reel({ top: '<!--asobi:p1--><!--asobi:p2-->', song: { id: "kick00000000", src: "/song/kick" },
    parts: { p1: valuePart("music", "low"), p2: part("click", { sound: "bell" }) } }))`);
  await sleep(300); await click(500, 400); await sleep(1000);
  const mu = { before: await ev("speakerLevel(1500)") };
  await key("m"); await sleep(100);
  mu.hint = await ev("hint()");
  const wm = ev("watch(2000, 50)");
  mu.muted = await ev("speakerLevel(1500)");
  const wmv = await wm;
  mu.state = (await ev("S()")).muted;
  mu.musicLowWhileMuted = [Math.min(...wmv.map((x) => x.low)), Math.max(...wmv.map((x) => x.low))];
  mu.beatsWhileMuted = wmv[wmv.length - 1].beats - wmv[0].beats;
  // record while muted: the recording still has the sound
  await key("r"); await sleep(2500); await key("r"); await sleep(1000);
  mu.recordingWhileMuted = await ev("inspectBlob()");
  await key("m"); await sleep(100);
  mu.hintUnmute = await ev("hint()");
  mu.after = await ev("speakerLevel(1000)");
  await key("r"); await sleep(3000); await key("r"); await sleep(1000);
  out.recording = await ev("inspectBlob()");
  out.mute = mu;
  expect("mute: the speakers go silent and come back", mu.before.rms > 0.05 && mu.muted.peak < 0.001 && mu.after.rms > 0.05 && mu.state === true, [mu.before, mu.muted, mu.after]);
  expect("mute: says so", mu.hint === "muted" && mu.hintUnmute === "sound on", [mu.hint, mu.hintUnmute]);
  expect("mute: the analysis keeps hearing", mu.musicLowWhileMuted[1] > 0.8 && mu.beatsWhileMuted >= 3, mu);
  expect("recording with a song has its sound", out.recording.soundTrack && out.recording.audio && out.recording.audio.peak > 0.2 && out.recording.audio.seconds > 2, out.recording);
  expect("recording while muted still has the sound", mu.recordingWhileMuted.soundTrack && mu.recordingWhileMuted.audio && mu.recordingWhileMuted.audio.peak > 0.2, mu.recordingWhileMuted);
  // A part that asks for the letter m takes it over.
  await ev(`p.update(reel({ top: '<!--asobi:p1-->', song: { id: "kick00000000", src: "/song/kick" }, parts: { p1: part("key", { key: "m", sound: "pop" }) } }))`);
  t = await ev("performance.now()");
  await key("m"); await sleep(200);
  out.mKeyTaken = { muted: (await ev("S()")).muted, played: await ev(`playedBy(${t})`) };
  expect("a part that asks for m takes the key (no mute)", out.mKeyTaken.muted === false && out.mKeyTaken.played.p1 === 1, out.mKeyTaken);
  errorsSeen.push(...(await pageErrors()).map((e) => "mute: " + e));

  // 9. The microphone, refused and allowed, next to asobi's own sound.
  for (const perm of ["denied", "granted"]) {
    await open(perm);
    await ev(`window.p = mount(reel({ top: '<!--asobi:p1--><!--asobi:p2--><!--asobi:p3-->', song: { id: "kick00000000", src: "/song/kick" },
      parts: { p1: valuePart("mic"), p2: valuePart("music"), p3: part("click", { sound: "pop" }) } }))`);
    await sleep(300);
    const hintBefore = await ev("hint()");
    t = await ev("performance.now()");
    await click(500, 400);
    const [px, py] = await ev("centre('p3', 0)");
    await sleep(700); await click(px, py);
    const w = await ev("watch(4000, 50)");
    const s = await ev("S()");
    out["mic_" + perm] = { hintBefore, hintAfter: await ev("hint()"), state: s.state, running: s.running, song: s.song, played: await ev(`playedBy(${t})`),
                           musicBeatsPerSecond: beatsPerSecond(w), micBeatsPerSecond: beatsPerSecond(w, "micBeats"), micVolMax: Math.max(...w.map((x) => x.micVol)) };
    errorsSeen.push(...(await pageErrors()).map((e) => "mic " + perm + ": " + e));
  }
  const md = out.mic_denied, mg = out.mic_granted;
  expect("mic + sound: the hint is the mic's", md.hintBefore === "click to listen", md.hintBefore);
  expect("refusing the mic does not stop asobi's sound", md.state === "refused" && md.running && md.song.playing && md.played.p3 === 1 && md.musicBeatsPerSecond > 1.5, md);
  expect("mic allowed: both heard, separately", mg.state === "on" && mg.song.playing && mg.micBeatsPerSecond > 1.5 && mg.musicBeatsPerSecond > 1.5, mg);

  // 10. (slow) The context stays open while sound is wanted, and closes after.
  if (SLOW) {
    await open();
    await ev(`window.p = mount(reel({ top: '<!--asobi:p1-->', song: { id: "kick00000000", src: "/song/kick" }, parts: { p1: valuePart("mic") } }))`);
    await sleep(300); await click(500, 400); await sleep(1000);
    await ev(`p.update(reel({ song: { id: "kick00000000", src: "/song/kick" } }))`); // no mic any more
    await sleep(31500);
    const k = { after31s: await ev("S()") };
    await ev("p.update(reel())"); // no sound any more
    await sleep(31500);
    k.afterNoSound31s = await ev("S()");
    out.keepOpen = { micAfter31s: k.after31s.state, contextAfter31s: k.after31s.context, songPlaying: k.after31s.song && k.after31s.song.playing,
                     contextAfterNoSound31s: k.afterNoSound31s.context };
    expect("the mic closes after 30 s; the context stays while the song plays", k.after31s.state === "off" && k.after31s.context === "running" && k.after31s.song.playing, out.keepOpen);
    expect("the context closes 30 s after nothing makes sound", k.afterNoSound31s.context === null, out.keepOpen);
    errorsSeen.push(...(await pageErrors()).map((e) => "keepOpen: " + e));
  }
} catch (e) {
  results.push({ name: "the check itself ran", ok: false, detail: String(e.stack || e) });
}
out.errors = errorsSeen;
expect("no errors in the console", errorsSeen.length === 0, errorsSeen);

console.log(JSON.stringify(out, null, 1));
for (const r of results) console.log((r.ok ? "ok    " : "FAIL  ") + r.name + (r.ok ? "" : "  " + JSON.stringify(r.detail)));
cleanup();
process.exit(results.every((r) => r.ok) ? 0 : 1);
