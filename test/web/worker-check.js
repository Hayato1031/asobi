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
function fakeEngine(log) {
  let waiting = null;
  return {
    boot: () => Promise.resolve(),
    run: (code) => "whole:" + code,
    start: (code) => {
      waiting = code.startsWith("motion") || code.startsWith("broken") ? { code, left: 20, slices: 0 } : null;
      return { json: (waiting ? "preview:" : "whole:") + code, pending: !!waiting };
    },
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

function startWorker() {
  const out = [];
  const log = [];
  const hash = Buffer.from(JSON.stringify({ api: "api.js", wasm: "ruby.wasm" })).toString("base64").replace(/=+$/, "");
  const sandbox = {
    location: { hash: "#" + hash },
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    MessageChannel: QueuedChannel,
    importScripts: () => { sandbox.AsobiRubyEngine = fakeEngine(log); },
    postMessage: (m) => out.push(m)
  };
  sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox);
  // Messages arrive as their own tasks, like in a real worker.
  const send = (m) => setTimeout(() => sandbox.onmessage({ data: m }), 0);
  return { out, log, send };
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

  console.log(JSON.stringify(result));
  process.exit(0);
})();
