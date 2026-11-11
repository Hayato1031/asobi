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
 */
(function (g) {
  "use strict";
  var vm = null, runner = null;

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
    });
  }

  function run(code, lang) {
    if (!runner) throw new Error("Ruby is not ready");
    return runner.call("call", vm.wrap(String(code)), vm.wrap(String(lang))).toString();
  }

  g.AsobiRubyEngine = { boot: boot, run: run };
})(typeof self !== "undefined" ? self : this);
