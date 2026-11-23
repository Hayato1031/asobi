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
//   anything else preview, one "working", then the whole Reel
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const [playJs, playHtml] = process.argv.slice(2);
const source = fs.readFileSync(playJs, "utf8");
// The page loads the checker (safe-reel.js, next to playground.js) first.
const safeSource = fs.readFileSync(path.join(path.dirname(playJs), "safe-reel.js"), "utf8");
const ATTACK = '<image href="x:" onerror="alert(1)"/>';
const config = fs.readFileSync(playHtml, "utf8").match(/id="play-config">([\s\S]*?)<\/script>/)[1];

function element(id) {
  const listeners = {};
  return {
    id, value: "", textContent: "", hidden: false, disabled: false, scrollTop: 0, scrollLeft: 0, innerHTML: "",
    href: "", download: "",
    firstChild: { innerHTML: "" },
    addEventListener: (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); },
    dispatchEvent: (e) => { (listeners[e.type] || []).forEach((fn) => fn(e)); },
    click: () => { (listeners.click || []).forEach((fn) => fn({ type: "click" })); },
    focus: () => {}, remove: () => {}, setAttribute: () => {}
  };
}

function page(options) {
  const workers = [];   // every pretend worker made, in order
  const shown = [];     // every Reel given to the player
  const scripts = [];   // scripts added to the page (the page engine)
  const downloads = []; // every file triggered via <a download>
  const fetched = [];   // URLs passed to fetch
  const blobs = {};
  let nextBlob = 1;
  const elements = {};
  ["code", "stage", "status", "play-fc", "code-tint", "copy", "reset", "download"].forEach((id) => { elements[id] = element(id); });
  elements.download.disabled = true;
  elements["play-config"] = element("play-config");
  elements["play-config"].textContent = config;
  const extra = [];

  class FakeWorker {
    constructor(url) {
      this.url = url;
      this.got = [];
      this.terminated = false;
      this.held = null;
      workers.push(this);
      const failBoot = options.failBootAfter !== undefined && workers.length > options.failBootAfter;
      setTimeout(() => this.say(failBoot ? { type: "failed", message: "no wasm" } : { type: "ready" }), 5);
    }
    say(m) { if (!this.terminated && this.onmessage) this.onmessage({ data: m }); }
    postMessage(m) {
      this.got.push(m);
      if (this.held !== null) return; // busy with "hold": never gets to this one
      setTimeout(() => {
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
    head: { appendChild: (s) => { scripts.push(s.src); setTimeout(() => s.onerror && s.onerror(), 0); return s; } },
    body: { appendChild: (e) => e },
    execCommand: () => false
  };
  const win = {
    document, Worker: FakeWorker, JSON, Promise, Object, Number, String, Math, Date, Uint8Array,
    Blob: FakeBlob, URL: FakeURL, fetch: fakeFetch,
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
    workers, shown, scripts, downloads, fetched,
    downloadBtn: elements.download,
    status: () => elements.status.textContent,
    marker: () => { const m = extra.find((e) => e.id === "selftest"); return m ? JSON.parse(m.textContent) : null; },
    edit: (code) => { editor.value = code; editor.dispatchEvent({ type: "input" }); }
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

  console.log(JSON.stringify(result));
  process.exit(0);
})();
