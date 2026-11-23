require "asobi"

# A self-portrait: this sketch reads its own code and draws it.
# Every line becomes a ring of letters, and the music sweeps a light over it.
play "loop.wav"
type = ->(letter) { text(letter, size: 8, font: "Menlo, monospace") }
bands = %i[low mid high]
lines = File.readlines(__FILE__).map(&:strip).reject(&:empty?)
rings = lines.sort_by(&:size).each_with_index.map do |line, i|
  radius = 28 + i * 12
  color = hsl(320 - i * 8, 90, 70)
  letters = (line + "  ").chars.cycle.first(radius).map(&type)
  code = letters.to_art.in_ring(radius:, facing_out: true).colored(color)
  beam = arc(radius:, from: 0, to: 80).stroke(color, width: 11).opacity(0.35)
  turn = i.even? ? 150 : -150
  beam.rotate(i * 50).sway(by: turn).by(:music, bands[i % 3]) + code
end
wave = ring(radius: 14, thickness: 0.5).colored(:white)
ripple = wave.animate(0.5) { |w, t| w.scale(1 + t * 18).opacity(1 - t) }
core = heart(16).colored(from: :deeppink, to: :crimson).pulse(to: 1.5)
art = rings.reduce(:+) + ripple.on_beat(:music) + core.by(:music, :low)
show art.glowing(2), on: "#0a0912", controls: false
