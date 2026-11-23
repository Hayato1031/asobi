# Changelog

## 0.2.2

Smoother hit/flash animations, an opt-in way to repaint a whole group, a safer live view that follows local files, and downloads right from the playground.

- `fade` now accepts `from:` (e.g. `fade(from: 0, to: 1)`), replacing any opacity on the picture so a picture starting at `opacity(0)` can fade in (ideal with `by(:mic)` / `by(:music)`). Without `from:`, `fade` behaves exactly as before.
- New motion word `flash(every: 0.5, from: 0, to: 1)`: stays at `from` (invisible by default) at rest, jumps bright to `to` when triggered, and decays smoothly back to `from`—built for `on_beat`, `when_clicked`, and `when_pressed`. Following a value with `by(...)` would make it brightest at the faintest sound, so `by` on a motion with a flash in it raises an error that suggests `fade(from: 0, to: 1).by(:mic)` instead.
- `colored` and `shift_color` accept `all: true` to repaint everything inside a group: inner fill colours give way, line-only shapes (`line`, `arc`, `wave`, anything `outlined`) get their lines recoloured, and reacting parts are painted too. Without `all:`, colouring a group works exactly as in 0.2.1: a colour given to a group does not overwrite colours given to the pictures inside it. `dot.colored(:red).repeat(5).in_row.shift_color(:red, :gold, all: true)` shifts every dot.
- Live view (`asobi` / `lib/asobi/live.rb`):
  - Replaced `Thread#kill` during background animation builds with cooperative cancellation using `Sketch.finish_some` (`Reel.steps`).
  - Added the playground's time limits, so an endless loop shows an error instead of locking up the live view: 15 seconds to run a sketch up to its preview, and 60 seconds for any one slice of the whole-Reel build. A slow build that keeps making progress is never cut off.
  - Automatically watches and reloads local `.rb` files loaded via `require_relative` under the sketch's folder (never Ruby's own or gems' files, even when they live under that folder). Top-level classes and constants those files made are cleared before each reload, so helpers like `class Planet < Struct.new(:size)` reload cleanly.
