require "asobi"

# An LED wall: 2040 lights, each a moment behind the next, turn a three-armed spiral.
light = ->(t) { 0.07 + 0.93 * ((1 + Math.cos(2 * Math::PI * t)) / 2)**6 }
leds = circle(2.8).repeat(2040).in_grid(60, gap: 2.4).change_each do |led, _, i|
  x, y = i % 60 - 29.5, i / 60 - 16.5
  lag = Math.hypot(x, y) / 16 + Math.atan2(y, x) * 3 / (2 * Math::PI)
  led.animate(2) { |l, t| l.opacity(light.(t - lag)) }
end
show leds.colored(from: :deeppink, to: :gold, angle: 30).glowing(2),
     on: "#05040a", paper: [480, 270]
