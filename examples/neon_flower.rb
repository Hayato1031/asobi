require "asobi"

# A neon flower with glow, screen blending, a short trail and grain.
petals = petal(50, 18).repeat(8).in_fan.colored(:deeppink, :cyan)
spinning = petals.animate(2) { |flower, t| flower.rotate(t * 90) }
show spinning.trail(4).glowing.blended(:screen), on: :black, grain: true
