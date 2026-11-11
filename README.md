# asobi

[日本語版](README.ja.md)

asobi (Japanese for “play”) is a Ruby library for making SVG pictures and looping animations. A picture is a Ruby value. Here, eight copies of a petal form a flower, and the whole flower turns once every eight seconds.

```ruby
require "asobi"

flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
show flower.spin(every: 8)
```

<img src="docs/first-sketch.svg" width="240" alt="Eight petals, alternating crimson and navy, arranged around a common centre.">

## Run your first sketch

You'll need Ruby **3.2 or newer** and a browser. The library uses only Ruby's standard library. Run this command from the repository root.

```sh
ruby exe/asobi
```

asobi creates `play.rb` with the flower sketch above and opens a live preview in your browser. If `play.rb` already exists, it opens that sketch. Change `repeat(8)` to `repeat(12)` and save to add four petals. Change `every: 8` to `every: 2` to make the flower turn once every two seconds. Press Ctrl-C in the terminal to stop the preview.

To open another sketch, pass its path, for example `ruby exe/asobi examples/flower.rb`. Add `--no-open` to open the URL printed in the terminal yourself. The server looks for a free port starting at 4567. Use `--port 5000` to start the search at 5000.

### Install the command for use in other folders

Build and install the gem from the repository root.

```sh
gem build asobi.gemspec --output asobi.gem
gem install --local ./asobi.gem
```

You can now run `asobi` in a sketch folder to start with `play.rb`, or open an existing sketch with `asobi sketch.rb`. A file that contains `require "asobi"` and calls `show` also runs with `ruby sketch.rb`.

## Build pictures in Ruby

To try each example in this section, keep `require "asobi"` at the top of `play.rb` and replace the lines beneath it.

### Arrange and combine shapes

`repeat` makes copies in the same spot. `in_fan` turns them around a shared centre. With `a + b`, the second picture sits on top, so a small circle added last becomes the centre of the flower.

```ruby
petals = petal(40, 16).repeat(8).in_fan.colored(:crimson, :navy)
flower = petals + circle(5).colored(:gold)
show flower.beside(flower.scale(0.6), gap: 12)
```

The smaller flower is a new picture. The original keeps its size. Lengths are relative to the other shapes in the sketch, and the preview fits the drawing to the screen. Angles are measured in degrees clockwise, so `rotate(90)` makes a quarter turn.

### Turn data into a picture

With `to_art`, a number becomes a disc, and an array becomes a row of pictures in element order. Give it a shape with `as:` to use each number as the size of that shape. Here the Fibonacci sequence becomes a row of growing stars.

```ruby
fib = [1, 1, 2, 3, 5, 8, 13, 21]
show fib.to_art(as: star).colored(:gold, :orange), on: :black
```

### Give your own class a visual form

Define `to_art` to return the picture for an instance. Include `Asobi::Art` when you also want to call methods such as `spin` on the instance itself.

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

### Animate a group

The dots below grow to twice their size and shrink back over two seconds. Placing `one_by_one` after `pulse` offsets the start of each dot's motion, sending a pulse around the ring.

```ruby
dots = circle(5).repeat(24).in_ring.colored(:gold, :orange)
show dots.pulse(every: 2, to: 2).one_by_one, on: :black
```

| To do this | Try |
| --- | --- |
| Start with a shape | `circle`, `rect`, `star`, `text`, `path`, `wave`, `heart`, `petal` |
| Arrange copies | `in_row` for a line, `in_grid` for tiles, `in_ring` for a circle, `in_spiral` for a spiral |
| Add colour and texture | `colored(from: :gold, to: :crimson)` for a gradient, `glowing` for a halo, `shadowed` for a shadow, `clipped_by` for a cut-out |
| Add motion | `spin` to rotate, `sway` to rock, `orbit` to circle a point, `trail` for fading copies, `animate` for your own motion |
| Set up the preview | In `show`, use `on:` for the background colour, `paper:` for page dimensions, or `grain: true` for film grain |

## Preview, export and record

When a saved sketch has an error, the live preview keeps the last picture that worked and displays the error underneath. Press **C** in the browser to toggle the source code. In browsers that support recording, **R** starts recording and **R** again downloads the clip as MP4 or WebM.

Use `save` to write a still picture as SVG or a playable animation as a self-contained HTML file. You can open the HTML file directly in a browser. The example writes both files to the current directory.

```ruby
flower = petal.repeat(8).in_fan.colored(:crimson, :navy)
motion = flower.spin(every: 4)

flower.save("flower.svg")
motion.save("flower.html")
show motion
```

To save a particular frame, use `motion.at(1).save("frame.svg")` for the picture one second into the loop.

## Use asobi from an existing Ruby program

Load `asobi/pure` to keep shape names under `Asobi` and leave Ruby's built-in classes untouched. Save the following as `export.rb` in the repository root and run `ruby -Ilib export.rb`. It writes three navy stars to `stars.svg` in the same directory.

```ruby
require "asobi/pure"

stars = Asobi.art([3, 1, 4], as: Asobi.star)
stars.colored(:navy).save("stars.svg")
```

## Examples and reference

Each file is a complete sketch that you can run with `ruby exe/asobi` followed by its path. [Browse all examples](examples/README.md)

- Turn a number sequence into a row of stars. [Number sequence](examples/sequence.rb)
- Layer glow, screen blending and trails. [Neon flower](examples/neon_flower.rb)
- Give a custom class an orbit and compose several instances into one picture. [Planets](examples/planets.rb)

The documentation site includes a step-by-step guide, a gallery, a reference with method defaults and examples, and a browser playground. To build it locally, run the following from the repository root.

```sh
bundle install
bundle exec rake site
```

Open `_site/index.html` in a browser for English or `_site/ja/index.html` for Japanese. Editing and running code in the playground requires an internet connection to load its Ruby WebAssembly runtime from a CDN.

## Development

After `bundle install`, run `bundle exec rake test`. The suite checks the library and CLI, builds the site with test data, and runs the sketch examples from the gallery and both READMEs. For the design of pictures, motion and the `to_art` protocol, see the [design notes (Japanese)](DESIGN.md).

## License

[MIT](LICENSE)
