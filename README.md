<div align="center">

<img src="docs/readme/header.png" alt="asobi" width="100%">

**English** · [日本語](README.ja.md)

# Object to Art. Art to Object.

**asobi (Japanese for “play”) is a zero-dependency creative coding gem for making geometric pictures and looping animations in Ruby.**<br>
Turn Ruby values and your own classes into pictures with `to_art` — **Object to Art**. Keep, compose, and animate every picture as an immutable Ruby object — **Art to Object**.

[![Gem Version](https://img.shields.io/gem/v/asobi?color=ff4d6d&label=gem)](https://rubygems.org/gems/asobi)
[![Downloads](https://img.shields.io/gem/dt/asobi?color=f6c177&label=downloads)](https://rubygems.org/gems/asobi)
[![Ruby 3.2 or newer](https://img.shields.io/badge/Ruby-%E2%89%A5%203.2-cc342d?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![MIT License](https://img.shields.io/badge/license-MIT-8b9cf7)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-3fb950)](#issues-and-pull-requests)
[![Featured in Ruby Weekly #827](https://img.shields.io/badge/featured%20in-Ruby%20Weekly%20%23827-e0475b)](https://rubyweekly.com/issues/827)

<a href="https://asobi.myura.me/playground"><img src="https://img.shields.io/badge/%E2%96%B6%20Try%20it%20in%20your%20browser-ff4d6d?style=for-the-badge" alt="Try it in your browser" height="36"></a>
<a href="https://asobi.myura.me/guide"><img src="https://img.shields.io/badge/Guide-20232e?style=for-the-badge" alt="Guide" height="36"></a>
<a href="https://asobi.myura.me/reference"><img src="https://img.shields.io/badge/Reference-20232e?style=for-the-badge" alt="Reference" height="36"></a>
<a href="https://asobi.myura.me/examples"><img src="https://img.shields.io/badge/Examples-20232e?style=for-the-badge" alt="Examples" height="36"></a>
<a href="https://asobi.myura.me/#film"><img src="https://img.shields.io/badge/32--second%20film-20232e?style=for-the-badge" alt="32-second film" height="36"></a>

<br>

<a href="examples/showcase/hanabi.rb"><img src="docs/readme/media/hanabi.gif" alt="Gold, pink, cyan, orange and violet fireworks open one after another in a dark night sky, then fade." width="100%"></a>

</div>

The fireworks above are drawn by the Ruby below, exactly as written. It makes one spark, fans copies of it into a burst, scatters six bursts across the sky, and opens them one by one.

```rb
require "asobi"

spark = petal(15, 1.8).move(up: 28)
burst = spark.repeat(26).in_fan + spark.repeat(13).in_fan.scale(0.5)
colors = %i[gold deeppink cyan orange violet]
sky = burst.repeat(6).change_each { |b, t, i| b.scale(0.75 + i % 3 * 0.3) }
           .scattered(over: [290, 130], seed: 5).colored(*colors)
bloom = sky.animate(3) { |b, t| b.scale(0.05 + t**0.35).opacity(1 - t**4) }

show bloom.one_by_one.trail(4).glowing(3), on: "#070812", paper: [360, 200]
```

## Made with asobi

Every piece below is one Ruby file that runs as it is. Select a picture to read its code.

<table>
<tr>
<td align="center" width="50%"><a href="examples/showcase/tunnel.rb"><img src="docs/readme/media/tunnel.gif" alt="Thin cyan, magenta and gold hexagons rush out of a dark centre, twisting, while a light sweeps round a fan of violet rays." width="100%"></a></td>
<td align="center" width="50%"><a href="examples/showcase/lace.rb"><img src="docs/readme/media/lace.gif" alt="Hundreds of hairline ellipses in cyan, violet and pink fold into ribbons that wave around the centre." width="100%"></a></td>
</tr>
<tr>
<td align="center"><b><a href="examples/showcase/tunnel.rb">Neon tunnel</a></b><br>24 hexagons fly out <code>one_by_one</code> · 7 lines</td>
<td align="center"><b><a href="examples/showcase/lace.rb">Lace</a></b><br>132 hairline ellipses folding in waves · 6 lines</td>
</tr>
<tr>
<td align="center" width="50%"><a href="examples/showcase/spectrum.rb"><img src="docs/readme/media/spectrum.gif" alt="A ring of 240 thin bars, cyan to violet to pink, leaps like a music visualiser, with a faint echo of itself around it." width="100%"></a></td>
<td align="center" width="50%"><a href="examples/showcase/galaxy.rb"><img src="docs/readme/media/galaxy.gif" alt="Eleven hundred gold-to-violet seeds on a sunflower spiral wind into turning galaxy arms over twinkling white stars." width="100%"></a></td>
</tr>
<tr>
<td align="center"><b><a href="examples/showcase/spectrum.rb">Spectrum without a song</a></b><br>240 bars <code>in_fan</code>, each on its own beat · 10 lines</td>
<td align="center"><b><a href="examples/showcase/galaxy.rb">Galaxy</a></b><br>1,100 seeds <code>in_spiral</code>, winding into arms · 10 lines</td>
</tr>
<tr>
<td align="center" width="50%"><a href="examples/showcase/poster.rb"><img src="docs/readme/media/poster.gif" alt="Eight rings of cyan and pink letters reading RUBY IS PLAY, ASOBI and あそび surround a glowing あそび; waves of light run round them." width="100%"></a></td>
<td align="center" width="50%"><a href="examples/showcase/led_wall.rb"><img src="docs/readme/media/led_wall.gif" alt="A wall of 2,040 small round lights, pink to gold, turns a three-armed spiral of light." width="100%"></a></td>
</tr>
<tr>
<td align="center"><b><a href="examples/showcase/poster.rb">Type poster</a></b><br>840 letters on eight rings, lit by waves · 14 lines</td>
<td align="center"><b><a href="examples/showcase/led_wall.rb">LED wall</a></b><br>2,040 lights, each a moment behind the next · 8 lines</td>
</tr>
<tr>
<td align="center" colspan="2"><a href="examples/reactions/self_portrait.rb"><img src="docs/readme/media/self_portrait.gif" alt="On the left, the Ruby source of the sketch. On the right, that same source set in glowing rings of letters around a pink heart, with bands of light sweeping round to the music." width="100%"></a></td>
</tr>
<tr>
<td align="center" colspan="2"><b><a href="examples/reactions/self_portrait.rb">Self-portrait</a></b><br>reads its own code and draws every line as a ring of letters that follows the music · 18 lines</td>
</tr>
</table>

## Contents

- [Made with asobi](#made-with-asobi)
- [How asobi thinks](#how-asobi-thinks)
- [Run your first sketch](#run-your-first-sketch)
- [Why asobi](#why-asobi)
- [Key features](#key-features)
- [Sketch gallery](#sketch-gallery)
- [Every word at a glance](#every-word-at-a-glance)
- [Export and record](#export-and-record)
- [Use asobi from an existing Ruby program](#use-asobi-from-an-existing-ruby-program)
- [FAQ](#faq) · [Documentation](#documentation) · [Development](#development) · [Issues and pull requests](#issues-and-pull-requests)

## How asobi thinks

<table>
<tr>
<td width="50%" valign="top"><b>Object to Art</b><br>Numbers become discs, strings become type, arrays and ranges become visual rows, and your own classes gain visual form through <code>to_art</code>. Once converted, they behave like any other picture.</td>
<td width="50%" valign="top"><b>Art to Object</b><br>Every picture is an immutable Ruby object. Hold it in a variable, pass it to a method, or reuse it across a composition — <code>flower.scale(0.6)</code> returns a new flower and leaves the original unchanged, with no <code>setup</code> or <code>draw</code> loop to wire up.</td>
</tr>
<tr>
<td width="50%" valign="top"><b>Reads like English</b><br><code>petal.repeat(8).in_fan.colored(:crimson, :navy)</code> reads from left to right: repeat a petal eight times, fan the copies out, colour them crimson and navy.</td>
<td width="50%" valign="top"><b>Nothing but Ruby</b><br>Zero external dependencies. Run <code>gem install asobi</code> and <code>asobi</code> to live-code in your browser with automatic reload, or run sketches straight in the <a href="https://asobi.myura.me/playground">browser playground</a>.</td>
</tr>
</table>

## Run your first sketch

For a local sketch, you'll need **Ruby 3.2 or newer** and a browser. Run these commands in the folder where you'd like to keep your sketch.

```sh
gem install asobi
asobi
```

asobi creates `play.rb` with the sketch below and opens the spinning flower in your browser. If `play.rb` already exists, it opens that sketch.

<table>
<tr>
<td>

```ruby
require "asobi"

flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
show flower.spin(every: 8)
```

</td>
<td align="center" width="230"><img src="docs/readme/media/play.gif" alt="A flower of eight crimson and navy petals turns slowly." width="200"></td>
</tr>
</table>

**Try a change.** In `play.rb`, change `repeat(8)` to `repeat(12)` and save. Four more petals appear in the browser. Change `every: 8` to `every: 2` and the flower completes a turn in two seconds. Press Ctrl-C in the terminal to stop the preview.

<details>
<summary>Open another sketch or choose a port</summary>

To open another sketch, pass its path to `asobi`, for example `asobi sketch.rb`. A file that contains `require "asobi"` and calls `show` also runs with `ruby sketch.rb`. Add `--no-open` to the `asobi` command to open the URL printed in the terminal yourself. The server looks for a free port starting at 4567. Use `--port 5000` to start the search at 5000.

</details>

## Why asobi

Here is one picture: 6×6 square tiles, rotating and shrinking, in two colors. This is all of it in asobi.

```ruby
require "asobi"
tiles = square(18).repeat(36).change_each { |s, t| s.rotate(t * 90).grow(to: 1 - t * 0.5) }
show tiles.in_grid(6, gap: 4).colored(:tomato, :navy)
```

And this is the same picture in p5.js, written out in full.

```javascript
function setup() {
  createCanvas(400, 400);
  angleMode(DEGREES);
  rectMode(CENTER);
  noStroke();
  noLoop();
}

function draw() {
  background(255);
  translate(width / 2, height / 2);
  const n = 6, size = 18, step = size + 4;
  const origin = ((n - 1) * step) / 2;
  for (let i = 0; i < 36; i++) {
    const t = i / 36;
    push();
    translate((i % n) * step - origin, Math.floor(i / n) * step - origin);
    rotate(t * 90);
    fill(i % 2 === 0 ? "tomato" : "navy");
    square(0, 0, size * (1 - t * 0.5));
    pop();
  }
}
```

In asobi, `in_grid` does the layout, `change_each` does the gradual change, and `colored(:tomato, :navy)` alternates the two colors. [Open the asobi version in the playground](https://asobi.myura.me/playground#code=cmVxdWlyZSAiYXNvYmkiCnRpbGVzID0gc3F1YXJlKDE4KS5yZXBlYXQoMzYpLmNoYW5nZV9lYWNoIHsgfHMsIHR8IHMucm90YXRlKHQgKiA5MCkuZ3Jvdyh0bzogMSAtIHQgKiAwLjUpIH0Kc2hvdyB0aWxlcy5pbl9ncmlkKDYsIGdhcDogNCkuY29sb3JlZCg6dG9tYXRvLCA6bmF2eSkK) and change a number to see what moves.

## Key features

To try each example in this section, keep `require "asobi"` at the top of `play.rb` and replace the lines beneath it.

### Arrange and combine shapes

`repeat` makes copies in the same spot. `in_fan` turns them around a shared centre. With `a + b`, the second picture sits on top, so a small circle added last becomes the centre of the flower. `scale(0.6)` returns a smaller flower, and `beside` puts the two side by side as one picture.

<table>
<tr>
<td>

```ruby
petals = petal(40, 16).repeat(8).in_fan.colored(:crimson, :navy)
flower = petals + circle(5).colored(:gold)
show flower.beside(flower.scale(0.6), gap: 12)
```

</td>
<td align="center" width="270"><img src="docs/readme/media/compose.png" alt="A large and a small flower side by side, each with crimson and navy petals around a gold centre." width="240"></td>
</tr>
</table>

Lengths are relative to the other shapes in the sketch, and the preview fits the drawing to the screen. Angles are measured in degrees clockwise, so `rotate(90)` makes a quarter turn.

### Object to Art: turn Ruby values into pictures

With `to_art`, any Ruby value becomes a shape: numbers become discs, strings and symbols become typography, arrays and ranges become visual rows in element order, and hashes become palette swatches. Pass `as:` to use each number as the size of another shape — here the Fibonacci sequence becomes a row of growing stars that you can colour and set in motion.

<table>
<tr>
<td>

```ruby
fib = [1, 1, 2, 3, 5, 8, 13, 21]
stars = fib.to_art(as: star).colored(:gold, :orange)
show stars.spin(every: 4).one_by_one, on: :black
```

</td>
<td align="center" width="270"><img src="docs/readme/media/to_art.gif" alt="Eight gold and orange stars in a row on black, from small to large, each turning a little after the one before." width="240"></td>
</tr>
</table>

### Art to Object: give your own class a visual form

Define `to_art` to return the picture for an instance, and you can pass any domain object directly to `show`. Include `Asobi::Art` when you want the reverse direction too — calling composition and animation methods like `spin` or `beside` straight on the object itself.

<table>
<tr>
<td>

```ruby
class Flower
  include Asobi::Art

  def initialize(count, color)
    @count = count
    @color = color
  end

  def to_art
    petal.repeat(@count).in_fan.colored(@color)
  end
end

show Flower.new(7, :coral).spin(every: 4)
```

</td>
<td align="center" width="230"><img src="docs/readme/media/own_class.gif" alt="A flower of seven coral petals turns." width="200"></td>
</tr>
</table>

### Ask for motion by name

Motion comes from words too: `spin`, `pulse`, `sway`, `orbit`. The dots below grow to twice their size and shrink back over two seconds. Placing `one_by_one` after `pulse` offsets the start of each dot's motion, sending a pulse around the ring. For a motion of your own, write it in an `animate` block.

<table>
<tr>
<td>

```ruby
dots = circle(5).repeat(24).in_ring.colored(:gold, :orange)
show dots.pulse(every: 2, to: 2).one_by_one, on: :black
```

</td>
<td align="center" width="230"><img src="docs/readme/media/one_by_one.gif" alt="A ring of gold and orange dots on black. A swelling pulse travels around the ring." width="200"></td>
</tr>
</table>

### Glow, trails and blending

Effects chain the same way. `trail(4)` keeps four fainter copies of where the picture just was. `glowing` lights its edges, and `blended(:screen)` brightens the places where shapes overlap. Pass `grain: true` to `show` for film grain over the whole picture.

<table>
<tr>
<td>

```ruby
petals = petal(50, 18).repeat(8).in_fan.colored(:deeppink, :cyan)
glow = petals.spin(every: 4).trail(4).glowing.blended(:screen)
show glow, on: :black, grain: true
```

</td>
<td align="center" width="230"><img src="docs/readme/media/effects.gif" alt="A glowing pink and cyan flower spins on black, leaving a short trail." width="200"></td>
</tr>
</table>

### React to clicks, the pointer and sound

Write who drives a motion after it, and a click, the pointer or sound turns it instead of the clock. `when_clicked` plays the motion once on a click, `while_hovered` plays it while the pointer is over the picture, and `when_pressed("a")` plays it once when the key is pressed. `by` picks a moment of the motion from a value: `by(:mouse_x)` follows the pointer from left to right.

```ruby
dot = circle(8).colored(:deeppink)
dots = dot.pulse(to: 2).when_clicked.repeat(8).in_ring(60)
needle = star(radius: 30).colored(:gold).spin.by(:mouse_x)
show dots + needle, on: :black
```

Only the dot you click swells, and the star turns as the pointer moves across. A picture that reacts is still a picture, so you can arrange it or set it in motion again. No Ruby runs in the browser, so a saved HTML file reacts in the same way.

Pictures can follow sound too. This sketch is for VJ use: it moves with what the microphone hears.

```ruby
burst = star(points: 8, radius: 60, inner: 24).colored(:deeppink)
bass = burst.pulse(to: 1.6).by(:mic, :low).spin(every: 8)
kick = ring(radius: 90, thickness: 3).colored(:cyan).pulse(every: 0.4, to: 1.3).on_beat
show bass.on(kick).glowing, on: :black, controls: false
```

`by(:mic, :low)` swells the star with the strength of the bass. `:mid` and `:high` follow the middle and high sounds, `:pitch` follows how high the sound is, and with no second word it follows the volume. `on_beat` plays the motion once on every beat. Browsers open the microphone only after a click, so click the page once. `controls: false` hides the record and code buttons, and **F** switches to full screen.

### Make sound

`play` plays a song file in a loop, and `sounding` plays a sound each time a reaction starts.

```ruby
play "beat.wav"
notes = [:c4, :e4, :g4, :c5]
keys = notes.map { |note| circle(18).colored(:gold).pulse(to: 1.4).when_clicked.sounding(note) }
beat = ring(radius: 90, thickness: 3).colored(:cyan).pulse(every: 0.4, to: 1.2).on_beat(:music)
show keys.to_art.in_row(gap: 16).on(beat), on: :black
```

Click the gold circles to hear C, E, G and C. Write a note as `:c4` or `"C#4"`. There are also six named sounds: `:pop`, `:kick`, `:snare`, `:hat`, `:clap` and `:bell`. asobi makes all of them in the browser, so you need no sound files.

`by(:music)` and `on_beat(:music)` listen to the sound asobi itself plays. The ring in this sketch jumps on each beat of the song, so pictures can follow music without a microphone.

`beat.wav` is a four-second loop in [examples/reactions](examples/reactions/). To use your own song, put the file in the same folder as the sketch and change the name. When you edit and save the sketch, the same song keeps playing without a break. Sound starts after you click the page once, and **M** mutes it.

### Save the file, see the change

While a sketch runs, asobi watches its file. Save it in your editor and the picture in the browser is replaced without a page reload. The animation clock keeps running, so you can tune a number while watching the motion.

| In the live preview | What happens |
| --- | --- |
| Press **C** | The sketch's source code appears over the picture, like subtitles. Press again to hide it. |
| Press **R**, then **R** again | Start recording, then download the clip as MP4 or WebM in a supported browser. The clip includes the sound asobi plays. |
| Press **F** | Switch to full screen. Press again to go back. |
| Press **M** | Mute the sound asobi plays. Press again to hear it. |
| Save a sketch with an error | The last picture stays visible, with the error message underneath. The message includes an example of how to fix it. |

## Sketch gallery

Each piece is a single Ruby file. Select a picture to read its code. From a checkout of the repository, run one with a command such as `asobi examples/showcase/phyllotaxis.rb`.

<table>
<tr>
<td align="center" width="33%"><a href="examples/showcase/phyllotaxis.rb"><img src="docs/readme/media/phyllotaxis.gif" alt="Four hundred seeds, shading from gold to pink, sit on a sunflower spiral and swell in a wave from the centre outwards." width="100%"></a></td>
<td align="center" width="33%"><a href="examples/showcase/type_rings.rb"><img src="docs/readme/media/type_rings.gif" alt="On cream paper, English and Japanese letters form three rings that turn against each other around a beating red heart." width="100%"></a></td>
<td align="center" width="33%"><a href="examples/showcase/orbits.rb"><img src="docs/readme/media/orbits.gif" alt="Four planets with fading tails circle a glowing sun." width="100%"></a></td>
</tr>
<tr>
<td align="center"><b><a href="examples/showcase/phyllotaxis.rb">Sunflower seeds</a></b><br>400 circles placed with <code>in_spiral</code> · 3 lines</td>
<td align="center"><b><a href="examples/showcase/type_rings.rb">Type rings</a></b><br>letters set <code>in_ring</code>, one by one · 12 lines</td>
<td align="center"><b><a href="examples/showcase/orbits.rb">Orbits</a></b><br>your own <code>Planet</code> drawn through <code>to_art</code> · 10 lines</td>
</tr>
</table>

<table>
<tr>
<td align="center" width="33%"><a href="examples/showcase/moire.rb"><img src="docs/readme/media/moire.gif" alt="Two sets of fine cyan-to-pink rings overlap; one circles and breathes, and curved moiré stripes ripple across the frame." width="100%"></a></td>
<td align="center" width="33%"><a href="examples/showcase/seigaiha.rb"><img src="docs/readme/media/seigaiha.gif" alt="Seigaiha, the Japanese wave pattern, in indigo lines. Pale blue washes through it row by row." width="100%"></a></td>
<td align="center" width="33%"><a href="examples/showcase/bubble_sort.rb"><img src="docs/readme/media/bubble_sort.gif" alt="A row of shuffled, many-coloured bars swaps neighbours again and again until the bars stand in order of length." width="100%"></a></td>
</tr>
<tr>
<td align="center"><b><a href="examples/showcase/moire.rb">Moiré</a></b><br>two sets of rings, one moving with <code>orbit</code> · 4 lines</td>
<td align="center"><b><a href="examples/showcase/seigaiha.rb">Seigaiha</a></b><br>overlapping rings and a tide of <code>shift_color</code> · 7 lines</td>
<td align="center"><b><a href="examples/showcase/bubble_sort.rb">Bubble sort</a></b><br>every swap of an array, drawn with <code>to_art</code> · 12 lines</td>
</tr>
</table>

The examples on the website can be edited right in the browser. Select an animation, then **Open in playground**.

| Flower | Through a heart | Night sky |
| :---: | :---: | :---: |
| [![Crimson and navy petals turn around a gold centre.](docs/readme/flower.gif)](https://asobi.myura.me/examples#flower) | [![Red and gold stripes rotate behind a heart-shaped window.](docs/readme/through_a_heart.gif)](https://asobi.myura.me/examples#through_a_heart) | [![Gold stars twinkle beside a glowing crescent moon.](docs/readme/night_sky.gif)](https://asobi.myura.me/examples#night_sky) |
| [`in_fan`](examples/flower.rb) | [`clipped_by`](examples/through_a_heart.rb) | [`fade`](examples/night_sky.rb) |

Find more in the [examples folder](examples/README.md) and on the [examples page](https://asobi.myura.me/examples).

## Every word at a glance

Look up arguments and defaults in the [method reference](https://asobi.myura.me/reference). When you leave out a number, asobi uses one that fits.

| To do this | Words |
| --- | --- |
| **Start with a shape** | `circle` `ellipse` `rect` `square` `triangle` `polygon` `star` `line` `text` |
| **Playful shapes** | `heart` `petal` `moon` `drop` `cloud` |
| **Draw lines** | `arc` `wave` `ring` `path` |
| **Layer and combine** | `+` `on` `under` `beside` `above` `repeat` (`*`) |
| **Arrange** | `in_row` `in_column` `in_grid` `in_ring` `in_fan` `in_spiral` `scattered` `change_each` |
| **Transform** | `move` `rotate` `scale` `grow` `shrink` `mirror` `flip` |
| **Colour** | `colored` `outlined` `stroke` `opacity` `hsl` `gray`, and `colored(from: :gold, to: :crimson)` for a gradient |
| **Add effects** | `glowing` `blurred` `blended` `shadowed` `clipped_by` `trail`, and `grain: true` in `show` |
| **Set in motion** | `spin` `pulse` `sway` `orbit` `fade` `bounce` `drift` `shift_color` `animate` `one_by_one` |
| **React** | `when_clicked` `while_hovered` `when_pressed` `on_beat`, and `by` to follow a value (`:mouse_x` `:mouse_y` `:mic` `:music`) |
| **Make sound** | `play` for a song, `sounding` for effect sounds and notes |
| **Turn values into pictures** | `to_art` on numbers, arrays, ranges, hashes, strings and symbols, and the `to_art` you define in your own class |
| **Show and save** | `show` (`on:` for the background, `paper:` for page dimensions, `controls: false` for no buttons), `save` for SVG or HTML, `at` for one moment of a motion |

## Export and record

Use `save` to write a still picture as SVG or a playable animation as a self-contained HTML file. You can open the HTML file directly in a browser. The example writes both files to the current directory, then shows the same animation live.

```ruby
flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
motion = flower.spin(every: 4)

flower.save("flower.svg")
motion.save("flower.html")
show motion
```

To save a particular frame, use `motion.at(1).save("frame.svg")` for the picture one second into the loop. For a video, press **R** in the live preview to record.

A picture that reacts keeps reacting in the saved HTML file. A song you `play` is stored inside the file too (up to 20 MB), so one file carries the picture and its sound. An SVG file holds the still picture from before any reaction.

## Use asobi from an existing Ruby program

Load `asobi/pure` to keep shape names under `Asobi` and leave Ruby's built-in classes untouched. Save the following as `export.rb` and run `ruby export.rb` from the same folder. It writes three navy stars to `stars.svg`.

```ruby
require "asobi/pure"

stars = Asobi.art([3, 1, 4], as: Asobi.star)
stars.colored(:navy).save("stars.svg")
```

## Documentation

| To do this | Go to |
| --- | --- |
| Learn **Object to Art / Art to Object** step by step | [Guide](https://asobi.myura.me/guide) ([Markdown](https://asobi.myura.me/guide.md)) |
| Look up shapes, layouts, motion, and defaults | [Method reference](https://asobi.myura.me/reference) ([Markdown](https://asobi.myura.me/reference.md)) |
| Try asobi in the browser without installing it | [Playground](https://asobi.myura.me/playground) |
| Read complete one-file sketches | [Examples](examples/README.md) |
| Give AI coding agents full API context | [llms.txt](https://asobi.myura.me/llms.txt) · [llms-full.txt](https://asobi.myura.me/llms-full.txt) · [SKILL.md](https://asobi.myura.me/.well-known/agent-skills/asobi/SKILL.md) |
| See why asobi is designed this way | [Design notes (Japanese)](DESIGN.md) |
| See what changed in each release | [Changelog](CHANGELOG.md) |

## FAQ

**Q: What is asobi?**

asobi (Japanese for “play”) is a zero-dependency Ruby 3.2+ gem for creative coding, generative SVG art, and looping animations that can react to clicks, the pointer, keys, a microphone, or a song. You can run sketches locally with live browser reload or try them in the browser playground powered by ruby.wasm.

**Q: What does “Object to Art. Art to Object.” mean?**

Object to Art means any Ruby value—numbers, strings, arrays, hashes, or your own classes defining `to_art`—can become a picture. Art to Object means the returned picture is itself an immutable Ruby object (`Asobi::Art`), so you can store it in variables, pass it to methods, put it back into arrays, and chain layouts or animations without canvas state bugs.

**Q: How is asobi different from p5.js, Processing, or Ruby 2D?**

p5.js and Processing draw imperatively inside `setup` and `draw` loops with mutable canvas state (`fill`, `translate`, `push`/`pop`), and Ruby 2D mutates drawable objects on an SDL window. asobi has no canvas state and no native library dependencies: every shape and motion is an immutable Ruby value composed with English-like words.

**Q: Can asobi react to clicks, music, or a microphone, and can it make sound?**

Yes. A word after a motion says who turns its frames instead of the clock: `when_clicked`, `while_hovered`, `when_pressed("a")`, `on_beat`, and `by(:mouse_x)`, `by(:mic, :low)` or `by(:music)`. `play "song.mp3"` plays a song in a loop, and `sounding(:kick)` or `sounding(:c4)` after a reaction plays a drum sound or a note made in the browser, with no sound files. Editing the code does not restart the song, so it suits live coding and VJ sets, and a saved HTML page still reacts and carries its song.

**Q: Do I need external tools like ImageMagick, SDL, or Node.js?**

No. asobi uses only the Ruby standard library (Ruby 3.2 or newer). Run `gem install asobi` and `asobi` to start live coding in your browser, or open the online playground with zero installation.

**Q: How do I turn my own Ruby class into art, and what formats can I export?**

Define a `to_art` method returning any asobi picture on your class (and optionally `include Asobi::Art` to call methods like `spin` or `colored` directly on instances). You can save stills as clean SVG files with `save` (`art.svg`), save looping animations as standalone HTML (`art.html`), or record MP4/WebM video in the live browser view.

## Development

From the repository root, use `ruby exe/asobi examples/flower.rb` to try changes to the library. Run the following commands to test the library and build the documentation site locally.

```sh
bundle install
bundle exec rake test
bundle exec rake site
```

Open `_site/index.html` in a browser for English or `_site/ja/index.html` for Japanese. Editing and running code in the playground requires an internet connection to load its Ruby WebAssembly runtime from a CDN.

The suite checks the library and CLI, builds the site with test data, and runs the sketches from the gallery and both READMEs. To rebuild the GIFs in this README, use the scripts in [docs/readme/tools](docs/readme/tools).

## Issues and pull requests

Issues are welcome in English or Japanese. For a bug, a small sketch that shows the problem helps us reproduce it. For an idea, tell us what you'd like to draw or animate. [Open an issue](https://github.com/Hayato1031/asobi/issues/new/choose)

Want to fix a bug, improve the docs, or share a sketch? [Fork asobi](https://github.com/Hayato1031/asobi/fork), make your change on a branch in your fork, and open a pull request against `Hayato1031/asobi:main`. English and Japanese are both welcome. For a larger change, an issue is a good place to discuss the idea first.

## License

[MIT](LICENSE) · [RubyGems](https://rubygems.org/gems/asobi) · [Official website](https://asobi.myura.me/) · [llms.txt](https://asobi.myura.me/llms.txt)
