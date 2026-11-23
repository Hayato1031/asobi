# frozen_string_literal: true

module Asobi
  # A motion whose pages are turned by something other than the clock.
  #
  #   flower.pulse.when_clicked       a click (or tap) on it plays the motion once
  #   flower.spin.while_hovered       it loops while the pointer is over it
  #   flower.spin.when_pressed("a")   the a key plays it once (no key: any key)
  #   flower.pulse.on_beat            each beat the microphone hears plays it once
  #   flower.spin.by(:mouse_x)        the pointer, left to right, picks the frame
  #   flower.pulse.by(:mic, :low)     the strength of the low sounds picks the frame
  #
  # After a reaction word (not after by), sounding makes a sound each time
  # the motion starts to play:
  #
  #   dot.pulse.when_clicked.sounding(:pop)    one of the named sounds
  #   dot.pulse.when_clicked.sounding(:c4)     a note
  #
  # The answer is a picture, not a motion: from the outside it does not
  # change with the clock, so every picture word and motion word works on
  # it (dot.pulse.when_clicked.repeat(12).in_ring). Inside it keeps the
  # motion and who turns its pages. No Ruby runs while it plays: its
  # frames are drawn ahead, like every frame of a reel, and the player
  # picks one (see Asobi::Reel and DESIGN.md section 9).
  #
  # Like every picture it knows nothing about drawing. Its size (box) is
  # the room that all of its frames take together, so a layout, an effect
  # or the view never has to change while it plays.
  #
  #   motion  the motion it plays
  #   turn    "click", "hover", "key", "beat" or "value"
  #   key     for "key": the key, or nil for any key
  #   from    for "beat": "mic" or "music"; for "value": "mouse_x",
  #           "mouse_y", "mic" or "music"
  #   what    for a sound value: "low", "mid", "high" or "pitch"
  #           (nil: how loud it is overall)
  #   sound   what it sounds each time it starts to play: one of
  #           Sounds::NAMES ("pop"), a MIDI note number (60 is c4), or nil
  #           for silence. Two reactions that sound different are two parts.
  Reaction = Picture.define(:motion, :turn, :key, :from, :what, :sound) do
    def initialize(motion:, turn:, key: nil, from: nil, what: nil, sound: nil) = super

    def inspect = "#<Asobi::Reaction #{[turn, key, from, what, sound].compact.join(" ")} #{motion.inspect}>"
    alias_method :to_s, :inspect

    # The same reaction, with a sound each time it starts to play (a click,
    # the pointer coming over it, a key, a beat). A second sounding
    # replaces the first.
    #   dot.pulse.when_clicked.sounding(:pop)       :pop :kick :snare :hat :clap :bell
    #   ring.pulse.when_pressed("a").sounding(:c4)  a note: :c4 :cs4 :db4, or "C#4"
    def sounding(sound = nil)
      raise Messages.error(ArgumentError, :sounding_on_by, from: ":#{from}") if turn == "value"

      Reaction.new(motion:, turn:, key:, from:, what:, sound: Sounds.of(sound))
    end

    # The picture it shows at rest (its first frame).
    def rest = picture_at(0)

    # The picture of the motion at +seconds+. At the end of the loop (the
    # last frame of a value that goes the whole loop) it is the loop's end
    # (see Motion#at_end), so your own animate gets t = 1.0 there.
    def picture_at(seconds)
      return Asobi.art(motion.at_end) if seconds >= motion.every

      Asobi.art(Memo.at(motion, seconds))
    end

    # The seconds of each of its frames, and how fast to play them:
    #
    #   click, hover, key, beat   one loop of the motion, at +fps+, by the
    #                             same rule as the frames of a reel
    #                             (Reel.moments)
    #   value                     VALUES frames for the values 0.0 to 1.0, and
    #                             nil for the speed (no clock plays them).
    #                             A motion that goes out and comes back is
    #                             shown only on its way out (start to farthest),
    #                             so a bigger value is farther out; any other
    #                             motion over its whole loop, both ends in.
    def moments(fps = 30)
      return Reel.moments(motion, fps) unless turn == "value"

      to = motion.peak || motion.every
      n = Asobi::Reaction::VALUES
      [Array.new(n) { |i| to * i / (n - 1.0) }, nil]
    end

    # Its frames as pictures (the first is the rest picture). While a reel
    # is built they are worked out once (see Asobi::Memo).
    def pictures(fps = 30)
      return moments(fps).first.map { picture_at(_1) } unless fps == 30

      Memo.recall(:strip, self) { moments.first.map { picture_at(_1) } }
    end

    # The room all of its frames (at 30 a second) take together. Under a
    # plain move the room is simply moved; under anything else each frame
    # is measured again, so the box stays exact.
    def box(m)
      if m.equal?(IDENTITY)
        Asobi::Box.union(pictures.map { _1.box(IDENTITY) })
      elsif m.translation?
        room = box(IDENTITY)
        room && Asobi::Box.new(room.x0 + m.e, room.y0 + m.f, room.x1 + m.e, room.y1 + m.f)
      else
        Asobi::Box.union(pictures.map { _1.box(m) })
      end
    end
  end

  class Reaction
    # How many frames a value part has: for the values 0.0, 1/60 ... 1.0.
    VALUES = 61
  end

  Reaction.prepend(Memo::Boxes)

  # Collecting the reacting parts while a reel's frames are written.
  #
  # Inside Parts.during, the SVG writer does not draw a reacting part:
  # it asks Parts.id_for(part) and writes a marker <!--asobi:p1--> where
  # the part goes. Reel then builds each part's own frames (which may hold
  # markers of further parts) until no new part turns up.
  #
  # Equal parts (==) share one id, so dot.pulse.when_clicked.repeat(12)
  # is one part with twelve markers. Ids are p1, p2 ... in the order the
  # parts first appear.
  #
  # Outside Parts.during (a plain .svg document, a preview) id_for answers
  # nil, and the writer draws the part's rest picture in its place.
  #
  # Like Asobi::Memo, the collection is kept per thread, and a build done
  # in pieces (Reel.steps) hands its own collection in for every piece.
  module Parts
    SLOT = :asobi_parts # the Thread.current slot

    # The parts found so far, in order, with their ids.
    class Collection
      attr_reader :list

      def initialize
        @ids = {}
        @list = []
      end

      def id_for(part)
        @ids.fetch(part) do
          @list << part
          @ids[part] = "p#{@list.size}"
        end
      end

      def size = @list.size
    end

    module_function

    # Run the block collecting into +collection+, and stop afterwards.
    def during(collection)
      saved = Thread.current[SLOT]
      Thread.current[SLOT] = collection
      begin
        yield
      ensure
        Thread.current[SLOT] = saved
      end
    end

    # The id of +part+ while parts are collected, else nil.
    def id_for(part) = Thread.current[SLOT]&.id_for(part)

    # The marker that stands for a part in a frame.
    def marker(id) = "<!--asobi:#{id}-->"
  end

  # --- the reaction words --------------------------------------------------

  module Reactions
    BEAT_SOURCES = %w[mic music].freeze
    VALUE_SOURCES = %w[mouse_x mouse_y mic music].freeze
    SOUND_PARTS = %w[volume low mid high pitch].freeze

    module_function

    # A key as KeyboardEvent.key names it: one character ("a", "1", " ")
    # or a name ("Enter", "ArrowUp"). :space is the space bar.
    def key(key)
      return nil if key.nil?

      name = key.is_a?(Symbol) ? key.to_s : key
      ok = name.is_a?(String) && (name.size == 1 || name.match?(/\A[A-Za-z][A-Za-z0-9]+\z/))
      raise Messages.error(ArgumentError, :bad_key, got: key.inspect) unless ok

      name.downcase == "space" ? " " : name
    end

    def beat_source(from)
      name = from.to_s if from.is_a?(Symbol) || from.is_a?(String)
      return name if BEAT_SOURCES.include?(name)

      raise Messages.error(ArgumentError, :bad_beat_source, got: from.inspect, sources: list(BEAT_SOURCES))
    end

    def value_source(from)
      name = from.to_s if from.is_a?(Symbol) || from.is_a?(String)
      return name if VALUE_SOURCES.include?(name)
      raise Messages.error(ArgumentError, :by_mouse, got: from.inspect) if name.to_s.start_with?("mouse", "pointer")

      raise Messages.error(ArgumentError, :bad_value_source, got: from.inspect, sources: list(VALUE_SOURCES))
    end

    # What of the sound to follow; nil for the overall loudness.
    def sound_part(from, what)
      return nil if what.nil?
      raise Messages.error(ArgumentError, :by_mouse_what, from: ":#{from}", got: what.inspect) if from.start_with?("mouse")

      name = what.to_s if what.is_a?(Symbol) || what.is_a?(String)
      unless SOUND_PARTS.include?(name)
        raise Messages.error(ArgumentError, :bad_sound_part, from: ":#{from}", got: what.inspect, parts: list(SOUND_PARTS))
      end

      name == "volume" ? nil : name
    end

    def list(names) = names.map { ":#{_1}" }.join(", ")
  end

  class Motion
    # A click (or tap) on it plays the motion once, then it rests.
    #   flower.pulse.when_clicked
    def when_clicked = Reaction.new(motion: self, turn: "click")

    # It plays round and round while the pointer is over it.
    #   flower.spin.while_hovered
    def while_hovered = Reaction.new(motion: self, turn: "hover")

    # A key plays the motion once: one key, or (without one) any key.
    #   flower.spin.when_pressed("a"), flower.pulse.when_pressed
    def when_pressed(key = nil) = Reaction.new(motion: self, turn: "key", key: Reactions.key(key))

    # Each beat heard plays the motion once. :mic is the microphone;
    # :music is the sound asobi itself plays.
    #   flower.pulse.on_beat
    def on_beat(from = :mic) = Reaction.new(motion: self, turn: "beat", from: Reactions.beat_source(from))

    # A value from 0 to 1 picks the frame:
    #   flower.spin.by(:mouse_x)       the pointer, left to right
    #   flower.spin.by(:mouse_y)       the pointer, top to bottom
    #   flower.pulse.by(:mic)          how loud the microphone is
    #   flower.pulse.by(:mic, :low)    the low sounds (also :mid, :high)
    #   flower.spin.by(:mic, :pitch)   how high the sound is
    #   flower.pulse.by(:music)        the sound asobi itself plays
    def by(from, what = nil)
      raise Messages.error(ArgumentError, :flash_on_by) if flashes

      source = Reactions.value_source(from)
      Reaction.new(motion: self, turn: "value", from: source, what: Reactions.sound_part(source, what))
    end
  end

  module Art
    # The reaction words need a picture in motion. On a still picture they
    # teach where to write them; on something that becomes a motion (a list
    # holding one) they work on that motion.
    def when_clicked = Reactions.motion_of(self, :when_clicked).when_clicked
    def while_hovered = Reactions.motion_of(self, :while_hovered).while_hovered
    def when_pressed(key = nil) = Reactions.motion_of(self, :when_pressed).when_pressed(key)
    def on_beat(from = :mic) = Reactions.motion_of(self, :on_beat).on_beat(from)
    def by(from, what = nil) = Reactions.motion_of(self, :by).by(from, what)

    # sounding belongs right after a reaction word (Reaction#sounding). On
    # any other picture, or on a motion, it teaches where to write it.
    def sounding(_sound = nil) = raise(Messages.error(ArgumentError, :sounding_needs_reaction))
  end

  module Reactions
    EXAMPLES = {
      when_clicked: "flower.pulse.when_clicked", while_hovered: "flower.spin.while_hovered",
      when_pressed: "flower.spin.when_pressed(\"a\")", on_beat: "flower.pulse.on_beat",
      by: "flower.spin.by(:mouse_x)"
    }.freeze

    # The motion +thing+ is, or a teaching error naming +word+.
    def self.motion_of(thing, word)
      found = Motion.reach(thing)
      return found if found.is_a?(Motion)

      raise Messages.error(ArgumentError, :reaction_needs_motion, word:, example: EXAMPLES.fetch(word))
    end
  end

  Messages.add(:flash_on_by,
               en: "flash jumps bright the moment it starts, so it cannot follow a value with by. " \
                   "To fade in as the value grows, use fade, like:  circle.fade(from: 0, to: 1).by(:mic)",
               ja: "flash は始まった瞬間にパッと光る動きなので、by で値に合わせることはできません。" \
                   "値が大きいほど現れるようにするなら fade を使ってください。例：circle.fade(from: 0, to: 1).by(:mic)")
  Messages.add(:reaction_needs_motion,
               en: "%{word} turns the pages of a motion, so write it right after a motion word (pulse, spin, sway ...), like %{example}",
               ja: "%{word} は動きのコマをめくる言葉です。動きの言葉（pulse、spin、sway など）のすぐ後ろに書いてください。例：%{example}")
  Messages.add(:bad_key,
               en: "when_pressed needs one key, as a letter or a key name, like when_pressed(\"a\") or when_pressed(\"ArrowUp\"). Leave it out for any key. You gave %{got}.",
               ja: "when_pressed にはキーを1つ、文字かキーの名前で渡してください（いまは %{got}）。どのキーでもよければ省きます。例：when_pressed(\"a\")、when_pressed(\"ArrowUp\")")
  Messages.add(:bad_beat_source,
               en: "on_beat can listen to %{sources}, like flower.pulse.on_beat(:mic). You gave %{got}.",
               ja: "on_beat が聞けるのは %{sources} です（いまは %{got}）。例：flower.pulse.on_beat(:mic)")
  Messages.add(:bad_value_source,
               en: "by can follow %{sources}, like flower.spin.by(:mouse_x) or flower.pulse.by(:mic). You gave %{got}.",
               ja: "by が追えるのは %{sources} です（いまは %{got}）。例：flower.spin.by(:mouse_x)、flower.pulse.by(:mic)")
  Messages.add(:by_mouse,
               en: "by follows the pointer one way at a time: :mouse_x (left to right) or :mouse_y (top to bottom), like flower.spin.by(:mouse_x). You gave %{got}.",
               ja: "マウスは向きを1つ選んでください。:mouse_x（左から右）か :mouse_y（上から下）です（いまは %{got}）。例：flower.spin.by(:mouse_x)")
  Messages.add(:by_mouse_what,
               en: "by(%{from}) follows the pointer and takes nothing more, so leave out %{got}, like flower.spin.by(%{from}). The second word is for sound, like flower.pulse.by(:mic, :low)",
               ja: "by(%{from}) はマウスを追うので、%{got} は要りません。例：flower.spin.by(%{from})。2つ目の言葉は音のためのものです。例：flower.pulse.by(:mic, :low)")
  Messages.add(:bad_sound_part,
               en: "by(%{from}, ...) can follow %{parts}, like flower.pulse.by(%{from}, :low). You gave %{got}.",
               ja: "by(%{from}, ...) で追えるのは %{parts} です（いまは %{got}）。例：flower.pulse.by(%{from}, :low)")
end
