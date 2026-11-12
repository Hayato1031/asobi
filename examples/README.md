# asobi examples

Each file is a complete Ruby sketch. From the repository root, try the flower first.

```sh
ruby exe/asobi examples/flower.rb
```

A browser opens with a spinning flower. Edit the sketch and save to see your changes. Press Ctrl-C in the terminal to stop.
With the gem installed, you can also run `asobi examples/flower.rb` or `ruby examples/flower.rb`.

| file | what it shows |
|---|---|
| `flower.rb` | a petal, copied and fanned out |
| `night_sky.rb` | glowing stars that twinkle, and a moon |
| `dot_wave.rb` | a wave of bouncing dots (`one_by_one`) |
| `ring_pulse.rb` | a ring of dots that pulse one by one |
| `rings.rb` | concentric rings |
| `sequence.rb` | a number sequence as stars (`to_art` with `as:`) |
| `typography.rb` | a word, letter by letter |
| `tiles.rb` | a grid pattern (`change_each`) |
| `hearts.rb` | bouncing hearts that change colour |
| `planets.rb` | your own `Planet` class, made a picture with `to_art` |
| `spiral.rb` | a sunflower-seed spiral |
| `neon_flower.rb` | glow, screen blending, a trail and film grain |
| `aurora.rb` | blurred, screen-blended waves |
| `paper_cutouts.rb` | paper cut-outs with soft shadows |
| `through_a_heart.rb` | gradient stripes seen through a heart-shaped window (`clipped_by`) |

## Showcase

Bigger pieces live in `showcase/`. They take a moment longer to draw, so they are not in the website's playground. Run one with `ruby exe/asobi examples/showcase/hanabi.rb`.

| file | what it shows |
|---|---|
| `showcase/hanabi.rb` | fireworks: fans of sparks that open one by one and leave streaks |
| `showcase/phyllotaxis.rb` | 400 seeds on a sunflower spiral (`in_spiral`) |
| `showcase/type_rings.rb` | letters on three rings, turning against each other |
| `showcase/orbits.rb` | your own `Planet` class with glowing tails (`to_art`, `trail`) |
| `showcase/seigaiha.rb` | the Japanese wave pattern with a tide of colour (`shift_color`) |
| `showcase/bubble_sort.rb` | every swap of a bubble sort, drawn as it happens |

リポジトリのルートで `ruby exe/asobi examples/flower.rb` を実行すると、ブラウザに回転する花が表示されます。コードを書き換えて保存すると、表示も更新されます。[日本語の使い方](../README.ja.md)
