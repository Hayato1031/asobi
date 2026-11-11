/* asobi home: the stage.
 * The first piece is on the page as inline SVG before any script runs. Here
 * it starts to play; then, every so often, the next piece's code is typed
 * over the picture, and when the code is complete the picture becomes what
 * the code makes. Only while the stage is on screen and the tab is visible.
 * With prefers-reduced-motion the first frame simply stays.
 */
(function () {
  "use strict";
  var stage = document.getElementById("stage");
  var S = window.AsobiSite;
  if (!stage || !S || !window.AsobiPlayer || S.still) return;

  var pieces = JSON.parse(document.getElementById("stage-data").textContent);
  var pic = stage.querySelector(".stage-pic .pic");
  var subs = stage.querySelector(".stage-subs");
  var meta = {
    file: stage.querySelector(".sm-file"), index: stage.querySelector(".sm-index"), fc: stage.querySelector(".sm-fc"),
    n: stage.querySelector(".sm-n"), every: stage.querySelector(".sm-every"), now: document.getElementById("stage-now")
  };
  var HOLD = 13000;      // ms a piece plays before the next one is written
  var FADE = 450;        // ms, matches .stage-pic .pic transition

  var idx = 0, reel = null, player = null, host = null, t0 = 0;
  var onScreen = false, holdTimer = 0, typeTimer = 0, raf = 0, busy = false;

  function template(id) { return stage.querySelector('template[data-subs="' + id + '"]'); }

  // ---- playing ----------------------------------------------------------
  // Mount only with a reel in hand: an empty player would cover the first
  // frame (already on the page as SVG) with a blank.
  function mount() {
    if (player || !reel) return;
    host = document.createElement("div");
    host.className = "pic-live";
    host.setAttribute("aria-hidden", "true");
    pic.appendChild(host);
    player = AsobiPlayer.mount(host, { controls: false, keys: false, language: S.language });
    t0 = performance.now();
    if (reel) player.update(reel);
    tick();
  }
  function unmount() {
    if (!player) return;
    player.destroy(); player = null;
    if (host) host.remove();
    host = null;
    cancelAnimationFrame(raf); raf = 0;
  }
  function tick() {
    raf = requestAnimationFrame(tick);
    if (!reel || !player) return;
    var f = S.pad(S.frameAt(t0, Number(reel.fps), reel.frames.length, performance.now()), reel.frames.length);
    if (meta.fc.textContent !== f) meta.fc.textContent = f;
  }

  function showMeta(piece) {
    meta.file.textContent = piece.file;
    meta.index.textContent = (pieces.indexOf(piece) + 1) + "/" + pieces.length;
    meta.n.textContent = piece.frames;
    meta.every.textContent = piece.timing;
    meta.now.textContent = meta.now.textContent.replace(/:.*$/, ": " + piece.file);
  }

  // ---- writing the next piece ---------------------------------------------------
  // Lines are typed into the same subtitle backing the live view uses; when
  // the code is complete it is swapped for the tinted version (same text).
  function typeCode(piece, done) {
    var tpl = template(piece.id);
    var lines = Array.prototype.map.call(tpl.content.querySelectorAll(".sub"), function (s) { return s.textContent; });
    var pre = document.createElement("pre");
    pre.className = "subs";
    var code = document.createElement("code");
    pre.appendChild(code);
    subs.replaceChildren(pre);
    var caret = document.createElement("span");
    caret.className = "caret";
    var total = lines.join("\n").length;
    var perTick = Math.max(1, Math.ceil(total / 110)); // about 3.3 s at 30 ms a tick
    var li = 0, ci = 0, row = null;
    function newRow() {
      if (li > 0) code.appendChild(document.createTextNode("\n"));
      row = document.createElement("span");
      row.className = "sub" + (lines[li].trim() === "" ? " blank" : "");
      code.appendChild(row);
      row.appendChild(caret);
    }
    newRow();
    typeTimer = setInterval(function () {
      for (var k = 0; k < perTick; k++) {
        if (ci < lines[li].length) {
          caret.before(lines[li][ci]); ci++;
        } else if (li < lines.length - 1) {
          li++; ci = 0; newRow();
        } else {
          clearInterval(typeTimer); typeTimer = 0;
          subs.replaceChildren(tpl.content.cloneNode(true));
          done();
          return;
        }
      }
    }, 30);
  }

  function next() {
    if (!onScreen || busy || pieces.length < 2) return;
    busy = true;
    var i = (idx + 1) % pieces.length, piece = pieces[i];
    var loaded = null, typed = false;
    S.loadReel(piece.key, function (r) { loaded = r; swap(); });
    pic.classList.add("typing");
    typeCode(piece, function () { typed = true; swap(); });
    function swap() {
      if (!loaded || !typed || !busy) return;
      pic.classList.add("fading");
      setTimeout(function () {
        idx = i; reel = loaded;
        stage.style.setProperty("--stage-bg", piece.background);
        if (player) player.update(reel); // the player's clock runs on: t0 stays the mount time
        showMeta(piece);
        pic.classList.remove("fading", "typing");
        busy = false;
        hold();
      }, FADE);
    }
  }
  function hold() {
    clearTimeout(holdTimer);
    if (onScreen && pieces.length > 1) holdTimer = setTimeout(next, HOLD);
  }

  // Stop everything off screen (or in a hidden tab); put back the current
  // piece's code if it was being written.
  function pause() {
    clearTimeout(holdTimer);
    if (typeTimer) { clearInterval(typeTimer); typeTimer = 0; }
    if (busy) {
      busy = false;
      subs.replaceChildren(template(pieces[idx].id).content.cloneNode(true));
      pic.classList.remove("typing", "fading");
    }
    unmount();
  }
  function resume() {
    if (!onScreen || document.hidden) return;
    mount();
    hold();
  }

  S.loadReel(pieces[0].key, function (r) {
    if (reel) return;
    reel = r;
    resume();
  });

  new IntersectionObserver(function (entries) {
    onScreen = entries[entries.length - 1].isIntersecting;
    onScreen ? resume() : pause();
  }, { threshold: 0.15 }).observe(stage);
  document.addEventListener("visibilitychange", function () { document.hidden ? pause() : resume(); });
})();
