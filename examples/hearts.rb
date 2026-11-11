require "asobi"

# Hearts that bounce and change colour.
hearts = heart(20).repeat(5).in_row(gap: 6)
show hearts.shift_color(:crimson, :orchid).one_by_one.bounce(height: 24).one_by_one
