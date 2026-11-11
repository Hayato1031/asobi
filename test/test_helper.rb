# frozen_string_literal: true

ENV["ASOBI_LIVE"] = "0"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "asobi"
require "minitest/autorun"

module AsobiTestHelper
  # Run a block with the message language fixed, then restore it.
  def in_language(lang)
    Asobi.language = lang
    yield
  ensure
    Asobi.language = :en
  end

  def assert_close(expected, actual, delta = 1e-6)
    assert_in_delta expected, actual, delta
  end

  def assert_box(box, x0, y0, x1, y1, delta = 1e-6)
    assert_in_delta x0, box.x0, delta, "x0"
    assert_in_delta y0, box.y0, delta, "y0"
    assert_in_delta x1, box.x1, delta, "x1"
    assert_in_delta y1, box.y1, delta, "y1"
  end
end

class Minitest::Test
  include AsobiTestHelper

  def setup
    Asobi.language = :en
  end
end
