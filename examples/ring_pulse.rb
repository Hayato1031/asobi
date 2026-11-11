require "asobi"

# A ring of dots that pulse one by one.
dots = circle(4).repeat(24).in_ring(60).colored(:crimson, :orange)
show dots.pulse(every: 2, to: 2).one_by_one
