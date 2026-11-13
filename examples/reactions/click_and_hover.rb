require "asobi"

# Click a flower and it blooms. Point at a star and it spins.
flower = petal(20, 8).repeat(8).in_fan.colored(:crimson, :orange)
blooms = flower.pulse(every: 0.6, to: 1.4).when_clicked.repeat(5).in_row(gap: 16)
stars = star(radius: 14).colored(:gold).spin(every: 1).while_hovered.repeat(5).in_row(gap: 24)
show blooms.above(stars, gap: 24)
