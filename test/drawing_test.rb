# frozen_string_literal: true

require_relative "test_helper"
require "json"

# Asobi::Drawing: a picture as drawing instructions, the layer between the
# pictures and the renderers. Whatever it says, SVG must already do (the
# SVG tests check the output); these check what it says.
class DrawingTest < Minitest::Test
  # A painter that writes down the call it gets, to see the step-by-step form.
  module Spy
    module_function

    %i[circle ellipse rect path text nothing transformed styled group].each do |name|
      define_method(name) { |*args| [name, *args] }
    end
  end

  def step(picture) = Asobi::Drawing.draw(picture, Spy)
  def data(picture) = Asobi::Drawing.data(picture)
  def style_of(picture) = data(picture)["style"]

  # --- shapes ----------------------------------------------------------------

  def test_each_shape_with_its_own_numbers
    assert_equal({ "shape" => "circle", "r" => 12.0 }, data(circle(12)))
    assert_equal({ "shape" => "ellipse", "rx" => 15.0, "ry" => 5.0 }, data(ellipse(width: 30, height: 10)))
    # A rectangle is centred on the origin: x, y is its top-left corner.
    assert_equal({ "shape" => "rect", "x" => -15.0, "y" => -10.0, "width" => 30.0, "height" => 20.0 }, data(rect))
    assert_equal({ "shape" => "nothing" }, data(space))
  end

  def test_text_is_centred_and_always_has_a_font
    assert_equal({ "shape" => "text", "text" => "ruby", "size" => 16.0, "font" => "sans-serif", "origin" => "center" },
                 data(text("ruby")))
    assert_equal "serif", data(text("x", font: "serif"))["font"]
    assert_equal "<&>", data(text("<&>"))["text"] # the words as they are: escaping is a renderer's business
  end

  def test_path_commands_and_fill_rule
    tri = Asobi::Path.polyline([[0, 0], [10, 0], [5, 8]], closed: true)
    assert_equal({ "shape" => "path", "fill_rule" => "nonzero",
                   "commands" => [["move", 0.0, 0.0], ["line", 10.0, 0.0], ["line", 5.0, 8.0], ["close"]] }, data(tri))
    assert_equal "evenodd", data(ring)["fill_rule"]
    assert(data(heart)["commands"].any? { _1.first == "cubic" && _1.size == 7 })
  end

  # --- putting together ------------------------------------------------------

  def test_a_transform_is_six_numbers
    moved = circle.move(right: 3, down: 4)
    assert_equal [1.0, 0.0, 0.0, 1.0, 3.0, 4.0], data(moved)["transform"]
    turned = data(square.rotate(90))
    assert_equal [0.0, 1.0, -1.0, 0.0, 0.0, 0.0], turned["transform"]
    assert_equal "rect", turned["draw"]["shape"]
    # Step by step, the painter gets the Affine and the part to draw.
    name, matrix, part = step(moved)
    assert_equal :transformed, name
    assert_equal Asobi::Affine.translate(3, 4), matrix
    assert_same moved.art, part
  end

  def test_groups_nest_in_order
    inner = circle.beside(square)
    outer = inner.above(star)
    d = data(outer)
    assert_equal 2, d["group"].size
    assert_equal 2, d["group"][0]["group"].size # the row (moving a group moves each of its parts)
    assert_equal({}, d["style"])
    name, style, parts = step(outer)
    assert_equal :group, name
    assert_same outer.style, style
    assert_equal outer.items, parts
  end

  # --- styles ----------------------------------------------------------------

  def test_plain_style_is_handed_over_as_it_is
    pic = circle.colored(:crimson).stroke(:navy, width: 2).opacity(0.5)
    name, style, part = step(pic)
    assert_equal :styled, name
    assert_same pic.style, style # nothing new is made for a plain style
    assert_equal pic.art, part
    assert_equal({ "fill" => "crimson", "stroke" => "navy", "stroke_width" => 2.0, "opacity" => 0.5 }, style_of(pic))
    assert_equal({ "fill" => "none", "stroke" => "black", "stroke_width" => 1.0 }, style_of(line))
  end

  # The colour of a group stays on the group: shapes inside that have no
  # colour of their own take it (the rule renderers follow), and colours
  # inside are kept.
  def test_group_colours_are_inherited_not_copied
    group = [circle, square.colored(:gold)].to_art.colored(:navy)
    d = data(group)
    assert_equal "navy", d["style"]["fill"]
    plain_circle = d["group"][0]["draw"]
    assert_equal({ "shape" => "circle", "r" => 10.0 }, plain_circle)
    assert_equal "gold", d["group"][1]["draw"]["style"]["fill"]
    assert_equal({ fill: "black", stroke: "none", stroke_width: 1.0, opacity: 1.0 }, Asobi::Drawing::DEFAULTS)
  end

  # --- gradients ---------------------------------------------------------------

  def test_linear_gradient_is_two_points_in_the_pictures_coordinates
    fill = style_of(circle.colored(from: :gold, to: :crimson))["fill"]
    assert_equal({ "gradient" => "linear", "x1" => 0.0, "y1" => -10.0, "x2" => 0.0, "y2" => 10.0,
                   "colors" => %w[gold crimson] }, fill)
    turned = style_of(circle.colored(from: :gold, to: :crimson, angle: 90))["fill"]
    assert_equal [10.0, 0.0, -10.0, 0.0], turned.values_at("x1", "y1", "x2", "y2")
  end

  def test_radial_gradient_is_a_centre_and_a_radius
    fill = data(rect(width: 40, height: 10).colored(from: :white, to: :navy, around: true))["style"]["fill"]
    assert_equal({ "gradient" => "radial", "cx" => 0.0, "cy" => 0.0, "r" => 20.0, "colors" => %w[white navy] }, fill)
  end

  def test_a_line_gradient_flows_along_the_line
    fill = style_of(line(20).colored(from: :gold, to: :red))["stroke"]
    assert_equal [-10.0, 0.0, 10.0, 0.0], fill.values_at("x1", "y1", "x2", "y2")
  end

  # A gradient on a group is ONE sheet over the whole group.
  def test_group_gradient_is_one_sheet
    group = circle.repeat(2).in_row.colored(from: :gold, to: :navy)
    style = style_of(group)
    assert_equal [0.0, -10.0, 0.0, 10.0], style["fill"].values_at("x1", "y1", "x2", "y2")
    assert_equal({ "paint" => "fill", "box" => [-20.0, -10.0, 40.0, 20.0] }, style["sheet"])
    # A group of lines gets the sheet on its line, and the sheet reaches
    # over the group's line width too.
    lines = line(10).repeat(2).in_column(gap: 4).outlined(:black, width: 2).colored(from: :gold, to: :navy)
    inside = Asobi::Box.union(lines.items.map { _1.box(Asobi::IDENTITY) })
    assert_equal({ "paint" => "stroke", "box" => inside.grow(1.0).to_a }, style_of(lines)["sheet"])
    # A single picture has no sheet: its gradient is simply its colour.
    refute style_of(circle.colored(from: :gold, to: :navy)).key?("sheet")
  end

  # --- effects -----------------------------------------------------------------

  def test_glow_with_its_box_and_area
    glow, = style_of(circle(10).glowing(4))["effects"]
    assert_equal({ "effect" => "glow", "size" => 4.0, "color" => nil,
                   "box" => [-10.0, -10.0, 20.0, 20.0], "area" => [-16.0, -16.0, 32.0, 32.0] }, glow)
    assert_equal "gold", style_of(circle.glowing(color: :gold))["effects"][0]["color"]
  end

  def test_blur_and_shadow
    blur, = style_of(circle.blurred(3))["effects"]
    assert_equal({ "effect" => "blur", "amount" => 3.0, "box" => [-10.0, -10.0, 20.0, 20.0],
                   "area" => [-19.0, -19.0, 38.0, 38.0] }, blur)
    shadow, = style_of(circle.shadowed(4, right: 3, color: :navy, opacity: 0.6))["effects"]
    assert_equal({ "effect" => "shadow", "right" => 3.0, "down" => 4.0, "blur" => 3.0, "color" => "navy", "opacity" => 0.6 },
                 shadow.slice("effect", "right", "down", "blur", "color", "opacity"))
  end

  def test_clip_is_a_nested_drawing
    clip, = style_of(square(20).clipped_by(circle(5).move(right: 2)))["effects"]
    assert_equal "clip", clip["effect"]
    assert_equal({ "transform" => [1.0, 0.0, 0.0, 1.0, 2.0, 0.0], "draw" => { "shape" => "circle", "r" => 5.0 } }, clip["window"])
    assert_equal [-3.0, -5.0, 10.0, 10.0], clip["window_box"]
    assert_equal [-3.0, -5.0, 10.0, 10.0], clip["area"] # what is left: where both are
  end

  # Effects come in the order written, each covering everything before it.
  def test_effects_in_order_each_around_the_last
    effects = style_of(circle(10).shadowed(down: 10, blur: 0).glowing(2))["effects"]
    assert_equal %w[shadow glow], effects.map { _1["effect"] }
    assert_equal effects[0]["area"], effects[1]["box"]
    assert_equal [-10.0, -10.0, 20.0, 30.0], effects[1]["box"] # the shadow made it taller
  end

  def test_a_line_counts_in_the_box_an_effect_covers
    glow, = style_of(circle(10).stroke(:black, width: 4).glowing)["effects"]
    assert_equal [-12.0, -12.0, 24.0, 24.0], glow["box"]
  end

  def test_blend_is_always_outermost_and_normal_is_nothing
    style = style_of(circle.blended(:screen).glowing)
    assert_equal "screen", style["blend"]
    assert_equal %w[glow], style["effects"].map { _1["effect"] }
    normal = style_of(circle.blended(:normal))
    refute normal.key?("blend")
    assert_equal [], normal["effects"] # effects were given; none to draw
  end

  def test_effects_on_nothing_are_left_out
    assert_equal [], style_of(Asobi.nothing.glowing)["effects"]
  end

  # A window that shows nothing lets nothing through: the picture is drawn
  # as nothing at all (effects after the clip too), as its box already says.
  def test_a_window_that_shows_nothing_draws_nothing
    nothing = { "shape" => "nothing" }
    windows = [Asobi.nothing, [], text(""), circle(5).clipped_by(circle(1).move(right: 50))]
    windows.each do |window|
      picture = circle(10).colored(:red).clipped_by(window)
      assert_nil picture.box(Asobi::IDENTITY)
      assert_equal [:nothing], step(picture)
      assert_equal nothing, data(picture)
      assert_equal nothing, data(picture.shadowed.glowing(2))
      assert_equal "", picture.svg
    end
  end

  def test_a_group_with_a_window_that_shows_nothing
    nothing = { "shape" => "nothing" }
    assert_equal nothing, data(circle(5).repeat(3).in_row.clipped_by(Asobi.nothing))
    # Inside a group, only that picture is nothing.
    group = [circle(5).clipped_by(Asobi.nothing).shadowed, circle(3)].to_art
    assert_equal [nothing, { "shape" => "circle", "r" => 3.0 }], data(group)["group"]
  end

  def test_a_window_that_shows_nothing_only_at_some_moments
    window = circle(8).animate(2) { |picture, t| t < 0.5 ? picture : Asobi.nothing }
    motion = square(20).clipped_by(window).glowing(2)
    assert_equal %w[clip glow], style_of(motion.at(0))["effects"].map { _1["effect"] }
    assert_equal({ "shape" => "nothing" }, data(motion.at(1.5)))
    # A window that shrinks to size 0 still has a place: it is a clip that
    # lets nothing through, not "nothing".
    shrunk = square(20).clipped_by(circle(8).pulse(to: 0)).at(0.5)
    assert_equal "clip", style_of(shrunk)["effects"].first["effect"]
  end

  def test_a_moved_group_moves_its_effects
    style = style_of(circle(5).repeat(2).in_row.shadowed(down: 2).scale(2))
    shadow, = style["effects"]
    assert_equal [4.0, 6.0], shadow.values_at("down", "blur")
  end

  # --- the page ----------------------------------------------------------------

  def test_page
    page = Asobi::Drawing.of(circle(10), on: :black, grain: true)
    assert_equal [-12.0, -12.0, 24.0, 24.0], page["view"]
    assert_equal "black", page["background"]
    assert_in_delta 0.12, page["grain"]
    assert_nil page["paper"]
    assert_equal %w[round round], page.values_at("line_join", "line_cap")
    assert_equal({ "fill" => "black", "stroke" => "none", "stroke_width" => 1.0, "opacity" => 1.0 }, page["defaults"])
    assert_equal({ "shape" => "circle", "r" => 10.0 }, page["picture"])

    clear = Asobi::Drawing.of(circle, on: nil, paper: [80, 40], grain: 0.3)
    assert_nil clear["background"]
    assert_equal [80.0, 40.0], clear["paper"]
    assert_equal [-40.0, -20.0, 80.0, 40.0], clear["view"]
    assert_in_delta 0.3, clear["grain"]
    assert_nil Asobi::Drawing.of(circle)["grain"]
    assert_raises(TypeError) { Asobi::Drawing.of(circle.spin) } # a motion: one moment at a time
  end

  def test_view_and_page_rules_are_the_svg_ones
    assert_equal Asobi::SVG.view(circle(10)), Asobi::Drawing.view(circle(10))
    assert_equal Asobi::SVG.grain_strength(true), Asobi::Drawing.grain_strength(true)
    assert_equal Asobi::SVG.paper_size([3, 4]), Asobi::Drawing.paper_size([3, 4])
  end

  # --- the data form -------------------------------------------------------------

  def everything
    sheet = petal.repeat(6).in_fan.colored(from: :gold, to: :crimson, angle: 30)
    clipped = square(20).colored(from: :white, to: :navy, around: true).clipped_by(heart(16)).shadowed
    words = text("asobi <&>", font: "serif").rotate(10).stroke(:black, width: 0.5).opacity(0.7)
    [[sheet, clipped, words], [circle.blurred.blended(:multiply), ring.glowing(color: :gold), space, line(9)]].to_art
  end

  def test_json_round_trip
    page = Asobi::Drawing.of(everything, on: :ivory, grain: true)
    assert_equal page, JSON.parse(JSON.generate(page))
  end

  def test_only_plain_values
    walk = lambda do |value|
      case value
      when Hash then value.each { |k, v| assert_kind_of String, k; walk.(v) }
      when Array then value.each { walk.(_1) }
      else assert([String, Integer, Float, TrueClass, FalseClass, NilClass].any? { value.is_a?(_1) }, value.inspect)
      end
    end
    walk.(Asobi::Drawing.of(everything))
  end

  # No SVG in the drawing: no markup, no references, no SVG words.
  def test_no_markup_in_the_drawing
    json = JSON.generate(Asobi::Drawing.of(everything, grain: true))
    %w[url( translate( matrix( viewBox stdDeviation feGaussian <defs <g <path <filter <mask asobi-].each do |svg_word|
      refute_includes json, svg_word
    end
    strings = json.scan(/"((?:[^"\\]|\\.)*)"/).flatten
    markup = strings.grep(/<\w|\/>/) - ["asobi <&>"] # the words written in the picture itself
    assert_empty markup
  end

  # A reacting part says what it sounds next to who turns it: a named
  # sound or a MIDI note, never both, nothing when it is silent.
  def test_a_reacting_part_carries_its_sound_in_the_data_form
    pulse = circle(radius: 2).pulse(every: 0.1)
    page = Asobi::Drawing.of([pulse.when_clicked.sounding(:snare), pulse.when_pressed("x").sounding(:db4),
                              pulse.while_hovered].to_art)
    reacting = JSON.generate(page).scan(/"reacting":(\{[^}]*\})/).flatten.map { JSON.parse(_1) }
    assert_equal [{ "turn" => "click", "sound" => "snare" }, { "turn" => "key", "key" => "x", "note" => 61 },
                  { "turn" => "hover" }], reacting
    assert_equal page, JSON.parse(JSON.generate(page))
  end

  # The data form is made while a reel is built too, and a part shared by
  # many frames is recorded once.
  def test_data_is_remembered_during_a_build
    pic = circle.glowing
    refute_same data(pic), data(pic)
    Asobi::Memo.during { assert_same data(pic), data(pic) }
  end

  # --- one definition of the rules -------------------------------------------------

  def test_svg_follows_the_drawing
    pic = everything
    assert_equal Asobi::SVG.fragment(pic), pic.svg
    refute Asobi::Circle.instance_methods(false).include?(:svg), "pictures do not write SVG themselves"
    refute Asobi::Many.instance_methods(false).include?(:svg)
    assert_equal Asobi::Art, Asobi::Circle.instance_method(:svg).owner
  end
end
