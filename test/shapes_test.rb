# frozen_string_literal: true

require "test_helper"

class ShapesTest < Minitest::Test
  def test_circle_default_and_shorthand
    assert_equal 10.0, circle.r
    assert_equal circle(radius: 12), circle(12)
    assert_box circle.bounds, -10, -10, 10, 10
  end

  def test_ellipse_rect_square
    assert_equal 30.0, ellipse.width
    assert_equal 20.0, ellipse.height
    assert_equal ellipse(width: 12, height: 32), ellipse(12, 32)
    assert_equal [30.0, 20.0], [rect.width, rect.height]
    assert_equal rect(width: 40, height: 10), rect(40, 10)
    assert_equal [20.0, 20.0], [square.width, square.height]
    assert_equal square(size: 5), square(5)
  end

  def test_triangle_is_equilateral_pointing_up_and_centred
    t = triangle
    assert_close 20.0, t.width
    assert_close 20 * Math.sqrt(3) / 2, t.height
    assert_close 0.0, t.bounds.cx
    assert_close 0.0, t.bounds.cy
    assert_equal [:move, 0.0, -t.height / 2], t.commands.first
    assert_equal triangle(size: 8), triangle(8)
  end

  def test_polygon_has_corner_up
    hexagon = polygon
    assert_equal 6, hexagon.commands.count { %i[move line].include?(_1.first) }
    assert_equal [:move, 0.0, -10.0], hexagon.commands.first
    assert_equal polygon(sides: 8), polygon(8)
    assert_equal polygon(sides: 5, radius: 3), polygon(5, 3)
  end

  def test_star
    s = star
    assert_equal 10, s.commands.count { %i[move line].include?(_1.first) }
    assert_equal [:move, 0.0, -10.0], s.commands.first
    inner = s.commands[1]
    assert_close 4.5, Math.hypot(inner[1], inner[2])
    assert_equal star(points: 7, radius: 20), star(7, 20)
    assert_close 2.0, Math.hypot(*star(inner: 2).commands[1][1, 2])
  end

  def test_line_is_a_black_unfilled_stroke
    l = line
    assert_instance_of Asobi::Styled, l
    assert_equal({ fill: "none", stroke: "black", stroke_width: 1.0 }, l.style)
    assert_close 20.0, l.art.width
    assert_equal line(length: 50), line(50)
  end

  def test_text
    assert_equal "asobi", text.string
    t = text("ruby")
    assert_equal 16.0, t.size
    assert_nil t.font
    assert_includes t.svg, ">ruby</text>"
    assert_includes text("x", font: "serif").svg, %(font-family="serif")
    assert_includes text("<&>").svg, "&lt;&amp;&gt;"
    assert text("あいう").width > text("abc").width
  end

  def test_path_defaults_open_line_centred
    p = path
    assert_instance_of Asobi::Styled, p
    assert_equal "none", p.style[:fill]
    assert_close 0.0, p.bounds.cx
    assert_close 0.0, p.bounds.cy
    assert_equal path([0, 0], [40, -30], [80, 0]), path
    assert_equal path([[0, 0], [40, -30], [80, 0]]), path
  end

  def test_path_closed_is_filled
    p = path([0, 0], [10, 0], [10, 10], closed: true)
    assert_instance_of Asobi::Path, p
    assert p.closed?
  end

  def test_smooth_path_uses_curves_and_box_contains_curve
    p = path([0, 0], [40, -30], [80, 0], smooth: true).art
    assert(p.commands.any? { _1.first == :cubic })
    straight = path([0, 0], [40, -30], [80, 0]).art
    assert_operator p.bounds.height, :>=, straight.bounds.height - 1e-9
  end

  def test_path_box_follows_bezier_exactly
    # A cubic bulging up to y = -7.5 (3/4 of the control height).
    p = Asobi::Path.new(commands: [[:move, 0, 0], [:cubic, 0, -10, 10, -10, 10, 0]])
    assert_box p.bounds, 0, -7.5, 10, 0
  end

  def test_path_build_and_even_odd
    ring = Asobi::Path.build(fill_rule: :evenodd) do |pen|
      pen.move(-10, -10).line(10, -10).line(10, 10).line(-10, 10).close
      pen.move(-5, -5).line(5, -5).line(5, 5).line(-5, 5).close
    end
    assert_includes ring.svg, %(fill-rule="evenodd")
    assert_box ring.bounds, -10, -10, 10, 10
  end

  def test_space_and_nothing
    assert_equal [10.0, 10.0], [space.width, space.height]
    assert_equal [4.0, 8.0], [space(4, 8).width, space(4, 8).height]
    assert_equal "", space.svg
    assert_equal 0.0, nothing.width
    assert_empty nothing.to_a
  end

  def test_hsl_and_gray
    assert_equal "hsl(200, 70%, 50%)", hsl(200)
    assert_equal "hsl(20, 30%, 40%)", hsl(380, 30, 40)
    assert_equal "hsl(0, 0%, 80%)", gray(80)
  end

  def test_bad_numbers_teach
    e = assert_raises(TypeError) { circle("big") }
    assert_includes e.message, "circle(radius: 10)"
    e = assert_raises(ArgumentError) { circle(-3) }
    assert_includes e.message, "-3"
    assert_raises(ArgumentError) { polygon(sides: 2) }
    e = assert_raises(ArgumentError) { path([0, 0]) }
    assert_includes e.message, "path([0, 0], [40, -30])"
    assert_raises(ArgumentError) { path([0, 0], [1]) }
  end

  def test_arc_defaults_shorthand_and_unfilled
    a = arc
    assert_instance_of Asobi::Styled, a
    assert_equal({ fill: "none", stroke: "black", stroke_width: 1.0 }, a.style)
    assert_equal arc(radius: 5), arc(5)
    assert_equal arc(20, from: 0, to: 180), arc
    # right half of a circle: from the top, round the right, to the bottom
    assert_close 20.0, a.art.bounds.y1
    assert_close(-20.0, a.art.bounds.y0)
    assert_close 20.0, a.art.bounds.x1
    assert_close 0.0, a.art.bounds.x0
  end

  def test_arc_spans
    three_quarters = arc(10, from: 90, to: 360).art
    assert_box three_quarters.bounds, -10, -10, 10, 10
    assert_equal 3, three_quarters.commands.count { _1.first == :cubic }
    assert_equal 4, arc(10, from: 0, to: 360).art.commands.count { _1.first == :cubic }
    assert_equal 5, arc(10, from: 0, to: 400).art.commands.count { _1.first == :cubic }
    assert_box arc(10, from: 0, to: -180).art.bounds, -10, -10, 0, 10
    assert_box arc(10, from: -90, to: 90).art.bounds, -10, -10, 10, 0
    last = arc(10, from: 0, to: 360).art.commands.last
    assert_close 0.0, last[5]
    assert_close(-10.0, last[6]) if last.size > 6
  end

  def test_wave
    w = wave
    assert_equal({ fill: "none", stroke: "black", stroke_width: 1.0 }, w.style)
    assert_close 100.0, w.art.width
    assert_close 10.0, w.art.height
    assert_equal 6, w.art.commands.count { _1.first == :cubic }
    assert_close 0.0, w.art.bounds.cx
    assert_equal wave(length: 50, height: 4, waves: 2), wave(50, 4, 2)
    assert_close 4.0, wave(40, 4).art.height
  end

  def test_ring_is_a_doughnut_with_a_real_hole
    r = ring
    assert_equal :evenodd, r.fill_rule
    assert_includes r.svg, 'fill-rule="evenodd"'
    assert_box r.bounds, -20, -20, 20, 20
    assert_equal 8, r.commands.count { _1.first == :cubic }
    assert_equal ring(radius: 30, thickness: 6), ring(30, 6)
    assert_equal circle(5), ring(5, 5)
    assert_equal circle(5), ring(5, 9)
  end

  def test_heart_is_as_wide_as_its_size
    h = heart
    assert_close 20.0, h.width
    assert_close 0.0, h.bounds.cx
    assert_close 0.0, h.bounds.cy
    assert h.height > 17 && h.height < 20
    assert_close 60.0, heart(60).width
    assert_equal heart(size: 7), heart(7)
    assert h.closed?
  end

  def test_heart_is_symmetric
    pts = heart.commands.select { _1.first == :cubic }.map { _1.last(2) }
    pts.each do |x, y|
      assert(pts.any? { |x2, y2| (x + x2).abs < 1e-9 && (y - y2).abs < 1e-9 })
    end
  end

  def test_petal_grows_up_from_the_origin
    p = petal
    assert_close 0.0, p.bounds.y1
    assert_close(-20.0, p.bounds.y0)
    assert_close 10.0, p.width
    assert_close 0.0, p.bounds.cx
    assert_equal petal(length: 30, width: 8), petal(30, 8)
    assert_close 30.0, petal(30).height
  end

  def test_moon_height_and_shape
    m = moon
    assert_close 20.0, m.height
    assert_close 0.0, m.bounds.cy
    assert m.width < m.height
    assert_close 0.0, m.bounds.cx
    assert_close 50.0, moon(50).height
    assert_equal moon(size: 9), moon(9)
    assert_equal :nonzero, m.fill_rule
    assert_equal 1, m.commands.count { _1.first == :close }
  end

  def test_drop_and_cloud
    d = drop
    assert_close 20.0, d.height
    assert_close 0.0, d.bounds.cy
    assert d.width < d.height
    assert_equal drop(size: 4), drop(4)
    c = cloud
    assert_close 30.0, c.width
    assert_close 0.0, c.bounds.cx
    assert c.height < c.width
    assert_close 80.0, cloud(80).width
    assert_equal cloud(size: 9), cloud(9)
    assert_equal 1, c.commands.count { _1.first == :move }
  end

  def test_new_shapes_are_equal_values_and_take_styling
    [arc, wave, ring, heart, petal, moon, drop, cloud].each do |shape|
      assert_equal shape.class, shape.class
      refute_empty shape.svg
      assert_includes shape.colored(:red).svg, "red"
      assert_includes shape.outlined(:blue).svg, "blue"
      assert_in_delta shape.width, shape.rotate(90).height, 0.01
      assert_in_delta shape.width * 2, shape.scale(2).width, 1e-6
      assert_in_delta shape.bounds.cx + 5, shape.move(right: 5).bounds.cx, 1e-6
    end
    assert_equal heart, heart
    assert_equal cloud(12), cloud(12)
    assert_equal moon.colored(:gold), moon.colored(:gold)
  end

  def test_new_shapes_compose
    assert_equal 8, petal.repeat(8).in_fan.to_a.size
    assert_operator heart.repeat(6).in_ring.width, :>, heart.width
    assert_operator moon.beside(star).width, :>, moon.width
  end

  def test_bad_numbers_teach_for_new_words
    e = assert_raises(TypeError) { heart("big") }
    assert_includes e.message, "heart(size: 20)"
    assert_raises(ArgumentError) { moon(-1) }
    assert_raises(ArgumentError) { cloud(-1) }
    assert_raises(TypeError) { arc(from: "up") }
    assert_raises(TypeError) { wave(waves: nil) }
    assert_raises(ArgumentError) { petal(width: -2) }
    e = assert_raises(ArgumentError) { ring(thickness: -1) }
    assert_includes e.message, "ring(radius: 20, thickness: 4)"
    in_language(:ja) do
      e = assert_raises(TypeError) { drop("x") }
      assert_includes e.message, "drop(size: 20)"
      refute_match(/\bmust\b/i, e.message)
    end
  end

  def test_words_are_private_everywhere
    assert_raises(NoMethodError) { 5.circle }
    assert_raises(NoMethodError) { circle.circle }
    assert_equal circle, Asobi.circle
  end
end
