# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

# Reactions: a motion whose frames something other than the clock turns
# (a click, the pointer, a key, a beat, a sound). See lib/asobi/reaction.rb.
class ReactionTest < Minitest::Test
  def dot = Asobi.circle(radius: 5)
  def reel(thing, **options) = Asobi::Reel.of(thing, **options)

  # --- the words ---------------------------------------------------------

  def test_each_word_answers_a_picture_that_remembers_who_turns_it
    pulse = dot.pulse
    {
      pulse.when_clicked => ["click", nil, nil, nil],
      pulse.while_hovered => ["hover", nil, nil, nil],
      pulse.when_pressed => ["key", nil, nil, nil],
      pulse.when_pressed("a") => ["key", "a", nil, nil],
      pulse.when_pressed(:space) => ["key", " ", nil, nil],
      pulse.when_pressed("ArrowUp") => ["key", "ArrowUp", nil, nil],
      pulse.on_beat => ["beat", nil, "mic", nil],
      pulse.on_beat(:music) => ["beat", nil, "music", nil],
      pulse.by(:mouse_x) => ["value", nil, "mouse_x", nil],
      pulse.by("mouse_y") => ["value", nil, "mouse_y", nil],
      pulse.by(:mic) => ["value", nil, "mic", nil],
      pulse.by(:mic, :volume) => ["value", nil, "mic", nil],
      pulse.by(:mic, :low) => ["value", nil, "mic", "low"],
      pulse.by(:music, :pitch) => ["value", nil, "music", "pitch"]
    }.each do |part, (turn, key, from, what)|
      assert_kind_of Asobi::Reaction, part
      assert_kind_of Asobi::Art, part
      assert_same pulse, part.motion
      assert_equal [turn, key, from, what], [part.turn, part.key, part.from, part.what], part.inspect
      refute Asobi::Reel.motion?(part), "from the outside it does not change with the clock"
    end
  end

  def test_equal_words_on_the_same_motion_are_equal_pictures
    pulse = dot.pulse
    assert_equal pulse.when_clicked, pulse.when_clicked
    refute_equal pulse.when_clicked, pulse.while_hovered
    refute_equal pulse.when_clicked, dot.pulse.when_clicked, "another motion is another part"
  end

  def test_every_picture_word_and_motion_word_works_on_it
    part = dot.pulse.when_clicked
    assert_kind_of Asobi::Many, part.repeat(12).in_ring
    assert_kind_of Asobi::Styled, part.colored(:crimson).glowing
    assert_kind_of Asobi::Motion, part.spin(every: 8)
    assert_kind_of Asobi::Motion, (part + dot.spin)
    assert_kind_of Asobi::Many, (Asobi.rect + part)
  end

  def test_trail_and_one_by_one_see_a_still_picture
    part = dot.pulse.when_clicked
    assert_same part, part.trail
    assert_raises(ArgumentError) { part.one_by_one }
    # Inside a motion, the motion's own words still work.
    staggered = part.repeat(3).in_row.spin.one_by_one
    assert_kind_of Asobi::Motion, staggered
    assert_kind_of Asobi::Motion, part.repeat(3).in_row.spin.trail(3)
    assert_includes reel(staggered.trail(2), fps: 2)["frames"].first, "<!--asobi:p1-->"
  end

  def test_a_list_that_becomes_a_motion_works_too
    part = [dot, dot.pulse].to_art.when_clicked
    assert_kind_of Asobi::Reaction, part
  end

  # --- teaching errors ---------------------------------------------------

  def test_a_reaction_word_on_a_still_picture_teaches_where_to_write_it
    %i[when_clicked while_hovered when_pressed on_beat].each do |word|
      e = assert_raises(ArgumentError) { dot.public_send(word) }
      assert_includes e.message, word.to_s
      assert_includes e.message, "pulse"
    end
    e = assert_raises(ArgumentError) { dot.by(:mouse_x) }
    assert_includes e.message, "flower.spin.by(:mouse_x)"
    assert_raises(ArgumentError) { dot.pulse.when_clicked.when_clicked }
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.when_clicked }
      assert_includes e.message, "例：flower.pulse.when_clicked"
    end
  end

  # --- flash cannot follow a value -----------------------------------------

  def test_by_on_a_motion_with_a_flash_teaches_fade
    chains = {
      "flash" => -> { dot.flash.by(:mic) },
      "flash.colored" => -> { dot.flash.colored(:red).by(:mouse_x) },
      "flash.spin" => -> { dot.flash.spin.by(:mic) },
      "spin.flash" => -> { dot.spin.flash.by(:mic) },
      "flash.trail" => -> { dot.flash.trail.by(:mic) },
      "flash.one_by_one" => -> { dot.flash.repeat(3).in_row.one_by_one.by(:mic) },
      "flash + still" => -> { (dot.flash + Asobi.square(size: 5)).by(:mic) }
    }
    chains.each do |name, chain|
      e = assert_raises(ArgumentError, name) { chain.call }
      assert_includes e.message, "fade(from: 0, to: 1)", name
    end
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.flash.by(:mic) }
      assert_includes e.message, "fade を使ってください"
    end
  end

  def test_flash_still_works_where_it_makes_sense
    assert_equal "beat", dot.flash.on_beat(:music).turn
    assert_equal "click", dot.flash.when_clicked.turn
    assert_equal "value", dot.fade(from: 0, to: 1).by(:mic).turn
    assert_equal "value", dot.spin.by(:mic).turn
  end

  def test_unknown_sources_list_the_good_ones
    e = assert_raises(ArgumentError) { dot.pulse.by(:volume) }
    assert_includes e.message, ":mouse_x, :mouse_y, :mic, :music"
    e = assert_raises(ArgumentError) { dot.pulse.on_beat(:mouse_x) }
    assert_includes e.message, ":mic, :music"
    assert_raises(ArgumentError) { dot.pulse.by(nil) }
  end

  def test_by_mouse_points_to_mouse_x_and_mouse_y
    e = assert_raises(ArgumentError) { dot.spin.by(:mouse) }
    assert_includes e.message, ":mouse_x"
    assert_includes e.message, ":mouse_y"
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.spin.by(:mouse) }
      assert_includes e.message, ":mouse_x"
      assert_includes e.message, "例："
    end
  end

  def test_what_is_only_for_sound_and_must_be_known
    e = assert_raises(ArgumentError) { dot.spin.by(:mouse_x, :low) }
    assert_includes e.message, "by(:mouse_x)"
    e = assert_raises(ArgumentError) { dot.pulse.by(:mic, :bass) }
    assert_includes e.message, ":volume, :low, :mid, :high, :pitch"
    assert_includes e.message, ":bass"
  end

  def test_a_bad_key_teaches
    ["", "a b", 3, ["a"], "--"].each do |key|
      e = assert_raises(ArgumentError) { dot.pulse.when_pressed(key) }
      assert_includes e.message, 'when_pressed("a")'
    end
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.pulse.when_pressed("") }
      assert_includes e.message, "例：when_pressed(\"a\")"
    end
  end

  # --- which way a motion goes ---------------------------------------------

  def test_motions_know_whether_they_go_out_and_come_back
    assert_equal 0.5, dot.pulse.peak
    assert_equal 1.0, dot.fade.peak
    assert_equal 1.0, dot.fade(from: 0, to: 1).peak
    assert_nil dot.flash.peak
    assert_equal 0.5, dot.sway.peak, "sway is farthest a quarter of the way in"
    assert_equal 0.5, dot.bounce.peak
    assert_equal 2.0, dot.drift.peak
    assert_equal 2.0, dot.shift_color.peak
    assert_nil dot.spin.peak
    assert_nil dot.orbit.peak
    assert_nil dot.animate(2) { |p, t| p.rotate(t * 90) }.peak
    assert_nil Asobi.motion(2) { dot }.peak
  end

  def test_picture_words_keep_it_and_mixed_motions_lose_it
    assert_equal 0.5, dot.pulse.colored(:red).repeat(3).in_row.glowing.peak
    assert_equal 0.5, dot.pulse.beside(Asobi.rect).peak
    assert_equal 0.5, (dot.pulse + dot.bounce).peak, "the same loop, farthest at the same moment"
    assert_equal 0.5, dot.pulse.fade(every: 1).peak
    assert_nil (dot.pulse + dot.fade(every: 1, to: 0.5).sway(every: 4)).peak
    assert_nil dot.pulse.spin.peak, "out and back with one way round: the whole loop"
    assert_nil (dot.pulse + dot.fade).peak, "different loops"
    assert_nil dot.repeat(3).in_row.pulse.one_by_one.peak, "staggered: never all at rest"
    assert_nil dot.pulse.trail.peak
  end

  # --- the frames of a part ----------------------------------------------

  def test_click_hover_key_and_beat_play_one_loop_like_a_reel
    motion = dot.pulse(every: 2)
    %i[when_clicked while_hovered when_pressed on_beat].each do |word|
      part = motion.public_send(word)
      seconds, fps = part.moments(30)
      assert_equal Asobi::Reel.moments(motion, 30), [seconds, fps]
      assert_equal 60, part.pictures.size
      assert_equal motion.at(0), part.rest
      assert_equal motion.at(0), part.pictures.first, "frame 0 is the rest picture"
    end
    assert_equal [[0.0, 0.5, 1.0, 1.5], 2], motion.when_clicked.moments(2)
  end

  def test_a_value_that_goes_out_and_back_shows_only_the_way_out
    motion = dot.pulse(every: 2, to: 2)
    part = motion.by(:mic)
    seconds, fps = part.moments
    assert_nil fps
    assert_equal 61, seconds.size
    assert_equal 0.0, seconds.first
    assert_equal 1.0, seconds.last, "the farthest moment"
    assert_box part.pictures.last.box(Asobi::IDENTITY), -10, -10, 10, 10
    assert_equal 5.0, part.pictures.first.box(Asobi::IDENTITY).x1
    sizes = part.pictures.map { _1.box(Asobi::IDENTITY).width }
    assert_equal sizes.sort, sizes, "a bigger value is bigger"
    assert_equal 0.5, dot.sway(every: 2).by(:mouse_x).moments.first.last

    lit = dot.fade(from: 0, to: 1).by(:music, :high)
    assert_equal dot.opacity(0), lit.pictures.first
    assert_equal dot.opacity(1), lit.pictures.last

    hit = dot.flash(every: 0.2).on_beat(:music)
    assert_equal dot.opacity(0), hit.rest
    assert_operator hit.pictures[1].style[:opacity], :>, hit.pictures.last.style[:opacity]
  end

  def test_a_value_that_goes_round_shows_the_whole_loop_both_ends
    part = dot.move(right: 10).spin(every: 4).by(:mouse_x)
    seconds, = part.moments
    assert_equal 61, seconds.size
    assert_equal [0.0, 2.0, 4.0], seconds.values_at(0, 30, 60)
    assert_equal part.pictures.first, part.pictures.last
  end

  def test_animate_gets_t_from_0_to_1_inclusive_for_a_value
    seen = []
    motion = dot.animate(2) do |picture, t|
      seen << t
      picture.grow(to: 1 + t)
    end
    part = motion.by(:mouse_y)
    pictures = part.pictures
    assert_equal 0.0, seen.first
    assert_equal 1.0, seen.last
    assert_box pictures.last.box(Asobi::IDENTITY), -10, -10, 10, 10
    assert_equal 0.0, Asobi::Motion.phase(2.0, 2.0), "the clock itself still wraps to the start"
  end

  def test_its_box_is_the_room_of_all_its_frames
    part = dot.pulse(to: 2).when_clicked
    assert_box part.box(Asobi::IDENTITY), -10, -10, 10, 10
    assert_box part.bounds, -10, -10, 10, 10
    assert_box part.move(right: 5).bounds, -5, -10, 15, 10
    assert_box part.scale(width: 2, height: 1).bounds, -20, -10, 20, 10
    turned = dot.move(right: 10).drift(right: 10).when_clicked.rotate(90)
    assert_box turned.bounds, -5, 5, 5, 25, 1e-6
    # A row leaves room for the part at its biggest.
    row = part.repeat(3).in_row
    assert_box row.bounds, -30, -10, 30, 10
  end

  # --- drawing -------------------------------------------------------------

  module Spy
    module_function

    %i[circle ellipse rect path text nothing transformed styled group reacting].each do |name|
      define_method(name) { |*args| [name, *args] }
    end
  end

  def test_the_step_by_step_form_hands_the_part_over
    part = dot.pulse.when_pressed("a")
    assert_equal [:reacting, part], Asobi::Drawing.draw(part, Spy)
    assert_equal({ turn: "key", key: "a" }, Asobi::Drawing.turn(part))
    assert_equal({ turn: "value", from: "mic", what: "low" }, Asobi::Drawing.turn(dot.pulse.by(:mic, :low)))
    assert_equal({ turn: "beat", from: "mic" }, Asobi::Drawing.turn(dot.pulse.on_beat))
  end

  def test_the_data_form_draws_every_frame
    motion = dot.pulse(every: 0.1)
    data = Asobi::Drawing.data(motion.when_clicked)
    assert_equal({ "turn" => "click" }, data["reacting"])
    assert_equal 30, data["fps"]
    assert_equal 3, data["frames"].size
    assert_equal({ "shape" => "circle", "r" => 5.0 }, data["frames"].first)
    value = Asobi::Drawing.data(motion.by(:mouse_x))
    assert_equal({ "turn" => "value", "from" => "mouse_x" }, value["reacting"])
    refute value.key?("fps")
    assert_equal 61, value["frames"].size
    assert_equal value, JSON.parse(JSON.generate(value))
  end

  def test_a_still_document_draws_the_part_at_rest
    part = dot.pulse.when_clicked.colored(:gold)
    assert_equal dot.colored(:gold).svg, part.svg
    svg = part.to_svg
    refute_includes svg, "asobi:"
    assert_includes svg, '<circle r="5"/>'
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dot.svg")
      part.save(path)
      refute_includes File.read(path), "<!--"
    end
  end

  # --- the reel ------------------------------------------------------------

  def test_a_part_is_a_marker_in_the_frames_and_its_frames_in_parts
    r = reel(dot.pulse(every: 0.1, to: 2).when_clicked)
    assert_equal ["<!--asobi:p1-->"], r["frames"]
    assert_equal 1, r["fps"]
    assert_equal %w[p1], r["parts"].keys
    p1 = r["parts"]["p1"]
    assert_equal %w[frames fps turn], p1.keys
    assert_equal '<circle r="5"/>', p1["frames"].first
    assert_equal 3, p1["frames"].size
    assert_equal 30, p1["fps"]
    assert_equal "click", p1["turn"]
    # The view has room for the part at its biggest.
    assert_operator r["view"][2], :>=, 20
  end

  def test_part_fields_follow_the_contract
    parts = reel([dot.pulse.when_pressed("a"), dot.pulse.on_beat(:music), dot.spin.by(:mic, :pitch),
                  dot.pulse.by(:mouse_y)].to_art)["parts"]
    assert_equal({ "turn" => "key", "key" => "a" }, parts["p1"].except("frames", "fps"))
    assert_equal({ "turn" => "beat", "from" => "music" }, parts["p2"].except("frames", "fps"))
    assert_equal %w[frames turn from what], parts["p3"].keys
    assert_equal({ "turn" => "value", "from" => "mic", "what" => "pitch" }, parts["p3"].except("frames"))
    assert_equal({ "turn" => "value", "from" => "mouse_y" }, parts["p4"].except("frames"))
    assert_equal 61, parts["p4"]["frames"].size
  end

  def test_part_fps_follows_the_reel_fps
    r = reel(dot.pulse(every: 2).when_clicked.spin(every: 1), fps: 10)
    assert_equal 10, r["fps"]
    assert_equal 20, r["parts"]["p1"]["frames"].size
    assert_equal 10, r["parts"]["p1"]["fps"]
  end

  def test_twelve_copies_are_one_part_with_twelve_markers_in_each_frame
    r = reel(dot.pulse.when_clicked.repeat(12).in_ring.spin(every: 1), fps: 4)
    assert_equal %w[p1], r["parts"].keys
    assert_equal 4, r["frames"].size
    r["frames"].each { assert_equal 12, _1.scan("<!--asobi:p1-->").size }
  end

  def test_ids_go_by_first_appearance_and_equal_parts_share_one
    a = dot.pulse.when_clicked
    b = dot.spin.while_hovered
    r = reel([b, a, b, a].to_art)
    assert_equal %w[p1 p2], r["parts"].keys
    assert_equal "hover", r["parts"]["p1"]["turn"]
    assert_equal "click", r["parts"]["p2"]["turn"]
    assert_equal %w[p1 p2 p1 p2], r["frames"].first.scan(/<!--asobi:(p\d+)-->/).flatten
  end

  def test_parts_inside_parts_are_found_and_built
    inner = dot.pulse.when_clicked.repeat(2).in_row
    outer = inner.spin(every: 1).while_hovered
    r = reel(outer.repeat(2).in_column, fps: 4)
    assert_equal %w[p1 p2], r["parts"].keys
    assert_equal "hover", r["parts"]["p1"]["turn"]
    assert_equal "click", r["parts"]["p2"]["turn"]
    assert_equal 2, r["frames"].first.scan("<!--asobi:p1-->").size
    r["parts"]["p1"]["frames"].each { assert_equal 2, _1.scan("<!--asobi:p2-->").size }
    refute_includes r["parts"]["p2"]["frames"].join, "<!--"
  end

  def test_effects_around_a_part_keep_its_marker
    r = reel(dot.pulse.on_beat.glowing.shadowed)
    assert_includes r["frames"].first, "<!--asobi:p1-->"
    assert_includes r["frames"].first, "filter"
  end

  def test_nothing_reacting_means_the_reel_of_old
    flower = Asobi.petal.repeat(6).in_fan
    [flower, flower.spin(every: 1)].each do |thing|
      r = reel(thing, fps: 6)
      assert_equal %w[frames fps view background code error], r.keys
      refute_includes JSON.generate(r), "asobi:p"
    end
  end

  def test_steps_build_parts_the_same_byte_for_byte
    inner = dot.pulse.when_clicked.repeat(2).in_row
    cases = [
      [inner.spin(every: 1).while_hovered.repeat(3).in_ring, {}],
      [dot.pulse.by(:mic, :low).spin(every: 2).glowing, { fps: 6, grain: true, controls: false }],
      [[dot.spin.by(:mouse_x), dot.pulse.on_beat].to_art, { code: "show it\n" }]
    ]
    cases.each do |thing, options|
      steps = Asobi::Reel.steps(thing, **options)
      calls = 0
      whole = nil
      (whole = steps.step(0); calls += 1) until steps.done?
      assert_equal JSON.generate(reel(thing, **options)), JSON.generate(whole)
      assert_operator calls, :>, 10
      assert_nil Thread.current[Asobi::Parts::SLOT], "nothing is left in the thread between pieces"
    end
  end

  def test_the_preview_draws_parts_at_rest
    motion = dot.pulse.when_clicked.repeat(3).in_row.spin(every: 2)
    preview = Asobi::Reel.preview(motion)
    whole = reel(motion)
    refute preview.key?("parts")
    refute_includes preview["frames"].first, "<!--"
    assert_includes preview["frames"].first, '<circle r="5"/>'
    assert_equal whole["view"], preview["view"] # the parts' room is already known
  end

  # --- sounding ----------------------------------------------------------------

  def test_sounding_names_the_six_sounds
    %i[pop kick snare hat clap bell].each do |name|
      part = dot.pulse.when_clicked.sounding(name)
      assert_kind_of Asobi::Reaction, part
      assert_equal name.to_s, part.sound
    end
    assert_equal "kick", dot.pulse.on_beat.sounding("kick").sound
  end

  def test_sounding_a_note_is_its_midi_number
    { c4: 60, cs4: 61, db4: 61, a4: 69, bb4: 70, b4: 71, c1: 24, b7: 107, e3: 52, fs2: 42,
      "C#4" => 61, "Bb3" => 58, "c4" => 60, "A4" => 69, "gB2" => 42 }.each do |note, midi|
      assert_equal midi, dot.pulse.when_pressed("a").sounding(note).sound, note.inspect
    end
  end

  def test_sounding_keeps_everything_else_and_works_on_every_turn_but_by
    pulse = dot.pulse
    [pulse.when_clicked, pulse.while_hovered, pulse.when_pressed("a"), pulse.on_beat(:music)].each do |part|
      sounding = part.sounding(:pop)
      assert_equal part.to_h.merge(sound: "pop"), sounding.to_h
      assert_nil part.sound, "the reaction itself is not changed"
    end
  end

  def test_a_second_sounding_replaces_the_first
    clicked = dot.pulse.when_clicked
    part = clicked.sounding(:pop).sounding(:c4)
    assert_equal 60, part.sound
    assert_equal clicked.sounding(:c4), part
  end

  def test_the_sound_is_part_of_what_a_part_is
    pulse = dot.pulse
    assert_equal pulse.when_clicked.sounding(:pop), pulse.when_clicked.sounding(:pop)
    refute_equal pulse.when_clicked.sounding(:pop), pulse.when_clicked.sounding(:kick)
    refute_equal pulse.when_clicked, pulse.when_clicked.sounding(:pop)
    assert_equal pulse.when_clicked.sounding(:cs4), pulse.when_clicked.sounding("Db4"), "the same note"
  end

  def test_every_picture_word_and_motion_word_works_on_a_sounding_part
    part = dot.pulse.when_clicked.sounding(:pop)
    assert_kind_of Asobi::Many, part.repeat(12).in_ring
    assert_kind_of Asobi::Styled, part.colored(:crimson).glowing
    assert_kind_of Asobi::Motion, part.spin(every: 8)
  end

  def test_sounding_on_by_teaches_to_use_a_moment
    e = assert_raises(ArgumentError) { dot.pulse.by(:mic, :low).sounding(:pop) }
    assert_includes e.message, "by(:mic)"
    assert_includes e.message, "when_clicked.sounding(:pop)"
    assert_includes e.message, "on_beat.sounding(:kick)"
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.spin.by(:mouse_x).sounding(:pop) }
      assert_includes e.message, "by(:mouse_x)"
      assert_includes e.message, "例：dot.pulse.when_clicked.sounding(:pop)"
    end
  end

  def test_sounding_on_a_motion_or_a_still_picture_teaches_where_to_write_it
    [dot.pulse, dot, dot.pulse.when_clicked.repeat(3), dot.pulse.when_clicked.spin].each do |thing|
      e = assert_raises(ArgumentError) { thing.sounding(:pop) }
      assert_includes e.message, "right after a reaction word"
      assert_includes e.message, "dot.pulse.when_clicked.sounding(:pop)"
    end
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.pulse.sounding(:kick) }
      assert_includes e.message, "反応の言葉"
      assert_includes e.message, "例：dot.pulse.when_clicked.sounding(:pop)"
    end
  end

  def test_an_unknown_sound_lists_the_names_and_the_note_form
    [:boom, :h4, :c8, :c0, :c, :cx4, "c#", 60, nil, "", "pop!"].each do |sound|
      e = assert_raises(ArgumentError) { dot.pulse.when_clicked.sounding(sound) }
      assert_includes e.message, ":pop, :kick, :snare, :hat, :clap, :bell"
      assert_includes e.message, "sounding(:c4)"
      assert_includes e.message, sound.inspect
    end
    e = assert_raises(ArgumentError) { dot.pulse.when_clicked.sounding }
    assert_includes e.message, "You gave nil"
    in_language(:ja) do
      e = assert_raises(ArgumentError) { dot.pulse.when_clicked.sounding(:boom) }
      assert_includes e.message, ":pop, :kick, :snare, :hat, :clap, :bell"
      assert_includes e.message, "（いまは :boom）"
      assert_includes e.message, "例：sounding(:pop)"
    end
  end

  def test_parts_carry_their_sound_or_their_note_never_both
    pulse = dot.pulse(every: 0.1)
    parts = reel([pulse.when_clicked.sounding(:pop), pulse.when_pressed("a").sounding(:c4),
                  pulse.on_beat(:music).sounding("C#4"), pulse.while_hovered, pulse.by(:mouse_x)].to_art)["parts"]
    assert_equal({ "fps" => 30, "turn" => "click", "sound" => "pop" }, parts["p1"].except("frames"))
    assert_equal %w[frames fps turn key note], parts["p2"].keys
    assert_equal({ "turn" => "key", "key" => "a", "note" => 60 }, parts["p2"].except("frames", "fps"))
    assert_equal({ "turn" => "beat", "from" => "music", "note" => 61 }, parts["p3"].except("frames", "fps"))
    refute parts["p4"].key?("sound") || parts["p4"].key?("note"), "silent: no sound at all"
    refute parts["p5"].key?("sound") || parts["p5"].key?("note"), "a value part never has a sound"
  end

  def test_the_same_motion_with_two_sounds_is_two_parts
    clicked = dot.pulse(every: 0.1).when_clicked
    r = reel([clicked.sounding(:pop), clicked.sounding(:kick), clicked.sounding(:pop), clicked].to_art)
    assert_equal %w[p1 p2 p3], r["parts"].keys
    assert_equal ["pop", "kick", nil], r["parts"].values.map { _1["sound"] }
    assert_equal %w[p1 p2 p1 p3], r["frames"].first.scan(/<!--asobi:(p\d+)-->/).flatten
    assert_equal r["parts"]["p1"]["frames"], r["parts"]["p2"]["frames"], "the same pictures"
  end

  def test_steps_build_sounding_parts_the_same_byte_for_byte
    thing = [dot.pulse.when_clicked.sounding(:bell), dot.spin.when_pressed("b").sounding(:bb4)].to_art.spin(every: 1)
    steps = Asobi::Reel.steps(thing, fps: 6)
    whole = steps.step(0) until steps.done?
    assert_equal JSON.generate(reel(thing, fps: 6)), JSON.generate(whole)
  end

  def test_the_data_form_carries_the_sound
    data = Asobi::Drawing.data(dot.pulse(every: 0.1).when_clicked.sounding(:pop))
    assert_equal({ "turn" => "click", "sound" => "pop" }, data["reacting"])
    data = Asobi::Drawing.data(dot.pulse(every: 0.1).when_pressed("a").sounding(:a4))
    assert_equal({ "turn" => "key", "key" => "a", "note" => 69 }, data["reacting"])
    assert_equal({ turn: "beat", from: "mic", sound: "kick" }, Asobi::Drawing.turn(dot.pulse.on_beat.sounding(:kick)))
  end

  def test_a_sounding_part_is_still_a_silent_picture_in_an_svg
    part = dot.pulse.when_clicked.sounding(:pop)
    assert_equal dot.svg, part.svg
    refute_includes part.to_svg, "pop"
  end

  # --- controls --------------------------------------------------------------

  def test_controls_false_is_written_and_true_is_left_out
    assert_equal false, reel(dot, controls: false)["controls"]
    refute reel(dot, controls: true).key?("controls")
    refute reel(dot).key?("controls")
    assert_equal false, Asobi::Reel.preview(dot.spin, controls: false)["controls"]
    keys = reel(dot.pulse.when_clicked, controls: false).keys
    assert_equal %w[frames fps view background code error controls parts], keys
    e = assert_raises(ArgumentError) { reel(dot, controls: "no") }
    assert_includes e.message, "controls: false"
  end

  def test_controls_in_a_saved_page
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dot.html")
      dot.save(path, controls: false)
      assert_includes File.read(path), '"controls":false'
      dot.spin.save(path, controls: false)
      assert_includes File.read(path), '"controls":false'
      dot.spin.save(path)
      refute_includes File.read(path), '"controls"'
    end
  end

  def test_show_carries_controls_through_the_sketch
    Asobi::Sketch.forget
    show dot, controls: false
    assert_equal false, Asobi::Sketch.shown.controls
    assert_equal false, Asobi::Sketch.reel["controls"]
    e = assert_raises(ArgumentError) { show dot, controls: :off }
    assert_includes e.message, "controls"

    first = Asobi::Sketch.run("show circle.pulse.when_clicked.spin, controls: false\n", preview: true)
    assert first["pending"]
    assert_equal false, first["controls"]
    refute first.key?("parts")
    whole = Asobi::Sketch.finish
    assert_equal false, whole["controls"]
    assert_equal "click", whole["parts"]["p1"]["turn"]

    Asobi::Sketch.run("show circle.spin, controls: false\n", preview: true)
    whole = Asobi::Sketch.finish_some(0.01) while Asobi::Sketch.waiting?
    assert_equal false, whole["controls"]
    refute Asobi::Sketch.run("show circle\n").key?("controls")
  ensure
    Asobi::Sketch.forget
  end
end
