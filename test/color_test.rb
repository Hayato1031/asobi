# frozen_string_literal: true

require "test_helper"

class ColorTest < Minitest::Test
  def test_names
    assert_operator Asobi::Color::NAMES.size, :>=, 147
    assert_equal [220, 20, 60], Asobi::Color.rgb(:crimson)
    assert_equal [102, 51, 153], Asobi::Color.rgb("RebeccaPurple")
  end

  def test_codes
    assert_equal [255, 0, 102], Asobi::Color.rgb("#ff0066")
    assert_equal [255, 0, 102], Asobi::Color.rgb("#f06")
    assert_equal [255, 0, 0], Asobi::Color.rgb("hsl(0, 100%, 50%)")
    assert_equal [0, 0, 255], Asobi::Color.rgb(Asobi::Color.hsl(240, 100, 50))
    assert_equal [10, 20, 30], Asobi::Color.rgb("rgb(10, 20, 30)")
    assert_equal [128, 128, 128], Asobi::Color.rgb(gray(50.2))
  end

  def test_css
    assert_equal "crimson", Asobi::Color.css(:crimson)
    assert_equal "none", Asobi::Color.css(nil)
    assert_raises(ArgumentError) { Asobi::Color.css("#ggg") }
  end

  def test_mix
    assert_equal "#000000", Asobi::Color.mix(:black, :white, 0)
    assert_equal "#ffffff", Asobi::Color.mix(:black, :white, 1)
    assert_equal "#808080", Asobi::Color.mix(:black, :white, 0.5)
    assert_equal "#ff0000", Asobi::Color.mix("#ff0000", :blue, -1)
    assert_equal "#800080", Asobi::Color.mix(:red, "hsl(240, 100%, 50%)", 0.5)
    assert_match(/\Argba\(/, Asobi::Color.mix(:transparent, :black, 0.5))
  end
end
