/* asobi player: draws a "Reel" (see DESIGN.md section 9) into an element.
 * Vanilla JS, no dependencies. Usage:
 *   const player = AsobiPlayer.mount(element, { controls: true, keys: true, language: "auto" });
 *   player.update(reel);   // swap the picture; the clock keeps running
 *   player.destroy();
 */
(function (global) {
  "use strict";

  var SVG_NS = "http://www.w3.org/2000/svg";
  var HIDE_AFTER_MS = 2500;
  var MAX_SIDE = 1080; // longest side of a recording, in pixels

  var TEXT = {
    en: { record: "record", stop: "stop", code: "code", noRecorder: "Recording is not available in this browser." },
    ja: { record: "録画", stop: "停止", code: "コード", noRecorder: "このブラウザでは録画できません。" }
  };

  var CSS = [
    ".asobi-root{position:relative;width:100%;height:100%;overflow:hidden;background:white;",
    "  font-family:system-ui,-apple-system,sans-serif}",
    ".asobi-root>svg.asobi-svg{position:absolute;left:0;top:0;width:100%;height:100%;display:block}",
    ".asobi-controls{position:absolute;top:10px;right:10px;display:flex;gap:6px;align-items:center;",
    "  opacity:0;pointer-events:none;transition:opacity .4s}",
    ".asobi-controls.asobi-on{opacity:1;pointer-events:auto}",
    ".asobi-btn{font:12px/1 system-ui,-apple-system,sans-serif;color:#fff;background:rgba(20,20,24,.55);",
    "  border:1px solid rgba(255,255,255,.35);border-radius:999px;padding:6px 11px;cursor:pointer}",
    ".asobi-btn:hover{background:rgba(20,20,24,.8)}",
    ".asobi-note{font:12px/1.3 system-ui,sans-serif;color:#fff;background:rgba(20,20,24,.75);",
    "  border-radius:6px;padding:5px 9px}",
    ".asobi-recdot{position:absolute;top:12px;left:12px;width:12px;height:12px;border-radius:50%;",
    "  background:#e5262b;box-shadow:0 0 0 2px rgba(255,255,255,.8);display:none;",
    "  animation:asobi-blink 1.2s ease-in-out infinite}",
    ".asobi-recdot.asobi-on{display:block}",
    "@keyframes asobi-blink{50%{opacity:.35}}",
    ".asobi-code{position:absolute;left:0;top:0;right:0;bottom:0;margin:0;padding:48px 20px 20px;overflow:auto;",
    "  box-sizing:border-box;display:none;background:none;color:#f4f4f6;",
    "  font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;white-space:pre;tab-size:2}",
    ".asobi-code.asobi-on{display:block}",
    ".asobi-line{display:block;width:max-content;min-height:1.5em;padding:0 8px;",
    "  background:rgba(14,14,20,.72);text-shadow:0 1px 2px rgba(0,0,0,.6)}",
    ".asobi-line.asobi-blank{background:none}",
    ".asobi-error{position:absolute;left:0;right:0;bottom:0;max-height:38%;overflow:auto;box-sizing:border-box;",
    "  margin:0;padding:12px 18px;display:none;background:rgba(150,20,30,.93);color:#fff;",
    "  font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;white-space:pre-wrap;word-break:break-word}",
    ".asobi-error.asobi-on{display:block}"
  ].join("\n");

  function injectStyle() {
    if (document.getElementById("asobi-style")) return;
    var s = document.createElement("style");
    s.id = "asobi-style";
    s.textContent = CSS;
    (document.head || document.documentElement).appendChild(s);
  }

  function el(tag, cls, parent) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (parent) parent.appendChild(e);
    return e;
  }

  function validReel(r) {
    return r && Array.isArray(r.frames) && r.frames.length > 0;
  }

  function pickMime() {
    if (typeof MediaRecorder === "undefined" || !MediaRecorder.isTypeSupported) return null;
    var list = ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];
    for (var i = 0; i < list.length; i++) if (MediaRecorder.isTypeSupported(list[i])) return list[i];
    return null;
  }

  function mount(element, options) {
    options = options || {};
    var useControls = options.controls !== false;
    var useKeys = options.keys !== false;
    var lang = options.language || "auto";
    if (lang === "auto") lang = /^ja/i.test((global.navigator && navigator.language) || "") ? "ja" : "en";
    var T = TEXT[lang] || TEXT.en;

    injectStyle();

    // ---- DOM ---------------------------------------------------------
    var root = el("div", "asobi-root");
    element.appendChild(root);

    var svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "asobi-svg");
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    svg.setAttribute("stroke-linejoin", "round");
    svg.setAttribute("stroke-linecap", "round");
    var bgRect = document.createElementNS(SVG_NS, "rect"); // background, also used when recording
    var content = document.createElementNS(SVG_NS, "g");
    svg.appendChild(bgRect);
    svg.appendChild(content);
    root.appendChild(svg);

    var codeBox = el("pre", "asobi-code", root);
    var errorBox = el("pre", "asobi-error", root);
    var recDot = el("div", "asobi-recdot", root);
    var controls = el("div", "asobi-controls", root);
    var note = el("span", "asobi-note", controls);
    note.style.display = "none";
    var recBtn = el("button", "asobi-btn", controls);
    var codeBtn = el("button", "asobi-btn", controls);
    recBtn.type = codeBtn.type = "button";
    recBtn.textContent = "● " + T.record;
    codeBtn.textContent = "</> " + T.code;
    if (!useControls) controls.style.display = "none";

    // ---- state -------------------------------------------------------
    var reel = null;            // last good reel
    var reelId = 0;             // bumps on every good reel
    var t0 = performance.now(); // the clock: never reset by update()
    var shown = { id: -1, idx: -1 };
    var raf = 0, destroyed = false;
    var hideTimer = 0, noteTimer = 0;

    function frameIndex(now) {
      var fps = Number(reel.fps) > 0 ? Number(reel.fps) : 1;
      return Math.floor(((now - t0) / 1000) * fps) % reel.frames.length;
    }

    // The code goes on the picture line by line, each line with its own
    // tight backing (like subtitles), so the picture stays visible.
    function setCode(text) {
      while (codeBox.firstChild) codeBox.removeChild(codeBox.firstChild);
      if (typeof text !== "string" || text === "") return;
      text.replace(/\n$/, "").split("\n").forEach(function (line) {
        var row = el("span", "asobi-line" + (line.trim() === "" ? " asobi-blank" : ""), codeBox);
        row.textContent = line;
      });
    }

    function viewOf(r) {
      var v = r.view;
      return Array.isArray(v) && v.length === 4 && v[2] > 0 && v[3] > 0 ? v : [0, 0, 100, 100];
    }

    function applyReel() {
      var v = viewOf(reel), bg = reel.background || "white";
      svg.setAttribute("viewBox", v.join(" "));
      root.style.background = bg;
      bgRect.setAttribute("x", v[0]); bgRect.setAttribute("y", v[1]);
      bgRect.setAttribute("width", v[2]); bgRect.setAttribute("height", v[3]);
      bgRect.setAttribute("fill", bg);
      setCode(reel.code);
    }

    // ---- render loop: touch the DOM only when frame or reel changed --
    function tick(now) {
      if (destroyed) return;
      if (reel) {
        var idx = frameIndex(now);
        if (shown.id !== reelId || shown.idx !== idx) {
          if (shown.id !== reelId) applyReel();
          content.innerHTML = reel.frames[idx];
          shown.id = reelId; shown.idx = idx;
        }
      }
      raf = requestAnimationFrame(tick);
    }
    raf = requestAnimationFrame(tick);

    // ---- update ------------------------------------------------------
    function update(next) {
      if (destroyed || !next) return;
      if (typeof next.error === "string" && next.error !== "") {
        errorBox.textContent = next.error;
        errorBox.classList.add("asobi-on");
        if (typeof next.code === "string") setCode(next.code);
        return; // keep the last good picture
      }
      errorBox.classList.remove("asobi-on");
      if (validReel(next)) { reel = next; reelId++; }
    }

    // ---- controls visibility ----------------------------------------
    function wake() {
      if (!useControls) return;
      controls.classList.add("asobi-on");
      clearTimeout(hideTimer);
      hideTimer = setTimeout(function () {
        if (!controls.matches(":hover")) controls.classList.remove("asobi-on");
        else wake();
      }, HIDE_AFTER_MS);
    }
    root.addEventListener("mousemove", wake);
    root.addEventListener("touchstart", wake, { passive: true });

    // ---- code overlay ------------------------------------------------
    function toggleCode() { codeBox.classList.toggle("asobi-on"); }
    codeBtn.addEventListener("click", toggleCode);

    // ---- recording ---------------------------------------------------
    var rec = null; // { recorder, timer, chunks, mime }

    function say(msg) {
      note.textContent = msg; note.style.display = "";
      wake();
      clearTimeout(noteTimer);
      noteTimer = setTimeout(function () { note.style.display = "none"; }, 4000);
    }

    // Serialise the current SVG (background included) at pixel size w x h.
    function svgSource(w, h) {
      var clone = svg.cloneNode(true);
      clone.setAttribute("xmlns", SVG_NS);
      clone.setAttribute("width", w);
      clone.setAttribute("height", h);
      clone.removeAttribute("class");
      return new XMLSerializer().serializeToString(clone);
    }

    function startRecording() {
      var mime = pickMime();
      if (!mime || !reel) { say(T.noRecorder); return; }
      var v = viewOf(reel), scale = MAX_SIDE / Math.max(v[2], v[3]);
      var w = Math.max(2, Math.round(v[2] * scale / 2) * 2), h = Math.max(2, Math.round(v[3] * scale / 2) * 2);
      var canvas = document.createElement("canvas");
      canvas.width = w; canvas.height = h;
      var ctx = canvas.getContext("2d");
      var fps = Number(reel.fps) >= 10 ? Math.min(Number(reel.fps), 60) : 30;
      var stream = canvas.captureStream(fps);
      var recorder;
      try { recorder = new MediaRecorder(stream, { mimeType: mime }); }
      catch (e) { say(T.noRecorder); return; }
      var state = { recorder: recorder, chunks: [], mime: mime, timer: 0, busy: false };
      recorder.ondataavailable = function (e) { if (e.data && e.data.size) state.chunks.push(e.data); };
      recorder.onstop = function () {
        var ext = /mp4/.test(mime) ? "mp4" : "webm";
        var blob = new Blob(state.chunks, { type: mime.split(";")[0] });
        var a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = "asobi." + ext;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(function () { URL.revokeObjectURL(a.href); }, 10000);
      };
      // Draw the frame that is on screen now. Skip a tick if the last image is still loading.
      function draw() {
        if (state.busy) return;
        state.busy = true;
        var img = new Image();
        img.onload = function () { ctx.drawImage(img, 0, 0, w, h); state.busy = false; };
        img.onerror = function () { state.busy = false; };
        img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svgSource(w, h));
      }
      draw();
      state.timer = setInterval(draw, 1000 / fps);
      recorder.start();
      rec = state;
      recDot.classList.add("asobi-on");
      recBtn.textContent = "■ " + T.stop;
    }

    function stopRecording() {
      if (!rec) return;
      clearInterval(rec.timer);
      if (rec.recorder.state !== "inactive") rec.recorder.stop();
      rec = null;
      recDot.classList.remove("asobi-on");
      recBtn.textContent = "● " + T.record;
    }

    function toggleRecording() { rec ? stopRecording() : startRecording(); }
    recBtn.addEventListener("click", toggleRecording);

    // ---- keys --------------------------------------------------------
    function onKey(e) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      var t = e.target && e.target.tagName;
      if (t === "INPUT" || t === "TEXTAREA" || t === "SELECT" || (e.target && e.target.isContentEditable)) return;
      if (e.key === "c" || e.key === "C") toggleCode();
      else if (e.key === "r" || e.key === "R") toggleRecording();
    }
    if (useKeys) document.addEventListener("keydown", onKey);

    return {
      update: update,
      destroy: function () {
        if (destroyed) return;
        stopRecording();
        destroyed = true;
        cancelAnimationFrame(raf);
        clearTimeout(hideTimer); clearTimeout(noteTimer);
        document.removeEventListener("keydown", onKey);
        root.remove();
      }
    };
  }

  global.AsobiPlayer = { mount: mount };
})(typeof window !== "undefined" ? window : this);
