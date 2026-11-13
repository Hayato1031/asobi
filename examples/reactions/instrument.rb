require "asobi"

# An instrument. Click a bar to play its note, click the star for a bell,
# point at the dots for a pop, and press a, s, d or f for the drums.
notes = %i[c4 d4 e4 f4 g4 a4 b4 c5]
bars = notes.each_with_index.map do |note, i|
  bar = rect(24, 90 - i * 6).colored(hsl(i * 40, 70, 60))
  bar.pulse(every: 0.4, to: 1.15).when_clicked.sounding(note)
end
drums = { "a" => :kick, "s" => :snare, "d" => :hat, "f" => :clap }.map do |key, sound|
  pad = circle(22).colored(:dimgray) + text(key, size: 20).colored(:white)
  pad.pulse(every: 0.3, to: 1.3).when_pressed(key).sounding(sound)
end
bell = star(points: 6, radius: 30).colored(:gold).spin(every: 1).when_clicked.sounding(:bell)
dots = circle(6).colored(:deeppink).pulse(every: 0.3, to: 1.8).while_hovered.sounding(:pop).repeat(5).in_row(gap: 14)
keys = bars.to_art.in_row(gap: 8).above(drums.to_art.in_row(gap: 24), gap: 24)
show bell.above(keys, gap: 24).above(dots, gap: 20)
