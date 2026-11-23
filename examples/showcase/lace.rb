require "asobi"

# Lace: 132 hairline ellipses in two fans, folding in waves one after another.
fold = ->(fan, by) { fan.animate(4) { |l, t| l.rotate(by * Math.sin(2 * Math::PI * t)) } }
veil = ellipse(470, 150).outlined(:white, width: 0.35).repeat(72).in_fan
bloom = ellipse(130, 34).move(right: 62).outlined(:white, width: 0.4).repeat(60).in_fan
veil = fold.(veil, 12).one_by_one(gap: 4 / 12.0).colored(:cyan, :blueviolet, around: true)
bloom = fold.(bloom, -20).one_by_one(gap: 4 / 12.0).colored(:white, :deeppink, around: true)
show veil + bloom, on: "#05060c", paper: [480, 270]
