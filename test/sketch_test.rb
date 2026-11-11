# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "stringio"

class SketchTest < Minitest::Test
  def setup
    super
    ENV["ASOBI_LIVE"] = "0"
    Asobi::Sketch.forget
    @dir = Dir.mktmpdir
  end

  def teardown
    Asobi::Sketch.forget
    FileUtils.remove_entry(@dir)
  end

  def sketch(source, name: "sketch.rb")
    path = File.join(@dir, name)
    File.write(path, source, encoding: "UTF-8")
    path
  end

  def quietly
    old = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old
  end

  def test_show_returns_the_picture_and_remembers_the_last
    first = Asobi.circle(radius: 3)
    second = Asobi.rect
    assert_same first, show(first)
    show second, on: :black, paper: [100, 100]
    shown = Asobi::Sketch.shown
    assert_same second, shown.thing
    assert_equal :black, shown.on
    assert_equal [100, 100], shown.paper
  end

  def test_asobi_show_works_too
    Asobi.show(Asobi.circle)
    assert_equal Asobi.circle, Asobi::Sketch.shown.thing
  end

  def test_show_complains_at_once_about_things_that_are_not_pictures
    assert_raises(TypeError) { show Object.new }
    assert_raises(ArgumentError) { show Asobi.circle, on: :nocolour }
    assert_raises(ArgumentError) { show Asobi.circle, paper: 5 }
  end

  def test_evaluate_a_good_sketch
    path = sketch(<<~RUBY)
      require "asobi"
      show circle(radius: 4), on: :black
    RUBY
    reel = Asobi::Sketch.evaluate(path)
    assert_nil reel["error"]
    assert_equal ['<circle r="4"/>'], reel["frames"]
    assert_equal "black", reel["background"]
    assert_includes reel["code"], "show circle"
  end

  def test_evaluate_with_a_typo_names_file_and_line
    path = sketch("require \"asobi\"\n\nflower = circle\nshow flowr\n")
    reel = Asobi::Sketch.evaluate(path)
    assert_match(/\Asketch\.rb:4 /, reel["error"])
    assert_includes reel["error"], "flowr"
    assert_includes reel["code"], "flower"
  end

  def test_error_from_inside_a_word_still_points_at_the_sketch_line
    path = sketch("show circle\nshow circle.colored(:nocolour)\n")
    reel = Asobi::Sketch.evaluate(path)
    assert_match(/\Asketch\.rb:2 /, reel["error"])
    assert_includes reel["error"], "nocolour"
  end

  def test_error_message_follows_the_language
    path = sketch("show circle.colored(:nocolour)\n")
    in_language(:ja) do
      assert_includes Asobi::Sketch.evaluate(path)["error"], "知らない色"
    end
  end

  def test_syntax_error_becomes_an_error_reel
    path = sketch("show circle\nx = [1, 2\n")
    reel = Asobi::Sketch.evaluate(path)
    assert_kind_of String, reel["error"]
    assert_includes reel["error"], "sketch.rb"
    assert_match(/\d/, reel["error"])
    refute_includes reel["error"], @dir
  end

  def test_sketch_that_never_shows_teaches_show
    path = sketch("x = circle\n")
    reel = Asobi::Sketch.evaluate(path)
    assert_includes reel["error"], "show circle"
    in_language(:ja) { assert_includes Asobi::Sketch.evaluate(path)["error"], "show circle" }
  end

  def test_missing_file_is_an_error_reel
    reel = Asobi::Sketch.evaluate(File.join(@dir, "nope.rb"))
    assert_includes reel["error"], "nope.rb"
  end

  def test_class_with_to_art_in_a_sketch
    path = sketch(<<~RUBY)
      class Eye
        def to_art = circle(radius: 6).on(circle(radius: 9))
      end
      show Eye.new
    RUBY
    reel = Asobi::Sketch.evaluate(path)
    assert_nil reel["error"], reel["error"].to_s
    assert_equal 1, reel["frames"].size
    refute Object.const_defined?(:Eye), "the sketch's class must not leak"
  end

  def test_methods_and_constants_do_not_leak_or_warn
    path = sketch(<<~RUBY)
      SIZE = 5
      def dot = circle(radius: SIZE)
      show dot
    RUBY
    warnings = quietly do
      3.times { assert_nil Asobi::Sketch.evaluate(path)["error"] }
    end
    assert_equal "", warnings
    refute Object.const_defined?(:SIZE)
    refute Object.new.respond_to?(:dot, true)
  end

  def test_japanese_in_strings_and_comments
    path = sketch(<<~RUBY)
      # 日本語のコメント
      name = "あそび"
      show text(name)
    RUBY
    reel = Asobi::Sketch.evaluate(path)
    assert_nil reel["error"], reel["error"].to_s
    assert_includes reel["code"], "日本語のコメント"
    assert_equal Encoding::UTF_8, reel["code"].encoding
    assert_includes JSON.generate(reel), "あそび"
  end

  def test_japanese_works_even_when_the_locale_is_not_utf8
    path = sketch("# あ\nshow circle\n")
    external = Encoding.default_external
    begin
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_external = Encoding::US_ASCII
      assert_includes Asobi::Sketch.evaluate(path)["code"], "あ"
    ensure
      Encoding.default_external = external
      $VERBOSE = verbose
    end
  end

  def test_evaluating_twice_gives_the_same_scatter
    path = sketch("show (circle(radius: 2) * 12).scattered(over: 200)\n")
    a = Asobi::Sketch.evaluate(path)
    b = Asobi::Sketch.evaluate(path)
    assert_nil a["error"], a["error"].to_s
    assert_equal a["frames"], b["frames"]
  end

  def test_sketch_that_calls_exit_still_shows
    path = sketch("show circle\nexit\n")
    assert_nil Asobi::Sketch.evaluate(path)["error"]
  end

  def test_evaluating_does_not_start_anything_even_without_the_switch
    ENV["ASOBI_LIVE"] = "1"
    path = sketch("show circle\n")
    assert_nil Asobi::Sketch.evaluate(path)["error"]
    refute Asobi::Sketch.instance_variable_get(:@exit_hook)
  ensure
    ENV["ASOBI_LIVE"] = "0"
  end

  # Sketch.run: the same, from a String (the web playground, the site builder)

  def test_run_a_string
    reel = Asobi::Sketch.run("show circle(radius: 4), on: :black\n")
    assert_nil reel["error"]
    assert_equal ['<circle r="4"/>'], reel["frames"]
    assert_equal "black", reel["background"]
    assert_includes reel["code"], "show circle"
  end

  def test_run_names_the_given_name_and_line
    reel = Asobi::Sketch.run("flower = circle\n\nshow flowr\n", name: "play.rb")
    assert_match(/\Aplay\.rb:3 /, reel["error"])
    assert_includes reel["error"], "flower" # did you mean
    assert_includes reel["error"], "for main"
    refute_match(/#<|Module/, reel["error"])
    reel = Asobi::Sketch.run("show circle.colored(:nocolour)\n")
    assert_match(/\Asketch\.rb:1 /, reel["error"])
  end

  def test_run_syntax_error_and_no_show
    reel = Asobi::Sketch.run("show circle\nx = [1, 2\n", name: "play.rb")
    assert_includes reel["error"], "play.rb"
    assert_includes Asobi::Sketch.run("x = 1\n")["error"], "show circle"
  end

  def test_run_keeps_its_classes_and_constants_to_itself
    source = "LEAK_SIZE = 3\nclass LeakEye\n  def to_art = circle(radius: LEAK_SIZE)\nend\ndef leak_dot = LeakEye.new\nshow leak_dot\n"
    warnings = quietly { 2.times { assert_nil Asobi::Sketch.run(source)["error"] } }
    assert_equal "", warnings
    refute Object.const_defined?(:LEAK_SIZE)
    refute Object.const_defined?(:LeakEye)
    refute Object.new.respond_to?(:leak_dot, true)
  end

  def test_run_japanese_and_a_binary_string
    source = "# 日本語\nshow text(\"あそび\")\n".b
    reel = Asobi::Sketch.run(source)
    assert_nil reel["error"], reel["error"].to_s
    assert_equal Encoding::UTF_8, reel["code"].encoding
    assert_includes JSON.generate(reel), "あそび"
  end

  def test_run_twice_gives_the_same_scatter_and_motion_frames
    source = "show (circle(radius: 2) * 12).scattered(over: 200)\n"
    assert_equal Asobi::Sketch.run(source)["frames"], Asobi::Sketch.run(source)["frames"]
    moving = Asobi::Sketch.run("show circle.pulse(every: 1)\n")
    assert_operator moving["frames"].size, :>, 1
  end

  def test_evaluate_and_run_agree
    source = "show star.colored(:gold)\n"
    assert_equal Asobi::Sketch.run(source, name: "x.rb")["frames"], Asobi::Sketch.evaluate(sketch(source))["frames"]
  end
end