- Playground: added a Save button that downloads still pictures as `asobi.svg` and moving, reacting, or song-playing sketches as standalone `asobi.html` (embedding `player.js` and the site's song as a data URI), built strictly from the `AsobiSafeReel`-verified Reel without relaxing the CSP.
- Docs: fixed `Hash#to_art` description in both READMEs (key-value tables, not palette swatches) and removed outdated `(silent for now)` comments in `lib/asobi/reaction.rb`.

## 0.2.1

A security fix for the live view, and clearer pages for people finding asobi.

- Security: the live view now answers only when it is asked for as `127.0.0.1` or `localhost`, so another web site cannot read the sketch through a made-up host name.
- Publishing asobi to RubyGems now requires multi-factor authentication.
- Both READMEs have a "Why asobi" section (one picture in asobi and in p5.js, side by side) and an FAQ, mention the Ruby Weekly feature, and link to the website without `.html`.
- The summary and description on RubyGems say creative coding, generative art and zero dependencies.

## 0.2.0

asobi now reacts and makes sound: a click, the pointer, a key, the microphone or a song can turn a motion, for live coding and VJ sets. Animations also build much faster.

- Reactions: a word after a motion says who turns its frames instead of the clock. `flower.pulse.when_clicked`, `flower.spin.while_hovered`, `flower.spin.when_pressed("a")`, `flower.pulse.on_beat` (the microphone), and `by` to pick the frame from a value: `flower.spin.by(:mouse_x)`, `by(:mouse_y)`, `flower.pulse.by(:mic)`, `by(:mic, :low)` (also `:mid`, `:high`, `:pitch`), and `by(:music)` for the sound asobi itself plays. The answer is a picture, so every word still works on it: `dot.pulse.when_clicked.repeat(12).in_ring` gives twelve dots that each react on their own, and `flower.pulse.by(:mic, :low).spin(every: 8)` spins by the clock while it swells with the bass. Frames are drawn ahead, so this also works in a saved `.html` page. Motions that go out and come back (pulse, sway, fade, bounce, drift, shift_color) follow a value on their way out only, so louder means bigger. Saved `.svg` files show the picture at rest.
- The player listens to the microphone after the first click or key press ("click to listen"), with automatic sensitivity, fast attack and slower release; silence is exactly 0, and beats come from sudden rises of the low frequencies. One microphone is shared by every player on the page.
- `show flower, controls: false` (also `save("flower.html", controls: false)`) never shows the record and code buttons, and `f` toggles full screen, for projecting and VJ use.
- asobi makes sound. `play "song.mp3"` plays a song in a loop while the sketch shows (`volume: 0.5` to turn it down), and `sounding` after a reaction plays a sound each time the reaction starts: `dot.pulse.when_clicked.sounding(:pop)`. Six named sounds (`:pop`, `:kick`, `:snare`, `:hat`, `:clap`, `:bell`) and notes (`:c4`, `:cs4`, `"Bb3"`) are made in the browser, with no files. `by(:music)` and `on_beat(:music)` follow what asobi plays, so `play "song.mp3"` with `star.pulse.by(:music, :low)` is a VJ sketch that needs no microphone.
- For live coding: editing the code does not restart the song, and a mistake in the code does not stop it. Removing the `play` line does.
- A saved `.html` page carries its song inside (up to 20 MB). Recordings include asobi's sound, as mp4 where the browser can. `m` mutes the speakers.
- On a page with many pictures, a picture makes sound only after you click that picture, so one example never starts another example's song.
- New examples in `examples/reactions/`: click and hover, the pointer, a microphone VJ sketch, an instrument you click and type on, and a VJ sketch that plays its own loop (`beat.wav`). The gallery gains `chimes.rb`, a ring of notes to click.
- Website: the reference has a new group, "React and sound" (`when_clicked`, `while_hovered`, `when_pressed`, `on_beat`, `by`, `sounding`, `play`), the guide has a new chapter, "Make it react", and pictures that react can be clicked right on the pages. The site and the playground ship one song, so `play "beat.wav"` works there; any other file name in the playground explains that your own songs play when asobi runs on your computer.
- Both READMEs describe reactions and sound.
- The gem's summary and description on RubyGems, the home page FAQ, and the files for AI readers (`llms.txt`, the agent skill) now describe reactions and sound.
- The gem no longer carries the README's pictures, so it stays small to install (about 130 KB instead of 2 MB).
- Animations build much faster. While one reel or SVG document is built, asobi reuses the boxes and SVG it has already worked out for the same picture, and a `trail` reuses earlier frames instead of drawing them again. The showcase fireworks (`hanabi.rb`) build in about an eighth of the time. The output is byte-for-byte the same as before, except for the next point.
- `trail` without `gap:` now leaves its copies 1/15 of a second apart (two frames at 30 fps; it was 0.05), so the trail is slightly longer and every copy is a frame that is drawn anyway. A `gap:` you write is used exactly as written.
- A moving sketch shows its first picture right away, in the live view and in the browser playground, while the rest of the motion is still being made. A small grey dot in the corner says the motion is on its way. Saving again (or typing again in the playground) before it is ready skips the out-of-date work, so the newest code always wins.
- Playground: a motion is now made in slices of about 80 ms, so a newer edit no longer waits for an older build: the old build is dropped and the new sketch shows its first picture at once. The output is byte-for-byte the same. `Asobi::Reel.steps(thing)` builds what `Reel.of` builds, a little at a time (`step(seconds)`, `done?`), and `Asobi::Sketch.finish_some(seconds)` is `Sketch.finish` in slices.
- Playground: if Ruby itself crashes inside ruby.wasm, the playground starts a fresh Ruby and keeps working without a page reload, and says what happened (English and Japanese). The sketch that crashed runs again only after it is edited.
- Fixed: a picture clipped by a window that shows nothing (`Asobi.nothing`, `[]`, `text("")`, or a window clipped away itself) was drawn unclipped, without the effects after the clip. It now draws nothing, as its bounds already said.
- The orbits showcase glows each planet once, after its trail, instead of glowing every trail copy. It plays at 60 fps instead of about 15 and builds twice as fast, with the same look. The README GIFs for hanabi and orbits are regenerated.
- Inside, what a picture is and how it is drawn are now separate. Pictures no longer write SVG themselves: the new `Asobi::Drawing` turns a picture into drawing instructions with every asobi rule already applied (gradient end points, the box each effect covers, blend always outermost), and `Asobi::SVG` is one renderer that follows them. `Asobi::Drawing.of(picture)` gives the same instructions as plain data for `JSON.generate`, ready for other renderers such as a future Canvas player. SVG output is byte-for-byte the same.
- The Reel can now carry `"parts"` (each reacting part's own frames, and who turns them) and `"controls": false`. A sketch without reactions gives exactly the same Reel as before.
- The Reel can carry `"song"`, and a part can carry `"sound"` or `"note"`. The live view serves the song at `/song/ID`. A sketch without sound gives exactly the same Reel as before.

## 0.1.1

- RubyGems links to the [official website](https://asobi.myura.me/), the [method reference](https://asobi.myura.me/reference), and the changelog for this version.
- The English and Japanese READMEs now start with `gem install asobi` and link to the browser playground and the short film [Your Objects](https://asobi.myura.me/#film).

## 0.1.0

- Initial release. Create pictures and looping animations with Ruby objects, preview sketches live with `asobi`, and export them as SVG or standalone HTML.
