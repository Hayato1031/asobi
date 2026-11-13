require "asobi"

# Move the pointer over the picture.
# Left to right turns the wheel; top to bottom changes its colour.
wheel = petal(40, 14).repeat(12).in_fan
colors = wheel.shift_color(:navy, :gold).by(:mouse_y)
show colors.spin.by(:mouse_x) + circle(8).colored(:crimson)
