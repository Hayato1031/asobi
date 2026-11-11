require "asobi"

# Concentric rings that ripple.
rings = ring(80, 4).repeat(10).change_each { |r, t| r.scale(1 - t * 0.9) }
show rings.colored(:navy, :skyblue).pulse(every: 2, to: 1.1).one_by_one
