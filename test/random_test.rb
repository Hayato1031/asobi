# frozen_string_literal: true

require "test_helper"

class RandomTest < Minitest::Test
  def scatter = circle.repeat(10).scattered(over: 100)

  def teardown
    Asobi::Random.session_seed = 1234
  end

  def test_same_session_and_order_gives_same_pictures
    Asobi::Random.session_seed = 42
    first = [scatter, scatter]
    Asobi::Random.reset_calls!
    second = [scatter, scatter]
    assert_equal first, second
    refute_equal first[0], first[1] # the second call is a different scatter
  end

  def test_different_session_seed_differs
    Asobi::Random.session_seed = 1
    a = scatter
    Asobi::Random.session_seed = 2
    refute_equal a, scatter
  end

  def test_explicit_seed_is_always_the_same
    Asobi::Random.session_seed = 1
    a = circle.repeat(10).scattered(seed: 7)
    Asobi::Random.session_seed = 99
    assert_equal a, circle.repeat(10).scattered(seed: 7)
    assert_equal 0, Asobi::Random.calls # seeded calls do not count
  end

  def test_bad_seed
    e = assert_raises(ArgumentError) { circle.repeat(2).scattered(seed: "x") }
    assert_includes e.message, "scattered(seed: 7)"
  end

  def test_counter
    Asobi::Random.session_seed = 5
    scatter
    scatter
    assert_equal 2, Asobi::Random.calls
    Asobi::Random.reset_calls!
    assert_equal 0, Asobi::Random.calls
  end
end
