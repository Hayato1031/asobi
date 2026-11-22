# Player manual test

Open `test/web/fixture.html` directly in a browser (`file://` works; no server needed).

It mounts `lib/asobi/web/player.js` full-window and plays a hand-written 60-frame, 30 fps Reel
(a rotating ring of circles). Three buttons at the bottom left drive the checks.

What to look for:

- Idle: only the picture, centred, filling the window. No controls visible.
- Move the mouse: "record" and "code" appear top-right and fade after about 2.5 s. The picture does not move.
- Press `c` (or click "code"): a semi-transparent code overlay appears; press again to hide it.
- "swap reel": the ring changes (6 -> 3 circles) but the rotation continues from the same moment (no jump back to frame 0).
- "send error": a red panel appears at the bottom; the previous picture keeps animating behind it.
  Line breaks in the message are preserved.
- "clear error": the panel disappears.
- "send preview": the ring stops on its first frame (a motion's quick preview, `"pending": true`).
  After about half a second a small grey dot fades in and breathes at the top left. Three seconds
  later the whole reel arrives: the ring turns again and the dot is gone. While the dot shows,
  pressing `r` does not record; a note says to try again in a moment.
  "send error" while the dot shows also removes it.
- Press `r` (or click "record"): a red dot shows top-left. Press `r` again: `asobi.mp4` or `asobi.webm` downloads.
  Check that it plays and shows the animation on the background colour.

- "reactions" (or `?react=1`): a Reel with every kind of reacting part. Check each one:
  - Click (or tap) one red dot: only that dot swells once, then rests. Click it again while it
    plays: it starts over. The dot in the middle of the square is a copy too (a part inside a part).
  - Hover the blue square: it turns while the pointer is on it and stops (back to its first
    picture) when the pointer leaves. Hovering the middle dot keeps the square turning.
  - Press `a`: the small gold bar top left flashes once. Holding `a` does not repeat it. Other
    keys do nothing (`c`, `r` and `f` still work as shortcuts).
  - Move the pointer: the green marker on the top edge follows left..right, the one on the right
    edge follows top..bottom. Make the window much wider than tall: the markers reach their ends
    at the edges of the picture, not of the window.
  - A small "click to listen" hint shows at the bottom. Click the picture and allow the
    microphone: the hint goes away; the four bars (vol, low, high, pitch) follow the sound and the
    big pink ring flashes on each beat (play music with a clear kick). Silence: every bar goes
    fully down. Refuse the microphone instead (or block it in the site settings and reload): a
    short note says so once, then the bars stay down.
  - Without a microphone: tick "pretend sound" in the panel top left and move the sliders; "beat"
    sends one beat. The line at the end of the panel shows what the player hears now.
  - Press `f`: the player goes full screen; `f` or Esc leaves.
  - `?react=1&controls=0` (a Reel with `"controls": false`): moving the mouse shows no buttons.
  - Press `r`, play with the dots and the square, press `r` again: the video shows the reactions.
  - "swap reel" while listening: the microphone stays on, the clock goes on.

- "sound" (or `?sound=1`): asobi's own sound. A song (a 120 BPM loop made in the page, as a data URI)
  and parts that sound. Use speakers or headphones:
  - "click for sound" shows at the bottom. Click anywhere: the loop starts and the hint goes away.
  - Each of the 8 dots in the ring makes one of the six sounds when clicked (pop, kick, snare, hat,
    clap, bell, then pop and bell again); the 8 small squares in the middle play c4 d4 e4 f4 g4 a4 b4 c5.
    One click is one sound.
  - The big ring flashes on each kick of the song with a soft hat. It must not trigger itself: the
    hats follow the song's kicks and stop when the song stops ("sound, no song").
  - `s` plays a kick and flashes the gold bar. The two bars (vol, low) follow the song.
  - `m`: "muted" shows; the speakers go silent while the bars and the ring go on. `m` again: "sound on".
  - `r` while the loop plays (muted or not): the video has the sound.
  - "swap reel" (or "reactions") stops the song; "sound" again starts it from its start.

Query strings for forcing states (used for headless screenshots):
`?code=1`, `?error=1`, `?swap=1`, `?dark=1`, `?notools=1`, `?pending=1` (sends a preview and keeps it),
`?react=1` (the reactions reel), `&controls=0` (that reel with `"controls": false`), `?sound=1` (the sound reel).

# Player checks without a browser

`player-check.js` loads `lib/asobi/web/player.js` in plain Node and checks the parts that need no
page (through `AsobiPlayer._internals`, a test hook): markers replaced by numbered copies (also
nested, out-of-range frames, a cycle), value -> frame, a one-time play, the beat detector on made-up
onset series (120 BPM kicks give 20 beats in 10 s, hats and wobbles give none, never closer than
0.2 s), and the sound levels (silence and a quiet room are exactly 0, fast attack and slower
release, pitch of a sweep rises from near 0 to near 1).

    node test/web/player-check.js lib/asobi/web/player.js

It also checks the plain parts of asobi's own sound: which parts sound (the six names and notes;
never a value part, never an unknown name) and which song a Reel plays (volume absent means 1).

Headless example:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
      --window-size=800,600 --virtual-time-budget=3000 --screenshot=out.png \
      "file://$PWD/test/web/fixture.html?error=1&notools=1"

# Sound checks in headless Chrome

