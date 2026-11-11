# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class PureTest < Minitest::Test
  def test_pure_does_not_touch_ruby
    lib = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      require "asobi/pure"
      raise "Integer changed" if 1.respond_to?(:to_art)
      raise "Array changed" if [].respond_to?(:to_art)
      raise "Numeric changed" if 1.respond_to?(:turn)
      raise "Object changed" if Object.private_method_defined?(:circle)
      raise "circle" unless Asobi.circle(3) == Asobi::Circle.new(3.0)
      raise "art" unless Asobi.art(8) == Asobi.circle(8)
      raise "as" unless Asobi.art([3, 1, 4], as: Asobi.star).size == 3
      print "ok"
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)
    assert status.success?, err
    assert_equal "ok", out
  end
end
