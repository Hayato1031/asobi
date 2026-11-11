# frozen_string_literal: true

require "test_helper"

class Planet
  def to_art = circle(8).colored(:orange)
end

class Garden
  include Asobi::Art

  def initialize(count) = @count = count
  def to_art = ellipse(width: 6, height: 16).move(up: 10).repeat(@count).in_fan
end

class ToArtTest < Minitest::Test
  def test_numbers
    assert_equal circle(8), 8.to_art
    assert_equal circle(2.5), 2.5.to_art
    assert_equal circle(0.5), Rational(1, 2).to_art
    assert_equal circle(8).outlined, -8.to_art
    assert_equal nothing, 0.to_art
  end

  def test_number_as_shape
    s = 8.to_art(as: star)
    assert_close 8.0, [s.width, s.height].max / 2
    assert_close 16.0, 8.to_art(as: square).width
  end

  def test_array_side_by_side_with_gap
    row = [10, 10].to_art
    assert_close 44.0, row.width
    assert_equal 2, row.size
    assert_equal [10, 10].to_art, Asobi.art([10, 10])
  end

  def test_range
    assert_equal [1, 2, 3].to_art, (1..3).to_art
    e = assert_raises(ArgumentError) { (1..).to_art }
    assert_includes e.message, "(1..10).to_art"
  end

  def test_as_propagates_through_nested_arrays
    table = [[1, 2], [3]].to_art(as: square)
    assert_equal 2, table.size
    cells = table.flat_map(&:to_a)
    assert(cells.all? { _1.is_a?(Asobi::Transformed) && _1.art.is_a?(Asobi::Rect) })
  end

  def test_array_of_arrays_stacks_rows
    table = [[5, 5], [5, 5, 5]].to_art
    assert_operator table[0].bounds.cy, :<, table[1].bounds.cy
    assert_close 24.0, table[0].width
    assert_close 38.0, table[1].width
  end

  def test_strings_and_symbols
    assert_equal text("hi"), "hi".to_art
    assert_equal text("hi"), :hi.to_art
  end

  def test_hash_rows_of_key_beside_value
    t = { a: 1, b: 2 }.to_art
    assert_equal 2, t.size
    assert_equal 2, t[0].size
    assert_operator t[0].bounds.cy, :<, t[1].bounds.cy
    assert_operator t[0][0].bounds.cx, :<, t[0][1].bounds.cx
  end

  def test_nil
    assert_equal nothing, nil.to_art
  end

  def test_plain_class_with_only_to_art
    planet = Planet.new
    refute_kind_of Asobi::Art, planet
    assert_equal 2, circle.on(planet).size
    assert_includes circle.on(planet).svg, "orange"
    assert_close 36.0, circle.beside(planet).width
    assert_equal 2, [planet, planet].to_art.size
    assert_equal Asobi.art(planet), planet.to_art
  end

  def test_class_including_art_gets_every_word
    g = Garden.new(6)
    assert_instance_of Asobi::Many, g.rotate(15)
    assert_includes g.colored(:crimson).svg, "crimson"
    assert_equal 6, g.colored(:red, :blue).size
    assert_operator g.width, :>, 0
    assert_equal 2, g.repeat(2).size
    assert g.to_svg.start_with?("<svg")
  end

  def test_unknown_objects_teach_to_art
    e = assert_raises(TypeError) { Asobi.art(Object.new) }
    assert_includes e.message, "to_art"
    assert_includes e.message, "def to_art = circle(radius: 10)"
    assert_raises(TypeError) { circle.on(Object.new) }
  end

  def test_hooks
    assert_equal [circle, square], Asobi.pair(10, square) { |a, b| [a, b] }
    assert_equal [circle(1), circle(2)], Asobi.gather([1, 2]) { _1 }
    assert_close 2.0, Asobi.gather([1], as: square) { _1 }.first.width
  end

  def test_turn
    assert_equal 90.0, 0.25.turn
    assert_equal 720.0, 2.turns
  end
end
