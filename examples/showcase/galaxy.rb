require "asobi"

# A galaxy of 1,100 seeds: the middle turns faster, winding the spiral into arms.
seeds = (1..1100).map do |i|
  circle(1.9 - i * 0.001).colored(hsl(50 - i * 0.12, 95, 80 - i * 0.02))
end
disc = seeds.to_art.in_spiral(7.2).change_each do |seed, t|
  seed.animate(8) do |s, u|
    s.rotate(360 * u + (1 - t) * (200 + 140 * Math.sin(2 * Math::PI * u)))
  end
end
stars = circle(0.6).colored(:white).repeat(500).in_spiral(11).fade(every: 2, to: 0)
show stars.one_by_one(gap: 0.37) + disc, on: "#05060c", paper: [480, 270]
