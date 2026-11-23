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

  def test_all_true_colour_wins_even_inside_a_group
    group = circle.colored(:red).beside(square).colored(:blue, all: true)
    svg = group.svg
    assert svg.start_with?(%(<g fill="blue">))
    refute_includes svg, "red"

    row = circle.colored(:red).repeat(5).in_row.colored(:blue, all: true)
    assert_equal "blue", row.style[:fill]
    assert_equal circle.repeat(5).in_row.colored(:blue), row

    # nested groups are cleared too
    nested = [circle.colored(:red).repeat(2).in_row.colored(:gold), square].to_art.in_column.colored(:blue, all: true)
    refute_includes nested.svg, "red"
    refute_includes nested.svg, "gold"

    # stroke and opacity on inner shapes stay when fill is repainted
    stroked = circle.colored(:red).stroke(:black, width: 2).opacity(0.5).repeat(3).in_row.colored(:blue, all: true)
    assert_includes stroked.svg, %(fill="blue")
    assert_includes stroked.svg, %(stroke="black")
    assert_includes stroked.svg, %(opacity="0.5")
    refute_includes stroked.svg, "red"

    # line-only shapes inside a group get their line recoloured too
    lines = line.repeat(3).in_row.colored(:cyan, all: true)
    assert_equal 3, lines.svg.scan(%(stroke="cyan")).size
    refute_includes lines.svg, %(stroke="black")

    # cycling after a single colour, and a single colour after cycling
    cycled = circle.repeat(4).in_row.colored(:gold).colored(:red, :blue, all: true)
    refute_includes cycled.svg, "gold"
    assert_equal %w[red blue red blue], cycled.map { _1.svg[/fill="(\w+)"/, 1] }
    repainted = cycled.colored(:green, all: true)
    assert_equal "green", repainted.style[:fill]
    refute_includes repainted.svg, "red"
    refute_includes repainted.svg, "blue"

    # a gradient clears the colours inside as well
    sheet = circle.colored(:red).repeat(3).in_row.colored(from: :gold, to: :navy, all: true)
    refute_includes sheet.svg, "red"
    assert_includes sheet.svg, "mask"
  end

  def test_all_true_keeps_an_outlined_group_as_lines
    outlines = circle.repeat(4).in_row.outlined(:black, width: 2).colored(:red, :blue, all: true)
    assert_equal %w[red blue red blue], outlines.map { _1.svg[/stroke="(\w+)"/, 1] }
    refute_match(/fill="(red|blue)"/, outlines.svg)
    gold_outlines = outlines.colored(:gold, all: true)
    assert_equal %w[gold gold gold gold], gold_outlines.map { _1.svg[/stroke="(\w+)"/, 1] }
    refute_includes gold_outlines.svg, %(fill="gold")
    refute_includes gold_outlines.svg, "red"
    refute_includes gold_outlines.svg, "blue"
    # without all: (as in 0.2.1) the pictures are filled inside the outline
    filled = circle.repeat(4).in_row.outlined(:black, width: 2).colored(:red, :blue)
    assert_equal %w[red blue red blue], filled.map { _1.svg[/fill="(\w+)"/, 1] }
  end

  def test_all_true_paints_reacting_parts_inside_a_group
    part = circle(5).colored(:red).pulse.when_clicked
    group = part.repeat(3).in_row.colored(:blue, all: true)
    refute_includes group.svg, "red" # the rest picture, drawn in place
    reel = Asobi::Reel.of(group)
    assert_equal %w[p1], reel["parts"].keys # the same part three times is still one part
    reel["parts"]["p1"]["frames"].each { refute_includes _1, "red" }
    assert reel["frames"].all? { _1.include?(%(fill="blue")) }
    # without all: the part keeps its own colour
    assert_includes part.repeat(3).in_row.colored(:blue).svg, "red"

    # several colours paint each part in turn
    cycled = part.repeat(4).in_row.colored(:blue, :gold, all: true)
    refute_includes cycled.svg, "red"
    assert_equal %w[blue gold blue gold], cycled.map { _1.svg[/fill="(\w+)"/, 1] }
    assert_equal 2, Asobi::Reel.of(cycled)["parts"].size

    # a line that reacts gets its line recoloured
    ring = circle(5).outlined(:black).spin.when_clicked
    frames = Asobi::Reel.of(ring.repeat(2).in_row.colored(:gold, all: true))["parts"]["p1"]["frames"]
    assert frames.all? { _1.include?(%(stroke="gold")) && !_1.include?("black") }

    # a part with no colour of its own is left as it is
    plain = circle(5).pulse.when_clicked.repeat(3).in_row
    assert_equal plain.colored(:blue), plain.colored(:blue, all: true)

    # shift_color(all: true) clears the part once: it stays one part and takes the colour around it
    shifting = Asobi::Reel.of(part.repeat(3).in_row.shift_color(:navy, :gold, all: true))
    assert_equal %w[p1], shifting["parts"].keys
    shifting["parts"]["p1"]["frames"].each { refute_includes _1, "red" }
  end

  def test_all_true_on_a_single_picture_is_the_same_as_without
    [circle, circle.colored(:red), line, circle.outlined(:red), star.move(up: 3).rotate(20),
     circle.colored(:red).glowing].each do |pic|
      assert_equal pic.colored(:blue), pic.colored(:blue, all: true)
      assert_equal pic.colored(:blue, :gold), pic.colored(:blue, :gold, all: true)
      assert_equal pic.colored(from: :gold, to: :navy, angle: 30), pic.colored(from: :gold, to: :navy, angle: 30, all: true)
    end
    assert_equal circle.colored(:red).repeat(3).in_row.colored(:blue), circle.colored(:red).repeat(3).in_row.colored(:blue, all: false)
  end

  def test_all_must_be_true_or_false
    [nil, :yes, 1, "true"].each do |bad|
      e = assert_raises(ArgumentError) { circle.colored(:red, all: bad) }
      assert_includes e.message, "true or false"
      assert_includes e.message, "colored(:navy, all: true)"
      assert_includes e.message, bad.inspect
    end
    e = assert_raises(ArgumentError) { circle.colored(from: :red, all: :yes) }
    assert_includes e.message, "colored"
    in_language(:ja) do
      e = assert_raises(ArgumentError) { circle.colored(:red, all: :yes) }
      assert_includes e.message, "true か false を渡してください"
      assert_includes e.message, "例：row.colored(:navy, all: true)"
    end
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
