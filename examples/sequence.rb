require "asobi"

# A number sequence, drawn as stars.
fib = [1, 1, 2, 3, 5, 8, 13, 21]
show fib.to_art(as: star).colored(:gold, :orange), on: :black
