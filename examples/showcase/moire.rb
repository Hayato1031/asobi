require "asobi"

# Moire: two sets of rings, one circling and breathing, weave a pattern neither one has.
rings = (1..56).map { |i| ring(i * 6, 2.4) }.reduce(:+)
drift = rings.pulse(2, to: 1.08).orbit(36, every: 2)
show (rings + drift).colored(from: :cyan, to: :deeppink, angle: 30),
     on: "#05040c", paper: [480, 270]
