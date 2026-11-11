require "asobi"

# An aurora from blurred, screen-blended waves.
ribbon = wave(240, 30, 2).outlined(:springgreen, width: 14)
bands = ribbon.repeat(3).change_each { |w, t, i| w.move(down: i * 14).colored(hsl(150 + i * 50)) }
show bands.drift(right: 40, every: 6).blurred(4).blended(:screen), on: :midnightblue, grain: true
