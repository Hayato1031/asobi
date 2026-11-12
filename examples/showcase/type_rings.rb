require "asobi"

# Words on three rings, turning against each other.
ink, red, paper = "#22252e", "#e2432f", "#f1ebdd"
band = ->(words, size, radius) do
  words.chars.map { |c| text(c, size:, font: "Helvetica Neue, Arial, sans-serif") }
       .to_art.in_ring(radius:, facing_out: true)
end
outer = band.("RUBY IS PLAY • ASOBI • " * 2, 9, 78).colored(ink)
middle = band.("あそび・遊び・" * 2, 13, 52).colored(red)
inner = band.("to_art • " * 2, 8, 28).colored(ink)
rings = [outer, middle, inner].each_with_index.map do |ring, i|
  ring.animate(6) { |r, t| r.rotate(t * 180 * (i.odd? ? -1 : 1)) }
end
show rings.reduce(:+) + heart(18).colored(red).pulse(every: 2, to: 1.15), on: paper, grain: 0.08
