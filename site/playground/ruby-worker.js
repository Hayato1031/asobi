/* asobi playground: runs Ruby off the page, so typing never freezes.
 * Started as  new Worker("assets/ruby-worker.js#<base64url of JSON {api, wasm}>").
 * Messages in:  { id, code, lang }
 * Messages out: { type: "ready" } | { type: "failed", message } | { id, json } | { id, fatal }
 */
"use strict";
var config = JSON.parse(atob(self.location.hash.slice(1).replace(/-/g, "+").replace(/_/g, "/")));
var ready;
try {
  // ruby.wasm's browser API from the jsDelivr CDN (pinned version; the only external resource).
  importScripts(config.api, "asobi-ruby.js", "ruby-engine.js");
  ready = self.AsobiRubyEngine.boot(config.wasm);
} catch (e) {
  ready = Promise.reject(e);
}
ready.then(
  function () { self.postMessage({ type: "ready" }); },
  function (e) { self.postMessage({ type: "failed", message: String(e && e.message || e) }); }
);
self.onmessage = function (event) {
  var msg = event.data;
  ready.then(function () {
    try {
      self.postMessage({ id: msg.id, json: self.AsobiRubyEngine.run(msg.code, msg.lang) });
    } catch (e) {
      self.postMessage({ id: msg.id, fatal: String(e && e.message || e) });
    }
  }, function () {});
};
