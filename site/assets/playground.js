/* asobi playground: code on one side, the picture on the other.
 * Ruby runs in the browser with ruby.wasm, in a Web Worker. Only on file://
 * (where a page cannot start a worker) does it run on the page itself: there
 * Ruby can reach the whole page, so a site on http/https never does that.
 * The code lives in the address (#code=<base64url>), so a link shares it.
 * Anyone can write that code, so whatever an engine answers is untrusted:
 * it goes through AsobiSafeReel (safe-reel.js) before the player sees it.
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

  // ---- the stage window: a second window that shows code and picture big ----
  // It only receives (BroadcastChannel "asobi-stage"); Ruby, sound and
  // reactions stay here. While no stage window is listening this costs
  // nothing. A stage counts as alive while its hello / here was heard within
  // the last 6 s (they come as messages, which a hidden page still gets).
  // The stage gets the code as typed, the error, and the Reel on show
  // (without the song, which plays here). It checks the Reel with
  // AsobiSafeReel as this page does and plays it by its own clock, so this
  // page does no work per frame for it. Only a Reel with reacting parts is
  // mirrored: then this page also sends a snapshot of its player's <svg>
  // whenever it changes (at most once per frame), so a click here shows
  // there; while this page is hidden (no animation frames), the stage plays
  // that Reel itself too, its parts at rest. Every shown Reel gets a seq
  // (this page's own prefix, then a count); a hello names the seq the stage
  // has, so a big Reel goes over once, not with every hello. visibility
  // tells the stage when to play by itself and when to mirror again.
  var channel = null, aliveUntil = 0, observer = null, observed = null;
  var sendQueued = false, watchTimer = 0, stageError = null;
  var reelPrefix = Math.random().toString(36).slice(2, 8), reelCount = 0, reelSeq = null, reelOnShow = null;
  var rawJson = typeof WeakMap === "function" ? new WeakMap() : null; // Reel -> the engine's JSON for it
  try { if (window.BroadcastChannel) channel = new BroadcastChannel("asobi-stage"); } catch (e) { channel = null; }

  function stageAlive() { return !!channel && performance.now() < aliveUntil; }
  function post(message) { try { channel.postMessage(message); } catch (e) { /* a closed channel: nothing to tell */ } }

  function postCode() { if (stageAlive()) post({ type: "code", code: editor.value }); }
  function postError() { if (stageAlive()) post({ type: "error", error: stageError }); }

  // The player's svg as standalone markup for the stage (which draws it as an image only).
  function serialisePicture() {
    var svg = stage.querySelector("svg.asobi-svg");
    var box = svg && svg.getAttribute("viewBox");
    if (!svg || !box) return null;
    var view = box.trim().split(/[\s,]+/).map(Number);
    if (view.length !== 4 || view.some(function (n) { return !isFinite(n); })) return null;
    var copy = svg.cloneNode(true);
    copy.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    copy.removeAttribute("class");
    copy.removeAttribute("width");
    copy.removeAttribute("height");
    var rect = svg.querySelector("rect");
    return {
      type: "picture",
      svg: new XMLSerializer().serializeToString(copy),
      view: view,
      background: (rect && rect.getAttribute("fill")) || ""
    };
  }

  // The Reel on show, for the stage to play. A Reel from the engine goes as
  // the JSON text it came in (a big one is tens of MB: making it again would
  // stop this page); the stage checks it again and leaves out the song.
  function postReel() {
    if (!stageAlive() || !reelOnShow) return;
    var r = reelOnShow, json = rawJson && rawJson.get(r);
    if (!json) {
      var copy = {};
      for (var k in r) if (k !== "song") copy[k] = r[k];
      json = JSON.stringify(copy);
    }
    post({ type: "reel", seq: reelSeq, json: json, frames: r.frames.length, fps: Number(r.fps) || 1, parts: !!r.parts, at: Date.now() });
  }

  // At most one picture per animation frame; the newest state wins.
  function queuePicture() {
    if (sendQueued) return;
    sendQueued = true;
    requestAnimationFrame(function () {
      sendQueued = false;
      if (!stageAlive()) { detach(); return; }
      var m = serialisePicture();
      if (m) post(m);
    });
  }

  // Pictures go to the stage only for a Reel with reacting parts (it plays the rest itself).
  function mirrored() { return !!(reelOnShow && reelOnShow.parts); }

  function attach() {
    if (!mirrored()) { detach(); return; }
    var svg = stage.querySelector("svg.asobi-svg");
    if (!svg || (observer && observed === svg)) return;
    detach();
    observer = new MutationObserver(queuePicture);
    observer.observe(svg, { subtree: true, childList: true, attributes: true, characterData: true });
    observed = svg;
  }
  function detach() {
    if (observer) observer.disconnect();
    observer = observed = null;
  }

  // Every 2 s (the stage's heartbeat) check the stage is still there; once it
  // has been silent for 6 s, stop watching the picture.
  function watchStage() {
    if (stageAlive()) { watchTimer = setTimeout(watchStage, 2000); return; }
    watchTimer = 0;
    detach();
  }

  function hearStage() {
    aliveUntil = performance.now() + 6000;
    attach();
    if (!watchTimer) watchTimer = setTimeout(watchStage, 2000);
  }

  if (channel) {
    channel.onmessage = function (e) {
      var m = e.data;
      if (!m || typeof m !== "object") return;
      if (m.type === "here") { hearStage(); return; }
      if (m.type === "bye") { aliveUntil = 0; detach(); return; }
      if (m.type !== "hello") return;
      hearStage();
      post({ type: "setup", lang: cfg.lang, words: cfg.words, playground: location.href.split("#")[0], hidden: !!document.hidden });
      postCode();
      postError();
      if (m.seq !== reelSeq) postReel();
      var picture = mirrored() ? serialisePicture() : null;
      if (picture) post(picture);
    };
    window.addEventListener("pagehide", function () { post({ type: "bye" }); });
    if (document.addEventListener) {
      document.addEventListener("visibilitychange", function () {
        if (!stageAlive()) return;
        post({ type: "visibility", hidden: !!document.hidden });
        if (!document.hidden) attach();
      });
    }
  }
  var stageBtn = document.getElementById("stage-window");
  // A phone or tablet without a pointer has no second window to put it in.
  var touchOnly = !!(window.matchMedia && window.matchMedia("(hover: none) and (pointer: coarse)").matches);
  if (stageBtn) {
    if (!channel || touchOnly) stageBtn.hidden = true;
    else {
      stageBtn.hidden = false;
      // noopener: the stage gets a browsing context group of its own, so
      // (normally) its own process and main thread: its drawing cannot stall
      // this page and this page's work cannot stall it. The channel still
      // joins them. Each click opens another stage (two screens, two stages).
      stageBtn.addEventListener("click", function () {
        window.open(cfg.stage, "_blank", "popup,noopener,width=1280,height=720");
      });
    }
  }

  // A small truthful readout in the bar: which frame is on screen, how long a loop is.
  var fcEl = document.getElementById("play-fc");
  var downloadBtn = document.getElementById("download");
  var onScreen = null;
  function isDynamic(reel) {
    return !!(reel && (reel.frames.length > 1 || reel.parts || reel.song));
  }
  function updateDownloadButton() {
    if (!downloadBtn) return;
    if (!onScreen) { downloadBtn.disabled = true; return; }
    downloadBtn.disabled = false;
    downloadBtn.textContent = (onScreen.pending || isDynamic(onScreen)) ? U.save_html : U.save_svg;
  }
  function show(reel) {
    // The song the site ships (play "beat.wav") has a src from the site's
    // root: put this page's assets folder in front, so it plays from /ja/ too.
    var s = reel && reel.song;
    if (s && typeof s.src === "string" && /^assets\//.test(s.src)) s.src = cfg.assets + s.src.slice(7);
    player.update(reel);
    stageError = reel && reel.error ? String(reel.error) : null;
    postError();
    if (stageAlive()) attach();
    if (reel && !reel.error && reel.frames) {
      onScreen = reel;
      updateDownloadButton();
      reelOnShow = reel;
      reelSeq = reelPrefix + "-" + (++reelCount);
      postReel();
      if (stageAlive()) attach(); // watch the picture only when it is mirrored
    }
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
  // A Reel from an engine (a JSON string) as the page may show it: checked
  // by AsobiSafeReel, or an error Reel saying it was not shown. Without the
  // checker nothing from the engine is shown.
  function fromEngine(json, code) {
    var reel = window.AsobiSafeReel ? AsobiSafeReel.parse(json) : null;
    if (reel && rawJson) rawJson.set(reel, json); // the stage gets this text as it came (no second JSON.stringify)
    return reel || { error: U.blocked, code: code };
  }

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
        // A new address for a changed worker: a cache may keep old headers for the old one.
        var v = cfg.workerVersion;
        var where = JSON.stringify({ api: cfg.rubyWasm.api, wasm: cfg.rubyWasm.wasm, v: v });
        worker = new Worker(cfg.assets + "ruby-worker.js" + (v ? "?v=" + v : "") + "#" + b64(where));
      } catch (e) { reject(e); return; }
      worker.onmessage = function (e) {
        var m = e.data;
        if (!m || typeof m !== "object") return; // only the worker's own kind of message
        if (m.type === "ready") { settled = true; resolve(api); return; }
        if (m.type === "failed") { settled = true; worker.terminate(); reject(new Error(m.message)); return; }
        if (m.fatal) { crash(m.fatal); return; }
        var r = Object.prototype.hasOwnProperty.call(runs, m.id) ? runs[m.id] : null; // not "__proto__"
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

  // Fallback, on file:// only (see boot): the same engine on the page.
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
          // Ruby on the page could reach the whole page: only for file://.
          if (afterCrash || location.protocol !== "file:") throw e;
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
      showAnswer(run, fromEngine(json, code));
    }
    return engine.run(code, cfg.lang, onFirst).then(function (json) {
      if (json === null) return null;
      var reel = fromEngine(json, code);
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
    postCode();
    replaceHash(sketchHash());
    clearTimeout(debounce);
    debounce = setTimeout(request, 350);
  });

  window.addEventListener("hashchange", function () {
    var code = CodeURL.fromHash(location.hash);
    if (code !== null && code !== editor.value) { editor.value = code; retint(); postCode(); request(); }
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
    postCode();
    replaceHash("");
    if (engine) request(); else { shownFor = null; showPrebuilt(cfg.defaultCode); }
    editor.focus();
  });

  // ---- saving: build SVG or standalone HTML strictly from the checked Reel ----
  // Never ask Ruby for the file: onScreen has already passed AsobiSafeReel, so
  // only asobi's own SVG and verified fields can ever end up in a download.
  function fmtNumber(n) {
    var r = Math.round(Number(n) * 1000) / 1000;
    if (r === 0) r = 0;
    return String(r);
  }
  function escapeAttr(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }
  function buildSvg(reel) {
    var v = reel.view, x = v[0], y = v[1], w = v[2], h = v[3];
    var k = 512 / Math.max(w, h, 1e-9);
    var bg = reel.background;
    var rect = bg && bg !== "none" && bg !== "transparent"
      ? '<rect x="' + fmtNumber(x) + '" y="' + fmtNumber(y) + '" width="' + fmtNumber(w) + '" height="' + fmtNumber(h) + '" fill="' + escapeAttr(bg) + '"/>'
      : "";
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + [x, y, w, h].map(fmtNumber).join(" ") + '" ' +
      'width="' + fmtNumber(w * k) + '" height="' + fmtNumber(h * k) + '" ' +
      'stroke-linejoin="round" stroke-linecap="round">' +
      rect + reel.frames[0] + "</svg>\n";
  }
  function scriptJson(data) {
    return JSON.stringify(data).replace(/</g, "\\u003c");
  }
  function buildHtml(reel, playerJs, songDataUri) {
    var copy = {
      frames: reel.frames,
      fps: reel.fps,
      view: reel.view,
      background: reel.background,
      code: reel.code,
      error: null
    };
    if (reel.controls === false) copy.controls = false;
    if (reel.parts) copy.parts = reel.parts;
    if (reel.song && songDataUri) {
      copy.song = { id: reel.song.id, src: songDataUri };
      if (typeof reel.song.volume === "number") copy.song.volume = reel.song.volume;
    }
    var safePlayer = String(playerJs).replace(/<\/script/gi, "<\\/script");
    return "<!doctype html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n" +
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" +
      "<title>asobi</title>\n<style>\n" +
      "  html, body { margin: 0; height: 100%; overflow: hidden; }\n" +
      "  #stage { position: fixed; inset: 0; }\n" +
      "</style>\n</head>\n<body>\n<div id=\"stage\"></div>\n" +
      "<script>" + safePlayer + "</script>\n<script>\n" +
      "  AsobiPlayer.mount(document.getElementById(\"stage\")).update(" + scriptJson(copy) + ");\n" +
      "</script>\n</body>\n</html>\n";
  }
  var cachedPlayerJs = null;
  function fetchPlayerJs() {
    if (cachedPlayerJs) return cachedPlayerJs;
    return cachedPlayerJs = fetch(cfg.assets + "player.js").then(function (r) {
      if (!r.ok) throw new Error("player.js: " + r.status);
      return r.text();
    }).catch(function (e) { cachedPlayerJs = null; throw e; });
  }
  var songDataCache = {};
  function songMime(src, response) {
    var ct = response && response.headers && response.headers.get && response.headers.get("content-type");
    if (ct && /^audio\//i.test(ct)) return ct.split(";")[0].trim();
    if (/\.mp3$/i.test(src)) return "audio/mpeg";
    if (/\.ogg$/i.test(src)) return "audio/ogg";
    return "audio/wav";
  }
  function fetchSongDataUri(src) {
    if (typeof src !== "string" || src.indexOf(cfg.assets) !== 0 || /\.\./.test(src.slice(cfg.assets.length))) {
      return Promise.reject(new Error("unexpected song path"));
    }
    if (songDataCache[src]) return songDataCache[src];
    return songDataCache[src] = fetch(src).then(function (r) {
      if (!r.ok) throw new Error("song: " + r.status);
      var mime = songMime(src, r);
      return r.arrayBuffer().then(function (buf) {
        var bytes = new Uint8Array(buf), bin = "";
        for (var i = 0; i < bytes.length; i += 0x8000) {
          bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
        }
        return "data:" + mime + ";base64," + btoa(bin);
      });
    }).catch(function (e) { delete songDataCache[src]; throw e; });
  }
  function triggerDownload(content, mime, filename) {
    var blob = new Blob([content], { type: mime });
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  }
  if (downloadBtn) {
    downloadBtn.addEventListener("click", function () {
      var reel = onScreen;
      if (!reel) return;
      if (reel.pending) { status(U.wait_to_save, 3000); return; }
      if (!isDynamic(reel)) {
        triggerDownload(buildSvg(reel), "image/svg+xml;charset=utf-8", "asobi.svg");
        status(U.saved_svg, 3000);
        return;
      }
      var songPromise = reel.song && reel.song.src ? fetchSongDataUri(reel.song.src) : Promise.resolve(null);
      Promise.all([fetchPlayerJs(), songPromise]).then(function (both) {
        triggerDownload(buildHtml(reel, both[0], both[1]), "text/html;charset=utf-8", "asobi.html");
        status(U.saved_html, 3000);
      }, function () {
        status(U.save_failed, 4000);
      });
    });
  }

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
          postCode();
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
