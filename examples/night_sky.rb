require "asobi"

# Glowing stars that twinkle one by one, and a moon.
stars = star(radius: 4).repeat(40).change_each { |s, t| s.grow(to: 0.6 + t) }
sky = stars.colored(:gold).scattered(over: [320, 180]).glowing.fade(every: 3, to: 0.4).one_by_one
show sky + moon(size: 40).colored(:ivory).glowing(8).move(right: 110, up: 50), on: :midnightblue