`sound-check.mjs` runs the player in headless Chrome (Node 24, no packages; Chrome at the usual macOS
place or `CHROME=/path`). It serves a page, the player and test songs (made in the script; the song
URL answers `Range` like the live server), and sends real clicks and key presses over the DevTools
protocol, so the browser's "sound only after a click" rule is the real one. `rake test` does not
run it (it needs Chrome and takes about a minute).

    node test/web/sound-check.mjs lib/asobi/web/player.js
    node test/web/sound-check.mjs lib/asobi/web/player.js --slow   # +70 s: the context is kept, then closed

It prints the measurements as JSON, then one `ok` / `FAIL` line per expectation, and exits 1 on a
failure. What it checks: a Reel without sound makes no audio context and records video only, with
the same file type as before; a song (data URI and URL) waits for a click ("click for sound"),
loops, and the "music" analysis beats twice a second on a 120 BPM loop; update() with the same song
id goes on (also after a preview and through an error Reel), another id switches, no song stops it,
two players share one song; one sound per click on one of 12 copies, per key press on 12 copies
(none on auto-repeat), per hover entry (not per loop), per beat, one each for nested click parts;
20 at once start but at most 16 sound; `on_beat(:music).sounding(:kick)` does not trigger itself;
each of the six sounds and a note rendered offline (peak, length, frequencies; a4 at 440 Hz),
16 at once under full scale; mute silences the speakers (measured after the mute gain) while the
analysis goes on, and says so; a part asking for `m` takes the key; a recording has the sound (also
while muted); refusing the microphone keeps asobi's sound; no errors in the console.
Temporary files (the Chrome profile) go in `TMPDIR` and are removed at the end.

# Playground checks without a browser

`rake test` runs small Node scripts here (they are skipped when `node` is not installed):

- `worker-check.js` runs `ruby-worker.js` with a pretend Ruby engine: a motion's whole Reel is made
  in slices with `{ id, working: true }` between them; a newer request stops the build (`skipped`);
  a failing engine answers `{ id, fatal }`.
- `playground-check.js` runs `playground.js` on a pretend page with a pretend worker: after Ruby
  breaks (`{ id, fatal }` or a worker `error` event) the page starts a fresh worker, shows a short
  message, does not run the crashed code again by itself, runs the newest waiting edit, and stops
  (no loop) when the fresh worker cannot start. A worker answer whose frame is not asobi's own SVG
  reaches the player as an error Reel with the `blocked` text, never as frames; odd worker messages
  are ignored; on http/https a worker that cannot start never leads to Ruby on the page (only on
  `file://`).
- `safe-reel-check.js` checks `site/assets/safe-reel.js`, the playground's checker for what an
  engine sends (a link can carry any Ruby, and that Ruby can change how asobi writes SVG). Every
  Reel in the built site's `reels/` must pass with the same frames and parts; a list of attacks
  (event handlers, `<script>`, `<foreignObject>`, `href`, `url(https://…)`, CSS escapes, entities,
  comments, odd spacing and quotes) must not pass `markup`; `reel` rejects non-objects, missing
  frames, a part named `__proto__`, a `url(…)` background and a bad view, drops a song from
  elsewhere (keeping the picture), and keeps only `error` and `code` of an error Reel.

      node test/web/safe-reel-check.js _site/assets/safe-reel.js _site/reels

- `ruby-string-check.js` checks how `ruby-engine.js` hands a sketch to Ruby without the js gem
  (which needs `'unsafe-eval'`): `rubyString(text)` is `["<hex>"].pack("H*").force_encoding("UTF-8")`
  with hex digits only between the quotes, for ASCII, Japanese, emoji, quotes, backslashes, `#{}`,
  newlines and an empty string; `test/site_test.rb` also evals each one in Ruby and compares.

      node test/web/ruby-string-check.js _site/assets/ruby-engine.js

# Playground crash, by hand (real ruby.wasm)

These steps use `JS.eval` from a sketch (ruby.wasm's js gem, which runs `Function(code)`). The
deployed site's Content-Security-Policy (`_headers`, no `'unsafe-eval'`) stops that, so the sketch
only gets an `EvalError`: do this on a plain local server that sends no headers, for example
`rake site`, then `ruby -run -e httpd _site -p 8000` (or `python3 -m http.server -d _site`).
The engine no longer loads the js gem itself, so the sketch asks for it (`require "js"`).

Open `http://localhost:8000/playground.html` and paste this sketch. It leaves Ruby broken the way a
crash inside ruby.wasm did (the sketch lock stays held, so every later run would fail with
`ThreadError: deadlock; recursive locking`) and makes the worker report a fatal failure:

```ruby
require "js"
m = Mutex.new
m.lock
Asobi::Sketch.instance_variable_set(:@mutex, m)
JS.eval(%q{ var post = self.postMessage; self.postMessage = function (m) { post.call(self, m);
  if (m.pending) { self.postMessage = post; post.call(self, { id: m.id, fatal: "RuntimeError: unreachable (simulated)" }); } }; })
show circle(radius: 3).spin
```

What to look for: the picture area says Ruby stopped and was started again; the status line shows
"Loading Ruby…" then "Ruby is ready". Change the code to `show circle(radius: 5).spin`: it runs.
For a worker `error` event instead, replace the `JS.eval` line with
`JS.eval(%q{ setTimeout(function () { throw new Error("simulated"); }, 0); })`.
