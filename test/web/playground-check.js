// Checks how the playground page (site/assets/playground.js) gets over a
// Ruby crash, in plain Node with a pretend page and a pretend worker
// (no browser, no ruby.wasm).
//
//   node test/web/playground-check.js _site/assets/playground.js _site/playground.html
//
// Prints a JSON object with what happened in each scenario.
// test/site_test.rb runs it and checks the answers.
//
// The pretend worker answers like ruby-worker.js. What it does depends on
// the code it is asked to run:
//   "crash ..."   preview, then { id, fatal }        (Ruby broke)
//   "error ..."   preview, then a worker error event  (the worker itself broke)
//   "hold ..."    preview, then nothing until the test says so (later
//                 requests wait behind it: a worker answers in order)
//   "attack ..."  a preview and a whole Reel whose frame is not asobi's own
//                 SVG (what a sketch that changes asobi's SVG writer sends)
//   "bad ..."     an error Reel
//   "spoof ..."   a Reel whose song is "user/<an id the page was not given>"
//   play "NAME"   (anywhere) like Asobi::Web.offer_song: a Reel playing the
//                 song the page offered under NAME ({ type: "song" }), or an
//                 error when there is none; with "moving" in the code, a
//                 preview first
//   anything else preview, one "working", then the whole Reel
// Song files are pretend Files whose bytes come from a function, so a
// "21 MB" file costs only the bytes the page actually reads.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const nodeCrypto = require("crypto");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const [playJs, playHtml] = process.argv.slice(2);
const source = fs.readFileSync(playJs, "utf8");
// The page loads the checker (safe-reel.js, next to playground.js) first.
const safeSource = fs.readFileSync(path.join(path.dirname(playJs), "safe-reel.js"), "utf8");
const ATTACK = '<image href="x:" onerror="alert(1)"/>';
const config = fs.readFileSync(playHtml, "utf8").match(/id="play-config">([\s\S]*?)<\/script>/)[1];

function element(id) {
  const listeners = {};
  const classes = new Set();
  return {
    id, value: "", textContent: "", title: "", hidden: false, disabled: false, scrollTop: 0, scrollLeft: 0, innerHTML: "",
    href: "", download: "",
    firstChild: { innerHTML: "" },
    classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c), contains: (c) => classes.has(c) },
    addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
    dispatchEvent: (e) => { (listeners[e.type] || []).forEach((fn) => fn(e)); },
    click: () => { (listeners.click || []).forEach((fn) => fn({ type: "click" })); },
    focus: () => {}, remove: () => {}, setAttribute: () => {}, querySelector: () => null
  };
}

// A pretend File (or a slice of one): byte i is byteAt(start + i). reads
// gets { name, start, size } for every piece the page reads.
class FakeFile {
  constructor(name, size, type, byteAt, reads, start = 0) {
    Object.assign(this, { name, size, type, byteAt, reads, start });
  }
  bytes() {
    const out = new Uint8Array(this.size);
    for (let i = 0; i < this.size; i++) out[i] = this.byteAt(this.start + i);
    return out;
  }
  slice(a = 0, b = this.size) { return new FakeFile(this.name, b - a, this.type, this.byteAt, this.reads, this.start + a); }
  arrayBuffer() {
    this.reads.push({ name: this.name, start: this.start, size: this.size });
    return Promise.resolve(this.bytes().buffer);
  }
}
const pattern = (i) => (i * 31 + (i >> 8)) & 255; // the bytes of every pretend song

// What the page should name a song: SHA-256 of its size (decimal digits),
// its first MiB and its last MiB (or all of it up to 2 MiB), first 12 hex.
function expectedId(size, byteAt) {
  const MIB = 1024 * 1024;
  const range = (a, b) => { const out = Buffer.alloc(b - a); for (let i = a; i < b; i++) out[i - a] = byteAt(i); return out; };
  const h = nodeCrypto.createHash("sha256").update(String(size));
  if (size <= 2 * MIB) h.update(range(0, size)); else h.update(range(0, MIB)).update(range(size - MIB, size));
  return h.digest("hex").slice(0, 12);
}

