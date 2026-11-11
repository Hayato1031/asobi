require "asobi"

# A wave made of bouncing dots.
dots = circle(6).repeat(16).in_row(gap: 6).colored(:teal)
show dots.bounce(height: 30, every: 2).one_by_one
