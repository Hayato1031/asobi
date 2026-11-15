require "asobi"

# For live music. Click once to let asobi listen, then play something loud.
# The star turns by the clock and swells with the bass; a ring jumps on every beat.
burst = star(points: 8, radius: 60, inner: 24).colored(:deeppink)
bass = burst.pulse(to: 1.6).by(:mic, :low).spin(every: 8)
kick = ring(radius: 90, thickness: 3).colored(:cyan).pulse(every: 0.4, to: 1.3).on_beat
show bass.on(kick).glowing, on: :black, controls: false
