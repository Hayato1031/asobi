/* asobi playground: runs Ruby off the page, so typing never freezes.
 * Started as  new Worker("assets/ruby-worker.js#<base64url of JSON {api, wasm}>").
 *
 * Messages in:  { id, code, lang }                 one step: answers the whole Reel
 *               { id, code, lang, preview: true }  two steps: a motion's preview first
 * Messages out: { type: "ready" } | { type: "failed", message }
 *               { id, json }                 the whole Reel (the last answer for this id)
 *               { id, json, pending: true }  a motion's quick preview; { id, json } follows
 *               { id, working: true }        the whole Reel is still being made (sent
 *                                            between slices, many times a second)
 *               { id, skipped: true }        a newer request came first, so this one's
 *                                            (rest of the) work was not done
 *               { id, fatal }                the engine itself failed: do not trust it again
 * ids must grow: the newest request is the one with the largest id.
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

var newest = 0; // the id of the newest request that has arrived

// Run fn after any messages that are already waiting have been received:
// a message through a MessageChannel queues behind them.
var later = [];
var channel = new MessageChannel();
channel.port1.onmessage = function () { later.shift()(); };
function afterWaitingMessages(fn) {
  later.push(fn);
  channel.port2.postMessage(0);
}

function fatal(id, e) {
  self.postMessage({ id: id, fatal: String(e && e.message || e) });
}

function oneStep(msg) {
  try {
    self.postMessage({ id: msg.id, json: self.AsobiRubyEngine.run(msg.code, msg.lang) });
  } catch (e) { fatal(msg.id, e); }
}

// A motion's whole Reel is made in slices of about this many seconds. Between
// slices, waiting messages come in, so a newer request can stop the build.
var SLICE_SECONDS = 0.08;
var building = 0; // the id whose whole Reel is being made, or 0

// A newer request has come: give up the whole Reel being made.
function stopBuilding() {
  if (!building) return;
  var id = building;
  building = 0;
  try {
    self.AsobiRubyEngine.drop();
    self.postMessage({ id: id, skipped: true });
  } catch (e) { fatal(id, e); }
}

function twoSteps(msg) {
  if (msg.id < newest) { self.postMessage({ id: msg.id, skipped: true }); return; } // already out of date
  var first;
  try { first = self.AsobiRubyEngine.start(msg.code, msg.lang); } catch (e) { fatal(msg.id, e); return; }
  if (!first.pending) { self.postMessage({ id: msg.id, json: first.json }); return; }

  self.postMessage({ id: msg.id, json: first.json, pending: true });
  building = msg.id;
  afterWaitingMessages(function slice() {
    if (building !== msg.id) return;                // stopped (and answered) already
    if (msg.id < newest) { stopBuilding(); return; } // a newer edit arrived: this Reel would be stale
    var done;
    try { done = self.AsobiRubyEngine.step(SLICE_SECONDS); } catch (e) { building = 0; fatal(msg.id, e); return; }
    if (!done.done) {
      self.postMessage({ id: msg.id, working: true });
      afterWaitingMessages(slice);
      return;
    }
    building = 0;
    self.postMessage(done.json === null ? { id: msg.id, skipped: true } : { id: msg.id, json: done.json });
  });
}

self.onmessage = function (event) {
  var msg = event.data;
  if (msg.id > newest) newest = msg.id;
  ready.then(function () {
    stopBuilding(); // anything newer ends the build of an older whole Reel
    msg.preview ? twoSteps(msg) : oneStep(msg);
  }, function () {});
};
