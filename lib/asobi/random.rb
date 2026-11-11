# frozen_string_literal: true

module Asobi
  # Randomness with a memory.
  #
  # Without seed:, every run of a sketch looks different. But within one run
  # the picture stays put: the live view re-evaluates the sketch on every
  # save, and the dots must not jump around each time.
  #
  # So one "session seed" is picked when the program starts. Each evaluation
  # of a sketch begins with reset_calls!, and the n-th seedless random word
  # in that evaluation gets a seed made from (session seed, n).
  module Random
    MASK = (1 << 64) - 1
    MIX = 0x9E3779B97F4A7C15 # odd constant, spreads consecutive counts apart

    @session_seed = ::Random.new_seed & MASK
    @calls = 0

    class << self
      attr_reader :session_seed, :calls

      # Fix the session seed (for tests, or to reproduce a run).
      def session_seed=(seed)
        @session_seed = Integer(seed) & MASK
        @calls = 0
      end

      # Start counting from zero again; called before each sketch evaluation.
      def reset_calls!
        @calls = 0
      end

      # The seed for the next seedless call.
      def next_seed
        seed = (@session_seed ^ ((@calls + 1) * MIX)) & MASK
        @calls += 1
        seed
      end

      # A generator: from the explicit seed when there is one, otherwise
      # from the session seed and the call count.
      def generator(seed = nil)
        return ::Random.new(next_seed) if seed.nil?
        raise Messages.error(ArgumentError, :bad_seed, got: seed.inspect) unless seed.is_a?(Integer)

        ::Random.new(seed)
      end
    end
  end
end
