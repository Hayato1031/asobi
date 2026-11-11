require "asobi"

# A grid of tiles, turned and shrunk.
tiles = square(18).repeat(36).change_each { |s, t| s.rotate(t * 90).grow(to: 1 - t * 0.5) }
show tiles.in_grid(6, gap: 4).colored(:tomato, :navy)
