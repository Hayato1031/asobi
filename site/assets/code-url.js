/* asobi: code <-> URL fragment, and the key of a pre-rendered picture.
 * The same rules as site/build.rb (AsobiSite.encode_code / code_key):
 *   encode: base64url (no padding) of the UTF-8 bytes
 *   key:    "r" + FNV-1a 32-bit hex of the UTF-8 bytes
 */
(function (g) {
  "use strict";
  function bytes(text) { return new TextEncoder().encode(String(text)); }

  function encode(text) {
    var b = bytes(text), s = "";
    for (var i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
    return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function decode(text) {
    var s = String(text).replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    var bin = atob(s), b = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);
    return new TextDecoder("utf-8", { fatal: true }).decode(b);
  }

  function key(text) {
    var b = bytes(text), h = 0x811c9dc5;
    for (var i = 0; i < b.length; i++) { h ^= b[i]; h = Math.imul(h, 0x01000193) >>> 0; }
    return "r" + ("0000000" + h.toString(16)).slice(-8);
  }

  // "#code=..." -> code, or null
  function fromHash(hash) {
    var m = /(?:^#|&)code=([A-Za-z0-9_-]*)/.exec(hash || "");
    if (!m) return null;
    try { return decode(m[1]); } catch (e) { return null; }
  }

  var api = { encode: encode, decode: decode, key: key, fromHash: fromHash };
  g.AsobiCodeURL = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof self !== "undefined" ? self : this);
