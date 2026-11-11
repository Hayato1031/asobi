# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class MotionTest < Minitest::Test
  WORDS = {
    spin: ->(a) { a.spin }, pulse: ->(a) { a.pulse }, sway: ->(a) { a.sway }, orbit: ->(a) { a.orbit },
    fade: ->(a) { a.fade }, bounce: ->(a) { a.bounce }, drift: ->(a) { a.drift },
    shift_color: ->(a) { a.shift_color }, animate: ->(a) { a.animate { |pic, t| pic.rotate(t * 360) } }
  }.freeze

  # Answer +value+ from Asobi::Motion.reel while the block runs.
  def with_reel(value)
    original = Asobi::Motion.method(:reel)
    Asobi::Motion.define_singleton_method(:reel) { value }
    yield
  ensure
    Asobi::Motion.define_singleton_method(:reel, original)
  end

  def flower = ellipse(width: 12, height: 32).move(up: 22).repeat(8).in_fan
  def box_of(node) = node.box(Asobi::IDENTITY)

  # --- the Motion itself ---------------------------------------------------

  def test_motion_new_and_asobi_motion
    m = Asobi::Motion.new(2) { |s| circle.rotate(s * 10) }
    assert_equal 2.0, m.every
    assert_instance_of Float, m.every
    assert_equal circle.rotate(5), m.at(0.5)
    assert_kind_of Asobi::Node, m.at(1)
    assert_equal 1.0, Asobi.motion { circle }.every
    assert_equal "#<Asobi::Motion every 2s>", m.inspect
    assert_equal "#<Asobi::Motion every 0.5s>", circle.pulse(0.5).inspect
  end

  def test_block_may_answer_anything_with_to_art_or_a_motion
    assert_equal circle(3), Asobi.motion(1) { 3 }.at(0.2)
    assert_kind_of Asobi::Many, Asobi.motion(1) { [1, 2] }.at(0.2)
    m = Asobi.motion(1) { circle.spin }
    assert_equal circle.rotate(90), m.at(1)
  end

  def test_at_is_pure
    m = flower.spin.pulse.sway.colored(:crimson).repeat(3).in_row
    a = m.at(0.7)
    m.at(3.1)
    m.at(0.1)
    assert_equal a, m.at(0.7)
    assert_equal m.at(0.1), m.at(0.1)
  end

  def test_frames_are_lazy_and_one_loop
    calls = 0
    m = Asobi.motion(2) { |s| calls += 1; circle.move(right: s) }
    frames = m.frames(fps: 10)
    assert_instance_of Enumerator::Lazy, frames
    assert_equal 0, calls
    assert_equal 20, frames.to_a.size
    assert_equal 20, calls
    assert_equal m.at(0), frames.first
    assert_equal 30, circle.spin(every: 1).frames.count
    assert_equal 1, circle.spin(every: 0.01).frames(fps: 30).count
  end

  # --- each word: default, effect, loop ------------------------------------

  def test_defaults
    assert_equal 4.0, circle.spin.every
    assert_equal 1.0, circle.pulse.every
    assert_equal 2.0, circle.sway.every
    assert_equal 4.0, circle.orbit.every
    assert_equal 2.0, circle.fade.every
    assert_equal 1.0, circle.bounce.every
    assert_equal 4.0, circle.drift.every
    assert_equal 4.0, circle.shift_color.every
    assert_equal 4.0, circle.animate { |pic, _t| pic }.every
  end

  def test_every_word_loops_seamlessly
    WORDS.each do |name, word|
      [square, flower, square.spin(every: 3)].each do |picture|
        m = word.call(picture)
        assert_equal m.at(0), m.at(m.every), "#{name} at 0 and at every"
        assert_equal m.at(0.3).svg, m.at(0.3 + 2 * m.every).svg, "#{name} repeats"
      end
    end
  end

  def test_spin
    s = square.spin
    assert_equal square, s.at(0)
    assert_equal square.rotate(90), s.at(1)
    assert_equal square.rotate(180), s.at(2)
    assert_equal square.rotate(-90), square.spin(every: 4, clockwise: false).at(1)
    assert_equal square.rotate(45), square.spin(8).at(1)
  end

  def test_pulse
    p = square.pulse
    assert_equal square, p.at(0)
    assert_close 24.0, p.at(0.5).width
    assert_close 30.0, square.pulse(every: 2, to: 1.5).at(1).width
    assert_operator p.at(0.25).width, :>, 20
  end

  def test_sway
    s = square.sway
    assert_equal square, s.at(0)
    assert_equal square.rotate(10).bounds, s.at(0.5).bounds
    assert_equal square.rotate(-10).bounds, s.at(1.5).bounds
    assert_equal square.rotate(25).bounds, square.sway(by: 25).at(0.5).bounds
  end

  def test_orbit
    o = circle.orbit
    assert_equal circle.move(up: 20), o.at(0)
    assert_box box_of(o.at(1)), 10, -10, 30, 10
    assert_box box_of(circle.orbit(50).at(2)), -10, 40, 10, 60
  end

  def test_fade
    f = circle.fade
    assert_equal circle, f.at(0)
    assert_equal circle.opacity(0.2), f.at(1)
    assert_equal circle.opacity(0.5), circle.fade(to: 0.5).at(1)
    # it multiplies an opacity already there
    assert_equal circle.opacity(0.1), circle.opacity(0.5).fade.at(1)
  end

  def test_bounce
    b = circle.bounce
    assert_equal circle, b.at(0)
    assert_equal circle.move(up: 20), b.at(0.5)
    assert_equal circle.move(up: 30), circle.bounce(30, every: 2).at(1)
    # fast near the ground, slow at the top
    near_ground = b.at(0.1).bounds.cy - b.at(0).bounds.cy
    near_top = b.at(0.5).bounds.cy - b.at(0.4).bounds.cy
    assert_operator near_ground.abs, :>, near_top.abs * 3
  end

  def test_drift
    d = square.drift
    assert_equal square, d.at(0)
    assert_equal square.move(right: 20), d.at(2)
    assert_equal square.move(left: 30, up: 10), square.drift(left: 30, up: 10).at(2)
    assert_equal square.move(right: 15), square.drift(15).at(2)
    assert_equal square, square.drift(right: 0).at(2)
  end

  def test_shift_color
    s = circle.shift_color
    assert_equal circle.colored("#000000"), s.at(0)
    assert_equal circle.colored("#dc143c"), s.at(2)
    assert_equal circle.colored("#ffd700"), circle.shift_color(:gold).at(2)
    assert_equal circle.colored("#000080"), circle.shift_color(:navy, :gold).at(0)
    assert_equal circle.colored("#ffd700"), circle.shift_color(from: :navy, to: :gold, every: 2).at(1)
  end

  def test_animate
    a = star.animate(2) { |pic, t| pic.rotate(t * 360) }
    assert_equal 2.0, a.every
    assert_equal star.rotate(90), a.at(0.5)
    seen = []
    circle.animate(4) { |pic, t| seen << t; pic }.frames(fps: 1).to_a
    assert_equal [0.0, 0.25, 0.5, 0.75], seen
    assert_equal circle.spin.at(1), circle.animate { |pic, _t| pic.spin }.at(1)
  end

  # --- lifting the picture words -------------------------------------------

  def test_every_picture_word_on_a_motion
    m = circle.spin(every: 4)
    t = 1
    base = m.at(t)
    {
      ->(x) { x.move(right: 5, up: 2) } => nil, ->(x) { x.rotate(30) } => nil, ->(x) { x.scale(2) } => nil,
      ->(x) { x.scale(width: 2, height: 1) } => nil, ->(x) { x.grow(to: 3) } => nil, ->(x) { x.shrink } => nil,
      ->(x) { x.mirror } => nil, ->(x) { x.flip } => nil, ->(x) { x.colored(:crimson) } => nil,
      ->(x) { x.outlined(:navy, width: 2) } => nil, ->(x) { x.stroke(:red) } => nil, ->(x) { x.opacity(0.3) } => nil,
      ->(x) { x.repeat(3) } => nil, ->(x) { x * 4 } => nil
    }.each_key do |word|
      lifted = word.call(m)
      assert_instance_of Asobi::Motion, lifted
      assert_equal word.call(base), lifted.at(t)
    end
  end

  def test_every_many_word_on_a_motion
    m = circle(3).repeat(6).spin
    base = m.at(1)
    words = [
      ->(x) { x.in_row(gap: 2) }, ->(x) { x.in_column(2) }, ->(x) { x.in_grid(columns: 3) },
      ->(x) { x.in_ring(40) }, ->(x) { x.in_fan(over: 90) }, ->(x) { x.in_spiral },
      ->(x) { x.scattered(seed: 7) }, ->(x) { x.change_each { |one, t| one.grow(to: 1 + t) } },
      ->(x) { x.colored(:red, :blue) }
    ]
    words.each do |word|
      lifted = word.call(m)
      assert_instance_of Asobi::Motion, lifted
      assert_equal word.call(base), lifted.at(1)
    end
  end

  def test_many_words_on_a_single_picture_motion
    m = circle.spin
    assert_equal circle.rotate(90).in_ring, m.in_ring.at(1)
    assert_instance_of Asobi::Many, m.in_grid.at(1)
    assert_equal circle.rotate(90).change_each { |one| one.grow }, m.change_each { |one| one.grow }.at(1)
    assert_equal 1, m.scattered.at(2).size
  end

  def test_the_design_example
    m = flower.spin(every: 8).pulse(every: 1).colored(:crimson).repeat(6).in_ring
    assert_equal 8.0, m.every
    expected = flower.rotate(112.5).scale(1.2).colored(:crimson).repeat(6).in_ring
    assert_equal expected.svg, m.at(2.5).svg # spin 2.5/8 of a turn, pulse halfway
  end

  # --- combining motions ---------------------------------------------------

  def test_motion_of_motion_and_lcm
    assert_equal 4.0, circle.spin(every: 4).pulse(every: 1).every
    assert_equal 6.0, circle.spin(every: 2).pulse(every: 3).every
    assert_equal 3.0, circle.spin(every: 1.5).pulse(every: 1).every
    assert_equal 1.0, circle.spin(every: 1.0 / 3).pulse(every: 0.5).every
    assert_close 0.3, circle.spin(every: 0.1).pulse(every: 0.3).every
    assert_equal 11.0, circle.spin(every: 7).pulse(every: 11).every
    assert_equal 59.0, circle.spin(every: 59).pulse(every: 1).every
    assert_equal 12.0, circle.spin(every: 3).on(square.pulse(every: 4)).every
  end

  def test_combined_loops_seamlessly
    m = square.spin(every: 0.1).pulse(every: 0.3).on(circle.sway(every: 0.2))
    assert_close 0.6, m.every
    assert_equal m.at(0), m.at(m.every)
  end

  def test_mixing_pictures_and_motions_both_ways
    dot = circle(4)
    moving = dot.pulse
    ring_ = ring
    t = 0.5
    pairs = {
      on: [ring_.on(moving), ring_.on(moving.at(t)), moving.on(ring_), moving.at(t).on(ring_)],
      under: [ring_.under(moving), ring_.under(moving.at(t)), moving.under(ring_), moving.at(t).under(ring_)],
      plus: [ring_ + moving, ring_ + moving.at(t), moving + ring_, moving.at(t) + ring_],
      beside: [ring_.beside(moving, gap: 3), ring_.beside(moving.at(t), gap: 3),
               moving.beside(ring_), moving.at(t).beside(ring_)],
      above: [ring_.above(moving), ring_.above(moving.at(t)), moving.above(ring_, gap: 2),
              moving.at(t).above(ring_, gap: 2)]
    }
    pairs.each do |name, (a, a_still, b, b_still)|
      assert_instance_of Asobi::Motion, a, name
      assert_instance_of Asobi::Motion, b, name
      assert_equal a_still, a.at(t), name
      assert_equal b_still, b.at(t), name
    end
    both = circle.spin.beside(square.pulse)
    assert_equal circle.rotate(90).beside(square), both.at(1)
  end

  def test_arrays_ranges_and_hashes_with_motions
    m = circle.spin
    list = [square, m].to_art
    assert_instance_of Asobi::Motion, list
    assert_equal [square, circle.rotate(90)].to_art, list.at(1)

    nested = [[1, m], [m.pulse, 2]].to_art
    assert_instance_of Asobi::Motion, nested
    assert_equal [[1, m.at(0.5)], [m.pulse.at(0.5), 2]].to_art, nested.at(0.5)

    table = { m => "spin", "dot" => circle.pulse }.to_art
    assert_instance_of Asobi::Motion, table
    assert_equal({ m.at(0.5) => "spin", "dot" => circle.pulse.at(0.5) }.to_art, table.at(0.5))

    assert_equal 4.0, Asobi.art([1, [2, m]]).every
    assert_equal [1, 2].to_art, Asobi.art([1, 2]) # still pictures stay pictures
  end

  def test_as_may_be_a_motion
    m = [1, 2].to_art(as: star.spin)
    assert_instance_of Asobi::Motion, m
    assert_equal [1, 2].to_art(as: star.rotate(90)), m.at(1)
    assert_equal 8.to_art(as: star.rotate(90)), 8.to_art(as: star.spin).at(1)
  end

  class Planet
    def to_art = Asobi.circle(5).orbit(radius: 30)
  end

  class Pet
    include Asobi::Art
    def to_art = Asobi.square(4).spin
  end

  def test_a_class_whose_to_art_is_a_motion
    planet = Planet.new
    sun = circle(10).on(planet)
    assert_instance_of Asobi::Motion, sun
    assert_equal circle(10).on(circle(5).move(right: 30)), sun.at(1)
    assert_instance_of Asobi::Motion, [planet, planet].to_art
    assert_instance_of Asobi::Motion, planet.to_art.colored(:gold)
    assert_instance_of Asobi::Motion, Asobi.art(planet)

    pet = Pet.new
    assert_equal square(4).rotate(90).move(up: 3), pet.move(up: 3).at(1)
    assert_equal square(4).rotate(45).scale(1.2).svg, pet.pulse.at(0.5).svg
  end

  # --- one_by_one ----------------------------------------------------------

  def test_one_by_one_makes_a_wave
    dots = circle(3).repeat(12).in_ring
    wave = dots.pulse(every: 1).one_by_one
    assert_equal 1.0, wave.every
    frame = wave.at(0.25)
    assert_operator frame.items.map { _1.width.round(9) }.uniq.size, :>=, 6
    # item i is the plain pulse, i twelfths of a second late
    # item i is pulsed around its own centre, i twelfths of a second late
    dots.items.each_with_index do |dot, i|
      c = dot.bounds
      expected = circle(3).pulse(every: 1).at(0.25 - i / 12.0).move(right: c.cx, down: c.cy)
      assert_equal expected.svg, frame.items[i].svg
    end
    assert_equal wave.at(0), wave.at(1)
  end

  def centres(node) = node.items.map { |item| [item.bounds.cx.round(9), item.bounds.cy.round(9)] }

  def test_one_by_one_turns_and_grows_each_in_place
    ring_ = circle(4).repeat(12).in_ring(radius: 30)
    squares = square(6).repeat(8).in_ring(radius: 30)
    rest = centres(ring_)
    square_rest = centres(squares)
    [0, 0.13, 0.25, 0.5, 0.71, 0.9].each do |t|
      assert_equal rest, centres(ring_.pulse(every: 1, to: 1.8).one_by_one.at(t)), "pulse at #{t}"
      assert_equal square_rest, centres(squares.spin(every: 1).one_by_one.at(t)), "spin at #{t}"
      assert_equal square_rest, centres(squares.sway(every: 1, by: 30).one_by_one.at(t)), "sway at #{t}"
    end
    # each dot really grows: at its peak a dot is 1.8 times as wide
    sizes = ring_.pulse(every: 1, to: 1.8).one_by_one.at(0.5).items.map { _1.width.round(6) }
    assert_includes sizes, (8 * 1.8).round(6)
    # spin in place: a square a quarter of the way round is turned 90 degrees where it stands
    first = squares.items.first
    turned = squares.spin(every: 1).one_by_one.at(0.25).items.first
    assert_equal first.bounds, turned.bounds
  end

  def test_without_one_by_one_the_group_moves_as_a_whole
    ring_ = circle(4).repeat(12).in_ring(radius: 30)
    assert_equal ring_.scale(1.8), ring_.pulse(every: 1, to: 1.8).at(0.5)
    assert_equal ring_.rotate(90), ring_.spin(every: 4).at(1)
    refute_equal centres(ring_), centres(ring_.pulse(every: 1, to: 1.8).at(0.5))
  end

  def test_one_by_one_leaves_moving_and_colouring_words_alone
    dots = circle(3).repeat(5).in_row(gap: 4)
    { bounce: ->(x) { x.bounce }, drift: ->(x) { x.drift(right: 10) }, orbit: ->(x) { x.orbit(20) },
      fade: ->(x) { x.fade }, shift_color: ->(x) { x.shift_color(:gold) } }.each do |name, word|
      staggered = word.call(dots).one_by_one.at(0.3)
      dots.items.each_with_index do |dot, i|
        late = 0.3 - i * word.call(dots).every / 5
        assert_equal word.call(dot).at(late).svg, staggered.items[i].svg, "#{name} item #{i}"
      end
    end
  end

  def test_one_by_one_gap
    dots = square.repeat(3)
    s = dots.spin(every: 4).one_by_one(gap: 1)
    assert_equal [square.rotate(90), square, square.rotate(-90)], s.at(1).items
    assert_equal s.at(1).items, dots.spin.one_by_one(1).at(1).items
  end

  def test_one_by_one_on_a_single_picture_changes_nothing
    plain = square.pulse
    staggered = square.pulse.one_by_one
    [0, 0.2, 0.5, 0.9].each { |t| assert_equal plain.at(t), staggered.at(t) }
  end

  def test_one_by_one_after_chained_words
    dots = circle(3).repeat(6)
    chained = dots.pulse.colored(:red).in_ring.one_by_one
    expected = dots.pulse.one_by_one.colored(:red).in_ring
    assert_equal expected.at(0.3), chained.at(0.3)
    refute_equal dots.pulse.colored(:red).in_ring.at(0.3), chained.at(0.3)
    # the last motion word is the one staggered
    late = dots.spin.pulse.one_by_one.at(0.5).items
    assert_equal dots.spin.at(0.5).items.map(&:width).uniq.size, 1
    assert_operator late.map(&:width).uniq.size, :>, 1
    # mixed with a still picture, it still finds the word
    mixed = ring.on(dots.in_ring.pulse).one_by_one
    assert_instance_of Asobi::Motion, mixed
  end

  def test_one_by_one_without_a_motion_word
    error = assert_raises(ArgumentError) { circle.repeat(3).colored(:red).one_by_one }
    assert_includes error.message, "pulse(every: 1).one_by_one"
    assert_raises(ArgumentError) { Asobi.motion { circle }.one_by_one }
    assert_raises(ArgumentError) { circle.repeat(3).pulse.one_by_one.one_by_one }
    assert_raises(ArgumentError) { circle.spin.on(square.pulse).one_by_one } # two words: which one?
    in_language(:ja) do
      assert_includes assert_raises(ArgumentError) { circle.one_by_one }.message, "直後"
    end
  end

  # --- randomness ----------------------------------------------------------

  def test_scatter_before_the_motion_happens_once
    Asobi::Random.reset_calls!
    stars = star.repeat(20).scattered
    m = stars.spin
    calls = Asobi::Random.calls
    m.frames(fps: 5).to_a
    assert_equal calls, Asobi::Random.calls, "sampling must not move the counter"
    assert_equal stars, m.at(0)
    assert_equal stars.rotate(90), m.at(1)
  end

  def test_scatter_after_the_motion_is_stable_every_frame
    m = circle(3).repeat(20).spin.scattered
    centres = ->(node) { node.items.map { |s| [s.bounds.cx.round(6), s.bounds.cy.round(6)] } }
    assert_equal centres.(m.at(0)), centres.(m.at(1.3))
    assert_equal centres.(m.at(0)), centres.(m.at(3.7))
    assert_equal m.at(2), m.at(2)
    assert_equal m.at(0), m.at(4)
  end

  def test_scatter_inside_a_block_is_stable
    m = Asobi.motion(2) { |s| circle(2).repeat(10).scattered.rotate(s * 10) }
    assert_equal m.at(0.5), m.at(0.5)
    assert_equal m.at(0), m.at(0.0)
  end

  def test_same_sketch_same_motion_after_reset
    Asobi::Random.reset_calls!
    a = star.repeat(10).spin.scattered.at(1)
    Asobi::Random.reset_calls!
    b = star.repeat(10).spin.scattered.at(1)
    assert_equal a, b
  end

  # --- errors --------------------------------------------------------------

  def test_asobi_art_of_a_motion_teaches_at
    error = assert_raises(TypeError) { Asobi.art(circle.spin) }
    assert_includes error.message, "at(0)"
    assert_includes error.message, "in motion"
    assert_raises(TypeError) { circle.spin.to_svg }
    in_language(:ja) do
      message = assert_raises(TypeError) { Asobi.art(circle.spin) }.message
      assert_includes message, "動いている絵"
      assert_includes message, "at(0)"
    end
  end

  def test_bad_numbers_teach
    assert_includes assert_raises(ArgumentError) { circle.spin(every: 0) }.message, "spin(every: 4)"
    assert_raises(ArgumentError) { circle.spin(every: -1) }
    assert_raises(TypeError) { circle.pulse(to: "big") }
    assert_raises(ArgumentError) { circle.fade(to: 2) }
    assert_raises(TypeError) { circle.drift(right: :far) }
    assert_raises(ArgumentError) { circle.shift_color(:not_a_colour) }
    assert_raises(ArgumentError) { Asobi::Motion.new(0) { circle } }
    assert_raises(TypeError) { circle.spin.at("now") }
    assert_raises(ArgumentError) { circle.spin.frames(fps: 0) }
    assert_raises(ArgumentError) { circle.spin.one_by_one(gap: -1) }
    in_language(:ja) do
      assert_includes assert_raises(ArgumentError) { circle.spin(every: 0) }.message, "0 より大きい"
    end
  end

  def test_blocks_are_asked_for
    assert_includes assert_raises(ArgumentError) { Asobi::Motion.new(2) }.message, "Asobi.motion(2)"
    assert_includes assert_raises(ArgumentError) { circle.animate(2) }.message, "animate(4)"
    in_language(:ja) { assert_includes assert_raises(ArgumentError) { Asobi.motion }.message, "ブロック" }
  end

  def test_save_goes_to_the_reel
    calls = []
    fake = Object.new
    fake.define_singleton_method(:save) { |thing, path, **options| calls << [thing, path, options]; path }
    m = circle.spin
    with_reel(fake) { m.save("spin.html", fps: 12) }
    assert_equal [[m, "spin.html", { fps: 12 }]], calls

    with_reel(nil) do
      error = assert_raises(NameError) { m.save("spin.html") }
      assert_includes error.message, "at(0).save"
      in_language(:ja) { assert_includes assert_raises(NameError) { m.save("x.html") }.message, "Reel" }
    end
  end

  # --- measuring -----------------------------------------------------------

  def test_bounds_cover_the_whole_loop
    assert_box circle.orbit(radius: 30).bounds, -40, -40, 40, 40, 0.5
    assert_close 24.0, square.pulse.width, 0.01
    assert_equal 10.0, circle(5).orbit.at(1).bounds.cx # radius twice the size (5): the larger side
    assert_close 20.0, circle(5).drift.width, 0.01
  end

  def test_still_pictures_are_unchanged
    assert_instance_of Asobi::Many, circle.on(square)
    assert_instance_of Asobi::Many, [1, 2, 3].to_art
    assert_instance_of Asobi::Transformed, circle.move(up: 2)
  end

  # --- pure mode -----------------------------------------------------------

  def test_pure_mode_has_motion_and_leaves_ruby_alone
    lib = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      require "asobi/pure"
      raise "Integer changed" if 1.respond_to?(:to_art)
      raise "Array changed" if [].respond_to?(:to_art)
      raise "Object changed" if Object.private_method_defined?(:circle)
      m = Asobi.circle.spin.pulse
      raise "motion" unless m.is_a?(Asobi::Motion) && m.every == 4.0
      raise "array" unless Asobi.art([1, m]).is_a?(Asobi::Motion)
      raise "at" unless m.at(1) == Asobi.circle.rotate(90)
      print "ok"
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)
    assert status.success?, err
    assert_equal "ok", out
  end
end
