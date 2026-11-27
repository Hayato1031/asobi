# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "stringio"
require "digest"
require "open3"
require "rbconfig"

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

  # play "song.mp3": a song while the sketch shows

  def song_file(name = "beat.wav", bytes = "RIFF not really a song".b)
    File.binwrite(File.join(@dir, name), bytes)
    Digest::SHA256.hexdigest(bytes)[0, 12]
  end

  def test_play_finds_the_song_next_to_the_sketch_file
    id = song_file
    path = sketch("play \"beat.wav\"\nshow circle\n")
    reel = Dir.chdir(Dir.tmpdir) { Asobi::Sketch.evaluate(path) } # wherever asobi was started
    assert_nil reel["error"]
    assert_equal({ "id" => id, "src" => "/song/#{id}" }, reel["song"])
    assert_equal %w[frames fps view background code error song], reel.keys
    assert_equal File.join(@dir, "beat.wav"), Asobi::Song.find(id)
  end

  def test_play_finds_a_song_in_a_folder_and_by_a_full_path
    Dir.mkdir(File.join(@dir, "music"))
    id = song_file("music/loop.mp3")
    assert_equal id, Asobi::Sketch.evaluate(sketch("play \"music/loop.mp3\"\nshow circle\n"))["song"]["id"]
    full = File.join(@dir, "music", "loop.mp3")
    assert_equal id, Asobi::Sketch.run("play #{full.dump}\nshow circle\n")["song"]["id"]
  end

  def test_without_a_sketch_file_play_looks_in_the_current_folder
    id = song_file
    reel = Dir.chdir(@dir) { Asobi::Sketch.run("play \"beat.wav\"\nshow circle\n", name: "play.rb") }
    assert_equal id, reel["song"]["id"]
  end

  def test_play_with_a_volume
    song_file
    reel = Asobi::Sketch.evaluate(sketch("play \"beat.wav\", volume: 0.5\nshow circle\n"))
    assert_equal 0.5, reel["song"]["volume"]
    reel = Asobi::Sketch.evaluate(sketch("play \"beat.wav\", volume: 1\nshow circle\n"))
    refute reel["song"].key?("volume"), "1 is left out"
    assert_equal 0.0, Asobi::Sketch.evaluate(sketch("play \"beat.wav\", volume: 0\nshow circle\n"))["song"]["volume"]
  end

  def test_a_later_play_replaces_the_song
    song_file("one.mp3", "one".b)
    two = song_file("two.mp3", "two".b)
    reel = Asobi::Sketch.evaluate(sketch("play \"one.mp3\"\nplay \"two.mp3\"\nshow circle\n"))
    assert_equal two, reel["song"]["id"]
  end

  def test_play_after_show_still_plays
    id = song_file
    assert_equal id, Asobi::Sketch.evaluate(sketch("show circle\nplay \"beat.wav\"\n"))["song"]["id"]
  end

  def test_every_run_starts_without_a_song
    song_file
    path = sketch("play \"beat.wav\"\nshow circle\n")
    assert Asobi::Sketch.evaluate(path)["song"]
    assert Asobi::Sketch.song
    reel = Asobi::Sketch.evaluate(sketch("show circle\n", name: "quiet.rb"))
    refute reel.key?("song"), "taking out the play line stops the song"
    assert_nil Asobi::Sketch.song
    assert Asobi::Sketch.evaluate(path)["song"]
    refute Asobi::Sketch.run("show circle\n").key?("song")
    assert Asobi::Sketch.evaluate(path)["song"]
    Asobi::Sketch.forget
    assert_nil Asobi::Sketch.song
  end

  def test_a_sketch_without_play_gives_the_reel_of_old
    source = "show circle(radius: 3).spin(every: 0.2)\n"
    assert_equal JSON.generate(Asobi::Reel.of(Asobi.circle(radius: 3).spin(every: 0.2), code: source)),
                 JSON.generate(Asobi::Sketch.run(source))
  end

  def test_the_preview_and_the_whole_reel_both_carry_the_song
    id = song_file
    path = sketch("play \"beat.wav\"\nshow circle.move(right: 5).spin(every: 1)\n")
    first = Asobi::Sketch.evaluate(path, preview: true)
    assert first["pending"]
    assert_equal id, first["song"]["id"]
    assert_equal id, Asobi::Sketch.finish["song"]["id"]
    Asobi::Sketch.evaluate(path, preview: true)
    whole = Asobi::Sketch.finish_some(0.01) while Asobi::Sketch.waiting?
    assert_equal id, whole["song"]["id"]
    assert_equal Asobi::Sketch.evaluate(path), whole
  end

  def test_a_broken_sketch_has_no_song_so_the_player_keeps_its_own
    song_file
    reel = Asobi::Sketch.evaluate(sketch("play \"beat.wav\"\nshow circel\n"))
    assert reel["error"]
    refute reel.key?("song")
  end

  def test_play_mistakes_teach_on_the_line_of_play
    song_file
    {
      "play \"nope.mp3\"" => ["can't find \"nope.mp3\" in #{@dir}", "next to the sketch"],
      "play \"beat.mid\"" => [".mp3 .wav .m4a .aac .ogg .oga .opus .flac .webm", "\"beat.mid\""],
      "play \"beat\"" => [".mp3 .wav", "play \"song.mp3\""],
      "play 3" => ["the name of a sound file", "You gave 3"],
      "play nil" => ["the name of a sound file", "You gave nil"],
      "play \"beat.wav\", volume: 2" => ["volume to be from 0 to 1", "volume: 0.5", "You gave 2"],
      "play \"beat.wav\", volume: -0.5" => ["from 0 to 1"],
      "play \"beat.wav\", volume: \"loud\"" => ["needs a number for volume"]
    }.each do |line, texts|
      reel = Asobi::Sketch.evaluate(sketch("show circle\n\n#{line}\n"))
      assert_match(/\Asketch\.rb:3 /, reel["error"], line)
      texts.each { assert_includes reel["error"], _1, line }
    end
    in_language(:ja) do
      error = Asobi::Sketch.evaluate(sketch("play \"nope.mp3\"\nshow circle\n"))["error"]
      assert_match(/\Asketch\.rb:1 /, error)
      assert_includes error, "見つかりません"
      assert_includes error, "例：play \"song.mp3\""
      error = Asobi::Sketch.evaluate(sketch("play \"beat.mid\"\nshow circle\n"))["error"]
      assert_includes error, "例：play \"song.mp3\""
      error = Asobi::Sketch.evaluate(sketch("play 3\nshow circle\n"))["error"]
      assert_includes error, "音のファイルの名前"
      error = Asobi::Sketch.evaluate(sketch("play \"beat.wav\", volume: 2\nshow circle\n"))["error"]
      assert_includes error, "0 から 1 まで"
    end
  end

  def test_play_goes_with_every_html_saved_after_it_but_never_with_svg
    bytes = "RIFF a song".b
    song_file("beat.wav", bytes)
    path = sketch(<<~RUBY)
      circle.save("before.html")
      play "beat.wav"
      circle.save("after.html")
      circle.spin.save("moving.html")
      circle.save("after.svg")
      show circle
    RUBY
    Dir.chdir(@dir) { assert_nil Asobi::Sketch.evaluate(path)["error"] }
    page = ->(name) { File.read(File.join(@dir, name), encoding: "UTF-8") }
    refute_includes page["before.html"], '"song"'
    %w[after.html moving.html].each do |name|
      assert_includes page[name], "\"song\":{\"id\":\"#{Digest::SHA256.hexdigest(bytes)[0, 12]}\","
      assert_includes page[name], "\"src\":\"data:audio/wav;base64,#{[bytes].pack("m0")}\""
    end
    refute_includes page["after.svg"], "song"
    refute_includes page["after.svg"], "base64"
  end

  def test_a_script_play_goes_with_its_saves_too
    song_file
    Asobi.play(File.join(@dir, "beat.wav"), volume: 0.5)
    out = File.join(@dir, "x.html")
    Asobi.circle.save(out)
    assert_includes File.read(out, encoding: "UTF-8"), '"volume":0.5'
    assert_nil play(File.join(@dir, "beat.wav")), "play answers nothing, like puts"
    assert_equal 1.0, Asobi::Sketch.song.volume
    assert_equal Asobi::Sketch.song.entry, Asobi::Sketch.tap { show Asobi.circle }.reel["song"]
  end

  # The playground has no files, only the songs the site ships: play takes
  # those names (no file needed) and teaches about any other.
  def test_play_in_the_playground_takes_only_the_songs_the_site_ships
    offered = Asobi::Song.new(path: "beat.wav", id: "0123456789ab", src: "assets/beat.wav")
    Asobi::Sketch.playground = { "beat.wav" => offered }
    reel = Dir.chdir(@dir) { Asobi::Sketch.run("show circle\nplay \"beat.wav\", volume: 0.5\n", name: "play.rb") }
    assert_nil reel["error"], "no file is needed: the page has the song"
    assert_equal({ "id" => "0123456789ab", "src" => "assets/beat.wav", "volume" => 0.5 }, reel["song"])
    assert_equal({ "id" => "0123456789ab", "src" => "assets/beat.wav" },
                 Asobi::Sketch.run("play \"beat.wav\"\nshow circle\n", name: "play.rb")["song"])

    song_file("song.mp3") # even a real file: the playground has no files of its own
    reel = Dir.chdir(@dir) { Asobi::Sketch.run("show circle\nplay \"song.mp3\"\n", name: "play.rb") }
    assert_match(/\Aplay\.rb:2 /, reel["error"])
    assert_includes reel["error"], "only one song"
    assert_includes reel["error"], 'play "beat.wav"'
    assert_includes reel["error"], "on your computer"
    assert_nil reel["song"]
    in_language(:ja) do
      error = Asobi::Sketch.run("play \"song.mp3\"\nshow circle\n", name: "play.rb")["error"]
      assert_includes error, "遊び場で流せる曲は \"beat.wav\" だけです"
      assert_includes error, "自分のパソコン"
      assert_includes error, "例："
    end
    assert_match(/play\.rb:1 .*volume/, Asobi::Sketch.run("play \"beat.wav\", volume: 2\nshow circle\n", name: "play.rb")["error"])
    good = Asobi::Sketch.run("show circle.pulse.when_clicked.sounding(:pop)\n", name: "play.rb")
    assert_nil good["error"]
    assert_equal "pop", good["parts"]["p1"]["sound"]
  ensure
    Asobi::Sketch.playground = false
  end

  # The playground's own entry point offers beat.wav, with the id of the
  # real file (so the song the pages play and the playground's are one).
  # Any other song: its own message, naming the songs it has and the button
  # that adds one (songs chosen on the page: test/site_test.rb).
  def test_the_playground_runner_offers_beat_wav
    script = <<~'RUBY'
      require "asobi"
      require "json"
      load ARGV[0]
      bad = JSON.parse(Asobi::Web.run(%(play "song.mp3"\nshow circle\n), "en"))
      beat = JSON.parse(Asobi::Web.run(%(play "beat.wav"\nshow circle.pulse.by(:music, :low)\n), "en"))
      good = JSON.parse(Asobi::Web.run(%(show circle.pulse.when_pressed("a").sounding(:c4)\n), "en"))
      puts JSON.generate([bad["error"], beat["error"], beat["song"], good["error"], good["parts"]["p1"]["note"]])
    RUBY
    runner = File.expand_path("../site/playground/runner.rb", __dir__)
    out, err, status = Open3.capture3({ "ASOBI_LIVE" => "0" }, RbConfig.ruby, "-I", File.expand_path("../lib", __dir__),
                                      "-e", script, runner, chdir: @dir)
    assert status.success?, err
    bad, beat_error, song, good, note = JSON.parse(out)
    assert_match(/\Aplay\.rb:1 .*no song "song\.mp3"\. It can play "beat\.wav" now, .*“Choose song”/, bad)
    assert_nil beat_error
    wav = File.expand_path("../examples/reactions/beat.wav", __dir__)
    assert_equal({ "id" => Digest::SHA256.file(wav).hexdigest[0, 12], "src" => "assets/beat.wav" }, song)
    assert_nil good
    assert_equal 60, note
  end

  # Two steps: a quick preview of a motion, then finish makes the whole Reel

  def test_preview_of_a_motion_then_finish
    source = "show circle(radius: 3).move(right: 10).spin(every: 2), on: :black\n"
    first = Asobi::Sketch.run(source, name: "play.rb", preview: true)
    assert_equal true, first["pending"]
    assert_equal 1, first["frames"].size
    assert_equal source, first["code"]
    assert Asobi::Sketch.waiting?
    whole = Asobi::Sketch.finish
    refute Asobi::Sketch.waiting?
    assert_equal Asobi::Sketch.run(source, name: "play.rb"), whole
    assert_nil Asobi::Sketch.finish, "nothing left to finish"
  end

  def test_preview_runs_the_sketch_only_once
    $asobi_preview_runs = 0
    Asobi::Sketch.run("$asobi_preview_runs += 1\nshow circle.spin\n", preview: true)
    Asobi::Sketch.finish
    assert_equal 1, $asobi_preview_runs
  end

  def test_preview_of_a_still_picture_is_already_whole
    first = Asobi::Sketch.run("show circle(radius: 4)\n", preview: true)
    assert_equal Asobi::Sketch.run("show circle(radius: 4)\n"), first
    refute first.key?("pending")
    refute Asobi::Sketch.waiting?
    assert_nil Asobi::Sketch.finish
  end

  def test_preview_of_a_broken_sketch_is_the_error
    first = Asobi::Sketch.run("show circl.spin\n", name: "play.rb", preview: true)
    assert_match(/\Aplay\.rb:1 /, first["error"])
    assert_nil Asobi::Sketch.finish
  end

  def test_a_mistake_later_in_the_loop_comes_from_finish
    source = "show circle.animate(2) { |c, t| t > 0.9 ? c.colored(:nocolour) : c }\n"
    first = Asobi::Sketch.run(source, name: "play.rb", preview: true)
    assert_nil first["error"]
    whole = Asobi::Sketch.finish
    assert_match(/\Aplay\.rb:1 /, whole["error"])
    assert_equal source, whole["code"]
  end

  def test_a_new_run_forgets_the_old_preview
    Asobi::Sketch.run("show circle.spin\n", preview: true)
    Asobi::Sketch.run("show circle\n")
    assert_nil Asobi::Sketch.finish
  end

  # finish_some: finish in slices, so the playground can stop halfway

  def finish_in_slices
    slices = 0
    whole = nil
    while Asobi::Sketch.waiting?
      whole = Asobi::Sketch.finish_some(0)
      slices += 1
    end
    [whole, slices]
  end

  def test_finish_some_makes_the_same_whole_reel_as_finish
    source = "show circle(radius: 3).move(right: 10).spin(every: 2).trail, on: :black\n"
    Asobi::Sketch.run(source, name: "play.rb", preview: true)
    whole, slices = finish_in_slices
    assert_operator slices, :>, 1
    Asobi::Sketch.run(source, name: "play.rb", preview: true)
    assert_equal JSON.generate(Asobi::Sketch.finish), JSON.generate(whole)
  end

  def test_finish_some_answers_nil_while_not_ready
    Asobi::Sketch.run("show circle.spin\n", preview: true)
    assert_nil Asobi::Sketch.finish_some(0)
    assert Asobi::Sketch.waiting?
    whole, = finish_in_slices
    assert_operator whole["frames"].size, :>, 1
    assert_nil Asobi::Sketch.finish_some(0), "nothing left"
  end

  def test_finish_some_with_nothing_waiting_is_nil
    Asobi::Sketch.run("show circle\n", preview: true)
    refute Asobi::Sketch.waiting?
    assert_nil Asobi::Sketch.finish_some(0.08)
  end

  def test_a_mistake_later_in_the_loop_comes_from_finish_some
    source = "show circle.animate(2) { |c, t| t > 0.9 ? c.colored(:nocolour) : c }\n"
    Asobi::Sketch.run(source, name: "play.rb", preview: true)
    whole, = finish_in_slices
    assert_match(/\Aplay\.rb:1 /, whole["error"])
    refute Asobi::Sketch.waiting?
  end

  def test_forget_drops_a_half_made_whole_reel
    Asobi::Sketch.run("show circle.spin\n", preview: true)
    assert_nil Asobi::Sketch.finish_some(0)
    Asobi::Sketch.forget
    refute Asobi::Sketch.waiting?
    assert_nil Asobi::Sketch.finish_some(0)
  end

  def test_a_new_run_drops_a_half_made_whole_reel
    Asobi::Sketch.run("show circle.spin\n", preview: true)
    Asobi::Sketch.finish_some(0)
    Asobi::Sketch.run("show star.pulse\n", preview: true)
    whole, = finish_in_slices
    assert_equal Asobi::Sketch.run("show star.pulse\n"), whole
  end

  def test_evaluate_with_preview
    first = Asobi::Sketch.evaluate(sketch("show star.pulse\n"), preview: true)
    assert first["pending"]
    assert_operator Asobi::Sketch.finish["frames"].size, :>, 1
  end
end