// A Reel for code that says play "NAME": the song offered under NAME, or an error.
function songAnswers(code, songs) {
  const named = /^[ \t]*play[ \t]*\(?[ \t]*"((?:[^"\\]|\\.)*)"/m.exec(code);
  if (!named) return null;
  const name = named[1].replace(/\\(.)/g, "$1");
  const id = songs[name];
  if (!id) return { whole: JSON.stringify({ error: "no song " + JSON.stringify(name), code }) };
  const song = { id, src: "user/" + id };
  const whole = JSON.stringify({ frames: ["<g/>", '<circle r="1"/>'], fps: 30, view: [0, 0, 1, 1], code, error: null, song });
  if (!code.includes("moving")) return { whole };
  return { preview: JSON.stringify({ frames: ["<g/>"], fps: 30, view: [0, 0, 1, 1], code, error: null, pending: true, song }), whole };
}

function page(options) {
  const workers = [];   // every pretend worker made, in order
  const shown = [];     // every Reel given to the player
  const scripts = [];   // scripts added to the page (the page engine)
  const downloads = []; // every file triggered via <a download>
  const fetched = [];   // URLs passed to fetch
  const reads = [];     // pieces of song files read (FakeFile.arrayBuffer)
  const dataReads = []; // song files read whole for a saved page (FileReader.readAsDataURL)
  const posted = [];    // messages to the stage (BroadcastChannel "asobi-stage")
  const channels = [];
  const blobs = {};
  let nextBlob = 1;
  const elements = {};
  ["code", "stage", "status", "play-fc", "code-tint", "copy", "reset", "download", "song", "song-file"].forEach((id) => { elements[id] = element(id); });
  elements.download.disabled = true;
  elements["play-config"] = element("play-config");
  elements["play-config"].textContent = config;
  const playEl = element("");
  const extra = [];

  // The page engine's Ruby (file:// only), when options.pageEngine.
  const pageRuby = {
    calls: [], songs: {},
    boot: () => Promise.resolve(),
    run: (code) => pageRuby.start(code).json,
    start: (code) => {
      pageRuby.calls.push("start:" + code);
      if (code.startsWith("crash")) throw new Error("RuntimeError: unreachable");
      const s = songAnswers(code, pageRuby.songs);
      return { json: s ? s.whole : JSON.stringify({ frames: ["<g/>"], fps: 1, view: [0, 0, 1, 1], code, error: null }), pending: false };
    },
    step: () => ({ done: true, json: null }),
    drop: () => {},
    offerSong: (name, id) => { pageRuby.calls.push("song:" + name + ":" + id); pageRuby.songs[name] = id; return true; }
  };

  class FakeWorker {
    constructor(url) {
      this.url = url;
      this.got = [];
      this.songs = {};
      this.terminated = false;
      this.held = null;
      workers.push(this);
      const failBoot = options.failBootAfter !== undefined && workers.length > options.failBootAfter;
      setTimeout(() => this.say(failBoot ? { type: "failed", message: "no wasm" } : { type: "ready" }), 5);
    }
    say(m) { if (!this.terminated && this.onmessage) this.onmessage({ data: m }); }
    postMessage(m) {
      this.got.push(m);
      if (m.type === "song") { this.songs[m.name] = m.id; return; } // like Asobi::Web.offer_song: no answer
      if (this.held !== null) return; // busy with "hold": never gets to this one
      setTimeout(() => {
        const s = songAnswers(m.code, this.songs);
        if (s) {
          if (s.preview) this.say({ id: m.id, json: s.preview, pending: true });
          this.say({ id: m.id, json: s.whole });
          return;
        }
        if (m.code.startsWith("bad")) {
          this.say({ id: m.id, json: JSON.stringify({ error: "boom", code: m.code }) });
          return;
        }
        if (m.code.startsWith("spoof")) {
          this.say({ id: m.id, json: JSON.stringify({ frames: ["<g/>"], fps: 1, view: [0, 0, 1, 1], code: m.code, error: null,
                                                      song: { id: "aaaaaaaaaaaa", src: "user/aaaaaaaaaaaa" } }) });
          return;
        }
        if (m.code.startsWith("attack")) {
          this.say("not an object");
          this.say(null);
          this.say({ id: "__proto__", json: "{}", pending: true });
          this.say({ id: m.id, json: JSON.stringify({ frames: [ATTACK], fps: 30, view: [0, 0, 1, 1], pending: true }), pending: true });
          this.say({ id: m.id, json: JSON.stringify({ frames: [ATTACK, "<g/>"], fps: 30, view: [0, 0, 1, 1], code: m.code, error: null }) });
          return;
        }
        if (m.code.startsWith("still")) {
          this.say({ id: m.id, json: JSON.stringify({ frames: ['<circle r="10"/>'], fps: 1, view: [-12, -12, 24, 24], background: "white", code: m.code, error: null }) });
          return;
        }
        if (m.code.startsWith("song")) {
          this.say({ id: m.id, json: JSON.stringify({
            frames: ['<!--asobi:p1-->'], fps: 1, view: [-12, -12, 24, 24], background: "black",
            code: m.code + "\n# </script>", error: null,
            parts: { p1: { frames: ['<circle r="10"/>'], fps: 30, turn: "beat", from: "music" } },
            song: { id: "3ff79180f05b", src: "assets/beat.wav", volume: 0.5 }
          }) });
          return;
        }
        this.say({ id: m.id, json: JSON.stringify({ frames: ["<g/>"], fps: 30, view: [0, 0, 1, 1], pending: true }), pending: true });
        if (m.code.startsWith("crash")) this.say({ id: m.id, fatal: "RuntimeError: unreachable" });
        else if (m.code.startsWith("error")) { if (!this.terminated) this.onerror({ message: "Uncaught Error", preventDefault: () => {} }); }
        else if (m.code.startsWith("hold")) this.held = m.id;
        else {
          this.say({ id: m.id, working: true });
          this.say({ id: m.id, json: JSON.stringify({ frames: ["<g/>", "<g/>"], fps: 30, view: [0, 0, 1, 1], code: m.code, error: null }) });
        }
      }, 5);
    }
    terminate() { this.terminated = true; }
  }

  class FakeBlob {
    constructor(parts, opts) { this.text = parts.join(""); this.type = (opts && opts.type) || ""; }
  }
  const FakeURL = {
    createObjectURL: (blob) => { const u = "blob:" + (nextBlob++); blobs[u] = blob; return u; },
    revokeObjectURL: () => {}
  };
  const fakeFetch = (url) => {
    fetched.push(url);
    if (url.endsWith("player.js")) {
      return Promise.resolve({ ok: true, status: 200, text: () => Promise.resolve("/*PLAYER*/ var end = '</script>';") });
    }
    if (url.endsWith("beat.wav")) {
      const buf = Uint8Array.from([82, 73, 70, 70]).buffer; // "RIFF"
      return Promise.resolve({ ok: true, status: 200, headers: { get: () => "audio/wav" }, arrayBuffer: () => Promise.resolve(buf) });
    }
    return Promise.resolve({ ok: false, status: 404 });
  };

  const document = {
    getElementById: (id) => elements[id] || extra.find((e) => e.id === id) || null,
    createElement: (tag) => {
      const e = element("");
      e.tag = tag;
      if (tag === "a") {
        e.click = () => {
          const b = blobs[e.href];
          downloads.push({ filename: e.download, mime: b ? b.type : "", content: b ? b.text : "" });
        };
      }
      extra.push(e);
      return e;
    },
    head: {
      appendChild: (s) => {
        scripts.push(s.src);
        setTimeout(() => {
          if (!options.pageEngine) { if (s.onerror) s.onerror(); return; }
          if (s.src.endsWith("ruby-engine.js")) win.AsobiRubyEngine = pageRuby;
          if (s.onload) s.onload();
        }, 0);
        return s;
      }
    },
    body: { appendChild: (e) => e },
    execCommand: () => false,
    querySelector: (sel) => (sel === ".play" ? playEl : null)
  };
  class FakeFileReader {
    readAsDataURL(file) {
      dataReads.push(file.name);
      setTimeout(() => {
        this.result = "data:" + (file.type || "application/octet-stream") + ";base64," + Buffer.from(file.bytes()).toString("base64");
        this.onload();
      }, 0);
    }
  }
  class FakeChannel {
    constructor(name) { this.name = name; channels.push(this); }
    postMessage(m) { posted.push(m); }
  }
  const win = {
    document, Worker: FakeWorker, JSON, Promise, Object, Number, String, Math, Date, Uint8Array,
    Blob: FakeBlob, URL: FakeURL, fetch: fakeFetch, FileReader: FakeFileReader,
    crypto: options.subtle === false ? undefined : nodeCrypto.webcrypto,
    BroadcastChannel: options.stage ? FakeChannel : undefined,
    Event: class { constructor(type) { this.type = type; } },
    setTimeout, clearTimeout, setInterval, clearInterval,
    performance: { now: () => Date.now() },
    location: { protocol: options.protocol || "https:", hash: "", search: options.selftest === false ? "" : "?selftest=1", pathname: "/playground.html", href: "http://x/playground.html" },
    history: { replaceState: () => {} },
    navigator: {},
    btoa: (s) => Buffer.from(s, "binary").toString("base64"),
    requestAnimationFrame: () => 0,
    addEventListener: () => {},
    console: { error: () => {}, log: () => {} },
    AsobiPlayer: { mount: () => ({ update: (reel) => shown.push(reel) }) },
    AsobiCodeURL: { fromHash: () => null, key: () => "k", encode: () => "e" },
    AsobiSite: { loadReel: () => {}, setLanguageHash: () => {}, pad: String, frameAt: () => 0 }
  };
  win.window = win;
  vm.createContext(win);
  if (!options.noChecker) vm.runInContext(safeSource, win);
  vm.runInContext(source, win);

  const editor = elements.code;
  return {
    workers, shown, scripts, downloads, fetched, reads, dataReads, posted, blobs, pageRuby, playEl, editor,
    downloadBtn: elements.download,
    status: () => elements.status.textContent,
    marker: () => { const m = extra.find((e) => e.id === "selftest"); return m ? JSON.parse(m.textContent) : null; },
    edit: (code) => { editor.value = code; editor.dispatchEvent({ type: "input" }); },
    file: (name, size, type) => new FakeFile(name, size, type, pattern, reads),
    // what the file input does once files are chosen
    choose: (files) => { const input = elements["song-file"]; input.files = files; input.dispatchEvent({ type: "change" }); },
    // a stage window says hello on the channel
    stageHello: () => channels[0].onmessage({ data: { type: "hello", seq: null } }),
    songMessages: (w) => w.got.filter((m) => m.type === "song")
  };
}

