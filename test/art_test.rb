# frozen_string_literal: true

require "test_helper"

class ArtTest < Minitest::Test
  def test_pictures_are_equal_values_and_frozen
    assert_equal circle(10), circle(10.0)
    assert_equal circle.move(up: 3).colored(:red), circle.move(up: 3).colored(:red)
    refute_equal circle(10), circle(11)
    assert circle.frozen?
    a = circle
    a.move(right: 5)
    a.colored(:red)
    assert_equal circle, a
    refute_respond_to circle, :with
  end

  def test_on_under_and_plus_order
    a = circle.colored(:red)
    b = square.colored(:blue)
    svg_on = a.on(b).svg
    assert_operator svg_on.index("blue"), :<, svg_on.index("red")
    svg_under = a.under(b).svg
    assert_operator svg_under.index("red"), :<, svg_under.index("blue")
    assert_equal a.under(b), a + b
  end

  def test_repeat_and_star
    many = circle.repeat(3)
    assert_instance_of Asobi::Many, many
    assert_equal 3, many.size
    assert_equal many, circle * 3
    assert_equal 2, circle.repeat.size
    assert_equal 0, circle.repeat(0).size
    assert_equal 4, circle.repeat(times: 4).size
    e = assert_raises(ArgumentError) { circle.repeat(1.5) }
    assert_includes e.message, "repeat(12)"
  end

  def test_beside_and_above
    row = square(10).beside(square(20))
    assert_close 30.0, row.width
    assert_close(-15.0, row.bounds.x0)
    assert_close 0.0, row[0].bounds.cx + 10
    assert_close 34.0, square(10).beside(square(20), gap: 4).width
    col = square(10).above(square(20), gap: 2)
    assert_close 32.0, col.height
    assert_operator col[0].bounds.cy, :<, col[1].bounds.cy
  end

  def test_move_uses_words
    b = circle.move(right: 5, up: 3).bounds
    assert_close 5.0, b.cx
    assert_close(-3.0, b.cy)
    b = circle.move(left: 2, down: 4).bounds
    assert_close(-2.0, b.cx)
    assert_close 4.0, b.cy
    assert_equal circle, circle.move
  end

  def test_rotate_is_clockwise_degrees
    stick = rect(width: 2, height: 20).move(up: 10)
    turned = stick.rotate(90).bounds
    # Pointing up, a quarter turn clockwise makes it point right.
    assert_close 10.0, turned.cx
    assert_close 0.0, turned.cy
    assert_equal stick.rotate(0.25.turn), stick.rotate(90)
    assert_equal stick, stick.rotate(90).rotate(90).rotate(90).rotate(90)
  end

  def test_scale_grow_shrink
    assert_close 40.0, circle.scale(2).width
    assert_close 40.0, circle.scale.width
    s = circle.scale(width: 2, height: 1)
    assert_close 40.0, s.width
    assert_close 20.0, s.height
    assert_close 60.0, circle.grow(to: 3).width
    assert_close 40.0, circle.grow.width
    assert_close 10.0, circle.shrink(to: 0.5).width
    assert_close 10.0, circle.shrink.width
  end

  def test_mirror_and_flip
    thing = square(4).move(right: 10, up: 5)
    assert_close(-10.0, thing.mirror.bounds.cx)
    assert_close(-5.0, thing.mirror.bounds.cy)
    assert_close 5.0, thing.flip.bounds.cy
    assert_close 10.0, thing.flip.bounds.cx
  end

  def test_latest_colour_wins_on_the_same_picture
    assert_equal circle.colored(:blue), circle.colored(:red).colored(:blue)
    moved = circle.colored(:red).move(up: 3).colored(:blue)
    assert_includes moved.svg, "blue"
    refute_includes moved.svg, "red"
    assert_equal circle.colored(:red).move(up: 3), circle.move(up: 3).colored(:red)
  end

  def test_group_colour_does_not_override_inner_colour
    group = circle.colored(:red).beside(square).colored(:blue)
    svg = group.svg
    assert svg.start_with?(%(<g fill="blue">))
    assert_includes svg, %(fill="red")
  end

  def test_colored_cycles_on_many_and_uses_first_on_single
    dots = circle.repeat(5).in_row.colored(:red, :blue)
    fills = dots.map { _1.svg[/fill="(\w+)"/, 1] }
    assert_equal %w[red blue red blue red], fills
    assert_equal circle.colored(:red), circle.colored(:red, :blue)
    assert_equal circle.colored(:crimson), circle.colored
  end

  def test_colored_recolours_lines
    assert_equal "red", line.colored(:red).style[:stroke]
    assert_equal "none", line.colored(:red).style[:fill]
  end

  def test_outlined_stroke_opacity
    o = circle.outlined(:navy, width: 2)
    assert_equal({ fill: "none", stroke: "navy", stroke_width: 2.0 }, o.style)
    assert_box o.bounds, -11, -11, 11, 11
    s = circle.colored(:red).stroke(:black, width: 1)
    assert_equal "red", s.style[:fill]
    assert_equal "black", s.style[:stroke]
    assert_equal 0.5, circle.opacity.style[:opacity]
    assert_equal 0.3, circle.opacity(0.3).style[:opacity]
    assert_raises(ArgumentError) { circle.opacity(2) }
  end

  def test_colour_names_and_strings
    assert_equal "darkred", circle.colored(:dark_red).style[:fill]
    assert_equal "#ff0066", circle.colored("#ff0066").style[:fill]
    assert_equal "hsl(200, 70%, 50%)", circle.colored(hsl(200)).style[:fill]
    e = assert_raises(ArgumentError) { circle.colored(:crimsn) }
    assert_includes e.message, "crimson"
  end

  def test_measuring
    assert_equal 20.0, circle.width
    assert_equal 20.0, circle.height
    assert_instance_of Asobi::Box, circle.bounds
  end

  def test_save_writes_svg
    Dir.mktmpdir do |dir|
      file = File.join(dir, "a.svg")
      assert_equal file, circle.save(file)
      assert File.read(file).start_with?("<svg")
      e = assert_raises(ArgumentError) { circle.save(File.join(dir, "a.png")) }
      assert_includes e.message, %(save("flower.svg"))
    end
  end
end

require "tmpdir"
