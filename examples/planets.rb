require "asobi"

# Your own Planet class, made a picture with to_art.
class Planet
  def initialize(size, distance, color, year)
    @size, @distance, @color, @year = size, distance, color, year
  end

  def to_art
    ring(@distance, 0.4).colored(:dimgray) +
      circle(@size).colored(@color).orbit(@distance, every: @year)
  end
end

sun = circle(10).colored(:gold)
planets = [Planet.new(3, 22, :skyblue, 3), Planet.new(5, 38, :tomato, 7), Planet.new(4, 54, :orchid, 12)]
show planets.reduce(sun) { |system, planet| system + planet }, on: :black
