# frozen_string_literal: true

module Asobi
  # Remembering work while one reel or one SVG document is being built.
  #
  # Pictures never change, so the same picture object always has the same
  # box and draws the same way. While a reel is built, the same picture is
  # asked again and again: the reel measures each frame, then a glow on
  # that frame measures it again; one_by_one measures every item; the one
  # spark shape that a firework repeats 1,170 times is written as SVG
  # 1,170 times. Inside Memo.during, the first answer is written down and
  # the next question about the same object gets it back.
  #
  #   Memo.during { frames.map(&:svg) }   remembered while the block runs
  #   frames.map(&:svg)                   outside: worked out every time
  #
  # The notes are kept on shelves, one per kind of answer:
  #   :box       box(IDENTITY) of a picture (Memo::Boxes, below)
  #   :moments   motion.at(seconds) (Memo.at, below)
  #   :svg       the SVG written for a picture (Asobi::SVG.fragment)
  #   :drawing   the data form of its drawing (Asobi::Drawing.data)
  # A renderer that wants to remember its own work uses a shelf of its own.
  #
  # The notes are keyed by the object itself (equal?), not by == : two
  # equal pictures would give equal answers too, but comparing whole trees
  # of pictures costs more than it saves.
  #
  # How long the notes live: exactly one Memo.during block. They are
  # thrown away when the block ends, also when it ends with an error, so
  # nothing piles up while the live view redraws a sketch for hours. A
  # Memo.during inside another one simply shares the outer notes.
  #
  # Whose notes: each thread (strictly, each fiber) has its own, kept in
  # Thread.current, so the live view's threads never share them and never
  # need a lock.
  module Memo
    NOTES = :asobi_memo # the Thread.current slot

    module_function

    # Run the block with notes, and forget them afterwards.
    #
    # A build done in pieces (Reel.steps) keeps its own notes between
    # pieces and hands them in each time, so the reuse spans the whole
    # build. Between pieces they are not in Thread.current: they live
    # only as long as the build that holds them.
    #   notes = {}
    #   Memo.during(notes) { first half }
    #   Memo.during(notes) { second half }   remembers what the first half did
    def during(notes = {})
      return yield if Thread.current[NOTES] # already inside one: share it

      Thread.current[NOTES] = notes
      begin
        yield
      ensure
        Thread.current[NOTES] = nil
      end
    end

    # The answer for +object+ on the +shelf+ (:box, :svg ...): the one
    # written down earlier, or the block's, written down now. Without notes
    # (outside Memo.during) the block simply runs.
    def recall(shelf, object)
      notes = Thread.current[NOTES]
      return yield unless notes

      found = (notes[shelf] ||= {}.compare_by_identity)
      found.fetch(object) { found[object] = yield }
    end

    # motion.at(seconds), remembered for that motion and that exact number
    # of seconds. A trail asks for the same moments again and again: the
    # picture 2 frames ago is the picture of the frame 2 frames ago.
    #
    # Only exactly the same number counts as the same moment. 1.0 and
    # 0.9999999999999999 are different moments here, even though they
    # would almost certainly draw the same: almost is not enough.
    # -0.0 is never remembered: it is the same Hash key as 0.0, but not
    # quite the same number (1.0 / -0.0 is -Infinity).
    def at(motion, seconds)
      notes = Thread.current[NOTES]
      negative_zero = seconds.zero? && (1.0 / seconds).negative?
      return motion.at(seconds) if notes.nil? || negative_zero

      moments = ((notes[:moments] ||= {}.compare_by_identity)[motion] ||= {})
      moments.fetch(seconds) { moments[seconds] = motion.at(seconds) }
    end

    # Pictures answer box(IDENTITY), the box as they stand, from the notes.
    # (Boxes under other transforms are asked far less often; they are
    # always worked out.)
    module Boxes
      def box(m)
        return super unless m.equal?(IDENTITY)

        Memo.recall(:box, self) { super }
      end
    end

    [Circle, Ellipse, Rect, Text, Space, Path, Styled, Transformed, Many].each do |picture|
      picture.prepend(Boxes)
    end
  end
end
