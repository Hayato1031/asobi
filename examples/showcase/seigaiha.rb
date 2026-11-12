require "asobi"

# Seigaiha, the Japanese wave pattern: rows of rings, each row half a step over.
paper, indigo = "#f3ecdc", "#1f3a68"
crest = [20, 15, 10, 5].map { |r| circle(r).stroke(indigo, width: 1.6) }.reduce(:+)
sea = crest.repeat(11 * 7).change_each do |one, _t, i|
  row, col = i.divmod(7)
  one.move(right: (col - 3) * 40 + row % 2 * 20, down: (row - 5) * 11)
end
show sea.shift_color(from: paper, to: "#8fb5d6", every: 4).one_by_one, on: paper, paper: [200, 112]
