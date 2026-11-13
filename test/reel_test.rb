# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"
require "digest"

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

  # ---- the song: play "song.mp3" ----------------------------------------------

  # A small file that stands for a song (asobi never looks inside it).
  def with_song(name = "song.mp3", bytes = "ID3 not really music \x00\xff".b, volume: 1)
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, name), bytes)
      yield Asobi::Song.open(name, volume:, from: dir), dir
    end
  end

  def test_without_a_song_the_reel_is_what_it_always_was
    assert_equal '{"frames":["<circle r=\"3\"/>"],"fps":1,"view":[-5.0,-5.0,10.0,10.0],"background":"white","code":null,"error":null}',
                 JSON.generate(Asobi::Reel.of(Asobi.circle(radius: 3)))
    parts = Asobi.circle(radius: 3).pulse(every: 0.1).when_clicked
    assert_equal '{"frames":["<!--asobi:p1-->"],"fps":1,"view":[-5.45,-5.45,10.9,10.9],"background":"white","code":null,' \
                 '"error":null,"controls":false,"parts":{"p1":{"frames":["<circle r=\"3\"/>","<g transform=\"matrix(1.15 0 0 1.15 0 0)\">' \
                 '<circle r=\"3\"/></g>","<g transform=\"matrix(1.15 0 0 1.15 0 0)\"><circle r=\"3\"/></g>"],"fps":30,"turn":"click"}}}',
                 JSON.generate(Asobi::Reel.of(parts, controls: false))
    [Asobi.circle, Slide.new(0.2)].each do |thing|
      assert_equal JSON.generate(Asobi::Reel.of(thing)), JSON.generate(Asobi::Reel.of(thing, song: nil))
      refute_includes JSON.generate(Asobi::Reel.of(thing)), "song"
    end
    refute_includes Asobi::Reel.html(Asobi.circle), '"song"'
    refute Asobi::Reel.preview(Slide.new(1.0)).key?("song")
  end

  def test_a_song_is_its_id_its_url_and_its_volume
    bytes = "ID3 not really music".b
    with_song("song.mp3", bytes) do |song, dir|
      assert_equal File.join(dir, "song.mp3"), song.path
      assert_equal Digest::SHA256.hexdigest(bytes)[0, 12], song.id
      assert_match(/\A[0-9a-f]{12}\z/, song.id)
      assert_equal 1.0, song.volume
      assert_equal "audio/mpeg", song.type
      assert_equal "/song/#{song.id}", song.url
      assert_equal({ "id" => song.id, "src" => "/song/#{song.id}" }, song.entry)
      assert_equal song.path, Asobi::Song.find(song.id), "the live view may serve it"
    end
    with_song("loop.WAV", volume: 0.5) do |song|
      assert_equal "audio/wav", song.type
      assert_equal({ "id" => song.id, "src" => song.url, "volume" => 0.5 }, song.entry)
    end
    assert_nil Asobi::Song.find("000000000000")
  end

  def test_every_kind_of_song_file_has_its_type
    { ".mp3" => "audio/mpeg", ".wav" => "audio/wav", ".m4a" => "audio/mp4", ".aac" => "audio/aac",
      ".ogg" => "audio/ogg", ".oga" => "audio/ogg", ".opus" => "audio/ogg", ".flac" => "audio/flac",
      ".webm" => "audio/webm" }.each do |kind, type|
      with_song("song#{kind}") { |song| assert_equal type, song.type }
    end
  end

  def test_the_reel_carries_the_song_after_controls_and_before_parts
    with_song(volume: 0.25) do |song|
      reel = Asobi::Reel.of(Asobi.circle, song:)
      assert_equal %w[frames fps view background code error song], reel.keys
      assert_equal({ "id" => song.id, "src" => "/song/#{song.id}", "volume" => 0.25 }, reel["song"])
      keys = Asobi::Reel.of(Asobi.circle.pulse.when_clicked.sounding(:pop), song:, controls: false).keys
      assert_equal %w[frames fps view background code error controls song parts], keys
      steps = Asobi::Reel.steps(Slide.new(0.2), song:)
      whole = steps.step(0) until steps.done?
      assert_equal JSON.generate(Asobi::Reel.of(Slide.new(0.2), song:)), JSON.generate(whole)
      assert_raises(ArgumentError) { Asobi::Reel.of(Asobi.circle, song: "song.mp3") }
    end
  end

  def test_a_preview_carries_the_song_and_still_no_parts
    with_song do |song|
      preview = Asobi::Reel.preview(Asobi.circle.pulse.when_clicked.spin(every: 1), song:)
      assert preview["pending"]
      assert_equal song.entry, preview["song"]
      refute preview.key?("parts")
      assert_equal %w[frames fps view background code error pending song], preview.keys
    end
  end

  def test_a_saved_page_holds_the_whole_song
    bytes = (0..255).map(&:chr).join.b * 3
    with_song("beat.wav", bytes, volume: 0.5) do |song, dir|
      path = File.join(dir, "beat.html")
      Asobi::Reel.save(Slide.new(0.2), path, song:)
      reel = JSON.parse(File.read(path, encoding: "UTF-8")[/\.update\((.*)\);\n/, 1])
      assert_equal song.id, reel["song"]["id"]
      assert_equal 0.5, reel["song"]["volume"]
      head, data = reel["song"]["src"].split(",", 2)
      assert_equal "data:audio/wav;base64", head
      assert_equal bytes, data.unpack1("m0")
      assert_equal %w[frames fps view background code error song], reel.keys
    end
  end

  def test_a_song_too_big_for_a_page_teaches_and_writes_nothing
    Dir.mktmpdir do |dir|
      big = File.join(dir, "mix.mp3")
      File.open(big, "wb") { _1.truncate(Asobi::Song::EMBED_LIMIT + 1) } # sparse: takes no room on the disk
      song = Asobi::Song.open("mix.mp3", from: dir)
      path = File.join(dir, "mix.html")
      e = assert_raises(ArgumentError) { Asobi::Reel.save(Asobi.circle, path, song:) }
      assert_includes e.message, "mix.mp3 is 20.0 MB"
      assert_includes e.message, "20 MB at most"
      assert_includes e.message, "shorter or more compressed"
      refute_path_exists path
      in_language(:ja) do
        e = assert_raises(ArgumentError) { Asobi::Reel.html(Asobi.circle, song:) }
        assert_includes e.message, "20 MB まで"
        assert_includes e.message, "例："
      end
      # Exactly the limit still fits, and the live view has no limit at all.
      assert_equal({ "id" => song.id, "src" => song.url }, Asobi::Reel.of(Asobi.circle, song:)["song"])
      File.open(big, "wb") { _1.truncate(Asobi::Song::EMBED_LIMIT) }
      assert_match(/\Adata:audio\/mpeg;base64,/, Asobi::Song.open(big).data_uri)
    end
  end

  def test_a_saved_svg_has_no_song
    with_song do |song, dir|
      path = File.join(dir, "x.svg")
      Asobi.circle.save(path)
      refute_includes File.read(path), "song"
      assert_raises(ArgumentError) { Asobi::Song.open("x.svg", from: dir) }
    end
  end

  # ---- the preview: a quick first look at a motion ----------------------------

  def test_preview_is_the_first_frame_marked_pending
    motion = Asobi.circle(3).move(right: 20).spin(every: 2)
    preview = Asobi::Reel.preview(motion, on: :black, code: "show x\n")
    whole = Asobi::Reel.of(motion, on: :black, code: "show x\n")
    assert_equal (KEYS + ["pending"]).sort, preview.keys.sort
    assert_equal true, preview["pending"]
    assert_equal [whole["frames"].first], preview["frames"]
    assert_equal whole["fps"], preview["fps"]
    assert_equal "black", preview["background"]
    assert_equal "show x\n", preview["code"]
    assert_nil preview["error"]
    refute whole.key?("pending"), "the whole reel is not pending"
  end

  def test_preview_view_guesses_the_whole_loop
    # A circle that orbits: at 0 s it is only on the right, but the guess
    # already covers the whole circle it travels on.
    motion = Asobi.circle(3).move(right: 20).spin(every: 2)
    view = Asobi::Reel.preview(motion)["view"]
    whole = Asobi::Reel.of(motion)["view"]
    assert_operator view[0], :<, -20
    view.zip(whole).each { |guess, real| assert_in_delta real, guess, 0.05 * whole[2] }
  end

  def test_preview_view_is_never_bigger_than_the_whole_view
    view = Asobi::Reel.preview(Slide.new(2.0), fps: 10)["view"]
    whole = Asobi::Reel.of(Slide.new(2.0), fps: 10)["view"]
    assert_operator view[0], :>=, whole[0] - 1e-9
    assert_operator view[1], :>=, whole[1] - 1e-9
    assert_operator view[0] + view[2], :<=, whole[0] + whole[2] + 1e-9
    assert_operator view[1] + view[3], :<=, whole[1] + whole[3] + 1e-9
  end

  def test_preview_uses_the_paper_when_there_is_one
    preview = Asobi::Reel.preview(Asobi.circle.spin, paper: [300, 200])
    assert_equal [-150.0, -100.0, 300, 200], preview["view"]
  end

  def test_preview_looks_at_only_a_few_moments
    asked = []
    slide = Slide.new(4.0)
    slide.define_singleton_method(:at) { |t| asked << t; Asobi.circle(radius: 5).move(right: t) }
    Asobi::Reel.preview(slide, fps: 30)
    assert_operator asked.size, :<=, Asobi::Reel::PREVIEW_MOMENTS
    assert_equal 0, asked.first
  end

  def test_preview_has_the_same_grain_as_the_whole_reel
    motion = Asobi.circle(3).spin
    preview = Asobi::Reel.preview(motion, grain: true)
    assert_equal Asobi::Reel.of(motion, grain: true)["frames"].first, preview["frames"].first
  end

  def test_a_still_picture_needs_no_preview
    assert_nil Asobi::Reel.preview(Asobi.circle)
  end

  def test_preview_teaches_like_the_whole_reel
    assert_raises(ArgumentError) { Asobi::Reel.preview(Asobi.circle.spin, on: :nocolour) }
    assert_raises(ArgumentError) { Asobi::Reel.preview(Asobi.circle.spin, fps: 0) }
  end

  # Every moving example: the guessed view is close to the real one, so the
  # picture does not jump in size when the whole reel arrives.
  def test_preview_view_is_close_for_every_example
    root = File.expand_path("..", __dir__)
    files = Dir[File.join(root, "examples", "**", "*.rb")].sort
    checked = 0
    files.each do |file|
      next if File.basename(file) == "hanabi.rb" # slow; it has a paper, checked below

      preview = Asobi::Sketch.evaluate(file, preview: true)
      next unless preview["pending"]

      whole = Asobi::Sketch.finish
      side = [whole["view"][2], whole["view"][3]].max
      preview["view"].zip(whole["view"]).each do |guess, real|
        assert_in_delta real, guess, 0.05 * side, File.basename(file)
      end
      checked += 1
    end
    assert_operator checked, :>=, 10
    hanabi = Asobi::Sketch.evaluate(File.join(root, "examples", "showcase", "hanabi.rb"), preview: true)
    assert_equal [-180.0, -100.0, 360, 200], hanabi["view"]
  ensure
    Asobi::Sketch.forget
  end

  # ---- Reel.steps: the same reel, a little at a time ------------------------

  # A motion that writes down, for every moment it draws, the Memo notes
  # it was drawn with (nil when there were none).
  class NoteTaker
    attr_reader :seen

    def initialize = @seen = []
    def every = 1.0
    def at(seconds)
      @seen << Thread.current[Asobi::Memo::NOTES]
      Asobi.circle(radius: 5).move(right: seconds * 10)
    end
  end

  def all_steps(steps, seconds)
    calls = 0
    reel = nil
    (reel = steps.step(seconds); calls += 1) until steps.done?
    [reel, calls]
  end

  def test_steps_make_exactly_the_reel_of_makes
    flower = Asobi.circle(radius: 4).move(right: 10).repeat(6).colored(:gold)
    cases = [
      [flower.spin(every: 2), {}],
      [flower.spin(every: 1).trail, { fps: 12, on: :black }],
      [flower.pulse(every: 1), { paper: [200, 100], grain: true, code: "show flower\n" }],
      [Slide.new(0), {}],
      [flower, { grain: true }]
    ]
    cases.each do |thing, options|
      reel, calls = all_steps(Asobi::Reel.steps(thing, **options), 0)
      assert_equal JSON.generate(Asobi::Reel.of(thing, **options)), JSON.generate(reel)
      assert_operator calls, :>, 1, "a budget of 0 seconds still does one piece per call"
    end
  end

  def test_steps_with_a_budget_take_few_calls_and_without_one_take_one
    motion = Slide.new(2.0)
    assert_equal 1, all_steps(Asobi::Reel.steps(motion), nil)[1]
    assert_equal 1, all_steps(Asobi::Reel.steps(motion), 60)[1]
    assert_operator all_steps(Asobi::Reel.steps(motion), 0)[1], :>, 60
  end

  def test_steps_answer_nil_until_done_then_the_reel_again
    steps = Asobi::Reel.steps(Slide.new(1.0), fps: 4)
    assert_nil steps.step(0)
    refute steps.done?
    reel, = all_steps(steps, 0)
    assert steps.done?
    assert_same reel, steps.step(0)
  end

  def test_steps_keep_one_set_of_notes_for_the_whole_build_and_only_while_working
    motion = NoteTaker.new
    steps = Asobi::Reel.steps(motion, fps: 10)
    steps.step(0) until steps.done?
    assert_equal 10, motion.seen.size
    refute_nil motion.seen.first
    assert(motion.seen.all? { _1.equal?(motion.seen.first) }, "the same notes for every piece")
    assert_nil Thread.current[Asobi::Memo::NOTES], "nothing is left in the thread between pieces"
  end

  def test_steps_inside_memo_during_share_the_outer_notes
    motion = NoteTaker.new
    Asobi::Memo.during do
      outer = Thread.current[Asobi::Memo::NOTES]
      Asobi::Reel.steps(motion, fps: 4).step
      assert(motion.seen.all? { _1.equal?(outer) })
    end
  end

  def test_a_failing_step_leaves_no_notes_behind
    broken = Asobi.motion(1) { |t| t > 0.5 ? raise("boom") : Asobi.circle }
    steps = Asobi::Reel.steps(broken, fps: 10)
    assert_raises(RuntimeError) { steps.step(0) until steps.done? }
    assert_nil Thread.current[Asobi::Memo::NOTES]
  end

  def test_steps_check_their_options_at_once_like_of
    assert_raises(ArgumentError) { Asobi::Reel.steps(Slide.new(1.0), on: :nocolour) }
  end
end
