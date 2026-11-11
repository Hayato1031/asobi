# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class EffectsTest < Minitest::Test
  def flower = petal.repeat(8).in_fan
  def ids(svg) = svg.scan(/ id="([^"]+)"/).flatten

  # --- defaults and shorthand ------------------------------------------------

  def test_glowing
    assert_equal({ glow: { size: 4.0, color: nil } }, circle.glowing.style[:effects])
    assert_equal circle.glowing(size: 8), circle.glowing(8)
    assert_equal({ size: 8.0, color: "gold" }, circle.glowing(8, color: :gold).style[:effects][:glow])
    svg = circle.glowing.svg
    assert_includes svg, %(stdDeviation="2")
    assert_includes svg, %(<g filter="url(##{ids(svg).first})">)
    refute_includes svg, "feFlood" # its own colours
    assert_includes circle.glowing(color: :gold).svg, %(flood-color="gold")
  end

  def test_blurred
    assert_equal({ blur: 2.0 }, circle.blurred.style[:effects])
    assert_equal circle.blurred(amount: 5), circle.blurred(5)
    assert_includes circle.blurred(5).svg, %(stdDeviation="5")
  end

  def test_blended
    assert_equal({ blend: "screen" }, circle.blended.style[:effects])
    %i[normal screen multiply overlay lighten darken difference].each do |mode|
      assert_equal mode.to_s, circle.blended(mode).style[:effects][:blend]
    end
    assert_includes circle.blended.svg, %(style="mix-blend-mode:screen")
    assert_includes circle.blended("Multiply").svg, "mix-blend-mode:multiply"
    refute_includes circle.blended(:normal).svg, "mix-blend-mode"
  end

  def test_bad_blend_teaches_in_both_languages
    error = assert_raises(ArgumentError) { circle.blended(:sparkly) }
    assert_includes error.message, "blended(:screen)"
    assert_includes error.message, ":multiply"
    assert_includes error.message, ":sparkly"
    assert_raises(ArgumentError) { circle.blended(3) }
    in_language(:ja) do
      message = assert_raises(ArgumentError) { circle.blended(:sparkly) }.message
      assert_includes message, "混ざり方"
      assert_includes message, "blended(:screen)"
    end
  end

  def test_shadowed
    assert_equal({ right: 0.0, down: 2.0, blur: 3.0, color: "black", opacity: 0.4 }, circle.shadowed.style[:effects][:shadow])
    assert_equal circle.shadowed(down: 5), circle.shadowed(5)
    svg = circle.shadowed(4, right: 3, color: :navy, opacity: 0.6).svg
    assert_includes svg, %(dx="3" dy="4")
    assert_includes svg, %(flood-color="navy" flood-opacity="0.6")
  end

  def test_numbers_are_checked
    assert_raises(TypeError) { circle.glowing("big") }
    assert_raises(ArgumentError) { circle.glowing(-1) }
    assert_raises(ArgumentError) { circle.blurred(-2) }
    assert_raises(ArgumentError) { circle.shadowed(opacity: 2) }
    assert_raises(ArgumentError) { circle.glowing(color: :nope) }
    assert_raises(ArgumentError) { circle.spin.trail(0) }
    assert_includes assert_raises(TypeError) { circle.glowing("big") }.message, "glowing(size: 4)"
    in_language(:ja) { assert_includes assert_raises(TypeError) { circle.blurred(:x) }.message, "blurred(amount: 2)" }
  end

  # --- values, ids, defs -----------------------------------------------------

  def test_equal_pictures_equal_svg
    make = -> { flower.colored(from: :gold, to: :crimson).glowing.shadowed.blended.clipped_by(circle(15)) }
    assert_equal make.call, make.call
    assert_equal make.call.svg, make.call.svg
    assert_equal make.call.to_svg, make.call.to_svg
  end

  def test_ids_come_from_content
    a = ids(circle.glowing(4).svg)
    assert_equal a, ids(circle.glowing(4).svg)
    refute_equal a, ids(circle.glowing(5).svg)
    refute_equal a, ids(circle.glowing(4, color: :red).svg)
    refute_equal ids(circle.blurred(2).svg), ids(circle.blurred(3).svg)
    refute_equal ids(circle.colored(from: :red, to: :blue).svg), ids(circle.colored(from: :red, to: :green).svg)
    assert(a.all? { _1.start_with?("asobi-") })
  end

  def test_many_shares_one_definition
    svg = circle(3).glowing.repeat(36).in_ring.svg
    assert_equal 1, svg.scan("<filter").size
    assert_equal 36, svg.scan(/filter="url\(#/).size
    assert_equal 1, svg.scan("<defs>").size
    assert svg.start_with?("<defs>")
  end

  def test_fragment_is_self_contained
    svg = flower.glowing.clipped_by(circle(10)).colored(from: :gold, to: :red).svg
    ids(svg).each { |id| assert_includes svg, "url(##{id})" }
    svg.scan(/url\(#([^)]+)\)/).flatten.each { |id| assert_includes ids(svg), id }
  end

  # --- combining and replacing -------------------------------------------------

  def test_same_effect_twice_replaces
    assert_equal circle.glowing(8), circle.glowing(4).glowing(8)
    assert_equal 1, circle.glowing.move(right: 5).glowing(8).svg.scan("<filter").size
    assert_equal 1, circle.blurred.blurred(3).svg.scan("<filter").size
    assert_equal({ blend: "multiply" }, circle.blended.blended(:multiply).style[:effects])
    assert_equal({ glow: { size: 4.0, color: nil }, blur: 2.0 }, circle.glowing.blurred.style[:effects])
  end

  def test_color_after_glow_still_paints_and_the_glow_follows
    g = circle.glowing.colored(:red)
    assert_includes g.svg, %(fill="red")
    refute_includes g.svg, "feFlood"
    moved = circle.colored(:blue).move(right: 5).glowing.colored(:red)
    assert_includes moved.svg, %(fill="red")
    refute_includes moved.svg, %(fill="blue")
    assert_includes moved.svg, "<filter"
  end

  def test_effects_survive_changes_and_arranging
    g = circle(3).glowing
    [g.move(right: 4), g.rotate(30), g.scale(2), g.repeat(3).in_ring, g.repeat(4).in_grid,
     g.repeat(3).change_each { |one, t| one.grow(to: 1 + t) }, g.repeat(5).scattered(seed: 1)].each do |pic|
      assert_includes pic.svg, "<filter"
    end
    many = circle(3).repeat(4).in_row.glowing
    assert_equal({ glow: { size: 4.0, color: nil } }, many.style[:effects])
    assert_equal({ glow: { size: 4.0, color: nil } }, many.in_ring.style[:effects])
    assert_equal({ glow: { size: 8.0, color: nil } }, many.scale(2).style[:effects]) # grows with the group
    shadow = circle(3).repeat(2).shadowed(2).rotate(90).style[:effects][:shadow]
    assert_in_delta(-2.0, shadow[:right])
    assert_in_delta(0.0, shadow[:down])
  end

  # --- bounds and view -------------------------------------------------------------

  def test_bounds_include_the_spill
    assert_box circle.glowing.bounds, -16, -16, 16, 16 # 1.5 * size
    assert_box circle.blurred.bounds, -16, -16, 16, 16 # 3 * amount
    assert_box circle.shadowed.bounds, -14.5, -12.5, 14.5, 16.5
    assert_box circle.glowing.scale(2).bounds, -32, -32, 32, 32
    assert_box circle(3).repeat(3).in_row.glowing.bounds, -15, -9, 15, 9
    assert_box square(20).clipped_by(circle(5).move(right: 10)).bounds, 5, -5, 10, 5
    assert_box line(20).glowing.bounds, -16.5, -6.5, 16.5, 6.5 # the line is 1 wide
  end

  def test_view_and_reel_include_the_spill
    x, y, w, = Asobi::SVG.view(circle.glowing(10))
    assert_operator x, :<, -25
    assert_operator y, :<, -25
    assert_operator w, :>, 50
    view = Asobi::Reel.of(circle.glowing(10).spin)["view"]
    assert_operator view[0], :<, -25
  end

  def test_filter_region_covers_thin_shapes
    svg = line(30).glowing.svg
    height = svg[/<filter[^>]* height="([\d.]+)"/, 1].to_f
    assert_operator height, :>=, 12
  end

  # --- gradients ---------------------------------------------------------------------

  def test_gradient_on_a_single_picture
    g = circle.colored(from: :gold, to: :crimson)
    assert_equal Asobi::Gradient.new("gold", "crimson", 0.0, false), g.style[:fill]
    svg = g.svg
    assert_includes svg, %(x1="0" y1="-10" x2="0" y2="10") # top to bottom
    assert_includes svg, %(stop-color="gold")
    assert_includes svg, 'fill="url(#'
    assert_includes circle.colored(from: :gold, to: :crimson, angle: 90).svg, %(x1="10" y1="0" x2="-10" y2="0")
    assert_includes circle.colored(from: :white, to: :navy, around: true).svg, %(<radialGradient)
    assert_equal circle.colored(from: :gold, to: :red, around: true), circle.colored(:gold, :red, around: true)
  end

  def test_gradient_defaults
    assert_equal Asobi::Gradient.new("crimson", "navy", 0.0, false), circle.colored(to: :navy).style[:fill]
    assert_equal Asobi::Gradient.new("gold", "navy", 0.0, false), circle.colored(from: :gold).style[:fill]
    assert_equal Asobi::Gradient.new("crimson", "navy", 45.0, false), circle.colored(angle: 45).style[:fill]
    assert_equal ["crimson"], [circle.colored.style[:fill]] # plain colored is unchanged
    assert_raises(ArgumentError) { circle.colored(from: :nope) }
    assert_raises(TypeError) { circle.colored(from: :red, angle: "up") }
  end

  def test_gradient_on_a_many_flows_once
    g = flower.colored(from: :gold, to: :crimson)
    svg = g.svg
    assert_equal 1, svg.scan("<linearGradient").size
    assert_includes svg, "<mask"
    assert_includes svg, %(<rect )
    b = flower.bounds
    assert_includes svg, %(y1="#{Asobi.fmt(b.y0)}" x2="#{Asobi.fmt(b.cx)}" y2="#{Asobi.fmt(b.y1)}")
    arranged = circle(3).repeat(6).colored(from: :gold, to: :red).in_row(gap: 2)
    assert_includes arranged.svg, %(x1="0" y1="-3")
  end

  def test_gradient_travels_with_the_picture
    turned = circle.colored(from: :gold, to: :crimson).rotate(90)
    assert_equal circle.colored(from: :gold, to: :crimson), turned.art
    many = circle(3).repeat(3).in_row.colored(from: :gold, to: :red).rotate(90)
    assert_equal 90.0, many.style[:fill].angle
    flipped = circle(3).repeat(2).in_row.colored(from: :gold, to: :red).flip
    assert_equal 180.0, flipped.style[:fill].angle
    # painting a turned picture keeps the direction as seen from outside
    painted = square.rotate(90).colored(from: :gold, to: :red)
    assert_equal 270.0, painted.art.style[:fill].angle
  end

  def test_gradient_on_a_line
    svg = line(20).colored(from: :gold, to: :red).svg
    assert_includes svg, 'stroke="url(#'
    assert_includes svg, %(x1="-10" y1="0" x2="10" y2="0") # flat line: along the line
  end

  # --- clipped_by --------------------------------------------------------------------

  class Window
    def to_art = Asobi.square(10)
  end

  def test_clipped_by
    c = square(20).clipped_by(circle(5))
    assert_equal circle(5), c.style[:effects][:clip]
    assert_includes c.svg, "<mask"
    assert_includes c.svg, 'mask="url(#'
    assert_equal square(10), square(20).clipped_by(Window.new).style[:effects][:clip]
    assert_equal square(20).clipped_by(circle(8)), square(20).clipped_by(8)
    assert_includes square(20).clipped_by.svg, "<mask" # a round window by default
    assert_box square(20).clipped_by.bounds, -8, -8, 8, 8
  end

  def test_clipped_by_with_motions
    a = square(20).clipped_by(circle(5).orbit(5))
    assert_instance_of Asobi::Motion, a
    assert_equal square(20).clipped_by(circle(5).move(up: 5)), a.at(0)
    b = square(20).spin.clipped_by(circle(5))
    assert_instance_of Asobi::Motion, b
    assert_equal square(20).rotate(90).clipped_by(circle(5)), b.at(1)
  end

  # --- motions ---------------------------------------------------------------------

  def test_every_effect_word_lifts_onto_a_motion
    m = flower.spin
    words = [->(x) { x.glowing(6) }, ->(x) { x.blurred }, ->(x) { x.blended(:multiply) }, ->(x) { x.shadowed },
             ->(x) { x.clipped_by(circle(10)) }, ->(x) { x.colored(from: :gold, to: :red, around: true) }]
    words.each do |word|
      lifted = word.call(m)
      assert_instance_of Asobi::Motion, lifted
      assert_equal word.call(m.at(1)), lifted.at(1)
    end
  end

  def test_trail
    m = square.spin
    t = m.trail
    assert_instance_of Asobi::Motion, t
    assert_equal m.every, t.every
    frame = t.at(1)
    assert_equal 6, frame.size
    assert_equal m.at(1), frame.items.last
    opacities = frame.items.first(5).map { _1.art.style[:opacity] }
    assert_equal opacities.sort, opacities # oldest is faintest, drawn first
    assert_in_delta 0.1, opacities.first
    assert_in_delta 0.5, opacities.last
    assert_equal m.at(1 - 0.05).opacity(0.5), frame.items[4]
    assert_equal t.at(0), t.at(t.every)
    assert_equal 9, m.trail(8).at(0).size
    assert_equal m.at(1 - 0.2).opacity(0.5), m.trail(count: 2, gap: 0.2).at(1).items[1]
  end

  def test_trail_on_a_still_picture_changes_nothing
    pic = flower.colored(:red)
    assert_same pic, pic.trail
    assert_same pic, pic.trail(10, gap: 1)
  end

  def test_trail_composes
    m = flower.spin.trail.glowing.blended(:screen)
    assert_instance_of Asobi::Motion, m
    svg = m.at(0.5).svg
    assert_includes svg, "mix-blend-mode:screen"
    assert_includes svg, "<filter"
    assert_equal m.at(0), m.at(m.every)
    wave = circle(3).repeat(6).in_ring.pulse.trail(3).one_by_one
    assert_instance_of Asobi::Motion, wave
    assert_equal 4, wave.at(0.3).size
    assert_equal 6, circle(3).repeat(6).in_ring.pulse.trail(2).at(0.3).items.last.size
  end

  def test_trail_keeps_its_own_fade
    t = circle.opacity(0.5).spin.trail(1).at(1)
    assert_in_delta 0.25, t.items.first.art.style[:opacity]
  end

  # --- grain -------------------------------------------------------------------------

  def test_grain_in_svg_documents
    plain = circle.to_svg
    grained = circle.to_svg(grain: true)
    assert_includes grained, "feTurbulence"
    assert_includes grained, "0.48 0 0 0 -0.24" # true is 0.12
    assert_includes circle.to_svg(grain: 0.3), "1.2 0 0 0 -0.6"
    refute_includes circle.to_svg(grain: false), "feTurbulence"
    refute_includes circle.to_svg(grain: 0), "feTurbulence"
    assert_operator grained.index("<circle"), :<, grained.index("feTurbulence") # on top
    refute_includes plain, "feTurbulence"
    assert_raises(ArgumentError) { circle.to_svg(grain: 2) }
    assert_raises(TypeError) { circle.to_svg(grain: "lots") }
    Dir.mktmpdir do |dir|
      path = File.join(dir, "g.svg")
      circle.save(path, grain: true)
      assert_includes File.read(path), "feTurbulence"
    end
  end

  def test_grain_in_reels_is_the_same_on_every_frame
    reel = Asobi::Reel.of(flower.spin, grain: true, fps: 10)
    noise = reel["frames"].map { _1[/<defs><filter[^>]*><feTurbulence.*\z/] }
    assert_equal 1, noise.uniq.size
    refute_nil noise.first
    assert_operator noise.first.bytesize, :<, 600
    assert_includes Asobi::Reel.html(circle, grain: 0.2), "feTurbulence"
    still = Asobi::Reel.of(circle, grain: true)
    assert_includes still["frames"].first, "feTurbulence"
  end

  def test_show_carries_grain
    ENV["ASOBI_LIVE"] = "0"
    Asobi::Sketch.forget
    show circle, grain: true
    assert_equal true, Asobi::Sketch.shown.grain
    assert_includes Asobi::Sketch.reel["frames"].first, "feTurbulence"
    reel = Asobi::Sketch.run("show circle.spin, on: :black, grain: 0.3\n")
    assert_nil reel["error"]
    assert(reel["frames"].all? { _1.include?("1.2 0 0 0 -0.6") })
    show circle
    assert_nil Asobi::Sketch.shown.grain
    assert_raises(ArgumentError) { show circle, grain: 5 }
  ensure
    Asobi::Sketch.forget
  end

  # --- pure mode ---------------------------------------------------------------------

  def test_pure_mode_has_the_effects_and_leaves_ruby_alone
    lib = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      require "asobi/pure"
      raise "Integer changed" if 1.respond_to?(:to_art)
      raise "Object changed" if Object.private_method_defined?(:circle)
      pic = Asobi.circle.glowing.blurred.shadowed.blended.clipped_by(Asobi.square).colored(from: :red, to: :blue)
      raise "svg" unless pic.to_svg(grain: true).include?("feTurbulence")
      raise "trail" unless Asobi.circle.spin.trail.at(1).size == 6
      print "ok"
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)
    assert status.success?, err
    assert_equal "ok", out
  end
end
