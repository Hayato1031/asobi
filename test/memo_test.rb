# frozen_string_literal: true

require_relative "test_helper"

# Asobi::Memo: work remembered while one reel or document is built, and a
# trail that reuses earlier moments. The SVG renderer keeps the SVG it wrote
# for each picture object in the same notes (Asobi::SVG.fragment, which
# art.svg asks), so it is tested here too. The rule under test: remembering
# may make things faster, never different.
class MemoTest < Minitest::Test
  NOTES = Asobi::Memo::NOTES

  # Counts Asobi::Drawing.draw while Thread.current[:asobi_draws] is set:
  # each call is one picture object being drawn from scratch.
  module CountDraws
    def draw(node, painter)
      Thread.current[:asobi_draws] += 1 if Thread.current[:asobi_draws]
      super
    end
  end
  Asobi::Drawing.singleton_class.prepend(CountDraws)

  def draws
    Thread.current[:asobi_draws] = 0
    yield
    Thread.current[:asobi_draws]
  ensure
    Thread.current[:asobi_draws] = nil
  end

  def notes = Thread.current[NOTES]

  def teardown
    Asobi::Sketch.forget
  end

  # Frames of +motion+ as a reel builds them (with notes) ...
  def reel_frames(motion) = Asobi::Reel.of(motion)["frames"]

  # ... and the slow way: every frame worked out on its own, no notes.
  def slow_frames(motion)
    assert_nil notes
    count = (motion.every * 30).round.clamp(1, Asobi::Reel::MAX_FRAMES)
    Array.new(count) { |i| motion.at(motion.every * i / count).svg }
  end

  # Moving pictures of many kinds: staggered, scattered at every moment,
  # your own blocks, effects, gradients, a motion that is not a loop at all.
  def motions
    spark = petal(15, 1.8).move(up: 28)
    burst = spark.repeat(13).in_fan + spark.repeat(7).in_fan.scale(0.5)
    sky = burst.repeat(4).change_each { |b, _t, i| b.scale(0.75 + i % 3 * 0.3) }
               .scattered(over: [200, 100], seed: 5).colored(:gold, :cyan)
    {
      "spin" => petal.repeat(8).in_fan.colored(:deeppink, :cyan).spin(every: 4),
      "fireworks" => sky.animate(3) { |b, t| b.scale(0.05 + t**0.35).opacity(1 - t**4) }.one_by_one,
      "pulse one_by_one" => circle(3).repeat(6).in_ring.pulse.one_by_one,
      "scattered every moment" => circle(4).move(right: 10).spin(every: 2).repeat(5).scattered,
      "gradient and clip" => square(30).colored(from: :gold, to: :navy).clipped_by(circle(12)).sway,
      "words" => text("asobi").shadowed.bounce,
      "not a loop" => Asobi.motion(2) { |s| circle(3).move(right: s * 10).rotate(s * 7) }
    }
  end

  # --- the notes: when they exist, and when they are gone ------------------

  def test_no_notes_outside
    assert_nil notes
    pic = circle.glowing
    refute_same pic.svg, pic.svg
    refute_same pic.box(Asobi::IDENTITY), pic.box(Asobi::IDENTITY)
  end

  def test_inside_the_same_answer_is_handed_back
    pic = petal.repeat(5).in_fan.glowing
    Asobi::Memo.during do
      assert_same pic.svg, pic.svg
      assert pic.svg.frozen?
      assert_same pic.box(Asobi::IDENTITY), pic.box(Asobi::IDENTITY)
      # Other transforms are always worked out.
      m = Asobi::Affine.scale(2)
      refute_same pic.box(m), pic.box(m)
      # Keyed by the object, not by ==: an equal picture is a new question.
      twin = petal.repeat(5).in_fan.glowing
      assert_equal pic, twin
      refute_same pic.svg, twin.svg
      assert_equal pic.svg, twin.svg
    end
  end

  # The SVG renderer's notes: the SVG of a picture object is written once
  # per build, and a part shared by many pictures is reused inside them.
  def test_svg_of_each_picture_object_is_written_once
    spark = petal(15, 2)
    fan = spark.repeat(100).in_ring # 100 moved copies of the very same spark
    assert_equal 1 + 100 + 100, draws { fan.svg }
    Asobi::Memo.during do
      assert_equal 1 + 100 + 1, draws { fan.svg }
      assert_equal 0, draws { fan.svg }
      assert_same Asobi::SVG.fragment(spark), Asobi::SVG.fragment(fan.items.first.art)
      assert_same fan.svg, notes[:svg][fan]
    end
  end

  def test_notes_are_forgotten_when_the_block_ends
    Asobi::Memo.during do
      circle.svg
      refute_nil notes
    end
    assert_nil notes
  end

  def test_notes_are_forgotten_after_an_error
    assert_raises(RuntimeError) do
      Asobi::Memo.during do
        circle.svg
        raise "broken"
      end
    end
    assert_nil notes
  end

  def test_inner_during_shares_the_outer_notes
    pic = circle.glowing
    Asobi::Memo.during do
      outer = notes
      first = pic.svg
      Asobi::Memo.during { assert_same outer, notes }
      refute_nil notes, "the inner block must not throw the outer notes away"
      assert_same first, pic.svg
    end
    assert_nil notes
  end

  def test_reel_and_document_leave_no_notes
    Asobi::Reel.of(flower_motion)
    assert_nil notes
    Asobi::SVG.document(circle.glowing)
    assert_nil notes
    flower_motion.bounds
    assert_nil notes
  end

  def test_a_reel_that_breaks_halfway_leaves_no_notes
    broken = Asobi.motion(1) { |s| s > 0.5 ? raise("broken at #{s}") : circle }
    assert_raises(RuntimeError) { Asobi::Reel.of(broken.trail) }
    assert_nil notes
  end

  def test_each_thread_has_its_own_notes
    Asobi::Memo.during do
      circle.svg
      assert_nil Thread.new { Thread.current[NOTES] }.value
    end
  end

  def test_threads_building_reels_at_once_get_the_right_frames
    want = reel_frames(flower_motion.trail)
    results = Array.new(4) { Thread.new { reel_frames(flower_motion.trail) } }.map(&:value)
    results.each { assert_equal want, _1 }
  end

  # --- remembering never changes the picture ---------------------------------

  def test_reel_frames_are_the_slow_frames
    motions.each do |name, motion|
      assert_equal slow_frames(motion), reel_frames(motion), name
    end
  end

  def test_document_is_the_same_with_and_without_notes
    pic = petal.repeat(8).in_fan.colored(from: :gold, to: :navy).glowing.shadowed
    slow = Asobi::SVG.open_tag(Asobi::SVG.view(pic.box(Asobi::IDENTITY))) +
           Asobi::SVG.background(Asobi::SVG.view(pic.box(Asobi::IDENTITY)), :white) + pic.svg + "</svg>\n"
    assert_equal slow, Asobi::SVG.document(pic)
  end

  # For every gap, a trail that reuses moments draws exactly what one that
  # works out every moment again draws.
  def test_trail_with_reuse_is_the_trail_without
    gaps = [nil, 1 / 15.0, 0.1, 0.05, 0.02, 0]
    motions.each do |name, motion|
      gaps.each do |gap|
        trail = motion.trail(3, gap:).glowing(2)
        assert_equal slow_frames(trail), reel_frames(trail), "#{name}, gap: #{gap.inspect}"
      end
    end
  end

  def test_staggered_trail_with_reuse_is_the_trail_without
    [nil, 0.1].each do |gap|
      wave = circle(3).repeat(6).in_ring.pulse.trail(3, gap:).one_by_one
      assert_equal slow_frames(wave), reel_frames(wave), "gap: #{gap.inspect}"
    end
  end

  # --- the trail reuses its moments -------------------------------------------

  def test_default_trail_works_out_each_moment_once
    calls = 0
    counted = Asobi.motion(3) do |s|
      calls += 1
      circle(4).move(right: 20).rotate(s * 120)
    end
    Asobi::Reel.of(counted.trail(4))
    # 90 frames, plus the 8 moments before the loop starts.
    assert_equal 90 + 8, calls
    calls = 0
    slow_frames(counted.trail(4))
    assert_equal 90 * 5, calls
  end

  def test_minus_zero_is_its_own_moment
    m = Asobi.motion(1) { |s| text(s.to_s) }
    Asobi::Memo.during do
      assert_equal m.at(0.0), Asobi::Memo.at(m, 0.0)
      assert_equal m.at(-0.0), Asobi::Memo.at(m, -0.0)
      refute_equal Asobi::Memo.at(m, 0.0), Asobi::Memo.at(m, -0.0)
    end
  end

  def test_a_written_gap_is_used_as_written
    m = square.spin
    frame = m.trail(1, gap: 0.05).at(1)
    assert_equal m.at(1 - 0.05).opacity(0.5), frame.items.first
  end

  def test_the_default_gap_is_two_frames
    assert_equal 1 / 15.0, Asobi::Motion::TRAIL_GAP
    m = petal.repeat(8).in_fan.spin(every: 4)
    assert_equal reel_frames(m.trail(4, gap: 1 / 15.0)), reel_frames(m.trail(4))
  end

  private

  def flower_motion = petal.repeat(8).in_fan.colored(:deeppink, :cyan).spin(every: 2)
end
