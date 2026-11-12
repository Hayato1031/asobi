require "asobi"

# Every swap of a bubble sort, drawn as it happens.
values = (1..28).sort_by { |n| n * 37 % 29 }
steps = [values.dup]
(values.size - 1).downto(1) do |last|
  last.times do |i|
    next if values[i] <= values[i + 1]

    values[i], values[i + 1] = values[i + 1], values[i]
    steps << values.dup
  end
end
steps += [values] * 40

bars = ->(list) { list.map { |n| rect(5, n * 4).colored(hsl(n * 11 + 170, 85, 62)) }.to_art }
show Asobi.motion(8) { |seconds| bars.(steps[seconds / 8 * steps.size]) }.glowing(2), on: "#0c0d14", paper: [270, 150]
