/* asobi playground: code on one side, the picture on the other.
 * Ruby runs in the browser with ruby.wasm, in a Web Worker when the page
 * allows it (http/https), otherwise on the page itself (file://).
 * The code lives in the address (#code=<base64url>), so a link shares it.
 */
(function () {
  "use strict";
  var cfg = JSON.parse(document.getElementById("play-config").textContent);
  var U = cfg.ui;
  var CodeURL = window.AsobiCodeURL;
  var editor = document.getElementById("code");
  var stage = document.getElementById("stage");
  var statusEl = document.getElementById("status");
  var selftest = /[?&]selftest=1\b/.test(location.search);

  var player = AsobiPlayer.mount(stage, { controls: true, keys: true, language: cfg.lang });
  var playerT0 = performance.now(); // the player's own clock starts at mount and never resets

  // A small truthful readout in the bar: which frame is on screen, how long a loop is.
  var fcEl = document.getElementById("play-fc");
  var onScreen = null;
  function show(reel) {
    // The song the site ships (play "beat.wav") has a src from the site's
    // root: put this page's assets folder in front, so it plays from /ja/ too.
    var s = reel && reel.song;
    if (s && typeof s.src === "string" && /^assets\//.test(s.src)) s.src = cfg.assets + s.src.slice(7);
    player.update(reel);
    if (reel && !reel.error && reel.frames) onScreen = reel;
  }
  (function readout() {
    if (onScreen && fcEl) {
      var n = onScreen.frames.length, text;
      if (onScreen.pending) text = "…"; // a motion's preview: the frames are on their way
      else if (n < 2) text = onScreen.parts || onScreen.song ? U.reacts : U.still;
      else {
        var f = window.AsobiSite ? AsobiSite.pad(AsobiSite.frameAt(playerT0, Number(onScreen.fps), n, performance.now()), n) : "";
        text = f + "/" + n + " · " + U.every.replace("%s", String(Math.round(n / Number(onScreen.fps) * 10) / 10));
      }
      if (fcEl.textContent !== text) fcEl.textContent = text;
    }
    requestAnimationFrame(readout);
  })();

  // ---- status line ---------------------------------------------------
  var statusTimer = 0;
  function status(text, linger) {
    clearTimeout(statusTimer);
    statusEl.textContent = text || "";
    if (text && linger) statusTimer = setTimeout(function () { statusEl.textContent = ""; }, linger);
  }

  // ---- the first picture, before Ruby is here ---------------------------
  var fromAddress = CodeURL.fromHash(location.hash);
  if (fromAddress !== null) editor.value = fromAddress;
  var shownFor = null; // the code whose picture is on screen
  // The default sketch, and every example on the site, was drawn when the
  // site was built: show that picture at once, while Ruby downloads.
  function showPrebuilt(code) {
    if (!window.AsobiSite) return;
    var key = code === cfg.defaultCode ? cfg.defaultKey : CodeURL.key(code);
    AsobiSite.loadReel(key, function (reel) {
      if (shownFor === null && editor.value === code) { show(reel); shownFor = code; }
    });
  }
  showPrebuilt(editor.value);

  // ---- the Ruby engine ------------------------------------------------------
  // Both engines (worker and page) answer  run(code, lang, onFirst):
  //   a promise of the whole Reel as a JSON string, or null when a newer run
  //   made this one out of date before its whole Reel was made.
  //   With onFirst, a motion comes in two steps: onFirst(json) gets a quick
  //   preview ("pending": true, one frame) as soon as the sketch has run.
  // When Ruby itself breaks (a crash inside ruby.wasm), the engine cannot be
  // trusted again: the run it was working on fails with { crashed: true },
  // the other waiting runs with { restart: true }, and lost() is called once
  // so that a fresh engine can be started.
  function b64(text) { return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }

  function workerEngine(lost) {
    return new Promise(function (resolve, reject) {
      var worker, settled = false, dead = false, runs = {}, nextId = 1, watchdog = 0;

      function waitingIds() {
        return Object.keys(runs).map(Number).sort(function (a, b) { return a - b; });
      }

      // Stop the worker for good. The oldest waiting run (the one it was
      // working on: it answers in order) fails with +why+, the rest restart.
      function stop(why) {
        clearTimeout(watchdog);
        dead = true;
        worker.terminate();
        waitingIds().forEach(function (id, i) { runs[id].rej(i === 0 ? why(runs[id]) : { restart: true }); });
        runs = {};
      }

      // Ruby broke inside the worker: throw the worker away.
      function crash(message) {
        if (dead) return;
        stop(function () { return { crashed: true, message: message }; });
        lost();
      }

      // If the worker stays silent for too long while something waits, it is
      // stuck (a loop that never ends?): stop it. While a whole Reel is made,
      // the worker says { working: true } between slices, so silence there
      // means one slice is stuck.
      function watch() {
        clearTimeout(watchdog);
        var ids = waitingIds();
        if (!ids.length) return;
        var allPreviewed = ids.every(function (id) { return runs[id].previewed; });
        watchdog = setTimeout(function () {
          stop(function (r) { return { timeout: true, previewed: r.previewed }; });
        }, allPreviewed ? cfg.finishTimeout : cfg.timeout);
      }

      var api = {
        run: function (code, lang, onFirst) {
          return new Promise(function (res, rej) {
            if (dead) { rej({ restart: true }); return; }
            var id = nextId++;
            runs[id] = { res: res, rej: rej, onFirst: onFirst, previewed: false };
            worker.postMessage(onFirst ? { id: id, code: code, lang: lang, preview: true } : { id: id, code: code, lang: lang });
            watch();
          });
        }
      };
      try {
        var where = JSON.stringify({ api: cfg.rubyWasm.api, wasm: cfg.rubyWasm.wasm });
        worker = new Worker(cfg.assets + "ruby-worker.js#" + b64(where));
      } catch (e) { reject(e); return; }
      worker.onmessage = function (e) {
        var m = e.data;
        if (m.type === "ready") { settled = true; resolve(api); return; }
        if (m.type === "failed") { settled = true; worker.terminate(); reject(new Error(m.message)); return; }
        if (m.fatal) { crash(m.fatal); return; }
        var r = runs[m.id];
        if (!r) return;
        if (m.working) { watch(); return; } // still making the whole Reel
        if (m.pending) {
          r.previewed = true;
          if (r.onFirst) r.onFirst(m.json);
        } else {
          delete runs[m.id];
          r.res(m.skipped ? null : m.json);
        }
        watch();
      };
      worker.onerror = function (e) {
        if (e && e.preventDefault) e.preventDefault();
        if (settled) { crash(String((e && e.message) || "worker error")); return; }
        settled = true;
        reject(new Error("worker"));
      };
    });
  }

  var added = {}; // each script is added to the page once, even when Ruby restarts
  function addScript(src) {
    if (added[src]) return added[src];
    return added[src] = new Promise(function (resolve, reject) {
      var s = document.createElement("script");
      s.src = src; s.async = false;
      s.onload = resolve;
      s.onerror = function () { delete added[src]; reject(new Error("could not load " + src)); };
      document.head.appendChild(s);
    });
  }

  // Fallback (file://, or no Worker): the same engine on the page.
  // A motion's whole Reel is made in slices too, with a pause between them,
  // so the page keeps answering (and a newer run can stop the build).
  // After a crash it boots a fresh Ruby VM on the page.
  function pageEngine(lost) {
    var latest = 0;      // the number of the newest run asked for
    var building = null; // the run whose whole Reel is being made: { mine, res }
    var dead = false;
    var R;               // AsobiRubyEngine

    function stopBuilding() {
      if (!building) return;
      var b = building;
      building = null;
      b.res(null);
      R.drop();
    }

    function crash(rej, e) {
      building = null;
      dead = true;
      rej({ crashed: true, message: String((e && e.message) || e) });
      lost();
    }

    // ruby.wasm's browser API: the one external resource (pinned, cdn.jsdelivr.net).
    return addScript(cfg.rubyWasm.api)
      .then(function () { return addScript(cfg.assets + "asobi-ruby.js"); })
      .then(function () { return addScript(cfg.assets + "ruby-engine.js"); })
      .then(function () { R = window.AsobiRubyEngine; return R.boot(cfg.rubyWasm.wasm); })
      .then(function () {
        return {
          run: function (code, lang, onFirst) {
            var mine = ++latest;
            return new Promise(function (res, rej) {
              setTimeout(function () {
                if (dead) { rej({ restart: true }); return; }
                if (onFirst && mine !== latest) { res(null); return; } // a newer run is waiting
                try {
                  stopBuilding(); // anything newer ends the build of an older whole Reel
                  if (!onFirst) { res(R.run(code, lang)); return; }
                  var first = R.start(code, lang);
                  if (!first.pending) { res(first.json); return; }
                  onFirst(first.json);
                } catch (e) { crash(rej, e); return; }
                building = { mine: mine, res: res };
                // Give the page a moment to draw the preview (and to notice new
                // typing) before the long part.
                setTimeout(function slice() {
                  if (dead || !building || building.mine !== mine) return; // stopped (and answered) already
                  if (mine !== latest) { try { stopBuilding(); } catch (e) { crash(rej, e); } return; }
                  var done;
                  try { done = R.step(0.08); } catch (e) { crash(rej, e); return; }
                  if (!done.done) { setTimeout(slice, 0); return; }
                  building = null;
                  res(done.json);
                }, 50);
              }, 0);
            });
          }
        };
      });
  }

  var engine = null, onPage = false;
  // afterCrash: Ruby worked before and broke. Start a fresh engine of the same
  // kind; if that fails too, stop there (no restart loop, no switching).
  function boot(afterCrash) {
    status(U.loading_ruby);
    var start = onPage ? pageEngine(lost)
      : workerEngine(lost).catch(function (e) {
          if (afterCrash) throw e;
          onPage = true;
          return pageEngine(lost);
        });
    start.then(function (e) {
      engine = e;
      status(U.ruby_ready, 2500);
      if (selftest || editor.value !== shownFor) request();
    }, function (err) {
      status(U.ruby_failed);
      if (window.console) console.error("asobi playground:", err);
    });
  }

  // The engine broke (Ruby crashed inside ruby.wasm): start a fresh one.
  // The newest code runs on it once it is ready (see boot); the code that
  // crashed waits until it is changed (see runAndShow).
  function lost() {
    engine = null;
    boot(true);
  }

  // ---- running -------------------------------------------------------------
  // Every edit is sent at once, without waiting for the run before it: the
  // engine skips work that a newer edit has made out of date. Answers can
  // still arrive late, so each run has a number and the screen only moves
  // forward: an answer older than the one on screen is dropped.
  var debounce = 0;
  var stuck = null;     // code that ran too long: not run again until it changes
  var newestRun = 0;    // the number of the newest run
  var onScreenRun = 0;  // the number of the run whose answer is on screen

  function request() {
    if (!engine) return;            // runs once Ruby is ready
    if (editor.value === stuck) return;
    runAndShow(editor.value);
  }

  // Show an answer of run number +run+, unless a newer run is already on screen.
  function showAnswer(run, reel) {
    if (run < onScreenRun) return false;
    onScreenRun = run;
    show(reel);
    return true;
  }

  // Run the code and show what comes back: a motion's preview first, then
  // the whole Reel. Resolves with the whole Reel (an object), or null when a
  // newer run made it out of date.
  function runAndShow(code) {
    var run = ++newestRun;
    var hint = setTimeout(function () { status(U.running); }, 300);
    function quiet() {
      clearTimeout(hint);
      if (statusEl.textContent === U.running) status("");
    }
    function onFirst(json) {
      quiet();
      showAnswer(run, JSON.parse(json));
    }
    return engine.run(code, cfg.lang, onFirst).then(function (json) {
      if (json === null) return null;
      var reel = JSON.parse(json);
      if (showAnswer(run, reel) && !reel.error) shownFor = code;
      mark(reel);
      return reel;
    }, function (err) {
      if (err && err.restart) return null; // the engine is restarting; boot() runs the newest code again
      var message;
      if (err && err.timeout) {
        message = err.previewed ? U.too_slow_whole : U.too_slow;
        stuck = code;
        engine = null;
        boot();
      } else if (err && err.crashed) {
        message = U.crashed; // a fresh engine is already on its way (lost)
        stuck = code;
        if (window.console) console.error("asobi playground: Ruby crashed:", err.message);
      } else {
        message = String((err && err.message) || err);
      }
      showAnswer(run, { error: message, code: code });
      mark({ error: "engine: " + String((err && err.message) || (err && err.crashed ? "crashed" : "timeout")) });
      return { error: message };
    }).then(function (reel) {
      quiet();
      return reel;
    });
  }

  // ?selftest=1 : leave a marker for automated checks once Ruby has run.
  function mark(reel) {
    if (!selftest) return;
    var out = document.getElementById("selftest") || document.body.appendChild(document.createElement("output"));
    out.id = "selftest";
    out.hidden = true;
    out.textContent = JSON.stringify({
      error: reel.error || null,
      frames: reel.frames ? reel.frames.length : 0,
      first: reel.frames ? String(reel.frames[0]).slice(0, 300) : null
    });
  }

  // ---- tint: a tinted copy of the code sits under the (see-through) editor --
  var tintBox = document.getElementById("code-tint");
  var tintCode = tintBox && tintBox.firstChild;
  function retint() {
    if (!tintCode || !window.AsobiTint) return;
    var text = editor.value;
    tintCode.innerHTML = AsobiTint(text, cfg.words) + (text.endsWith("\n") ? " " : "");
    syncScroll();
  }
  function syncScroll() {
    if (tintBox) { tintBox.scrollTop = editor.scrollTop; tintBox.scrollLeft = editor.scrollLeft; }
  }
  editor.addEventListener("scroll", syncScroll);
  retint();

  // ---- the address keeps the code -----------------------------------------
  function sketchHash() { return "#code=" + CodeURL.encode(editor.value); }
  function replaceHash(hash) {
    try { history.replaceState(null, "", location.pathname + location.search + hash); } catch (e) { location.hash = hash; }
    AsobiSite.setLanguageHash(hash);
  }

  editor.addEventListener("input", function () {
    retint();
    replaceHash(sketchHash());
    clearTimeout(debounce);
    debounce = setTimeout(request, 350);
  });

  window.addEventListener("hashchange", function () {
    var code = CodeURL.fromHash(location.hash);
    if (code !== null && code !== editor.value) { editor.value = code; retint(); request(); }
    // Jumping to the word list changes the fragment. Keep the edited sketch in the translation link.
    if (code === null && editor.value !== cfg.defaultCode) AsobiSite.setLanguageHash(sketchHash());
  });

  // ---- editing: Tab inserts two spaces; Esc then Tab leaves --------------
  var escaped = false;
  editor.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { escaped = true; return; }
    if (e.key === "Tab" && !escaped && !e.shiftKey && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      if (!document.execCommand || !document.execCommand("insertText", false, "  ")) {
        editor.setRangeText("  ", editor.selectionStart, editor.selectionEnd, "end");
        editor.dispatchEvent(new Event("input"));
      }
      return;
    }
    if (e.key !== "Shift") escaped = false;
  });

  // ---- buttons -----------------------------------------------------------------
  document.getElementById("copy").addEventListener("click", function () {
    replaceHash(sketchHash());
    var link = location.href;
    function fallback() {
      var box = document.createElement("textarea");
      box.value = link; box.setAttribute("readonly", ""); box.style.position = "fixed"; box.style.opacity = "0";
      document.body.appendChild(box); box.select();
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      box.remove();
      status(ok ? U.copied : U.copy_failed, 3000);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(link).then(function () { status(U.copied, 3000); }, fallback);
    } else fallback();
  });

  document.getElementById("reset").addEventListener("click", function () {
    editor.value = cfg.defaultCode;
    retint();
    replaceHash("");
    if (engine) request(); else { shownFor = null; showPrebuilt(cfg.defaultCode); }
    editor.focus();
  });

  // ---- WebMCP: allow AI agents to run & inspect Ruby sketches in ruby.wasm ----
  function setupPlaygroundWebMCP() {
    if (!window.AsobiWebMCP) return;
    function waitForEngine(ms) {
      if (engine) return Promise.resolve(engine);
      return new Promise(function (resolve, reject) {
        var deadline = Date.now() + ms;
        var timer = setInterval(function () {
          if (engine) { clearInterval(timer); resolve(engine); }
          else if (Date.now() >= deadline) { clearInterval(timer); reject(new Error(U.loading_ruby)); }
        }, 120);
      });
    }
    function textResult(data, isError) {
      var res = { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
      if (isError) res.isError = true;
      return res;
    }

    window.AsobiWebMCP.register([
      {
        name: "asobi_get_editor_code",
        description: "Get the current Ruby code in the asobi playground editor, its shareable URL, and whether ruby.wasm is ready.",
        inputSchema: { type: "object", properties: {} },
        execute: function () {
          replaceHash(sketchHash());
          return textResult({
            rubyReady: !!engine,
            code: editor.value,
            shareUrl: location.href,
            frames: onScreen && onScreen.frames ? onScreen.frames.length : 0
          });
        }
      },
      {
        name: "asobi_run_code",
        description: "Set Ruby code in the asobi playground editor, run it using ruby.wasm, update the canvas, and return SVG frame metadata.",
        inputSchema: {
          type: "object",
          properties: { code: { type: "string", description: "Ruby sketch using asobi (typically ending with show)." } },
          required: ["code"]
        },
        execute: function (args) {
          var code = String((args && args.code) || "");
          if (!code.trim()) return textResult({ error: "code is required" }, true);
          editor.value = code;
          retint();
          replaceHash(sketchHash());
          return waitForEngine(20000).then(function () {
            return runAndShow(code); // shows a motion's preview first; answers with the whole Reel
          }).then(function (reel) {
            if (!reel) return textResult({ error: "A newer run replaced this one before it finished." }, true);
            return textResult({
              error: reel.error || null,
              frames: reel.frames ? reel.frames.length : 0,
              fps: reel.fps || null,
              view: reel.view || null,
              background: reel.background || null,
              firstFrameSvg: reel.frames && reel.frames[0] ? String(reel.frames[0]).slice(0, 4000) : null,
              shareUrl: location.href
            }, !!reel.error);
          }, function (err) {
            return textResult({ error: String((err && err.message) || err) }, true);
          });
        }
      }
    ]);
  }

  boot();
  setupPlaygroundWebMCP();
})();
