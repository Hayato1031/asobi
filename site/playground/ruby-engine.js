/* asobi playground: the Ruby engine. Works in a Web Worker and, as a
 * fallback, on the page itself.
 *
 * Needs, already loaded:
 *   - ruby.wasm's browser API (browser.umd.js of @ruby/wasm-wasi, which sets
 *     self["ruby-wasm-wasi"]) -- the one external resource of the site,
 *     from cdn.jsdelivr.net at a pinned version (see site/build.rb).
 *   - asobi-ruby.js (sets self.ASOBI_RUBY: the library as one Ruby source).
 *
 *   AsobiRubyEngine.boot(wasmUrl) -> Promise
 *   AsobiRubyEngine.run(code, lang) -> JSON string of a Reel
 *
 * The same in two steps, so a motion can be seen at once. The sketch runs
 * only once, in start:
 *   AsobiRubyEngine.start(code, lang) -> { json, pending }
 *       json: the first Reel as a JSON string. pending: true when it is a
 *       motion's quick preview ("pending": true in the Reel) and finish has the rest.
 *   AsobiRubyEngine.finish() -> JSON string of the whole Reel, or null when
 *       nothing is waiting (start answered everything, or another run came since).
 *
 * finish in slices, so a newer run can stop it halfway:
 *   AsobiRubyEngine.step(seconds) -> about that many seconds of work, then
 *       { done: false } while the whole Reel is not ready yet,
 *       { done: true, json } at the end (json: null when nothing was waiting).
 *   AsobiRubyEngine.drop() -> forgets the half-made whole Reel.
 */
(function (g) {
  "use strict";
  var vm = null, runner = null, starter = null, waiter = null, finisher = null, stepper = null, dropper = null;

  function boot(wasmUrl) {
    var api = g["ruby-wasm-wasi"];
    if (!api || !api.DefaultRubyVM) return Promise.reject(new Error("ruby.wasm API not loaded"));
    var compiled = WebAssembly.compileStreaming
      ? WebAssembly.compileStreaming(fetch(wasmUrl)).catch(function () {
          return fetch(wasmUrl).then(function (r) { return r.arrayBuffer(); }).then(function (b) { return WebAssembly.compile(b); });
        })
      : fetch(wasmUrl).then(function (r) { return r.arrayBuffer(); }).then(function (b) { return WebAssembly.compile(b); });
    return compiled.then(function (module) {
      return api.DefaultRubyVM(module, { env: { ASOBI_LIVE: "0" }, consolePrint: false });
    }).then(function (made) {
      vm = made.vm;
      vm.eval(g.ASOBI_RUBY);
      runner = vm.eval('require "js"\n->(source, lang) { Asobi::Web.run(source.to_s, lang.to_s) }');
      starter = vm.eval('->(source, lang) { Asobi::Web.start(source.to_s, lang.to_s) }');
      waiter = vm.eval('-> { Asobi::Web.waiting? }');
      finisher = vm.eval('-> { Asobi::Web.finish }');
      stepper = vm.eval('->(seconds) { Asobi::Web.finish_some(seconds.to_s) }');
      dropper = vm.eval('-> { Asobi::Web.drop }');
    });
  }

  function ready() {
    if (!runner) throw new Error("Ruby is not ready");
  }

  function run(code, lang) {
    ready();
    return runner.call("call", vm.wrap(String(code)), vm.wrap(String(lang))).toString();
  }

  function start(code, lang) {
    ready();
    var json = starter.call("call", vm.wrap(String(code)), vm.wrap(String(lang))).toString();
    return { json: json, pending: waiter.call("call").toString() === "true" };
  }

  function finish() {
    ready();
    var json = finisher.call("call").toString(); // Ruby's nil reads as ""
    return json === "" ? null : json;
  }

  function step(seconds) {
    ready();
    var json = stepper.call("call", vm.wrap(String(seconds))).toString(); // Ruby's nil reads as ""
    if (json !== "") return { done: true, json: json };
    if (waiter.call("call").toString() === "true") return { done: false };
    return { done: true, json: null };
  }

  function drop() {
    ready();
    dropper.call("call");
  }

  g.AsobiRubyEngine = { boot: boot, run: run, start: start, finish: finish, step: step, drop: drop };
})(typeof self !== "undefined" ? self : this);
