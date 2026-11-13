require "asobi"

# asobi plays beat.wav, and the pictures follow the music it plays.
# Click once to start the sound. The star swells with the bass; the ring jumps on every beat.
play "beat.wav"
burst = star(points: 8, radius: 60, inner: 24).colored(:orange)
bass = burst.pulse(to: 1.6).by(:music, :low).spin(every: 8)
kick = ring(radius: 90, thickness: 3).colored(:cyan).pulse(every: 0.4, to: 1.3).on_beat(:music)
show bass.on(kick).glowing, on: :black, controls: false
