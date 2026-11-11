/* asobi: Ruby tinting for the playground editor. The same rules as
 * AsobiSite.highlight in site/build.rb (comments, strings, symbols and
 * labels, numbers, keywords, constants, asobi words), so code looks the
 * same in the editor as everywhere else on the site.
 */
(function (g) {
  "use strict";
  var KEYWORDS = ("def end do if elsif else unless while until case when then class module return yield " +
    "begin rescue ensure self nil true false and or not in break next super loop lambda proc").split(" ");
  var RULES = [
    ["t-c", /#[^\n]*/y],
    ["t-s", /"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?/y],
    ["sym", /:[A-Za-z_]\w*[?!]?/y],
    ["t-y", /[A-Za-z_]\w*[?!]?:(?!:)/y],
    ["t-n", /\d[\d_]*(?:\.\d+)?/y],
    ["t-t", /[A-Z]\w*/y],
    ["id", /[a-z_]\w*[?!]?/y]
  ];
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

  function tint(code, words) {
    var out = "", i = 0, prev = "", n = code.length;
    var known = {};
    (words || []).forEach(function (w) { known[w] = true; });
    while (i < n) {
      var hit = null, cls = null;
      for (var r = 0; r < RULES.length && !hit; r++) {
        var re = RULES[r][1];
        if (RULES[r][0] === "sym" && /[\w:\])]/.test(prev)) continue;
        re.lastIndex = i;
        var m = re.exec(code);
        if (m && m[0].length) { hit = m[0]; cls = RULES[r][0]; }
      }
      if (!hit) { hit = code[i]; out += esc(hit); }
      else if (cls === "sym") out += '<span class="t-y">' + esc(hit) + "</span>";
      else if (cls === "id") {
        if (KEYWORDS.indexOf(hit) >= 0) out += '<span class="t-k">' + hit + "</span>";
        else if (known[hit]) out += '<span class="t-w">' + hit + "</span>";
        else out += hit;
      } else out += '<span class="' + cls + '">' + esc(hit) + "</span>";
      i += hit.length;
      prev = hit[hit.length - 1];
    }
    return out;
  }
  g.AsobiTint = tint;
  if (typeof module !== "undefined" && module.exports) module.exports = tint;
})(typeof self !== "undefined" ? self : this);
