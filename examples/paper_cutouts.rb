require "asobi"

# Paper cut-outs with soft shadows.
sun = circle(22).colored(:gold).move(up: 20, right: 40)
far = ellipse(240, 80).colored(:lightseagreen).move(down: 45, left: 30)
near = ellipse(220, 70).colored(:seagreen).move(down: 62, right: 40)
show [sun, far, near].map(&:shadowed).reduce(:+), on: :oldlace
