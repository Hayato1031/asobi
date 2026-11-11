require "asobi"

# A petal, copied and fanned out into a flower.
flower = petal(40, 16).repeat(8).in_fan.colored(:crimson, :navy)
bloom = flower + circle(5).colored(:gold)
show bloom.spin(every: 8)
