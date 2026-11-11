# frozen_string_literal: true

require "test_helper"

class MessagesTest < Minitest::Test
  def test_english_matches_design
    e = assert_raises(ArgumentError) { square.repeat(4).in_grid(columns: 0) }
    assert e.message.start_with?("in_grid needs a whole number of columns (1 or more), like in_grid(columns: 3)")
  end

  def test_japanese_matches_design
    in_language(:ja) do
      e = assert_raises(ArgumentError) { square.repeat(4).in_grid(columns: 0) }
      assert_equal "in_grid の columns には 1 以上の整数を渡してください（いまは 0）。例：in_grid(columns: 3)", e.message
      e = assert_raises(TypeError) { Asobi.art(Object.new) }
      assert_includes e.message, "to_art を書いてください"
    end
  end

  def test_every_message_has_an_example_in_both_languages
    Asobi::Messages::TEXTS.each do |key, texts|
      next if key == :did_you_mean

      assert_match(/like|Example|Use|Give|Make/, texts[:en], key.to_s)
      assert_includes texts[:ja], "例：", key.to_s
    end
  end

  def test_detects_language_from_environment
    assert_equal :ja, Asobi::Messages.detect({ "LANG" => "ja_JP.UTF-8" })
    assert_equal :en, Asobi::Messages.detect({ "LANG" => "en_US.UTF-8" })
    assert_equal :en, Asobi::Messages.detect({ "LC_ALL" => "C", "LANG" => "ja_JP.UTF-8" })
    assert_equal :ja, Asobi::Messages.detect({ "LC_ALL" => "", "LC_MESSAGES" => "ja_JP", "LANG" => "en_US" })
    assert_equal :en, Asobi::Messages.detect({})
  end

  def test_language_setter
    Asobi.language = "ja"
    assert_equal :ja, Asobi.language
    Asobi.language = :en
    assert_equal :en, Asobi.language
    assert_raises(ArgumentError) { Asobi.language = :fr }
  end

  def test_wrong_inputs_raise_with_examples
    {
      -> { circle.repeat(1.5) } => "repeat(12)",
      -> { circle.rotate("a lot") } => "rotate(45)",
      -> { circle.move(up: nil) } => "move(right: 10, up: 5)",
      -> { circle.scale("x") } => "scale(width: 2, height: 1)",
      -> { circle.repeat(3).in_ring(radius: -1) } => "in_ring(radius: 60)",
      -> { circle.repeat(3).in_spiral(spacing: :big) } => "in_spiral(spacing: 8)",
      -> { circle.repeat(3).in_fan(over: "all") } => "in_fan(over: 180)",
      -> { circle.colored(:nope) } => "colored(:crimson)",
      -> { circle.to_svg(paper: 800) } => "paper: [800, 800]"
    }.each do |action, example|
      e = assert_raises(ArgumentError, TypeError) { action.call }
      assert_includes e.message, example
    end
  end
end
