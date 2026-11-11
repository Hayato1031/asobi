# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class ReelTest < Minitest::Test
  # Anything with at and every counts as a motion (duck typing).
  class Slide
    def initialize(every) = @every = every
    def every = @every
    def at(seconds) = Asobi.circle(radius: 5).move(right: seconds * 10)
  end

  KEYS = %w[frames fps view background code error].sort

  def test_still_picture_is_one_frame
    reel = Asobi::Reel.of(Asobi.circle(radius: 10))
    assert_equal 1, reel["frames"].size
    assert_equal 1, reel["fps"]
    assert_equal ['<circle r="10"/>'], reel["frames"]
    assert_equal "white", reel["background"]
    assert_nil reel["code"]
    assert_nil reel["error"]
  end

  def test_view_has_the_automatic_margin
    reel = Asobi::Reel.of(Asobi.circle(radius: 10))
    assert_equal Asobi::SVG.view(Asobi.circle(radius: 10)).map { _1.to_f.round(3) }, reel["view"]
  end

  def test_motion_makes_one_loop_of_frames
    reel = Asobi::Reel.of(Slide.new(2.0), fps: 10)
    assert_equal 20, reel["frames"].size
    assert_equal 10, reel["fps"]
    assert_includes reel["frames"][5], "translate" # frame 5 is at 0.5 s: moved
  end

  def test_view_covers_every_frame
    reel = Asobi::Reel.of(Slide.new(2.0), fps: 10)
    x, _y, w, _h = reel["view"]
    # the circle travels from x=0 to x=19 (frame 19 = 1.9 s), radius 5
    assert_operator x, :<=, -5
    assert_operator x + w, :>=, 19 + 5
  end

  def test_frame_count_is_at_least_one
    assert_equal 1, Asobi::Reel.of(Slide.new(0.001), fps: 30)["frames"].size
  end

  def test_more_than_900_frames_lowers_the_fps
    reel = Asobi::Reel.of(Slide.new(60.0), fps: 30)
    assert_operator reel["frames"].size, :<=, 900
    assert_equal 15, reel["fps"]
    assert_equal 900, reel["frames"].size
  end

  def test_very_long_loops_are_cut_at_900
    reel = Asobi::Reel.of(Slide.new(5000.0), fps: 30)
    assert_equal 900, reel["frames"].size
    assert_in_delta 0.18, reel["fps"], 1e-12 # 900 frames over 5000 s
  end

  def test_frames_spread_evenly_over_one_loop
    # 1.05 s at 30 fps: 32 frames (31.5 rounded), each 1.05 / 32 s apart
    motion = Asobi.circle(3).spin(every: 1.05)
    reel = Asobi::Reel.of(motion, fps: 30)
    assert_equal 32, reel["frames"].size
    assert_instance_of Float, reel["fps"]
    assert_in_delta 32 / 1.05, reel["fps"], 1e-9
    assert_equal motion.frames(fps: 30).map(&:svg).to_a, reel["frames"]
    assert_equal motion.at(1.05 * 7 / 32).svg, reel["frames"][7]
  end

  def test_whole_fps_stays_an_integer_in_json
    reel = Asobi::Reel.of(Asobi.circle.spin(every: 2), fps: 24)
    assert_equal 24, reel["fps"]
    assert_instance_of Integer, reel["fps"]
    assert_includes Asobi::Reel.script_json(reel), '"fps":24,'
  end

  def test_background_and_paper
    reel = Asobi::Reel.of(Asobi.circle, on: :black, paper: [800, 600])
    assert_equal "black", reel["background"]
    assert_equal [-400.0, -300.0, 800, 600], reel["view"]
  end

  def test_bad_background_is_a_teaching_error
    error = assert_raises(ArgumentError) { Asobi::Reel.of(Asobi.circle, on: :nocolour) }
    assert_match(/colou?r/, error.message)
  end

  def test_not_a_picture_is_the_core_error
    assert_raises(TypeError) { Asobi::Reel.of(Object.new) }
  end

  def test_json_round_trip_matches_the_contract
    reel = Asobi::Reel.of(Asobi.circle, code: "show circle\n")
    back = JSON.parse(JSON.generate(reel))
    assert_equal KEYS, back.keys.sort
    assert_equal "show circle\n", back["code"]
    assert_equal 4, back["view"].size
  end

  def test_error_reel
    reel = Asobi::Reel.error("oops", code: "x")
    assert_equal({ "error" => "oops", "code" => "x" }, reel)
    assert_equal({ "error" => "oops", "code" => nil }, Asobi::Reel.error("oops"))
  end

  def test_html_has_player_and_reel_and_no_raw_script_end
    html = Asobi::Reel.html(Asobi.circle(radius: 3), title: "a <b> title")
    assert_includes html, "AsobiPlayer.mount"
    assert_includes html, "&lt;b&gt; title"
    assert_includes html, '\\u003ccircle r=\\"3\\"/>'
    assert_equal 2, html.scan("</script>").size # the player's and the reel's, nothing else
    assert_equal 2, html.scan("<script>").size
  end

  def test_script_end_inside_a_frame_is_escaped
    reel = { "frames" => ["<text>&lt;/script&gt;</text>", "</script><script>alert(1)</script>"], "fps" => 1,
             "view" => [0, 0, 1, 1], "background" => "white", "code" => "</script>", "error" => nil }
    html = Asobi::Reel.html(reel)
    assert_equal 2, html.scan("</script>").size
    assert_includes html, '\\u003c/script>'
  end

  def test_save_html_for_pictures_and_motions
    Dir.mktmpdir do |dir|
      path = File.join(dir, "x.html")
      assert_equal path, Asobi.circle.save(path)
      assert_includes File.read(path, encoding: "UTF-8"), "AsobiPlayer"

      other = File.join(dir, "m.html")
      Asobi::Reel.save(Slide.new(1.0), other, fps: 5)
      assert_includes File.read(other, encoding: "UTF-8"), '"fps":5'
    end
  end

  def test_saving_other_kinds_still_teaches
    assert_raises(ArgumentError) { Asobi.circle.save("x.png") }
    assert_includes Asobi::Art::SAVERS.keys, ".html"
  end

  def test_motion_save_checks_the_extension_before_writing
    motion = Asobi.circle.spin
    Dir.mktmpdir do |dir|
      %w[frame.svg movie.mp4].each do |name|
        path = File.join(dir, name)
        File.write(path, "existing work")
        error = assert_raises(ArgumentError) { motion.save(path) }
        assert_includes error.message, 'motion.save("flower.html")'
        assert_includes error.message, 'motion.at(0).save("still.svg")'
        assert_equal "existing work", File.read(path)
      end

      html = File.join(dir, "flower.HTML")
      assert_equal html, motion.save(html)
      assert_includes File.read(html), "<!doctype html>"
    end
  end
end
