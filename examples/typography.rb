require "asobi"

# A word, letter by letter, growing.
letters = "asobi".chars.to_art.change_each { |c, t| c.grow(to: 1 + t * 2) }
show letters.in_row(gap: 4).colored(:crimson, :navy)
