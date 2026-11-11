require "asobi"

# Gradient stripes seen through a heart-shaped window.
stripes = rect(10, 90).repeat(12).in_row(gap: 4).colored(from: :crimson, to: :gold, angle: 90)
show stripes.spin(every: 6).clipped_by(heart(70)), on: :navy
