require "asobi"

# A neon tunnel: hexagons rush out of the dark, twisting, while a beam sweeps the rays.
dots = circle(0.04).repeat(6).in_ring(2.5).colored(:white)
hexes = polygon(6, 2.5).outlined(:white, width: 0.012).repeat(24)
rings = hexes.colored(:cyan, :magenta, :gold).change_each { |hex| hex + dots }
fly = rings.animate(2) { |r, t| r.scale(130**t).rotate(t * 60).opacity([t * 3, 1].min) }
rays = line(600).outlined(:violet, width: 0.4).repeat(72).in_fan
beam = rays.animate(2) { |r, t| r.opacity(0.08 + 0.9 * t**6) }.one_by_one
show (beam + fly.one_by_one).glowing(2), on: "#04030b", paper: [480, 270]
