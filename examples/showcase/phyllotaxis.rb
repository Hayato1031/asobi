require "asobi"

# A sunflower head: 400 seeds on the golden angle, breathing from the centre out.
seeds = (1..400).map { |i| circle(1 + i * 0.008).colored(hsl(45 - i * 0.27, 95, 60)) }
head = seeds.to_art.in_spiral(spacing: 5.6)
show head.pulse(every: 3, to: 1.5).one_by_one.glowing(1), on: "#0b0a10"
