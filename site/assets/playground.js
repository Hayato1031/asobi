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
    player.update(reel);
    if (reel && !reel.error && reel.frames) onScreen = reel;
  }
  (function readout() {
    if (onScreen && fcEl) {
      var n = onScreen.frames.length, text;
      if (n < 2) text = U.still;
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
  function b64(text) { return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }

  function workerEngine() {
    return new Promise(function (resolve, reject) {
      var worker, settled = false, pending = {}, nextId = 1;
      var api = {
        run: function (code, lang) {
          return new Promise(function (res, rej) {
            var id = nextId++;
            pending[id] = {
              res: res, rej: rej,
              timer: setTimeout(function () { delete pending[id]; worker.terminate(); rej({ timeout: true }); }, cfg.timeout)
            };
            worker.postMessage({ id: id, code: code, lang: lang });
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
        var p = pending[m.id];
        if (!p) return;
        delete pending[m.id];
        clearTimeout(p.timer);
        if (m.fatal) p.rej(new Error(m.fatal)); else p.res(m.json);
      };
      worker.onerror = function (e) {
        if (settled) return;
        settled = true;
        if (e && e.preventDefault) e.preventDefault();
        reject(new Error("worker"));
      };
    });
  }

  function addScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement("script");
      s.src = src; s.async = false;
      s.onload = resolve;
      s.onerror = function () { reject(new Error("could not load " + src)); };
      document.head.appendChild(s);
    });
  }

  // Fallback (file://, or no Worker): the same engine on the page.
  function pageEngine() {
    // ruby.wasm's browser API: the one external resource (pinned, cdn.jsdelivr.net).
    return addScript(cfg.rubyWasm.api)
      .then(function () { return addScript(cfg.assets + "asobi-ruby.js"); })
      .then(function () { return addScript(cfg.assets + "ruby-engine.js"); })
      .then(function () { return AsobiRubyEngine.boot(cfg.rubyWasm.wasm); })
      .then(function () {
        return {
          run: function (code, lang) {
            return new Promise(function (res, rej) {
              setTimeout(function () {
                try { res(AsobiRubyEngine.run(code, lang)); } catch (e) { rej(e); }
              }, 0);
            });
          }
        };
      });
  }

  var engine = null, onPage = false;
  function boot() {
    status(U.loading_ruby);
    var start = onPage ? pageEngine() : workerEngine().catch(function () { onPage = true; return pageEngine(); });
    start.then(function (e) {
      engine = e;
      status(U.ruby_ready, 2500);
      if (selftest || editor.value !== shownFor) request();
    }, function (err) {
      status(U.ruby_failed);
      if (window.console) console.error("asobi playground:", err);
    });
  }

  // ---- running -------------------------------------------------------------
  var busy = false, queued = false, debounce = 0;
  var stuck = null; // code that ran too long: not run again until it changes

  function request() {
    if (!engine) return;            // runs once Ruby is ready
    if (busy) { queued = true; return; }
    if (editor.value === stuck) return;
    go(editor.value);
  }

  function go(code) {
    busy = true;
    var hint = setTimeout(function () { status(U.running); }, 300);
    engine.run(code, cfg.lang).then(function (json) {
      var reel = JSON.parse(json);
      show(reel);
      if (!reel.error) shownFor = code;
      mark(reel);
    }, function (err) {
      if (err && err.timeout) {
        player.update({ error: U.too_slow, code: code });
        stuck = code;
        engine = null;
        boot();
      } else {
        player.update({ error: String((err && err.message) || err), code: code });
      }
      mark({ error: "engine: " + String((err && err.message) || "timeout") });
    }).then(function () {
      clearTimeout(hint);
      if (statusEl.textContent === U.running) status("");
      busy = false;
      if (queued) { queued = false; request(); }
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
          return waitForEngine(20000).then(function (eng) {
            return eng.run(code, cfg.lang);
          }).then(function (json) {
            var reel = JSON.parse(json);
            show(reel);
            if (!reel.error) shownFor = code;
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
