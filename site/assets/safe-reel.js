/* asobi playground: what an engine sends is checked before the page shows it.
 * The Ruby in the playground comes from the address (#code=...), so anyone
 * can write it, and it can change how asobi writes SVG. The player puts a
 * frame on the page as it is (innerHTML), so the page lets through only the
 * SVG that asobi itself writes (lib/asobi/svg.rb) and nothing else.
 *
 * This checks, it does not clean: a frame is shown exactly as it came, or
 * not at all.
 *
 *   AsobiSafeReel.markup(text)  true when the text is only asobi's own SVG
 *   AsobiSafeReel.reel(value)   a fresh Reel with only known, checked fields, or null
 *   AsobiSafeReel.parse(json)   reel(JSON.parse(json)), or null
 */
(function (g) {
  "use strict";

  function set(words) {
    var out = Object.create(null);
    words.split(" ").forEach(function (w) { out[w] = true; });
    return out;
  }

  // Every element and attribute lib/asobi/svg.rb writes inside a frame.
  var NAMES = set("g circle ellipse rect path text defs linearGradient radialGradient stop mask filter " +
    "feFlood feComposite feGaussianBlur feMerge feMergeNode feOffset feTurbulence feColorMatrix");
  var ATTRIBUTES = set("r rx ry x y width height fill stroke stroke-width opacity mask filter style d fill-rule " +
    "text-anchor dominant-baseline xml:space font-family font-size transform id gradientUnits x1 y1 x2 y2 cx cy " +
    "offset stop-color maskUnits filterUnits color-interpolation-filters flood-color flood-opacity in in2 " +
    "operator result stdDeviation dx dy type baseFrequency numOctaves seed stitchTiles values");
  var FUNCTIONS = set("rgb rgba hsl hsla translate matrix");

  // One piece of a frame: text, a part marker, a closing tag, or an opening
  // (or self-closing) tag with its attributes.
  var TOKEN = /([^<>]+)|(<!--asobi:p[0-9]+-->)|<\/([A-Za-z]+)>|<([A-Za-z]+)((?: [A-Za-z0-9:-]+="[^"<>]*")*)\/?>/g;
  var ATTRIBUTE = / ([A-Za-z0-9:-]+)="([^"<>]*)"/g;
  var ID = /^asobi-[a-z0-9]+$/;
  var URL_ID = /^url\(#asobi-[a-z0-9]+\)$/;
  var STYLE = /^(?:mask-type:alpha|pointer-events:none|mix-blend-mode:[a-z-]+)$/;
  // asobi writes only these four: anything else (&#40; is "(", &lpar; too)
  // could spell what the checks below look for.
  var ENTITY = /&(?!(?:amp|lt|gt|quot);)/;

  // Every "(" comes right after one of FUNCTIONS (and not after another
  // letter or "-"): so no url(...), image-set(...), expression(...).
  function parensOk(v) {
    var i = -1;
    while ((i = v.indexOf("(", i + 1)) !== -1) {
      var before = v.slice(Math.max(0, i - 10), i);
      var name = /[A-Za-z-]*$/.exec(before)[0];
      if (name.length === before.length && i >= 10) return false; // longer than any name
      if (!FUNCTIONS[name.toLowerCase()]) return false;
    }
    return true;
  }

  function valueOk(name, v) {
    if (v.indexOf("\\") !== -1 || ENTITY.test(v)) return false;
    if (name === "id") return ID.test(v);
    if (name === "style") return STYLE.test(v);
    return URL_ID.test(v) || parensOk(v);
  }

  function attributesOk(text) {
    var m;
    ATTRIBUTE.lastIndex = 0;
    while ((m = ATTRIBUTE.exec(text))) {
      if (!ATTRIBUTES[m[1]] || !valueOk(m[1], m[2])) return false;
    }
    return true;
  }

  function markup(text) {
    if (typeof text !== "string") return false;
    var pos = 0, m;
    TOKEN.lastIndex = 0;
    while (pos < text.length) {
      m = TOKEN.exec(text);
      if (!m || m.index !== pos) return false;
      pos = TOKEN.lastIndex;
      if (m[3] !== undefined && !NAMES[m[3]]) return false;
      if (m[4] !== undefined && (!NAMES[m[4]] || !attributesOk(m[5]))) return false;
    }
    return true;
  }

  // ---- the Reel ---------------------------------------------------------------

  function plain(v) {
    if (!v || typeof v !== "object" || Array.isArray(v)) return false;
    var p = Object.getPrototypeOf(v);
    return p === Object.prototype || p === null;
  }
  function finite(v) { return typeof v === "number" && isFinite(v); }
  function own(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }

  function frames(list) {
    if (!Array.isArray(list) || list.length === 0) return null;
    var out = [];
    for (var i = 0; i < list.length; i++) {
      if (!markup(list[i])) return null;
      out.push(list[i]);
    }
    return out;
  }

  var PART_FIELDS = ["turn", "from", "fps", "sound", "what", "note", "key"];

  function parts(value) {
    if (!plain(value)) return null;
    var out = Object.create(null), keys = Object.keys(value);
    for (var i = 0; i < keys.length; i++) {
      var id = keys[i], d = value[id];
      if (!/^p[0-9]+$/.test(id) || !plain(d)) return null;
      var f = frames(d.frames);
      if (!f) return null;
      var copy = { frames: f };
      PART_FIELDS.forEach(function (k) {
        var v = own(d, k) ? d[k] : undefined;
        if (typeof v === "string" || typeof v === "boolean" || finite(v)) copy[k] = v;
      });
      out[id] = copy;
    }
    return out;
  }

  function background(v) {
    return typeof v === "string" && v.length <= 64 && /^[#A-Za-z0-9(),.%\s-]+$/.test(v) && parensOk(v);
  }

  function song(s) {
    if (!plain(s) || typeof s.src !== "string" || !/^assets\/[A-Za-z0-9._-]+$/.test(s.src)) return null;
    var id = String(own(s, "id") ? s.id : "");
    if (!/^[A-Za-z0-9._-]{1,64}$/.test(id)) return null;
    var out = { id: id, src: s.src };
    if (own(s, "volume") && s.volume !== undefined && s.volume !== null) {
      if (!finite(s.volume)) return null;
      out.volume = s.volume;
    }
    return out;
  }

  function reelOf(value) {
    if (!plain(value)) return null;
    var code = typeof value.code === "string" ? value.code : null;
    if (typeof value.error === "string" && value.error !== "") return { error: value.error, code: code };

    var f = frames(value.frames);
    if (!f) return null;
    var out = { frames: f };
    if (!finite(value.fps) || value.fps <= 0) return null;
    out.fps = value.fps;
    var v = value.view;
    if (!Array.isArray(v) || v.length !== 4 || !v.every(finite)) return null;
    out.view = v.slice();
    if (value.background !== undefined && value.background !== null) {
      if (!background(value.background)) return null;
      out.background = value.background;
    }
    out.code = code;
    out.error = null;
    if (typeof value.pending === "boolean") out.pending = value.pending;
    if (typeof value.controls === "boolean") out.controls = value.controls;
    if (value.parts !== undefined && value.parts !== null) {
      var p = parts(value.parts);
      if (!p) return null;
      out.parts = p;
    }
    if (value.song !== undefined && value.song !== null) {
      var s = song(value.song);
      if (s) out.song = s; // a song that is not the site's own is left out; the picture still shows
    }
    return out;
  }

  function reel(value) {
    try { return reelOf(value); } catch (e) { return null; }
  }

  function parse(json) {
    if (typeof json !== "string") return null;
    var value;
    try { value = JSON.parse(json); } catch (e) { return null; }
    return reel(value);
  }

  var api = { markup: markup, reel: reel, parse: parse };
  g.AsobiSafeReel = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof self !== "undefined" ? self : this);
