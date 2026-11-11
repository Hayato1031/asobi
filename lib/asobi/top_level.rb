# frozen_string_literal: true

require_relative "pure"

module Asobi
  # The shape words, everywhere, as private methods (like puts): you call
  # them bare, never on another object.
  module TopLevel
    include Shapes
    private(*Shapes::WORDS)
  end
end

Object.include(Asobi::TopLevel)
