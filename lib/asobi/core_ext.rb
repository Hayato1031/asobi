# frozen_string_literal: true

require_relative "pure"

# to_art is the new to_s.
#
# Ruby objects already know how to become a String (to_s), an Array (to_a),
# a Proc (to_proc). Here they learn to become a picture. The rules live in
# Asobi::Convert; these methods only open the door.
module Asobi
  module CoreExt
    module ToArt
      # 8.to_art, [3, 1, 4].to_art(as: star)
      def to_art(as: nil) = Asobi.art(self, as:)
    end

    module Turn
      # Angles in turns: 0.25.turn is 90.0 degrees.
      def turn = self * 360.0
      alias_method :turns, :turn
    end
  end
end

[Integer, Float, Rational, Array, Range, Hash, String, Symbol, NilClass].each do |klass|
  klass.include(Asobi::CoreExt::ToArt)
end
Numeric.include(Asobi::CoreExt::Turn)
