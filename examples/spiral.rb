require "asobi"

# A sunflower spiral at the golden angle.
seeds = circle(3).repeat(300).change_each { |d, t| d.grow(to: 0.4 + t).colored(hsl(20 + t * 40)) }
show seeds.in_spiral(5)