const cfg = JSON.parse(config);
const brief = (p) => ({
  workers: p.workers.map((w) => ({ terminated: w.terminated, ran: w.got.map((m) => m.code) })),
  errors: p.shown.filter((r) => r.error).map((r) => r.error),
  status: p.status(),
  marker: p.marker(),
  scripts: p.scripts.length
});

(async () => {
  const result = { crashed: cfg.ui.crashed, ruby_failed: cfg.ui.ruby_failed, blocked: cfg.ui.blocked };

  // 1. Ruby breaks while running a sketch ({ id, fatal }): a new worker, a
  //    friendly message, the crashed code is not run again, the next edit runs.
  {
    const p = page({});
    await sleep(50);
    p.edit("crash a");
    await sleep(500);
    result.fatalThen = brief(p);
    p.edit("fine b");
    await sleep(500);
    result.fatalAfter = brief(p);
  }

  // The worker is started at an address with the version, and the hash says the same.
  {
    const p = page({});
    await sleep(50);
    const [path, hash] = p.workers[0].url.split("#");
    const where = JSON.parse(Buffer.from(hash.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"));
    result.workerStart = { path, v: where.v };
  }

  // 2. The worker itself breaks (an error event): the same.
  {
    const p = page({});
    await sleep(50);
    p.edit("error a");
    await sleep(500);
    p.edit("fine b");
    await sleep(500);
    result.error = brief(p);
  }

  // 3. A newer edit is waiting when Ruby breaks: it runs on the new worker.
  //    (Without ?selftest=1, which would run the code again anyway.)
  {
    const p = page({ selftest: false });
    await sleep(50);
    p.edit("hold a");
    await sleep(450);
    p.edit("fine b");                    // sent to the old worker, which is still busy with "hold a"
    await sleep(400);
    const old = p.workers[p.workers.length - 1];
    old.say({ id: old.held, fatal: "RuntimeError: unreachable" });
    await sleep(200);
    result.newest = brief(p);
    result.newest.last = p.shown[p.shown.length - 1];
  }

  // 4. The fresh worker cannot start: stop there, say so, no loop and no
  //    switch to the page engine.
  {
    const p = page({ failBootAfter: 1 });
    await sleep(50);
    p.edit("crash a");
    await sleep(500);
    p.edit("fine b");
    await sleep(500);
    result.bootFails = brief(p);
  }

  // 5. A sketch whose SVG is not asobi's own (it changed the SVG writer):
  //    the player gets an error Reel saying so, never those frames. Odd
  //    messages from the worker (not objects, an id of "__proto__") are
  //    ignored.
  {
    const p = page({});
    await sleep(50);
    p.edit("attack a");
    await sleep(500);
    result.attack = brief(p);
    result.attack.shown = p.shown.map((r) => (r.error ? { error: r.error, code: r.code, frames: r.frames || null } : { frames: r.frames }));
    result.attack.polluted = Object.prototype.previewed !== undefined;
    p.edit("fine b");
    await sleep(500);
    result.attack.after = p.marker();
  }

  // 6. Without the checker on the page, nothing from the engine is shown.
  {
    const p = page({ noChecker: true });
    await sleep(50);
    p.edit("fine b");
    await sleep(500);
    result.noChecker = brief(p);
    result.noChecker.frames = p.shown.filter((r) => r.frames).length;
  }

  // 7. On http/https a worker that cannot start does not lead to Ruby on
  //    the page (it could reach the whole page): stop and say so. On
  //    file:// the page engine is still the fallback.
  {
    const p = page({ failBootAfter: 0, protocol: "https:" });
    await sleep(200);
    result.httpsNoWorker = brief(p);
    const f = page({ failBootAfter: 0, protocol: "file:" });
    await sleep(200);
    result.fileNoWorker = brief(f);
  }

  // 8. Saving: still picture -> asobi.svg; pending motion -> waits; moving /
  //    reacting / song picture -> standalone asobi.html with embedded player
  //    and song data URI, strictly from the checked Reel.
  {
    const p = page({ selftest: false });
    await sleep(50);
    p.edit("still a");
    await sleep(450);
    const stillLabel = p.downloadBtn.textContent;
    p.downloadBtn.click();

    p.edit("hold a");
    await sleep(450);
    const pendingLabel = p.downloadBtn.textContent;
    p.downloadBtn.click();
    const pendingStatus = p.status();
    const countWhilePending = p.downloads.length;

    const p2 = page({ selftest: false });
    await sleep(50);
    p2.edit("song a");
    await sleep(450);
    const dynamicLabel = p2.downloadBtn.textContent;
    p2.downloadBtn.click();
    await sleep(50);
    // An attack never overwrites onScreen, so saving stays safe.
    p2.edit("attack a");
    await sleep(450);
    p2.downloadBtn.click();
    await sleep(50);

    result.saving = {
      stillLabel, pendingLabel, pendingStatus, countWhilePending, dynamicLabel,
      waitToSave: cfg.ui.wait_to_save,
      saveSvg: cfg.ui.save_svg,
      saveHtml: cfg.ui.save_html,
      svgDownload: p.downloads[0],
      htmlDownload: p2.downloads[0],
      afterAttackDownload: p2.downloads[1],
      fetched: p2.fetched
    };
  }

  // 9. Songs chosen on the page: the code gets play "NAME", the worker is
  //    told the song before the run, the Reel's "user/<id>" plays from the
  //    file's blob: URL, the same file keeps its URL, asobi.html carries the
  //    song inside, a new worker after a crash is told every song first,
  //    and a link's "user/<id>" for a file never chosen plays nothing.
  // (9 to 14 are pages of their own, so they run side by side: see the end.)
  async function songsChosen() {
    const p = page({ selftest: false });
    await sleep(50);
    p.edit('require "asobi"\n\nshow circle\n');
    await sleep(450);
    const w0 = p.workers[0];

    p.choose([p.file("notes.txt", 10, "text/plain")]);
    await sleep(50);
    const notSong = { status: p.status(), told: p.songMessages(w0).length, read: p.reads.length, code: p.editor.value };

    const best = p.file('my "best" #{song}.mp3', 5000, "audio/mpeg");
    p.choose([best]);
    await sleep(150);
    const firstCode = p.editor.value;
    const told = w0.got.findIndex((m) => m.type === "song");
    const ranAfter = w0.got.findIndex((m) => m.code === firstCode);
    const playedBest = p.shown[p.shown.length - 1];
    const bestSrc = playedBest.song ? playedBest.song.src : null;
    const readyStatus = p.status();

    p.edit("play 'other.wav', volume: 0.5\nshow circle\n");
    await sleep(450);
    const copy = p.file("beat copy.wav", 3000, "audio/wav");
    p.choose([copy]);
    await sleep(150);
    const secondCode = p.editor.value;
    const copySrc = p.shown[p.shown.length - 1].song.src;
    const blobsBefore = Object.keys(p.blobs).length;
    p.choose([p.file("beat copy.wav", 3000, "audio/wav")]); // the same file again
    await sleep(150);
    const sameAgain = { blobs: Object.keys(p.blobs).length - blobsBefore, src: p.shown[p.shown.length - 1].song.src === copySrc };

    p.downloadBtn.click();
    await sleep(50);
    const html = p.downloads[p.downloads.length - 1];

    p.edit("crash a");
    await sleep(500);
    const w1 = p.workers[1];
    const replay = w1.got.map((m) => (m.type === "song" ? "song:" + m.name : "run:" + m.code));
    p.edit('play "my \\"best\\" \\#{song}.mp3"\nshow circle moving\n');
    await sleep(500);
    const again = p.shown[p.shown.length - 1];

    p.edit("spoof a");
    await sleep(450);
    const spoofed = p.shown[p.shown.length - 1];

    result.songs = {
      notSong,
      firstCode, songMessage: w0.got[told], expectedId: expectedId(5000, pattern), toldBeforeRun: told >= 0 && told < ranAfter,
      bestSrc, bestIsTheFile: p.blobs[bestSrc] === best, readyStatus,
      secondCode, copyIsBlob: /^blob:/.test(copySrc), sameAgain,
      html: { filename: html.filename, data: html.content.includes("data:audio/wav;base64," + Buffer.from(copy.bytes()).toString("base64")),
              blob: html.content.includes("blob:"), user: html.content.includes("user/") },
      fetchedBlob: p.fetched.some((u) => /^blob:/.test(u)), dataReads: p.dataReads.slice(),
      replay, againSrc: again.song ? again.song.src : null, againPending: !!again.pending, bestSrcNow: bestSrc,
      spoofed: { song: spoofed.song || null, frames: spoofed.frames ? spoofed.frames.length : 0 }
    };
  }

  // 10. The song's id is the same with the browser's SHA-256 and with the
  //     page's own (no crypto.subtle), and the same as Node's.
  async function songIds() {
    const MIB = 1024 * 1024;
    const sizes = [5000, 3 * MIB + 5];
    const idsOf = async (subtle) => {
      const p = page({ selftest: false, subtle });
      await sleep(50);
      p.edit("show circle\n");
      await sleep(450);
      for (const size of sizes) {
        p.choose([p.file("s" + size + ".mp3", size, "audio/mpeg")]);
        await sleep(400);
      }
      return p.songMessages(p.workers[0]).map((m) => m.id);
    };
    const [withSubtle, withoutSubtle] = await Promise.all([idsOf(true), idsOf(false)]);
    result.ids = { subtle: withSubtle, js: withoutSubtle, node: sizes.map((s) => expectedId(s, pattern)), sizes };
  }

  // 11. A long song: only its first and last MiB are read for the id, it
  //     plays, and saving refuses to put it inside the page (over 20 MB).
  async function longSong() {
    const p = page({ selftest: false });
    await sleep(50);
    p.edit("show circle\n");
    await sleep(450);
    const size = 21 * 1024 * 1024 + 7;
    p.choose([p.file("long mix.mp3", size, "audio/mpeg")]);
    await sleep(300);
    const reel = p.shown[p.shown.length - 1];
    const before = p.downloads.length;
    p.downloadBtn.click();
    await sleep(50);
    result.big = {
      size, reads: p.reads, id: p.songMessages(p.workers[0])[0].id, expected: expectedId(size, pattern),
      playing: !!(reel.song && /^blob:/.test(reel.song.src)),
      status: p.status(), saved: p.downloads.length - before, dataReads: p.dataReads.slice(), fetched: p.fetched.slice()
    };
  }

  // 12. Dropping files on the playground: a drag of text is left alone; a
  //     drag of files shows the drop frame, and the dropped song is chosen.
  async function dropping() {
    const p = page({ selftest: false });
    await sleep(50);
    p.edit("show circle\n");
    await sleep(450);
    const prevented = [];
    const ev = (type, types, files) => ({ type, dataTransfer: { types, files, dropEffect: "none" }, preventDefault: () => prevented.push(type) });
    p.playEl.dispatchEvent(ev("dragenter", ["text/plain"]));
    p.playEl.dispatchEvent(ev("dragover", ["text/plain"]));
    p.playEl.dispatchEvent(ev("drop", ["text/plain"]));
    const text = { dropping: p.playEl.classList.contains("dropping"), prevented: prevented.splice(0) };
    p.playEl.dispatchEvent(ev("dragenter", ["Files"]));
    p.playEl.dispatchEvent(ev("dragover", ["Files"]));
    const over = p.playEl.classList.contains("dropping");
    p.playEl.dispatchEvent(ev("drop", ["Files"], [p.file("dropped.ogg", 2000, "audio/ogg")]));
    await sleep(200);
    result.drop = { text, over, after: p.playEl.classList.contains("dropping"), prevented, code: p.editor.value,
                    told: p.songMessages(p.workers[0]).map((m) => m.name) };
  }

  // 13. Previews while something is on screen: neither the player nor the
  //     stage gets a motion's one-frame preview (the picture goes on until
  //     the whole Reel), an error before it goes away, saving waits, and
  //     the stage never gets a song. With nothing on screen yet, the
  //     preview shows at once.
  async function previews() {
    const p = page({ selftest: false, stage: true });
    await sleep(50);
    p.stageHello();
    p.edit("still a");
    await sleep(450);
    let mark = p.shown.length, postMark = p.posted.length;
    p.edit("moving b"); // preview, working, the whole Reel
    await sleep(450);
    const moving = {
      shown: p.shown.slice(mark).map((r) => ({ pending: !!r.pending, frames: r.frames ? r.frames.length : 0 })),
      reels: p.posted.slice(postMark).filter((m) => m.type === "reel").map((m) => JSON.parse(m.json).pending === true)
    };
    p.edit("bad c");
    await sleep(450);
    mark = p.shown.length; postMark = p.posted.length;
    p.edit("hold d"); // its preview comes, the whole Reel never does
    await sleep(450);
    const held = {
      shown: p.shown.slice(mark).map((r) => ({ pending: !!r.pending, error: r.error || null, frames: r.frames ? r.frames.length : 0 })),
      posted: p.posted.slice(postMark).map((m) => (m.type === "error" ? { type: m.type, error: m.error } : { type: m.type })),
      label: p.downloadBtn.textContent
    };
    p.downloadBtn.click();
    held.status = p.status();
    held.downloads = p.downloads.length;

    const q = page({ selftest: false, stage: true });
    await sleep(50);
    q.stageHello();
    q.edit("song a");
    await sleep(450);
    q.choose([q.file("mine.mp3", 1000, "audio/mpeg")]);
    await sleep(200);
    const reelTexts = q.posted.filter((m) => m.type === "reel").map((m) => m.json);

    const first = page({ selftest: false });
    await sleep(50);
    first.edit("hold x");
    await sleep(450);
    result.pending = {
      moving, held,
      stage: { reels: reelTexts.length, songs: reelTexts.filter((j) => /"song"|blob:|user\//.test(j)).length,
               playerSongs: q.shown.filter((r) => r.song).map((r) => r.song.src.split(":")[0]) },
      firstLoad: first.shown.map((r) => !!r.pending)
    };
  }

  // 14. On file:// (Ruby on the page): the song is offered to that engine,
  //     and again to the fresh one after a crash.
  async function onThePage() {
    const p = page({ selftest: false, failBootAfter: 0, protocol: "file:", pageEngine: true });
    await sleep(200);
    p.edit("show circle\n");
    await sleep(450);
    p.choose([p.file("page.mp3", 1000, "audio/mpeg")]);
    await sleep(200);
    const played = p.shown[p.shown.length - 1];
    p.edit("crash a");
    await sleep(450);
    result.pageEngine = { calls: p.pageRuby.calls.map((c) => c.replace(/:[0-9a-f]{12}$/, ":ID")), src: played.song ? played.song.src : null };
  }

  await Promise.all([songsChosen(), songIds(), longSong(), dropping(), previews(), onThePage()]);

  console.log(JSON.stringify(result));
  process.exit(0);
})();
