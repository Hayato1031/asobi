require "asobi"

# A poster that reads itself: 840 letters on eight rings, lit by waves running round.
phrase = "RUBY IS PLAY • ASOBI • あそび • "
band = ->(r, size) do
  n = (r * 6.0 / size / phrase.size).round * phrase.size
  glyphs = phrase.chars.cycle.first(n).map { text(_1, size: r * 6.0 / n) }
  glyphs.to_art.in_ring(r, facing_out: true)
end
rings = [[62, 5], [80, 11], [100, 4], [120, 15], [144, 5], [168, 19], [198, 6], [232, 22]]
lit = rings.each_with_index.map do |(r, size), i|
  band.(r, size).colored(i.even? ? :cyan : :deeppink)
                .fade(every: 4.0 / (1 + i % 3), to: 0.1).one_by_one
end
lines = (1..9).map { ring(50 + _1 * 21.5, 0.25) }.reduce(:+).colored(:white).opacity(0.3)
word = text("あそび", size: 40).colored(:white).glowing(3)
show lines + lit.reduce(:+).glowing(1) + word, on: "#05060c", paper: [480, 270]
