/* asobi player: draws a "Reel" (see DESIGN.md section 9) into an element.
 * Vanilla JS, no dependencies. Usage:
 *   const player = AsobiPlayer.mount(element, { controls: true, keys: true, language: "auto" });
 *   player.update(reel);   // swap the picture; the clock keeps running
 *                          // (a reel with pending: true is a quick first look at a
 *                          //  motion; a small grey dot says the rest is on its way)
 *   player.destroy();
 *
 * A Reel: { frames: ["<g>...</g>", ...], fps, view: [x, y, w, h], background, code, error,
 *           controls (false hides the buttons), parts (optional, see below) }
 *
 * Reacting parts. A frame may hold markers `<!--asobi:p1-->`. Each marker is
 * replaced by `<g data-asobi-part="p1" data-asobi-n="K">FRAME</g>`, where K
 * counts that part's copies in the finished frame (document order, from 0)
 * and FRAME is the part frame that copy shows now (its own markers replaced
 * the same way). reel.parts.p1 = { frames, fps, turn, key, from, what }:
 *   turn "click"  pointerdown on a copy plays that copy once, then frame 0
 *        "hover"  loops while the pointer is over the copy, frame 0 otherwise
 *        "key"    every copy plays once on keydown of `key` (any key if absent)
 *        "beat"   every copy plays once on each beat heard on `from` ("mic" / "music")
 *        "value"  frame round(v * (n - 1)); v (0..1) from `from`: "mouse_x", "mouse_y",
 *                 "mic" or "music" (`what`: "volume" (default), "low", "mid", "high", "pitch")
 * A Reel without parts is drawn exactly as before (one innerHTML per new frame).
 *
 * Sound ("mic"): one microphone and one analysis for the whole page, shared by
 * every player. It starts on the first pointerdown or keydown in a player whose
 * Reel asks for "mic" (browsers want a gesture), stays open across update() and
 * across players coming and going, and is closed RELEASE_MS after the last
 * player that wanted it stopped wanting it (destroyed, or a Reel without "mic").
 * "music" is the same analysis on the sound asobi itself plays (below).
 *
 * asobi's own sound. reel.song = { id, src, volume } loops a song (a media
 * element, so it streams); a part with `sound` ("pop", "kick", "snare", "hat",
 * "clap", "bell") or `note` (a MIDI number) plays that sound, made with Web
 * Audio, each time it starts to play (click: per clicked copy; hover: when the
 * pointer comes over a copy; key and beat: once per part). One graph for the page:
 *   song + effect sounds -> heard -> out -> mute -> speakers
 *                             |        `-> the recording (while recording)
 *                             `-> the "music" analysis
 *   effect sounds of a part that beats on "music" -> out (so it never hears itself)
 * It starts on the first pointerdown or keydown in a player whose Reel makes
 * sound (a hint says so). A page can hold many players, so each one waits for
 * its own: a pointerdown on it, or a keydown when its keys are on or the
 * pointer is over it. Before that it makes no sound and its song does not
 * start (a song already playing for another player goes on while either
 * wants it). update() with the same song id lets the song go on;
 * another id switches; a Reel without a song stops it; an error Reel changes
 * nothing. `m` mutes the speakers (not the analysis, not the recording).
 * A Reel that makes no sound never creates an audio context.
 *
 * Test hook (not for sketches): AsobiPlayer._internals holds the plain
 * functions (compose, valueIndex, makeListener, ...) for test/web/player-check.js,
 * plus sound() -> a copy of the current sound values and state (running, muted,
 * song: { id, playing, time, volume } or null, played: the last effect sounds
 * started, each { sound | note, part, at }),
 * feed(from, values) to pretend a source is heard: feed("mic", { volume: 0.5,
 * beat: true }) (beat: true counts one beat); feed("mic", null) stops pretending,
 * connect(from, audioNode) to analyse any Web Audio node as that source
 * (null disconnects it), and synth(ctx, destination, when, { sound } | { note })
 * to make one effect sound into any context (an OfflineAudioContext, say), and
 * fxBus(ctx, destination) -> the node effect sounds are summed into.
 */
