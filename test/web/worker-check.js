// Checks the playground worker's messages (site/playground/ruby-worker.js)
// with a pretend Ruby engine, in plain Node (no browser, no ruby.wasm).
//
//   node test/web/worker-check.js _site/assets/ruby-worker.js
//
// Prints a JSON object: for each scenario, the messages the worker sent.
// test/site_test.rb runs it and checks the answers.
"use strict";
const fs = require("fs");
const vm = require("vm");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const source = fs.readFileSync(process.argv[2], "utf8");

// A pretend engine. A motion ("motion ..." code) needs 20 slices of step,
// each about 5 ms of work.
// "broken ..." throws on its second slice, as a crashed ruby.wasm would.
// order: every start and offerSong, in the order the engine got them.
function fakeEngine(log, order) {
  let waiting = null;
  return {
    boot: () => Promise.resolve(),
    run: (code) => "whole:" + code,
    start: (code) => {
      order.push("start " + code);
      waiting = code.startsWith("motion") || code.startsWith("broken") ? { code, left: 20, slices: 0 } : null;
      return { json: (waiting ? "preview:" : "whole:") + code, pending: !!waiting };
    },
    offerSong: (name, id) => { order.push("song " + name + " " + id); return true; },
    step: (seconds) => {
      log.push("step " + seconds);
      if (!waiting) return { done: true, json: null };
      const end = Date.now() + 5;
      while (Date.now() < end) { /* work */ }
      waiting.slices++;
      if (waiting.code.startsWith("broken") && waiting.slices === 2) throw new Error("RuntimeError: unreachable");
      if (--waiting.left > 0) return { done: false };
      const json = "whole:" + waiting.code;
      waiting = null;
      return { done: true, json };
    },
    drop: () => { log.push("drop"); waiting = null; }
  };
}

// Like a browser's MessageChannel: a message posted to it queues behind the
// messages already waiting (here: timers that were set earlier).
class QueuedChannel {
  constructor() {
    const self = this;
    this.port1 = { onmessage: null };
    this.port2 = { postMessage: (data) => setTimeout(() => self.port1.onmessage({ data }), 0) };
  }
}

function startWorker(extra = {}) {
  const out = [];
  const log = [];
  const order = [];
  const imports = [];
  const hash = Buffer.from(JSON.stringify({ api: "api.js", wasm: "ruby.wasm", ...extra })).toString("base64").replace(/=+$/, "");
  const sandbox = {
    location: { hash: "#" + hash },
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    MessageChannel: QueuedChannel,
    importScripts: (...names) => { imports.push(names); sandbox.AsobiRubyEngine = fakeEngine(log, order); },
    postMessage: (m) => out.push(m)
  };
  sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  // Messages arrive as their own tasks, like in a real worker.
  const send = (m) => setTimeout(() => sandbox.onmessage({ data: m }), 0);
  return { out, log, order, send, imports };
}

async function until(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (fn()) return true; await sleep(5); }
  return false;
}

(async () => {
  const result = {};

  // 1. A motion: preview, "working" between slices, then the whole Reel.
  {
    const w = startWorker();
    w.send({ id: 1, code: "motion a", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.id === 1 && m.json && !m.pending));
    w.send({ id: 2, code: "still", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.id === 2));
    result.whole = { out: w.out, log: w.log };
  }

  // 2. A newer edit while the whole Reel is being made: the old build stops
  //    (dropped, answered skipped) before the newer one starts.
  {
    const w = startWorker();
    w.send({ id: 1, code: "motion a", lang: "en", preview: true });
    await until(() => w.out.filter((m) => m.id === 1 && m.working).length >= 1);
    w.send({ id: 2, code: "motion b", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.id === 2 && m.json && !m.pending));
    result.newer = { out: w.out, log: w.log };
  }

  // 3. The engine fails halfway through a build: { id, fatal }.
  {
    const w = startWorker();
    w.send({ id: 1, code: "broken a", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.fatal));
    await sleep(30);
    result.fatal = { out: w.out, log: w.log };
  }

  // 4. With a version, the site's own two scripts are asked for with ?v=<v>
  //    and the pinned CDN file is not. A v that is not hex is ignored.
  result.versioned = { imports: startWorker({ v: "0a1b" }).imports };
  result.notHex = ["../x", "a&b", 12].map((v) => ({ imports: startWorker({ v }).imports }));

  // 5. A song chosen on the page ({ type: "song" }) is offered before the
  //    run sent after it, and gets no answer.
  {
    const w = startWorker();
    w.send({ type: "song", name: "my.mp3", id: "0123456789ab" });
    w.send({ id: 1, code: "still", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.id === 1));
    result.song = { order: w.order, out: w.out };
  }

  // 6. A song offered while a motion's whole Reel is being made does not
  //    stop that build.
  {
    const w = startWorker();
    w.send({ id: 1, code: "motion a", lang: "en", preview: true });
    await until(() => w.out.some((m) => m.id === 1 && m.working));
    w.send({ type: "song", name: "b.mp3", id: "bbbbbbbbbbbb" });
    await until(() => w.out.some((m) => m.id === 1 && m.json && !m.pending));
    result.songWhileBuilding = { order: w.order, log: w.log, out: w.out.filter((m) => !m.working && !m.type) };
  }

  console.log(JSON.stringify(result));
  process.exit(0);
})();
