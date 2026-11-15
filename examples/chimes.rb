require "asobi"

# A small instrument: click the notes in the ring, and the bell in the middle.
notes = %i[c4 d4 e4 g4 a4 c5 d5 e5]
chimes = notes.each_with_index.map do |note, i|
  chime = circle(13).colored(hsl(i * 45, 75, 62))
  chime.pulse(every: 0.5, to: 1.4).when_clicked.sounding(note)
end
bell = star(points: 8, radius: 22, inner: 9).colored(:gold).spin(every: 1).when_clicked.sounding(:bell)
music_box = chimes.to_art.in_ring(58) + bell
show music_box.glowing, on: :midnightblue