(function (global) {
  "use strict";

  var SVG_NS = "http://www.w3.org/2000/svg";
  var HIDE_AFTER_MS = 2500;
  var MAX_SIDE = 1080;    // longest side of a recording, in pixels
  var RELEASE_MS = 30000; // the microphone closes this long after no player wants it
  var MAX_DEPTH = 32;     // parts inside parts, at most this deep

  var TEXT = {
    en: { record: "record", stop: "stop", code: "code", noRecorder: "Recording is not available in this browser.",
          waiting: "Working out the motion...", waitToRecord: "The motion is still being worked out. Try again in a moment.",
          listen: "click to listen", noMic: "No microphone: the picture will not hear the sound.",
          sound: "click for sound", muted: "muted", unmuted: "sound on" },
    ja: { record: "録画", stop: "停止", code: "コード", noRecorder: "このブラウザでは録画できません。",
          waiting: "動きを用意しています…", waitToRecord: "動きを用意しているところです。少し待ってからもう一度どうぞ。",
          listen: "クリックで音を聞きます", noMic: "マイクが使えないため、絵は音を聞けません。",
          sound: "クリックで音が出ます", muted: "消音", unmuted: "消音を解除" }
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
    // The "still working out the motion" sign: a small grey dot where the
    // recording dot sits. It fades in only if the wait is not over at once.
    ".asobi-wait{position:absolute;top:13px;left:13px;width:8px;height:8px;border-radius:50%;",
    "  background:rgba(130,130,140,.9);box-shadow:0 0 0 2px rgba(255,255,255,.7);display:none;opacity:0;",
    "  animation:asobi-breathe 1.6s ease-in-out .4s infinite}",
    ".asobi-wait.asobi-on{display:block}",
    ".asobi-recdot.asobi-on~.asobi-wait{left:34px}",
    "@keyframes asobi-breathe{0%,100%{opacity:.3}50%{opacity:.85}}",
    // The quiet "click to listen" hint (and the one-time "no microphone" note).
    ".asobi-listen{position:absolute;left:50%;bottom:14px;transform:translateX(-50%);display:none;",
    "  font:12px/1.3 system-ui,-apple-system,sans-serif;color:rgba(255,255,255,.9);background:rgba(20,20,24,.4);",
    "  border-radius:999px;padding:5px 12px;pointer-events:none;white-space:nowrap}",
    ".asobi-listen.asobi-on{display:block}",
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

  // withSound: the video also carries asobi's sound (H.264 + AAC first, then webm).
  function pickMime(withSound) {
    if (typeof MediaRecorder === "undefined" || !MediaRecorder.isTypeSupported) return null;
    var list = withSound ?
      ["video/mp4;codecs=avc1,mp4a.40.2", "video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm", "video/mp4"] :
      ["video/mp4;codecs=avc1", "video/mp4", "video/webm;codecs=vp9", "video/webm;codecs=vp8", "video/webm"];
    for (var i = 0; i < list.length; i++) if (MediaRecorder.isTypeSupported(list[i])) return list[i];
    return null;
  }

  function clamp01(v) { return v > 0 ? (v < 1 ? v : 1) : 0; } // NaN -> 0

  // How far to move toward a target in dt seconds, for a time constant tau.
  function ease(dt, tau) { return 1 - Math.exp(-dt / tau); }

  // ==== parts: markers, copies, frames ====================================

  var MARKER = /<!--asobi:([A-Za-z0-9_-]+)-->/g;

  // "a<!--asobi:p1-->b" -> ["a", "p1", "b"]: text at even places, part ids at odd.
  function parseFrame(s) {
    var out = [], last = 0, m;
    s = String(s);
    MARKER.lastIndex = 0;
    while ((m = MARKER.exec(s))) {
      out.push(s.slice(last, m.index), m[1]);
      last = m.index + m[0].length;
    }
    out.push(s.slice(last));
    return out;
  }

  // What a Reel's parts need, worked out once per Reel. Frames are parsed
  // when first shown. Returns null when the Reel has no usable parts.
  function prepare(reel) {
    var parts = reel.parts;
    if (!parts || typeof parts !== "object") return null;
    var prep = { reel: reel, parts: {}, cache: { "": [] }, ids: [],
                 has: { click: false, hover: false, key: false, beat: false, mouse: false, mic: false, music: false, sound: false } };
    for (var id in parts) {
      var d = parts[id];
      if (!d || !Array.isArray(d.frames) || d.frames.length === 0) continue;
      prep.parts[id] = d; prep.cache[id] = []; prep.ids.push(id);
      if (partSound(d)) prep.has.sound = true;
      if (d.turn === "click" || d.turn === "hover" || d.turn === "key") prep.has[d.turn] = true;
      if (d.turn === "beat") prep.has.beat = true;
      if (d.turn === "value" && (d.from === "mouse_x" || d.from === "mouse_y")) prep.has.mouse = true;
      if ((d.turn === "beat" || d.turn === "value") && (d.from === "mic" || d.from === "music")) prep.has[d.from] = true;
      if (d.turn === "beat" && !d.from) prep.has.mic = true; // "mic" is the default
    }
    return prep.ids.length ? prep : null;
  }

  // The sound a part plays when it starts: { sound: "pop" } or { note: 60 }; null for
  // none (also for value parts, and for a name that is not one of the six: silent).
  function partSound(d) {
    if (!d || d.turn === "value") return null;
    if (typeof d.sound === "string" && SOUNDS.hasOwnProperty(d.sound)) return { sound: d.sound };
    if (typeof d.note === "number" && d.note >= 0 && d.note <= 127) return { note: d.note };
    return null;
  }

  // The song a Reel plays: { id, src, volume } or null.
  function songOf(r) {
    var s = r && r.song;
    if (!s || typeof s.src !== "string" || s.src === "") return null;
    var v = Number(s.volume);
    return { id: String(s.id || s.src), src: s.src, volume: s.volume === undefined || s.volume === null || !isFinite(v) ? 1 : clamp01(v) };
  }

  function parsed(prep, id, i) {
    var c = prep.cache[id];
    return c[i] || (c[i] = parseFrame(id === "" ? prep.reel.frames[i] : prep.parts[id].frames[i]));
  }

  // Build the frame to show. pick(id, k, part) says which frame copy k of a
  // part shows now. Returns { pieces, copies }: pieces joined is the SVG text;
  // copies[i] = { id, k, idx, parent, from, to } in document order, where
  // pieces[from] is the copy's opening <g> and pieces[to - 1] its </g>.
  function compose(prep, topIdx, pick) {
    var pieces = [], copies = [], counts = {};
    function walk(list, parent, depth) {
      for (var i = 0; i < list.length; i++) {
        if (i % 2 === 0) { if (list[i]) pieces.push(list[i]); continue; }
        var id = list[i], d = prep.parts[id];
        if (!d || depth >= MAX_DEPTH) { pieces.push("<!--asobi:" + id + "-->"); continue; } // left as it was
        var k = counts[id] || 0;
        counts[id] = k + 1;
        var n = d.frames.length, f = pick(id, k, d) | 0;
        if (f < 0 || f >= n) f = 0;
        var c = { id: id, k: k, idx: f, parent: parent, from: pieces.length, to: 0 };
        copies.push(c);
        pieces.push('<g data-asobi-part="' + id + '" data-asobi-n="' + k + '">');
        walk(parsed(prep, id, f), copies.length - 1, depth + 1);
        pieces.push("</g>");
        c.to = pieces.length;
      }
    }
    walk(parsed(prep, "", topIdx), -1, 0);
    return { pieces: pieces, copies: copies };
  }

  // Same copies in the same places (only their frames may differ)?
  function sameShape(a, b) {
    if (!a || a.copies.length !== b.copies.length) return false;
    for (var i = 0; i < a.copies.length; i++) {
      if (a.copies[i].id !== b.copies[i].id || a.copies[i].parent !== b.copies[i].parent) return false;
    }
    return true;
  }

  // A value 0..1 -> one of n frames.
  function valueIndex(v, n) { return Math.round(clamp01(v) * (n - 1)); }

  // A frame of a motion started at `start` (ms), played once at fps; -1 when over.
  function onceIndex(start, now, fps, n) {
    var f = Math.floor(((now - start) / 1000) * (Number(fps) > 0 ? Number(fps) : 1));
    return f >= 0 && f < n ? f : -1;
  }

  // ==== sound analysis =====================================================
  // Each value is 0..1. Levels are measured in dB and mapped linearly from a
  // floor to the recent peak, so a quiet room and a loud club both use the
  // whole range. All times are in seconds.

  var SILENT_DB = -100;   // anything lower is silence
  var RANGE_DB = 24;      // 0..1 spans this many dB below the recent peak
  var PEAK_FALL = 2;      // dB per second the remembered peak sinks (automatic sensitivity)
  var MIN_SPAN_DB = 6;    // the peak stays at least this far above the floor
  var GATE_DB = 6;        // volume: sound must be this far above the room's noise
  var NOISE_SMOOTH = 0.1; // the noise follower looks at the level smoothed this much
  var NOISE_RISE = 3;     // seconds (time constant) the noise estimate takes to climb
  var NOISE_MAX = -50;    // dBFS: louder than this is never "noise" (it is music)
  var BAND_SPAN = 30;     // a band this far below the overall peak counts as empty
  var ATTACK = 0.01;      // time constants of the shown value: fast up,
  var RELEASE = 0.15;     //   slower down
  var PITCH_LOW = 80, PITCH_HIGH = 4000; // Hz at pitch 0 and 1 (log scale)
  var PITCH_SMOOTH = 0.08;
  var PITCH_HOLD = 2;     // seconds pitch holds its value when it is too quiet to tell,
  var PITCH_FADE = 0.5;   //   then eases back to 0
  var PITCH_MIN = 0.05;   // volume (target) needed to tell the pitch
  // A beat is a sudden rise of the low sounds: the "onset", how many dB the
  // low frequencies (20-250 Hz) rose since the last measurement, on average
  // per frequency bin (kicks give about 25, hats and wobbles under 7).
  var BEAT_MIN = 10;         // the onset must be at least this,
  var BEAT_K = 4;            // and at least BEAT_K times the recent average onset,
  var BEAT_AVG = 1;          // averaged over about this long (seconds),
  var BEAT_REST = 0.2;       // and not sooner than this after the last beat,
                             // while the volume is above the room's noise

  // One level (volume or a band). step(db, dt, peakFloor) updates
  // me.target (the level now, 0..1) and me.value (eased, what is shown).
  function makeLevel(gated) {
    var me = { peak: SILENT_DB, noise: SILENT_DB, slow: SILENT_DB, target: 0, value: 0 };
    me.step = function (db, dt, peakFloor) {
      if (!(db > SILENT_DB)) db = SILENT_DB; // also -Infinity and NaN
      var floor = SILENT_DB;
      if (gated) { // follow the room's noise: drops at once, climbs in a few seconds, never above NOISE_MAX
        if (me.slow === SILENT_DB) me.slow = me.noise = Math.min(db, NOISE_MAX); // the first sound heard
        me.slow += (db - me.slow) * ease(dt, NOISE_SMOOTH);
        me.noise = me.slow < me.noise ? me.slow : Math.min(me.noise + (me.slow - me.noise) * ease(dt, NOISE_RISE), NOISE_MAX);
        floor = Math.max(SILENT_DB, me.noise + GATE_DB);
      }
      me.peak = db > me.peak ? db : me.peak - PEAK_FALL * dt;
      var least = Math.max(floor, peakFloor > SILENT_DB ? peakFloor : SILENT_DB) + MIN_SPAN_DB;
      if (me.peak < least) me.peak = least;
      var low = Math.max(floor, me.peak - RANGE_DB);
      me.target = db <= low ? 0 : Math.min(1, (db - low) / (me.peak - low));
      me.value += (me.target - me.value) * ease(dt, me.target > me.value ? ATTACK : RELEASE);
      if (me.target === 0 && me.value < 0.004) me.value = 0; // silence is exactly 0
      return me.value;
    };
    return me;
  }

  // Pitch from the "centre" of the sound in Hz (0 when too quiet to tell).
  function makePitch() {
    var me = { value: 0, quiet: 0 };
    me.step = function (hz, dt) {
      if (hz > 0) {
        var t = clamp01(Math.log(hz / PITCH_LOW) / Math.log(PITCH_HIGH / PITCH_LOW));
        me.value += (t - me.value) * ease(dt, PITCH_SMOOTH);
        me.quiet = 0;
      } else if ((me.quiet += dt) > PITCH_HOLD) {
        me.value -= me.value * ease(dt, PITCH_FADE);
        if (me.value < 0.004) me.value = 0;
      }
      return me.value;
    };
    return me;
  }

  // Beats from the low onset (see BEAT_MIN) over time: true on a beat.
  function makeBeat() {
    var avg = 0, last = -1e9, prev = null;
    return function (onset, now) {
      var dt = prev === null ? 0.016 : Math.min(0.1, Math.max(0.001, now - prev));
      prev = now;
      var need = Math.max(BEAT_MIN, BEAT_K * avg);
      avg += (onset - avg) * ease(dt, BEAT_AVG);
      if (onset >= need && now - last >= BEAT_REST) { last = now; return true; }
      return false;
    };
  }

  // The whole analysis of one source, fed with measurements:
  // { volume: dB, low: dB, mid: dB, high: dB, centre: Hz, onset: dB }, now and dt in seconds.
  function makeListener() {
    var vol = makeLevel(true), pitch = makePitch(), beat = makeBeat();
    var bands = { low: makeLevel(false), mid: makeLevel(false), high: makeLevel(false) };
    var me = { volume: 0, low: 0, mid: 0, high: 0, pitch: 0, beats: 0 };
    me.step = function (m, now, dt) {
      me.volume = vol.step(m.volume, dt);
      var open = vol.target > 0; // below the room's noise, every band is silent too
      for (var name in bands) me[name] = bands[name].step(open ? m[name] : SILENT_DB, dt, vol.peak - BAND_SPAN);
      me.pitch = pitch.step(vol.target > PITCH_MIN ? m.centre : 0, dt);
      if (beat(open ? m.onset : 0, now)) me.beats++;
    };
    return me;
  }

  // Measure an AnalyserNode once per frame and feed a listener.
  var FFT_SIZE = 2048; // about 43 ms at 48 kHz: short enough for beats
  function makeAnalysis(ctx, input) {
    var an = ctx.createAnalyser();
    an.fftSize = FFT_SIZE;
    an.smoothingTimeConstant = 0; // the listener does its own smoothing
    input.connect(an);
    var freq = new Float32Array(an.frequencyBinCount), wave = new Float32Array(an.fftSize);
    var hz = ctx.sampleRate / an.fftSize, top = Math.min(freq.length, Math.floor(12000 / hz) + 1);
    var lows = Math.max(2, Math.ceil(250 / hz)), before = new Float32Array(lows).fill(SILENT_DB);
    var me = makeListener(), m = { volume: 0, low: 0, mid: 0, high: 0, centre: 0, onset: 0 };
    me.read = function (now, dt) {
      an.getFloatTimeDomainData(wave);
      var sq = 0, i;
      for (i = 0; i < wave.length; i++) sq += wave[i] * wave[i];
      m.volume = 10 * Math.log10(sq / wave.length); // dBFS of the RMS
      an.getFloatFrequencyData(freq);
      var most = -Infinity;
      for (i = 1; i < top; i++) if (freq[i] > most) most = freq[i];
      var all = 0, low = 0, mid = 0, high = 0, w = 0, wl = 0, rise = 0, floor = Math.max(SILENT_DB, most - 60);
      for (i = 1; i < lows; i++) { // onset: how much the low bins rose since last time
        var d = freq[i] > floor ? freq[i] : floor;
        if (d > before[i]) rise += d - before[i];
        before[i] = d;
      }
      m.onset = rise / (lows - 1);
      for (i = 1; i < top; i++) {
        var f = i * hz, p = Math.pow(10, freq[i] / 10);
        all += p;
        if (f < 250) low += p; else if (f < 2000) mid += p; else high += p;
        if (f >= 40 && freq[i] > floor) { var a = Math.sqrt(p); w += a; wl += a * Math.log(f); } // pitch: by loudness of each part, leakage ignored
      }
      // Each band on the same dB scale as the volume: volume + its share of the power.
      m.low = all > 0 ? m.volume + 10 * Math.log10(low / all) : SILENT_DB;
      m.mid = all > 0 ? m.volume + 10 * Math.log10(mid / all) : SILENT_DB;
      m.high = all > 0 ? m.volume + 10 * Math.log10(high / all) : SILENT_DB;
      m.centre = w > 0 ? Math.exp(wl / w) : 0;
      me.step(m, now / 1000, dt);
    };
    me.disconnect = function () { try { input.disconnect(an); } catch (e) { /* already gone */ } };
    return me;
  }

  // ---- the page's sound: one microphone and one graph for every player -----
  var sound = {
    state: "off",      // the microphone: "off" | "starting" | "on" | "refused"
    ctx: null, stream: null, input: null,
    graph: null,       // asobi's own sound: { ctx, heard, out, mute, fx, fxOut } (see the header)
    songs: {},         // song id -> { id, src, volume, users, el, node, gain, blocked, failed }
    voices: [],        // effect sounds still sounding, oldest first
    played: [],        // test hook: the last effect sounds started
    muted: false, muteEvent: null,
    sources: { mic: null, music: null }, // analyses; "music" listens to graph.heard
    fed: { mic: null, music: null },     // test hook: pretend values
    fedBeats: { mic: 0, music: 0 },
    wanting: [],       // players whose Reel asks for the microphone
    making: [],        // players whose Reel makes sound (a song, or parts with a sound)
    releaseTimer: 0, lastRead: -1
  };

  function listSet(list, item, on) {
    var i = list.indexOf(item);
    if (on && i < 0) list.push(item);
    if (!on && i >= 0) list.splice(i, 1);
  }

  function soundWant(token, mic, own) {
    listSet(sound.wanting, token, mic);
    listSet(sound.making, token, own);
    clearTimeout(sound.releaseTimer);
    if (sound.wanting.length) return;
    if (sound.state === "on" || sound.state === "starting" || (sound.ctx && !sound.making.length)) {
      sound.releaseTimer = setTimeout(soundRelease, RELEASE_MS);
    }
  }

  // The page's audio context, made or woken. Must run inside a click or key press.
  function contextNow() {
    var AC = global.AudioContext || global.webkitAudioContext;
    if (!AC) return null;
    try {
      if (!sound.ctx) sound.ctx = new AC();
      if (sound.ctx.state === "suspended") {
        var p = sound.ctx.resume();
        if (p && p.catch) p.catch(function () { /* stays suspended: the next click tries again */ });
      }
    } catch (e) { return null; }
    return sound.ctx;
  }

  // Must run inside a click or key press: browsers allow audio only then.
  // mic: open the microphone; own: start asobi's own sound.
  function soundStart(mic, own) {
    if (own) outStart();
    if (mic) micStart();
  }

  function micStart() {
    if (sound.state !== "off") return;
    var md = global.navigator && navigator.mediaDevices;
    if (!md || !md.getUserMedia) { sound.state = "refused"; return; }
    sound.state = "starting";
    if (!contextNow()) { sound.state = "refused"; return; }
    md.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false } }).then(
      function (stream) {
        if (sound.state !== "starting" || !sound.ctx) { stream.getTracks().forEach(function (t) { t.stop(); }); return; }
        sound.stream = stream;
        sound.input = sound.ctx.createMediaStreamSource(stream);
        connectSource("mic", sound.input);
        sound.state = "on";
      },
      // Refused: the microphone stays off; asobi's own sound goes on.
      function () { if (sound.state === "starting") { sound.state = "refused"; if (!sound.graph) closeContext(); } });
  }

  // Listen to a Web Audio node as a source ("mic" or "music"); null disconnects.
  function connectSource(from, node) {
    if (sound.sources[from]) sound.sources[from].disconnect();
    sound.sources[from] = node ? makeAnalysis(node.context, node) : null;
  }

  function closeContext() {
    for (var id in sound.songs) songStop(sound.songs[id]);
    if (sound.graph) { connectSource("music", null); sound.graph = null; }
    sound.voices = [];
    if (sound.ctx) { try { sound.ctx.close(); } catch (e) { /* closed */ } }
    sound.ctx = null;
  }

  // RELEASE_MS after the last player stopped wanting it: the microphone closes,
  // and the audio context too when no player makes sound.
  function soundRelease() {
    if (sound.wanting.length) return;
    connectSource("mic", null);
    if (sound.stream) sound.stream.getTracks().forEach(function (t) { t.stop(); });
    sound.stream = null; sound.input = null;
    if (sound.state !== "refused") sound.state = "off";
    if (!sound.making.length) closeContext();
  }

  // ---- asobi's own sound -------------------------------------------------
  var MAX_VOICES = 16;   // effect sounds at once; the oldest stops for a new one
  var FX_LEVEL = 0.8;    // loudness of the effect sounds next to a song at volume 1

  // Start the graph and every song a player wants. Inside a click or key press.
  function outStart() {
    var ctx = contextNow();
    if (!ctx) return;
    if (!sound.graph) {
      var g = { ctx: ctx };
      g.heard = ctx.createGain();
      g.out = ctx.createGain();
      g.mute = ctx.createGain();
      g.mute.gain.value = sound.muted ? 0 : 1;
      g.heard.connect(g.out);
      g.out.connect(g.mute);
      g.mute.connect(ctx.destination);
      g.fx = fxBus(ctx, g.heard);   // effect sounds the analysis hears
      g.fxOut = fxBus(ctx, g.out);  // effect sounds of a part that beats on "music"
      sound.graph = g;
      connectSource("music", g.heard);
    }
    for (var id in sound.songs) if (heardBy(sound.songs[id])) songPlay(sound.songs[id]);
  }

  // A song starts only for a player that was clicked (or got a key): a page
  // holds many players, and a click in one must not start another's song.
  // Once playing, it goes on while any player wants it.
  function heardBy(e) {
    for (var i = 0; i < e.users.length; i++) if (e.users[i].started) return true;
    return false;
  }

  // Effect sounds are summed here: a gentle compressor, then a soft ceiling
  // under full scale, so that many at once never clip.
  function fxBus(ctx, to) {
    var level = ctx.createGain(), comp = ctx.createDynamicsCompressor(), ceil = ctx.createWaveShaper();
    level.gain.value = FX_LEVEL;
    comp.threshold.value = -8; comp.knee.value = 4; comp.ratio.value = 12;
    comp.attack.value = 0.002; comp.release.value = 0.15;
    ceil.curve = softCeiling();
    level.connect(comp); comp.connect(ceil); ceil.connect(to);
    return level;
  }

  var ceilingCurve = null;
  function softCeiling() { // straight up to 0.5, then bends toward 0.95
    if (ceilingCurve) return ceilingCurve;
    var n = 2049, c = new Float32Array(n);
    for (var i = 0; i < n; i++) {
      var x = (i / (n - 1)) * 2 - 1, a = Math.abs(x);
      var y = a <= 0.5 ? a : 0.5 + 0.45 * Math.tanh((a - 0.5) / 0.45);
      c[i] = x < 0 ? -y : y;
    }
    return (ceilingCurve = c);
  }

  function soundRunning() {
    if (!sound.graph || !sound.ctx || sound.ctx.state !== "running") return false;
    for (var id in sound.songs) if (sound.songs[id].blocked) return false;
    return true;
  }

  // ---- the song: a media element, so even an hour-long mix streams ------
  // A player wants one song (or none, s = null). Players that want the same id
  // share it; a song no player wants stops.
  function songWant(token, s) {
    var id = s ? s.id : null, e;
    for (var k in sound.songs) {
      e = sound.songs[k];
      if (k === id || e.users.indexOf(token) < 0) continue;
      listSet(e.users, token, false);
      if (!e.users.length) songStop(e);
    }
    if (!s) return;
    e = sound.songs[id] || (sound.songs[id] = { id: id, src: s.src, volume: s.volume, users: [],
                                                el: null, node: null, gain: null, blocked: false, failed: false });
    listSet(e.users, token, true);
    if (e.volume !== s.volume) {
      e.volume = s.volume;
      if (e.gain) e.gain.gain.setTargetAtTime(s.volume, e.gain.context.currentTime, 0.03);
    }
    if (sound.graph && heardBy(e)) songPlay(e);
  }

  function songPlay(e) {
    var g = sound.graph;
    if (!e.el) {
      var a = e.el = document.createElement("audio");
      a.loop = true; a.preload = "auto"; a.src = e.src;
      a.addEventListener("error", function () { e.failed = true; });
      e.node = g.ctx.createMediaElementSource(a);
      e.gain = g.ctx.createGain();
      e.gain.gain.value = e.volume;
      e.node.connect(e.gain);
      e.gain.connect(g.heard);
    }
    if (!e.el.paused || e.failed) return;
    var p = e.el.play();
    if (p && p.then) {
      p.then(function () { e.blocked = false; },
             function (err) { if (err && err.name === "NotAllowedError") e.blocked = true; else e.failed = true; });
    }
  }

  function songStop(e) {
    delete sound.songs[e.id];
    if (!e.el) return;
    e.el.pause();
    e.el.removeAttribute("src");
    try { e.el.load(); } catch (err) { /* nothing to load */ }
    try { e.node.disconnect(); e.gain.disconnect(); } catch (err) { /* gone with the context */ }
  }

  // ---- effect sounds, made with Web Audio --------------------------------
  // Each maker builds one sound starting at t into v.out; v.at(t) sets when it is over.
  var noise = { ctx: null, buffer: null };
  function noiseBuffer(ctx) {
    if (noise.ctx !== ctx) {
      var b = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate), d = b.getChannelData(0), seed = 7;
      for (var i = 0; i < d.length; i++) { seed = (seed * 16807) % 2147483647; d[i] = seed / 1073741823.5 - 1; }
      noise.ctx = ctx; noise.buffer = b;
    }
    return noise.buffer;
  }

  var SOUNDS = {
    pop: function (v, t) { // a soft blip that drops in pitch
      var o = v.osc("sine", 900, t);
      o.frequency.exponentialRampToValueAtTime(260, t + 0.12);
      o.connect(v.env(0.8, 0.003, 0.15, t));
    },
    kick: function (v, t) {
      var o = v.osc("sine", 160, t);
      o.frequency.exponentialRampToValueAtTime(45, t + 0.14);
      o.connect(v.env(1, 0.002, 0.42, t));
      var c = v.osc("triangle", 900, t); // the beater's click
      c.frequency.exponentialRampToValueAtTime(200, t + 0.02);
      c.connect(v.env(0.25, 0.001, 0.02, t));
    },
    snare: function (v, t) {
      var n = v.noise(t), hp = v.filter("highpass", 1200, 0.7);
      n.connect(hp); hp.connect(v.env(0.55, 0.001, 0.2, t));
      var o = v.osc("triangle", 190, t);
      o.frequency.exponentialRampToValueAtTime(150, t + 0.08);
      o.connect(v.env(0.5, 0.001, 0.1, t));
    },
    hat: function (v, t) {
      var n = v.noise(t), hp = v.filter("highpass", 7500, 0.7);
      n.connect(hp); hp.connect(v.env(0.7, 0.001, 0.055, t));
    },
    clap: function (v, t) { // three quick slaps, then the room
      var n = v.noise(t), bp = v.filter("bandpass", 1300, 1.1);
      n.connect(bp);
      for (var i = 0; i < 3; i++) bp.connect(v.env(0.8, 0.001, 0.011, t + i * 0.011));
      bp.connect(v.env(0.7, 0.002, 0.2, t + 0.033));
    },
    bell: function (v, t) { // a ring of about a second
      var parts = [[1, 0.5, 1.3], [2.01, 0.22, 0.9], [2.76, 0.16, 0.6], [5.4, 0.07, 0.3]];
      for (var i = 0; i < parts.length; i++) {
        v.osc("sine", 880 * parts[i][0], t).connect(v.env(parts[i][1], 0.002, parts[i][2], t));
      }
    }
  };

  // A note: a soft pluck of about half a second at the note's pitch.
  function pluck(v, t, note) {
    var f = 440 * Math.pow(2, (note - 69) / 12);
    var lp = v.filter("lowpass", Math.min(f * 8, 16000), 0.8);
    lp.frequency.exponentialRampToValueAtTime(Math.min(f * 1.5, 16000), t + 0.3);
    v.osc("triangle", f, t).connect(lp);
    var h = v.osc("sine", f * 2, t), hg = v.ctx.createGain();
    hg.gain.value = 0.25;
    h.connect(hg); hg.connect(lp);
    lp.connect(v.env(0.7, 0.004, 0.5, t));
  }

  // One effect sound into dest, starting at `when`. Returns the voice
  // { out, sources, end } or null for no sound (an unknown name).
  function synth(ctx, dest, when, what) {
    var make = what && typeof what.sound === "string" && SOUNDS.hasOwnProperty(what.sound) ? SOUNDS[what.sound] : null;
    var isNote = !make && what && typeof what.note === "number" && what.note >= 0 && what.note <= 127;
    if (!make && !isNote) return null;
    var out = ctx.createGain();
    var v = { ctx: ctx, out: out, sources: [], end: when };
    v.osc = function (type, f, t) {
      var o = ctx.createOscillator();
      o.type = type; o.frequency.setValueAtTime(f, t);
      v.sources.push(o);
      return o;
    };
    v.noise = function () {
      var s = ctx.createBufferSource();
      s.buffer = noiseBuffer(ctx); s.loop = true;
      v.sources.push(s);
      return s;
    };
    v.filter = function (type, f, q) {
      var b = ctx.createBiquadFilter();
      b.type = type; b.frequency.setValueAtTime(f, when); b.Q.value = q;
      return b;
    };
    // A gain that rises to peak in `attack` seconds from t, then fades away in `decay`.
    v.env = function (peak, attack, decay, t) {
      var g = ctx.createGain();
      g.gain.setValueAtTime(0, when);
      g.gain.setValueAtTime(0, t);
      g.gain.linearRampToValueAtTime(peak, t + attack);
      g.gain.exponentialRampToValueAtTime(0.0005, t + attack + decay);
      g.gain.linearRampToValueAtTime(0, t + attack + decay + 0.01);
      g.connect(out);
      if (t + attack + decay + 0.01 > v.end) v.end = t + attack + decay + 0.01;
      return g;
    };
    if (make) make(v, when); else pluck(v, when, what.note);
    out.connect(dest);
    for (var i = 0; i < v.sources.length; i++) { v.sources[i].start(when); v.sources[i].stop(v.end + 0.02); }
    v.sources[0].onended = function () { try { out.disconnect(); } catch (e) { /* gone */ } };
    return v;
  }

  // Play a part's sound now on the page's graph. bypass: straight to [out],
  // not heard by the "music" analysis.
  function fxPlay(what, bypass, part) {
    var g = sound.graph;
    if (!g || !what) return;
    var now = g.ctx.currentTime, list = sound.voices;
    while (list.length && list[0].end < now) list.shift();
    while (list.length >= MAX_VOICES) { // too many: the oldest fades out at once
      var old = list.shift();
      try {
        old.out.gain.cancelScheduledValues(now);
        old.out.gain.setValueAtTime(old.out.gain.value, now);
        old.out.gain.linearRampToValueAtTime(0, now + 0.01);
        for (var i = 0; i < old.sources.length; i++) old.sources[i].stop(now + 0.015);
      } catch (e) { /* already over */ }
    }
    var v = synth(g.ctx, bypass ? g.fxOut : g.fx, now + 0.005, what);
    if (!v) return;
    list.push(v);
    var note = { part: part, at: performance.now() };
    if (what.sound) note.sound = what.sound; else note.note = what.note;
    sound.played.push(note);
    if (sound.played.length > 64) sound.played.shift();
  }

  function setMuted(on) {
    sound.muted = on;
    var g = sound.graph;
    if (g) g.mute.gain.setTargetAtTime(on ? 0 : 1, g.ctx.currentTime, 0.015);
  }

  // Measure every source once per animation frame, however many players ask.
  function soundRead(now) {
    if (now === sound.lastRead) return;
    var dt = sound.lastRead < 0 ? 0.016 : Math.min(0.1, Math.max(0.001, (now - sound.lastRead) / 1000));
    sound.lastRead = now;
    for (var from in sound.sources) if (sound.sources[from] && !sound.fed[from]) sound.sources[from].read(now, dt);
  }

  function soundValue(from, what) {
    var src = sound.fed[from] || sound.sources[from];
    var v = src ? src[what || "volume"] : 0;
    return typeof v === "number" ? v : 0;
  }

  function soundBeats(from) {
    return (sound.sources[from] ? sound.sources[from].beats : 0) + sound.fedBeats[from];
  }

  // ==== the player ==========================================================

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
    var waitDot = el("div", "asobi-wait", root); // outside the <svg>, so never in a recording
    waitDot.title = T.waiting;
    var listenHint = el("div", "asobi-listen", root); // outside the <svg> too
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
    var prep = null;            // its parts, worked out (null: no parts)
    var pending = false;        // is that reel a quick first look (the motion is on its way)?
    var reelId = 0;             // bumps on every good reel
    var t0 = performance.now(); // the clock: never reset by update()
    var shown = { id: -1, idx: -1 };
    var shownParts = null;      // what compose() gave for the frame on screen
    var copyEls = null;         // the copies' <g> elements on screen, in document order
    var raf = 0, destroyed = false;
    var hideTimer = 0, noteTimer = 0;
    var token = { started: false }; // this player, for the page's sound (started: clicked, or got a key)
    // Part state, kept across update() by part id (and copy number).
    var playFrom = {};          // "p1" or "p1|3" -> ms when a one-time play started
    var hoverFrom = {};         // "p1|3" -> ms when the pointer came over that copy
    var beatSeen = {};          // "p4" -> beats already used
    var pointer = { x: 0, y: 0, inside: false, seen: false, vx: 0, vy: 0 };
    var hint = { shown: "", toldNoMic: false, noMicUntil: 0, flash: "", flashUntil: 0 };
    var wants = { mic: false, own: false }; // what the Reel needs: the microphone, asobi's own sound

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

    // ---- which frame each part copy shows -----------------------------
    function partValue(d) {
      if (d.from === "mouse_x") return pointer.vx;
      if (d.from === "mouse_y") return pointer.vy;
      if (d.from === "mic" || d.from === "music") return soundValue(d.from, d.what);
      return 0;
    }

    function pick(id, k, d, now) {
      var n = d.frames.length, f, key;
      if (d.turn === "value") return valueIndex(partValue(d), n);
      if (d.turn === "hover") {
        key = id + "|" + k;
        if (hoverFrom[key] === undefined) return 0;
        f = Math.floor(((now - hoverFrom[key]) / 1000) * (Number(d.fps) > 0 ? Number(d.fps) : 1));
        return f > 0 ? f % n : 0;
      }
      key = d.turn === "click" ? id + "|" + k : id; // key and beat: every copy together
      if (playFrom[key] === undefined) return 0;
      f = onceIndex(playFrom[key], now, d.fps, n);
      if (f < 0) { delete playFrom[key]; return 0; } // over: rest at frame 0
      return f;
    }

    // The copies (part id and copy number) the element e is inside, innermost first.
    function copiesAt(e) {
      var out = [];
      while (e && e !== content && e.getAttribute) {
        var id = e.getAttribute("data-asobi-part");
        if (id !== null) out.push({ id: id, k: e.getAttribute("data-asobi-n") });
        e = e.parentNode;
      }
      return e === content ? out : [];
    }

    // Before drawing: pointer values, hover, beats. Reads the layout of the
    // frame already on screen, so it never forces an extra layout.
    function sense(now) {
      var has = prep.has, id;
      if (has.mic || has.music) soundRead(now);
      if (has.beat) {
        for (var i = 0; i < prep.ids.length; i++) {
          var d = prep.parts[prep.ids[i]];
          if (d.turn !== "beat") continue;
          id = prep.ids[i];
          var b = soundBeats(d.from || "mic");
          if (beatSeen[id] === undefined || b < beatSeen[id]) beatSeen[id] = b;
          else if (b > beatSeen[id]) { beatSeen[id] = b; playFrom[id] = now; sounding(id, d); }
        }
      }
      if (has.mouse && pointer.seen) {
        // 0 and 1 are the edges of the view as drawn (bars at the sides do not count).
        var r = svg.getBoundingClientRect(), v = viewOf(reel);
        var s = Math.min(r.width / v[2], r.height / v[3]);
        if (s > 0) {
          var w = v[2] * s, h = v[3] * s;
          pointer.vx = clamp01((pointer.x - r.left - (r.width - w) / 2) / w);
          pointer.vy = clamp01((pointer.y - r.top - (r.height - h) / 2) / h);
        }
      }
      if (has.hover) {
        var over = {};
        if (pointer.inside) {
          var list = copiesAt(document.elementFromPoint(pointer.x, pointer.y));
          for (var j = 0; j < list.length; j++) {
            var dd = prep.parts[list[j].id];
            if (dd && dd.turn === "hover") over[list[j].id + "|" + list[j].k] = true;
          }
        }
        for (var key in hoverFrom) if (!over[key]) delete hoverFrom[key];
        for (key in over) {
          if (hoverFrom[key] !== undefined) continue;
          hoverFrom[key] = now; // the pointer just came over this copy
          id = key.split("|")[0];
          sounding(id, prep.parts[id]);
        }
      }
    }

    // A part starts to play: its sound, if it has one. A part that beats on
    // "music" plays past the analysis, so it never hears its own sound.
    function sounding(id, d) {
      if (!token.started) return; // a player makes sound only after a click or key in it
      var what = partSound(d);
      if (what) fxPlay(what, d.turn === "beat" && d.from === "music", id);
    }

    // Draw a Reel with parts: the whole frame when the top frame or the copies
    // changed, otherwise only the copies whose frame changed.
    function drawParts(idx, now) {
      sense(now);
      var next = compose(prep, idx, function (id, k, d) { return pick(id, k, d, now); });
      var prev = shownParts;
      shownParts = next;
      if (shown.id !== reelId || shown.idx !== idx || !sameShape(prev, next)) {
        content.innerHTML = next.pieces.join("");
        copyEls = null;
        return;
      }
      var replaced = [], stale = false;
      for (var i = 0; i < next.copies.length; i++) {
        var c = next.copies[i];
        replaced[i] = c.parent >= 0 && replaced[c.parent]; // already redrawn with its outer copy
        if (replaced[i] || c.idx === prev.copies[i].idx) continue;
        if (!copyEls) copyEls = content.querySelectorAll("[data-asobi-part]");
        copyEls[i].innerHTML = next.pieces.slice(c.from + 1, c.to - 1).join("");
        replaced[i] = true;
        if (i + 1 < next.copies.length && next.copies[i + 1].parent === i) stale = true; // it had copies inside
      }
      if (stale) copyEls = null;
    }

    // ---- the quiet hint: "click to listen" / "click for sound" ---------
    function showHint(now) {
      var want = "";
      if (hint.flashUntil > now) want = hint.flash; // "muted" for a moment
      else if (wants.mic && sound.state === "off") want = T.listen;
      else if (wants.mic && sound.state === "refused" && !hint.toldNoMic) {
        hint.toldNoMic = true; // say it once, then never again
        hint.noMicUntil = now + 6000;
        want = T.noMic;
      } else if (hint.noMicUntil > now) want = T.noMic; // still showing the note
      else if (wants.own && !(token.started && soundRunning())) want = T.sound;
      if (want === hint.shown) return;
      hint.shown = want;
      listenHint.textContent = want;
      listenHint.classList.toggle("asobi-on", want !== "");
    }

    // ---- render loop: touch the DOM only when what is shown changed ---
    function tick(now) {
      if (destroyed) return;
      if (reel) {
        var idx = frameIndex(now);
        if (prep) {
          if (shown.id !== reelId) applyReel();
          drawParts(idx, now);
          shown.id = reelId; shown.idx = idx;
        } else if (shown.id !== reelId || shown.idx !== idx) {
          if (shown.id !== reelId) applyReel();
          content.innerHTML = reel.frames[idx];
          shown.id = reelId; shown.idx = idx;
        }
      }
      showHint(now); // touches the DOM only when the hint changes
      raf = requestAnimationFrame(tick);
    }
    raf = requestAnimationFrame(tick);

    // ---- update ------------------------------------------------------
    function setPending(on) {
      pending = on;
      waitDot.classList.toggle("asobi-on", on);
    }

    // Keep part state only for parts the new Reel still has.
    function keepState(map) {
      for (var key in map) if (!prep || !prep.parts[key.split("|")[0]]) delete map[key];
    }

    function update(next) {
      if (destroyed || !next) return;
      if (typeof next.error === "string" && next.error !== "") {
        errorBox.textContent = next.error;
        errorBox.classList.add("asobi-on");
        if (typeof next.code === "string") setCode(next.code);
        setPending(false); // no motion is coming after an error
        return; // keep the last good picture
      }
      errorBox.classList.remove("asobi-on");
      if (!validReel(next)) return;
      reel = next; reelId++; setPending(next.pending === true);
      prep = prepare(next);
      shownParts = null; copyEls = null;
      keepState(playFrom); keepState(hoverFrom); keepState(beatSeen);
      var song = songOf(next);
      wants.mic = !!(prep && prep.has.mic);
      wants.own = !!(song || (prep && prep.has.sound));
      soundWant(token, wants.mic, wants.own);
      songWant(token, song); // the same id goes on; another id switches; none stops it
      // Pointer reactions take touch drags for themselves (no page scrolling).
      root.style.touchAction = prep && (prep.has.hover || prep.has.mouse) ? "none" : "";
      if (!controlsOn()) controls.classList.remove("asobi-on");
    }

    // ---- controls visibility ----------------------------------------
    function controlsOn() { return useControls && !(reel && reel.controls === false); }

    function wake() {
      if (!controlsOn()) return;
      controls.classList.add("asobi-on");
      clearTimeout(hideTimer);
      hideTimer = setTimeout(function () {
        if (!controls.matches(":hover")) controls.classList.remove("asobi-on");
        else wake();
      }, HIDE_AFTER_MS);
    }
    root.addEventListener("mousemove", wake);
    root.addEventListener("touchstart", wake, { passive: true });

    // ---- pointer: position, clicks on parts, starting the sound ------
    function onPointerMove(e) {
      pointer.x = e.clientX; pointer.y = e.clientY;
      pointer.inside = true; pointer.seen = true;
    }
    function onPointerDown(e) {
      onPointerMove(e);
      token.started = true;
      if (wants.mic || wants.own) soundStart(wants.mic, wants.own);
      if (!prep || !prep.has.click) return;
      // `click` is unreliable while the picture is replaced many times a second.
      var list = copiesAt(e.target), now = performance.now();
      for (var i = 0; i < list.length; i++) {
        var d = prep.parts[list[i].id];
        if (!d || d.turn !== "click") continue;
        playFrom[list[i].id + "|" + list[i].k] = now; // a new click restarts it
        sounding(list[i].id, d);
      }
    }
    function onPointerLeave() { pointer.inside = false; }
    function onPointerUp(e) { if (e.pointerType === "touch") pointer.inside = false; } // a finger lifted hovers nothing
    root.addEventListener("pointermove", onPointerMove);
    root.addEventListener("pointerdown", onPointerDown);
    root.addEventListener("pointerleave", onPointerLeave);
    root.addEventListener("pointerup", onPointerUp);
    root.addEventListener("pointercancel", onPointerUp);

    // ---- code overlay ------------------------------------------------
    function toggleCode() { codeBox.classList.toggle("asobi-on"); }
    codeBtn.addEventListener("click", toggleCode);

    // ---- full screen ---------------------------------------------------
    function toggleFullscreen() {
      var d = document;
      if (d.fullscreenElement || d.webkitFullscreenElement) {
        var exit = d.exitFullscreen || d.webkitExitFullscreen;
        if (exit) exit.call(d);
        return;
      }
      var go = root.requestFullscreen || root.webkitRequestFullscreen;
      if (!go) return;
      var p = go.call(root);
      if (p && p.catch) p.catch(function () { /* refused: stay as is */ });
    }

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
      // A Reel that makes sound records it too: [out], before the mute (never the microphone).
      var g = wants.own ? sound.graph : null;
      var mime = pickMime(!!g);
      if (!mime || !reel) { say(T.noRecorder); return; }
      if (pending) { say(T.waitToRecord); return; } // a one-frame first look is not worth a video
      var v = viewOf(reel), scale = MAX_SIDE / Math.max(v[2], v[3]);
      var w = Math.max(2, Math.round(v[2] * scale / 2) * 2), h = Math.max(2, Math.round(v[3] * scale / 2) * 2);
      var canvas = document.createElement("canvas");
      canvas.width = w; canvas.height = h;
      var ctx = canvas.getContext("2d");
      var fps = Number(reel.fps) >= 10 ? Math.min(Number(reel.fps), 60) : 30;
      if (prep) fps = 30; // reacting parts change whenever they like, not at the Reel's fps
      var stream = canvas.captureStream(fps), heard = null;
      if (g) {
        heard = g.ctx.createMediaStreamDestination();
        g.out.connect(heard);
        heard.stream.getAudioTracks().forEach(function (t) { stream.addTrack(t); });
      }
      var recorder;
      try { recorder = new MediaRecorder(stream, { mimeType: mime }); }
      catch (e) { if (heard) g.out.disconnect(heard); say(T.noRecorder); return; }
      var state = { recorder: recorder, chunks: [], mime: mime, timer: 0, busy: false, from: g && g.out, heard: heard };
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
      if (rec.heard) { try { rec.from.disconnect(rec.heard); } catch (e) { /* the context is gone */ } }
      rec = null;
      recDot.classList.remove("asobi-on");
      recBtn.textContent = "● " + T.record;
    }

    function toggleRecording() { rec ? stopRecording() : startRecording(); }
    recBtn.addEventListener("click", toggleRecording);

    // ---- keys --------------------------------------------------------
    // Reaction keys always work; c, r and f only when the player's keys are on.
    // A part that asks for one of those letters by name takes it over.
    function sameKey(want, got) {
      want = String(want).toLowerCase();
      if (want === "space") want = " ";
      return want === String(got).toLowerCase();
    }

    function reactToKey(e) {
      if (!prep || !prep.has.key) return false;
      var taken = false, now = performance.now();
      for (var i = 0; i < prep.ids.length; i++) {
        var d = prep.parts[prep.ids[i]];
        if (d.turn !== "key") continue;
        var named = d.key !== undefined && d.key !== null && d.key !== "";
        if (named && !sameKey(d.key, e.key)) continue;
        if (named) taken = true;
        if (e.repeat) continue; // a key held down plays once
        playFrom[prep.ids[i]] = now;
        sounding(prep.ids[i], d);
      }
      return taken;
    }

    // Mute is for the whole page (one sound graph): one key press toggles it
    // once, however many players hear the key; each says so.
    function toggleMute(e) {
      if (sound.muteEvent !== e) { sound.muteEvent = e; setMuted(!sound.muted); }
      hint.flash = sound.muted ? T.muted : T.unmuted;
      hint.flashUntil = performance.now() + 1500;
    }

    function onKey(e) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      var t = e.target && e.target.tagName;
      if (t === "INPUT" || t === "TEXTAREA" || t === "SELECT" || (e.target && e.target.isContentEditable)) return;
      // A key is this player's when its keys are on (the only player on the
      // page) or the pointer is over it; only then does it start the sound.
      if (useKeys || pointer.inside) {
        token.started = true;
        if (wants.mic || wants.own) soundStart(wants.mic, wants.own);
      }
      if (reactToKey(e) || !useKeys) return;
      if (e.key === "c" || e.key === "C") toggleCode();
      else if (e.key === "r" || e.key === "R") toggleRecording();
      else if (e.key === "f" || e.key === "F") toggleFullscreen();
      else if (e.key === "m" || e.key === "M") toggleMute(e);
    }
    document.addEventListener("keydown", onKey);

    return {
      update: update,
      destroy: function () {
        if (destroyed) return;
        stopRecording();
        destroyed = true;
        cancelAnimationFrame(raf);
        clearTimeout(hideTimer); clearTimeout(noteTimer);
        document.removeEventListener("keydown", onKey);
        root.removeEventListener("mousemove", wake);
        root.removeEventListener("touchstart", wake);
        root.removeEventListener("pointermove", onPointerMove);
        root.removeEventListener("pointerdown", onPointerDown);
        root.removeEventListener("pointerleave", onPointerLeave);
        root.removeEventListener("pointerup", onPointerUp);
        root.removeEventListener("pointercancel", onPointerUp);
        songWant(token, null);          // a song only this player wanted stops
        soundWant(token, false, false); // the microphone and the audio context close later if no one else wants them
        root.remove();
      }
    };
  }

  // ---- test hook (see the header) ----------------------------------------
  function soundSnapshot() {
    var out = { state: sound.state, players: sound.wanting.length, making: sound.making.length,
                running: soundRunning(), muted: sound.muted, context: sound.ctx ? sound.ctx.state : null,
                voices: sound.voices.filter(function (v) { return sound.ctx && v.end >= sound.ctx.currentTime; }).length,
                song: null, played: sound.played.slice() };
    for (var id in sound.songs) {
      var e = sound.songs[id];
      out.song = { id: e.id, playing: !!(e.el && !e.el.paused && sound.ctx && sound.ctx.state === "running"),
                   time: e.el ? e.el.currentTime : 0, volume: e.volume };
      if (e.failed) out.song.failed = true;
    }
    ["mic", "music"].forEach(function (from) {
      out[from] = { volume: soundValue(from, "volume"), low: soundValue(from, "low"), mid: soundValue(from, "mid"),
                    high: soundValue(from, "high"), pitch: soundValue(from, "pitch"), beats: soundBeats(from) };
    });
    return out;
  }

  function feed(from, values) {
    if (!(from in sound.fed)) return;
    if (values && values.beat) sound.fedBeats[from]++;
    sound.fed[from] = values || null;
  }

  global.AsobiPlayer = {
    mount: mount,
    _internals: { parseFrame: parseFrame, prepare: prepare, compose: compose, sameShape: sameShape,
                  valueIndex: valueIndex, onceIndex: onceIndex, makeLevel: makeLevel, makePitch: makePitch,
                  makeBeat: makeBeat, makeListener: makeListener, sound: soundSnapshot, feed: feed,
                  connect: connectSource, partSound: partSound, songOf: songOf, synth: synth,
                  fxBus: fxBus }
  };
})(typeof window !== "undefined" ? window : this);
