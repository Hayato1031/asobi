require "asobi"

# Your own class as a picture: each Planet draws its orbit, itself and its tail.
Planet = Data.define(:size, :distance, :color, :year) do
  def to_art
    path = ring(distance, 0.25).colored("#2b3050")
    path + circle(size).colored(color).glowing(2).orbit(distance, every: year).trail(30, gap: 0.02)
  end
end

sun = circle(8).colored(from: :white, to: :gold, around: true).glowing(9)
planets = [Planet.new(1.6, 18, :skyblue, 2), Planet.new(2.6, 32, :tomato, 4),
           Planet.new(2, 46, :orchid, 8), Planet.new(3.2, 62, :aquamarine, 8)]
show planets.reduce(sun, :+), on: "#080a14", grain: true
