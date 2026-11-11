# frozen_string_literal: true

require "test_helper"

class ManyTest < Minitest::Test
  def boxes(many) = many.map(&:bounds)

  def refute_overlaps(many)
    bs = boxes(many)
    bs.each_with_index do |a, i|
      bs.each_with_index do |b, j|
        next if j <= i

        refute a.overlap?(b), "pictures #{i} and #{j} overlap"
      end
    end
  end

  def test_many_is_enumerable_and_a_picture
    many = circle.repeat(3)
    assert_kind_of Enumerable, many
    assert_kind_of Asobi::Art, many
    assert_equal 3, many.count
    assert_equal circle, many.first
  end

  def test_transforms_keep_a_many
    turned = circle.repeat(3).move(up: 4).rotate(30)
    assert_instance_of Asobi::Many, turned
    assert_equal 3, turned.in_row.size
  end

  def test_in_row_and_column
    row = square(10).repeat(3).in_row
    assert_box row.bounds, -15, -5, 15, 5
    refute_overlaps row
    assert_close 38.0, square(10).repeat(3).in_row(gap: 4).width
    assert_equal square(10).repeat(3).in_row(gap: 4), square(10).repeat(3).in_row(4)
    col = square(10).repeat(3).in_column(gap: 2)
    assert_close 34.0, col.height
    assert_equal col, square(10).repeat(3).in_column(2)
  end

  def test_in_grid_auto_columns
    grid = square(10).repeat(5).in_grid
    xs = grid.map { _1.bounds.cx.round(6) }.uniq
    ys = grid.map { _1.bounds.cy.round(6) }.uniq
    assert_equal 3, xs.size # ceil(sqrt(5))
    assert_equal 2, ys.size
    refute_overlaps grid
    assert_equal 4, square.repeat(8).in_grid(4).map { _1.bounds.cx.round(6) }.uniq.size
  end

  def test_in_grid_bad_columns
    e = assert_raises(ArgumentError) { square.repeat(4).in_grid(columns: 0) }
    assert_includes e.message, "in_grid needs a whole number of columns"
    assert_includes e.message, "in_grid(columns: 3)"
  end

  def test_in_ring_auto_radius_keeps_neighbours_apart
    [3, 8, 12, 30].each do |n|
      refute_overlaps square(10).repeat(n).in_ring
    end
    ring = circle.repeat(4).in_ring(60)
    assert_close(-60.0, ring[0].bounds.cy) # starts at the top
    assert_close 60.0, ring[1].bounds.cx   # then clockwise, to the right
    assert_equal ring, circle.repeat(4).in_ring(radius: 60)
  end

  def test_in_ring_facing_out
    ring = triangle.repeat(4).in_ring(radius: 40, facing_out: true)
    right = ring[1]
    # The second triangle sits on the right and its tip points right.
    assert_close 40.0, right.bounds.cx, 3
    assert_operator right.bounds.width, :<, right.bounds.height + 1e-9
  end

  def test_in_fan
    petal = ellipse(10, 30).move(up: 20)
    flower = petal.repeat(4).in_fan
    assert_close 20.0, flower[1].bounds.cx # 90 degrees clockwise
    fan = petal.repeat(3).in_fan(over: 90)
    assert_close 0.0, fan[1].bounds.cx      # the middle one points up
    assert_operator fan[0].bounds.cx, :<, 0
    assert_equal fan, petal.repeat(3).in_fan(90)
  end

  def test_in_spiral_auto_spacing
    spiral = circle(5).repeat(20).in_spiral
    assert_close 0.0, spiral[0].bounds.cx
    dots = circle(3).repeat(100).in_spiral.map { _1.bounds }
    dots.combination(2).each do |a, b|
      assert_operator Math.hypot(a.cx - b.cx, a.cy - b.cy), :>=, 6 - 1e-9 # discs never overlap
    end
    assert_equal circle.repeat(5).in_spiral(8), circle.repeat(5).in_spiral(spacing: 8)
    assert_operator circle(10).repeat(30).in_spiral.width, :>, circle(2).repeat(30).in_spiral.width
  end

  def test_scattered_area
    dots = circle(1).repeat(50).scattered(over: [100, 20], seed: 1)
    b = dots.bounds
    assert_operator b.width, :<=, 102
    assert_operator b.height, :<=, 22
    auto = circle(1).repeat(16).scattered(seed: 3)
    assert_operator auto.width, :<=, 2 * 2 * 4 + 2 # side 2*size*sqrt(n) plus one dot
    assert_raises(ArgumentError) { circle.repeat(3).scattered(over: "big") }
  end

  def test_change_each
    grown = circle.repeat(4).in_row.change_each { |one, t, i| one.grow(to: 1 + t + i * 0) }
    assert_close 20.0, grown[0].width
    assert_close 35.0, grown[3].width
    seen = []
    circle.repeat(2).change_each { |one, t, i| seen << [t, i]; one }
    assert_equal [[0.0, 0], [0.5, 1]], seen
    e = assert_raises(ArgumentError) { circle.repeat(2).change_each }
    assert_includes e.message, "change_each {"
  end

  def test_arranging_keeps_group_style
    many = circle.repeat(3).colored(:red).in_row
    assert_equal "red", many.style[:fill]
  end

  def test_empty_many
    assert_equal nothing, nothing.in_ring.in_row.in_grid.in_fan.in_spiral.scattered(seed: 1)
    assert_nil nothing.box(Asobi::IDENTITY)
  end

  class Badge
    include Asobi::Art
    def to_art = Asobi.star(6)
  end

  def test_a_single_picture_is_a_group_of_one
    words = {
      in_row: ->(x) { x.in_row }, in_column: ->(x) { x.in_column(gap: 2) }, in_grid: ->(x) { x.in_grid },
      in_ring: ->(x) { x.in_ring }, in_fan: ->(x) { x.in_fan(90) }, in_spiral: ->(x) { x.in_spiral },
      scattered: ->(x) { x.scattered(seed: 3) }, change_each: ->(x) { x.change_each { |one, t, i| one.grow(to: 1 + t + i) } }
    }
    [circle, star, heart, circle.move(up: 5).colored(:red), Badge.new].each do |picture|
      words.each do |name, word|
        got = word.call(picture)
        assert_instance_of Asobi::Many, got, "#{picture.class}##{name}"
        assert_equal 1, got.size
        assert_equal word.call(Asobi::Many.new([Asobi.art(picture)])), got, "#{picture.class}##{name}"
      end
    end
    assert_equal circle.repeat(1).in_ring, circle.in_ring
    assert_equal circle.grow, circle.change_each { |one| one.grow }.first
  end

  def test_a_group_of_one_is_still_a_group
    assert_equal circle.in_ring(20).repeat(3).size, 3
    assert_equal [circle], circle.in_grid.to_a
  end

  # [3, 1, 4].to_art is already a row. Asking it to stand in a ring must give
  # a ring, not a ring pulled apart by where the row had put each picture.
  def test_arranging_an_arranged_group_starts_from_scratch
    centres = ->(many) { boxes(many).map { |b| [b.cx.round(6), b.cy.round(6)] } }
    loose = Asobi::Many.new([circle(3), circle(5), circle(9), star(4)])
    row = loose.in_row(gap: 4)

    assert_equal centres.(loose.in_ring(40)), centres.(row.in_ring(40))
    assert_equal centres.(loose.in_spiral(12)), centres.(row.in_spiral(12))
    assert_equal centres.(loose.scattered(over: 80, seed: 3)), centres.(row.scattered(over: 80, seed: 3))
    assert_equal centres.(loose.in_ring), centres.(row.in_ring), "the automatic radius ignores the old places too"

    centres.([3, 1, 4, 1, 5, 9].to_art.in_ring(30)).each do |x, y|
      assert_in_delta 30, Math.hypot(x, y), 1e-6
    end
  end

  def test_a_shape_that_is_not_centred_sits_on_the_ring_by_its_middle
    ring = petal(20, 10).repeat(4).in_ring(50)
    boxes(ring).each { |b| assert_in_delta 50, Math.hypot(b.cx, b.cy), 1e-6 }
  end
end
