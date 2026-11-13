/* asobi site: plays the moving examples while they are on screen, and the
 * small things around them (frame counters, where-you-are, copy, code).
 *
 * Each moving picture is already on the page as its first frame (plain
 * SVG). Its reel lives in reels/<key>.js, a script that registers itself,
 * so this also works when the page is opened straight from file://.
 */
(function () {
  "use strict";
  var html = document.documentElement;
  var root = html.getAttribute("data-root") || "";
  var lang = html.lang === "ja" ? "ja" : "en";
  var reels = {}, waiting = {}, requested = {};
  var still = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // reels/<key>.js calls this.
  window.asobiReel = function (key, reel) {
    reels[key] = reel;
    (waiting[key] || []).forEach(function (fn) { fn(reel); });
    delete waiting[key];
  };

  function loadReel(key, done, failed) {
    if (reels[key]) { done(reels[key]); return; }
    (waiting[key] = waiting[key] || []).push(done);
    if (requested[key]) return;
    requested[key] = true;
    var s = document.createElement("script");
    s.src = root + "reels/" + key + ".js";
    s.async = true;
    s.onerror = function () { requested[key] = false; delete waiting[key]; if (failed) failed(); };
    document.head.appendChild(s);
  }

  // The frame a player shows: the same rule as player.js (seconds since it
  // was mounted, times fps, wrapped round the frame count).
  function frameAt(t0, fps, count, now) {
    return Math.floor(((now - t0) / 1000) * (fps > 0 ? fps : 1)) % count;
  }
  function pad(n, count) {
    var s = String(n), w = String(count).length;
    while (s.length < w) s = "0" + s;
    return s;
  }

  // Counters ("012/120") next to playing pictures: one shared loop.
  var counters = [];
  var counting = 0;
  function countLoop(now) {
    counters.forEach(function (c) {
      var f = pad(frameAt(c.t0, c.fps, c.count, now), c.count);
      if (c.el.textContent !== f) c.el.textContent = f;
    });
    counting = counters.length ? requestAnimationFrame(countLoop) : 0;
  }
  function addCounter(c) { counters.push(c); if (!counting) counting = requestAnimationFrame(countLoop); }
  function removeCounter(el) { counters = counters.filter(function (c) { return c.el !== el; }); }

  // Keep the actual link up to date for clicks, new tabs and copied links.
  var languageLink = document.querySelector("a[data-keep-hash]");
  function setLanguageHash(hash) {
    if (languageLink) languageLink.hash = hash;
  }
  setLanguageHash(location.hash);
  window.addEventListener("hashchange", function () { setLanguageHash(location.hash); });

  window.AsobiSite = {
    loadReel: loadReel, language: lang, root: root, still: still,
    frameAt: frameAt, pad: pad, addCounter: addCounter, removeCounter: removeCounter,
    setLanguageHash: setLanguageHash
  };

  // ---- pictures: play while on screen --------------------------------------
  function setupPictures() {
    var pics = document.querySelectorAll(".pic[data-reel]");
    if (!pics.length || !window.AsobiPlayer || !("IntersectionObserver" in window) || still) return;

    function start(pic) {
      pic._want = true;
      if (pic._player) return;
      loadReel(pic.getAttribute("data-reel"), function (reel) {
        if (!pic._want || pic._player) return;
        var host = document.createElement("div");
        host.className = "pic-live";
        host.setAttribute("aria-hidden", "true");
        pic.appendChild(host);
        var t0 = performance.now();
        pic._player = AsobiPlayer.mount(host, { controls: false, keys: false, language: lang });
        pic._player.update(reel);
        pic.classList.add("is-live");
        var fc = pic.parentNode.querySelector("[data-fc]");
        if (fc) { pic._fc = fc; addCounter({ el: fc, t0: t0, fps: Number(reel.fps), count: reel.frames.length }); }
      });
    }
    function stop(pic) {
      pic._want = false;
      if (!pic._player) return;
      pic._player.destroy();
      pic._player = null;
      pic.classList.remove("is-live");
      if (pic._fc) { removeCounter(pic._fc); pic._fc.textContent = pad(0, Number(pic.getAttribute("data-count"))); }
      var host = pic.querySelector(".pic-live");
      if (host) host.remove();
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { e.isIntersecting ? start(e.target) : stop(e.target); });
    }, { rootMargin: "150px 0px" });
    Array.prototype.forEach.call(pics, function (p) { io.observe(p); });
  }

  // ---- where you are: the sidebar follows the reading -------------------------
  function setupSpy() {
    var nav = document.querySelector("[data-spy]");
    if (!nav || !("IntersectionObserver" in window)) return;
    var links = {};
    Array.prototype.forEach.call(nav.querySelectorAll('a[href^="#"]'), function (a) { links[a.getAttribute("href").slice(1)] = a; });
    var targets = document.querySelectorAll("[data-spy-target]");
    var visible = {};
    var current = null;
    function mark() {
      var best = null;
      Array.prototype.forEach.call(targets, function (t) { if (visible[t.id] && !best) best = t; });
      if (!best || best === current) return;
      current = best;
      Array.prototype.forEach.call(nav.querySelectorAll('[aria-current="true"]'), function (a) { a.removeAttribute("aria-current"); });
      var link = links[best.id];
      if (link) {
        link.setAttribute("aria-current", "true");
        var group = best.closest(".group");
        if (group && links[group.id]) links[group.id].setAttribute("aria-current", "true");
        var box = nav.getBoundingClientRect(), r = link.getBoundingClientRect();
        if (nav.scrollHeight > nav.clientHeight && (r.top < box.top + 40 || r.bottom > box.bottom - 40)) {
          nav.scrollTop += r.top - box.top - nav.clientHeight / 3;
        }
      }
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { visible[e.target.id] = e.isIntersecting; });
      mark();
    }, { rootMargin: "-80px 0px -55% 0px" });
    Array.prototype.forEach.call(targets, function (t) { io.observe(t); });
  }

  // ---- copy buttons and code toggles --------------------------------------------
  function setupButtons() {
    document.addEventListener("click", function (e) {
      var copy = e.target.closest && e.target.closest("[data-copy]");
      if (copy) {
        var text = document.getElementById(copy.getAttribute("data-copy")).textContent;
        var label = copy.textContent;
        var done = function () { copy.textContent = copy.getAttribute("data-copied"); setTimeout(function () { copy.textContent = label; }, 1800); };
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, function () {});
        return;
      }
      var toggle = e.target.closest && e.target.closest("[data-toggle-code]");
      if (toggle) {
        var piece = toggle.closest(".piece");
        var on = !piece.classList.contains("show-code");
        piece.classList.toggle("show-code", on);
        toggle.setAttribute("aria-expanded", on ? "true" : "false");
      }
    });
  }

  // ---- WebMCP: expose read & navigation tools to AI agents when supported ----
  function registerWebMCP(tools) {
    var contexts = [document.modelContext, navigator.modelContext].filter(function (c, i, a) {
      return c && typeof c.registerTool === "function" && a.indexOf(c) === i;
    });
    if (!contexts.length) return;

    var ac = typeof AbortController === "function" ? new AbortController() : null;
    if (ac) window.addEventListener("pagehide", function () { ac.abort(); }, { once: true });
    var opts = ac ? { signal: ac.signal } : undefined;

    contexts.forEach(function (ctx) {
      tools.forEach(function (tool) {
        try {
          var res = opts ? ctx.registerTool(tool, opts) : ctx.registerTool(tool);
          if (res && typeof res.catch === "function") res.catch(function () {});
        } catch (e) {}
      });
    });
  }

  function setupWebMCP() {
    var root = document.documentElement.getAttribute("data-root") || "";
    var lang = document.documentElement.getAttribute("lang") || "en";
    var page = document.documentElement.getAttribute("data-page") || "index";

    function jsonResult(data, isError) {
      var out = { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
      if (isError) out.isError = true;
      return out;
    }

    registerWebMCP([
      {
        name: "asobi_get_page_summary",
        description: "Return metadata, Markdown mirror URL, llms.txt URL, and Ruby code examples shown on the current asobi documentation page.",
        inputSchema: { type: "object", properties: {} },
        execute: function () {
          var examples = Array.prototype.slice.call(document.querySelectorAll("pre.code")).slice(0, 20).map(function (el) {
            return el.textContent.trim();
          });
          return jsonResult({
            title: document.title,
            lang: lang,
            page: page,
            url: location.href,
            markdownUrl: new URL(page + ".md", location.href).href,
            llmsTxtUrl: new URL(root + "llms.txt", location.href).href,
            examplesCount: examples.length,
            examples: examples
          });
        }
      },
      {
        name: "asobi_lookup_word",
        description: "Look up an asobi Ruby word (e.g. to_art, petal, spin, orbit) and return its reference URL and details if on the reference page.",
        inputSchema: {
          type: "object",
          properties: { word: { type: "string", description: "Word name such as to_art, circle, in_ring, or spin." } },
          required: ["word"]
        },
        execute: function (args) {
          var word = String((args && args.word) || "").trim();
          if (!word) return jsonResult({ error: "word is required" }, true);
          var el = document.getElementById(word);
          var sig = el && el.querySelector(".signature");
          var sum = el && el.querySelector(".summary");
          return jsonResult({
            word: word,
            referenceUrl: new URL("reference.html#" + encodeURIComponent(word), location.href).href,
            markdownReferenceUrl: new URL("reference.md", location.href).href,
            signature: sig ? sig.textContent.trim() : null,
            summary: sum ? sum.textContent.trim() : null
          });
        }
      },
      {
        name: "asobi_open_in_playground",
        description: "Build a shareable Playground URL for an asobi Ruby sketch and optionally navigate to it.",
        inputSchema: {
          type: "object",
          properties: {
            code: { type: "string", description: "Complete Ruby sketch using asobi words ending with show." },
            navigate: { type: "boolean", description: "Set true to navigate the browser to the playground with this sketch." }
          },
          required: ["code"]
        },
        execute: function (args) {
          var code = String((args && args.code) || "");
          if (!code.trim()) return jsonResult({ error: "code is required" }, true);
          var target = new URL("playground.html#code=" + AsobiCodeURL.encode(code), location.href).href;
          if (args && args.navigate) location.href = target;
          return jsonResult({ url: target, code: code });
        }
      }
    ]);
  }

  window.AsobiWebMCP = { register: registerWebMCP };

  function setup() { setupPictures(); setupSpy(); setupButtons(); setupWebMCP(); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", setup);
  else setup();
})();
