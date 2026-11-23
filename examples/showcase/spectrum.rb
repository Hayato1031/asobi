require "asobi"

# A spectrum with no song: 240 bars in a ring, each on its own beat, under rolling waves.
wave = ->(a) { 0.5 + 0.5 * Math.sin(2 * Math::PI * a) }
bars = rect(0.9, 1).repeat(240).change_each do |bar, t, i|
  bar.colored(hsl(250 + 75 * Math.cos(2 * Math::PI * t), 95, 66)).animate(4) do |b, s|
    h = 2 + 100 * wave.(2 * t - s) * wave.(5 * t + s) * wave.(i * 0.37 + (i % 4 + 1) * s)**2
    b.scale(height: h).move(up: 56 + h / 2) + circle(0.7).move(up: 59 + h)
  end
end.in_fan
echo = bars.scale(2.4).opacity(0.25) + bars.scale(-0.7).opacity(0.3)
show (echo + bars + ring(53, 0.3).colored(:cyan)).glowing(1.5),
     on: "#05060c", paper: [480, 270]
