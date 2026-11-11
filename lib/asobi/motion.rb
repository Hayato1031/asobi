# frozen_string_literal: true

module Asobi
  # A picture in motion: a function from time (in seconds) to a picture.
  #
  #   wobble = Asobi.motion(2) { |seconds| circle.move(right: Math.sin(seconds * Math::PI) * 10) }
  #   wobble.at(0.5)          the picture half a second in
  #   wobble.every            2.0, the seconds until it is back where it started
  #   wobble.frames(fps: 30)  one loop of pictures, lazily
  #
  # There is no frame counter and no state: the same time always gives the
  # same picture, so playing can start (or restart) anywhere.
  #
  # A Motion understands every word a picture does (move, colored, repeat,
  # in_ring, on, beside ...), applied at every moment, and every motion word
  # (spin, pulse ...) too:
  #
  #   flower.spin(every: 8).pulse(every: 1).colored(:crimson).repeat(6).in_ring
  #
  # Pictures and motions mix freely: ring.on(dot.pulse) and [dot, dot.spin]
  # are motions as well.
  class Motion
    include Art

    # Combined loops longer than this give way to their longest part.
    LONGEST = 60
    # How close two periods may be and still count as the same (seconds).
    TOLERANCE = Rational(1, 10_000)

    # Asobi::Motion.new(2) { |seconds| picture }
    def initialize(every = 1.0, &block)
      unless block
        raise Messages.error(ArgumentError, :need_block, word: :motion,
                                                         example: "Asobi.motion(2) { |seconds| circle.rotate(seconds * 180) }")
      end

      setup(Motion.seconds(every, :motion, :every, "Asobi.motion(2) { |seconds| ... }"), block, nil)
    end

    # Seconds until the motion is back where it started (a positive Float).
    attr_reader :every

    # The picture at +seconds+ (any number; it repeats every +every+ seconds).
    def at(seconds = 0)
      Check.number(seconds, word: :at, name: :seconds, example: "motion.at(0.5)")
      Motion.quietly(@seed) { Motion.node_at(@function.call(seconds.to_f), seconds.to_f) }
    end

    # One loop of pictures, evenly spaced over +every+ seconds, computed only
    # when asked for. There are every * fps of them (at least one).
    def frames(fps: 30)
      Motion.seconds(fps, :frames, :fps, "frames(fps: 30)")
      count = [(every * fps).round, 1].max
      (0...count).lazy.map { |i| at(every * i / count) }
    end

    def to_art = self

    def inspect = "#<Asobi::Motion every #{Asobi.fmt(every)}s>"
    alias to_s inspect

    # The room the motion needs: the box around its pictures over one loop.
    def bounds
      n = [[(every * 30).round, 1].max, 240].min
      Box.union(Array.new(n) { |i| at(every * i / n).box(IDENTITY) }) || Box.new(0.0, 0.0, 0.0, 0.0)
    end

    # A motion is not one picture: these answer a teaching error.
    def box(_matrix = IDENTITY) = raise(Motion.not_a_picture(self))
    def svg = raise(Motion.not_a_picture(self))
    def to_svg(**) = raise(Motion.not_a_picture(self))

    # A page that plays by itself:  flower.spin.save("flower.html")
    def save(path, **options)
      unless File.extname(path.to_s).downcase == ".html"
        raise Messages.error(ArgumentError, :bad_motion_save, path: path.to_s.inspect)
      end

      reel = Motion.reel
      raise Messages.error(NameError, :no_reel, path: path.to_s.inspect) unless reel

      reel.save(self, path, **options)
    end

    # --- the words of Asobi::Many, at every moment -------------------------

    %i[in_row in_column in_grid in_ring in_fan in_spiral scattered change_each].each do |word|
      define_method(word) do |*args, **options, &block|
        changed = Motion.combine([self]) { |(node)| Many.of(node).public_send(word, *args, **options, &block) }
        changed.at(0) # say what is wrong now, not when playing
        changed
      end
    end

    # Each one, in turn, on its own. The last motion word is done by each
    # picture of the group separately, around that picture's own centre
    # (the middle of its box before the word moves it), and each starts
    # +gap+ seconds after the one before. By default the loop is shared out
    # evenly, which makes a wave.
    #
    # So with one_by_one, pulse grows each dot in place, spin turns each one
    # where it stands, sway rocks each one. Words that only move or colour
    # (bounce, drift, orbit, fade, shift_color) look the same either way,
    # only staggered. Without one_by_one the word acts on the whole group
    # around the origin: ring.pulse breathes, ring.spin turns the ring.
    # Your own animate block also gets each picture as if it sat alone at
    # the origin, and its answer is put back in place.
    #
    # On a single picture one_by_one changes nothing.
    #
    #   dot.repeat(12).in_ring.pulse(every: 1).one_by_one
    def one_by_one(gap_ = nil, gap: gap_)
      Check.number(gap, word: :one_by_one, name: :gap, example: "one_by_one(gap: 0.1)", min: 0) unless gap.nil?
      raise Messages.error(ArgumentError, :no_motion_word) unless @stagger

      @stagger.call(gap.nil? ? :even : gap.to_f)
    end

    # Earlier moments drawn under this one: the picture +gap+, 2 * +gap+ ...
    # seconds ago, each fainter than the last. +gap+ is a short moment
    # (TRAIL_GAP seconds) unless given.
    #   flower.spin.trail, dot.orbit.trail(count: 8, gap: 0.03)
    def trail(count_ = nil, count: count_ || 5, gap: nil)
      n = Check.whole(count, word: :trail, name: :count, example: "trail(count: 5, gap: 0.05)", min: 1)
      gap = gap.nil? ? TRAIL_GAP : Check.number(gap, word: :trail, name: :gap, example: "trail(count: 5, gap: 0.05)", min: 0)
      source = self
      stagger = @stagger && ->(g) { source.stagger_by(g).trail(count: n, gap:) }
      Motion.build(every, stagger:) do |t|
        layers = n.downto(1).map do |k|
          fade = (TRAIL_FIRST - (TRAIL_FIRST - TRAIL_FAINTEST) * (k - 1) / [n - 1, 1].max).round(6)
          Asobi.restyle(source.at(t - k * gap)) { |s| s.merge(opacity: ((s[:opacity] || 1.0) * fade).round(6)) }
        end
        Many.new(layers + [source.at(t)])
      end
    end

    TRAIL_GAP = 0.05
    TRAIL_FIRST = 0.5     # the most recent copy
    TRAIL_FAINTEST = 0.1  # the oldest copy

    # --- building ----------------------------------------------------------

    class << self
      # A Motion without the checks, for asobi's own words. +stagger+ is a
      # proc(gap) that rebuilds this motion with its last word staggered.
      def build(every, stagger: nil, &function)
        allocate.tap { _1.send(:setup, every.to_f, function, stagger) }
      end

      # Like Asobi.art, but a Motion (or anything that becomes one) is
      # answered as it is instead of being refused.
      def reach(object, as: nil)
        return object if object.is_a?(Motion)
        return combine([as]) { |(shape)| reach(object, as: shape) } if as.is_a?(Motion)

        original = object
        16.times do
          return object if object.is_a?(Node) || object.is_a?(Motion)

          built_in = Convert.call(object, as)
          return built_in if built_in
          unless object.respond_to?(:to_art)
            raise Messages.error(TypeError, :not_art, thing: Asobi.send(:describe, original))
          end

          object = object.to_art
        end
        raise Messages.error(TypeError, :to_art_loop, thing: Asobi.send(:describe, original))
      end

      # The picture +thing+ shows at +seconds+.
      def node_at(thing, seconds)
        found = reach(thing)
        found.is_a?(Motion) ? found.at(seconds) : found
      end

      # Several parts (pictures or motions) made into one with +block+,
      # which gets the parts' pictures at each moment. A motion if any part
      # is one.
      def combine(parts, &block)
        motions = parts.grep(Motion).uniq(&:__id__)
        return block.call(parts) if motions.empty?

        staggerable = motions.select(&:staggerable?)
        stagger =
          if staggerable.size == 1
            chosen = staggerable.first
            lambda do |gap|
              staggered = chosen.stagger_by(gap)
              combine(parts.map { _1.equal?(chosen) ? staggered : _1 }, &block)
            end
          end
        build(lcm_period(motions.map(&:every)), stagger:) do |t|
          block.call(parts.map { _1.is_a?(Motion) ? _1.at(t) : _1 })
        end
      end

      # A motion word: +effect+ gets a picture and the phase (0.0 up to 1.0)
      # and answers that picture at that point of the loop.
      def word(receiver, period, &effect)
        source = reach(receiver)
        period = period.to_f
        every = source.is_a?(Motion) ? lcm_period([source.every, period]) : period
        make = lambda do |gap|
          build(every, stagger: gap ? nil : make) do |t|
            node = source.is_a?(Motion) ? source.at(t) : source
            if gap && node.is_a?(Many) && node.size > 1
              step = gap == :even ? period / node.size : gap
              items = node.items.each_with_index.map do |item, i|
                on_its_own(item, t) { |alone| effect.call(alone, phase(t - i * step, period)) }
              end
              Many.new(items, node.style)
            else
              node_at(effect.call(node, phase(t, period)), t)
            end
          end
        end
        make.call(nil)
      end

      # +item+ moved so the centre of its box is at the origin, changed by
      # the block, then moved back: the change happens around its own centre.
      def on_its_own(item, t)
        box = item.box(IDENTITY)
        return node_at(yield(item), t) unless box

        x = box.cx
        y = box.cy
        alone = Asobi.transform(item, Affine.translate(-x, -y))
        Asobi.transform(node_at(yield(alone), t), Affine.translate(x, y))
      end

      # Where in its loop a motion of +period+ is at time +t+: 0.0 up to 1.0.
      def phase(t, period)
        q = t / period
        f = q - q.floor
        f < 1e-9 || f > 1 - 1e-9 ? 0.0 : f
      end

      # The least common multiple of the periods, worked out in fractions;
      # the longest one when that would be more than a minute.
      def lcm_period(periods)
        fractions = periods.map { _1.to_r.rationalize(TOLERANCE) }
        lcm = fractions.reduce do |a, b|
          Rational(a.numerator.lcm(b.numerator), a.denominator.gcd(b.denominator))
        end
        lcm > LONGEST ? periods.max.to_f : lcm.to_f
      end

      # A number of seconds (more than 0), or a teaching error.
      def seconds(value, word, name, example)
        Check.number(value, word:, name:, example:, min: 0)
        unless value.positive?
          raise Messages.error(ArgumentError, :need_positive, word:, name:, example:, got: value.inspect)
        end

        value.to_f
      end

      # The size of a picture or motion, as a Box (nil when empty).
      def extent(thing)
        found = reach(thing)
        found.is_a?(Motion) ? found.bounds : found.box(IDENTITY)
      end

      def not_a_picture(motion) = Messages.error(TypeError, :motion_not_picture, thing: motion.inspect)

      # The Reel writer, when it is loaded.
      def reel
        defined?(Asobi::Reel) && Asobi::Reel.respond_to?(:save) ? Asobi::Reel : nil
      end

      # Run +block+ with seedless randomness drawn from +seed+, starting
      # from the first call each time, and put things back afterwards. So a
      # motion that scatters at every moment scatters the same way at every
      # moment, and sampling it never disturbs anything else.
      def quietly(seed)
        saved_seed = Asobi::Random.session_seed
        saved_calls = Asobi::Random.calls
        Asobi::Random.session_seed = seed
        yield
      ensure
        Asobi::Random.session_seed = saved_seed
        Asobi::Random.instance_variable_set(:@calls, saved_calls)
      end
    end

    def staggerable? = !@stagger.nil?

    # This motion with its last word staggered (see one_by_one).
    def stagger_by(gap) = @stagger.call(gap)

    private

    def setup(every, function, stagger)
      @every = every
      @function = function
      @stagger = stagger
      # Each motion takes one seed from the run's random sequence when it is
      # made, so it is the same in every evaluation of the same sketch.
      @seed = ::Random.new(Asobi::Random.next_seed).rand(1 << 64)
    end
  end

  # A picture in motion from a block that gets the time in seconds.
  #   Asobi.motion(2) { |seconds| circle.rotate(seconds * 180) }
  def self.motion(every = 1.0, &) = Motion.new(every, &)

  # --- the motion words, on every picture (and every motion) ---------------
  module Art
    # Turn round and round, once every +every+ seconds.
    def spin(every_ = nil, every: every_ || 4, clockwise: true)
      period = Motion.seconds(every, :spin, :every, "spin(every: 4)")
      sign = clockwise ? 1 : -1
      Motion.word(self, period) { |art, p| Asobi.transform(art, Affine.rotate(sign * 360.0 * p)) }
    end

    # Grow to +to+ times the size and back.
    def pulse(every_ = nil, every: every_ || 1, to: 1.2)
      period = Motion.seconds(every, :pulse, :every, "pulse(every: 1, to: 1.2)")
      Check.number(to, word: :pulse, name: :to, example: "pulse(every: 1, to: 1.2)", min: 0)
      Motion.word(self, period) { |art, p| Asobi.transform(art, Affine.scale(1 + (to - 1) * Asobi.swell(p))) }
    end

    # Rock +by+ degrees one way, then the other.
    def sway(every_ = nil, every: every_ || 2, by: 10)
      period = Motion.seconds(every, :sway, :every, "sway(every: 2, by: 10)")
      Check.number(by, word: :sway, name: :by, example: "sway(every: 2, by: 10)")
      Motion.word(self, period) { |art, p| Asobi.transform(art, Affine.rotate(by * Math.sin(2 * Math::PI * p))) }
    end

    # Go round a circle of +radius+ (clockwise from the top). Without
    # radius:, twice the picture's size (its larger side).
    def orbit(radius_ = nil, radius: radius_, every: 4)
      period = Motion.seconds(every, :orbit, :every, "orbit(radius: 40, every: 4)")
      if radius.nil?
        box = Motion.extent(self)
        radius = box ? [box.width, box.height].max : 20.0
      end
      Check.number(radius, word: :orbit, name: :radius, example: "orbit(radius: 40, every: 4)", min: 0)
      Motion.word(self, period) do |art, p|
        x, y = Geometry.polar(radius, 360.0 * p)
        Asobi.transform(art, Affine.translate(x, y))
      end
    end

    # Fade to +to+ (0 is invisible, 1 is solid) and back.
    def fade(every_ = nil, every: every_ || 2, to: 0.2)
      period = Motion.seconds(every, :fade, :every, "fade(every: 2, to: 0.2)")
      Check.number(to, word: :fade, name: :to, example: "fade(every: 2, to: 0.2)", min: 0, max: 1)
      Motion.word(self, period) do |art, p|
        amount = (1 - (1 - to) * Asobi.swell(p)).round(9) # so fade(to: 0.2) reaches exactly 0.2
        next art if amount == 1

        Asobi.restyle(art) { |s| s.merge(opacity: (s[:opacity] || 1.0) * amount) }
      end
    end

    # Jump +height+ up and fall back, like a ball: slow at the top, fast
    # near the ground.
    def bounce(height_ = nil, height: height_ || 20, every: 1)
      period = Motion.seconds(every, :bounce, :every, "bounce(height: 20, every: 1)")
      Check.number(height, word: :bounce, name: :height, example: "bounce(height: 20, every: 1)")
      Motion.word(self, period) { |art, p| Asobi.transform(art, Affine.translate(0, -height * 4 * p * (1 - p))) }
    end

    # Go there and come back, smoothly. With nothing given, to the right by
    # the picture's width.
    def drift(right_ = nil, right: right_, left: nil, up: nil, down: nil, every: 4)
      period = Motion.seconds(every, :drift, :every, "drift(right: 40, every: 4)")
      if [right, left, up, down].all?(&:nil?)
        box = Motion.extent(self)
        right = box ? box.width : 0
      end
      amounts = { right:, left:, up:, down: }.transform_values { _1 || 0 }
      amounts.each { |name, v| Check.number(v, word: :drift, name:, example: "drift(right: 40, every: 4)") }
      dx = amounts[:right] - amounts[:left]
      dy = amounts[:down] - amounts[:up]
      Motion.word(self, period) do |art, p|
        s = Asobi.swell(p)
        Asobi.transform(art, Affine.translate(dx * s, dy * s))
      end
    end

    # Change colour from +from+ (black if not given) to +to+ and back.
    #   shift_color(:gold)           black, gold, black ...
    #   shift_color(:navy, :gold)    navy, gold, navy ...
    def shift_color(first = nil, second = nil, from: nil, to: nil, every: 4)
      if second.nil?
        to ||= first
      else
        from ||= first
        to ||= second
      end
      from ||= :black
      to ||= :crimson
      period = Motion.seconds(every, :shift_color, :every, "shift_color(to: :crimson, every: 4)")
      Color.css(from)
      Color.css(to)
      Motion.word(self, period) { |art, p| Asobi.paint(art, [Color.mix(from, to, Asobi.swell(p))]) }
    end

    # Your own motion. The block gets the picture and t, which runs from
    # 0.0 up to 1.0 every +seconds+ seconds, and answers the picture then.
    #   star.animate(4) { |picture, t| picture.rotate(t * 360).grow(to: 1 + t) }
    def animate(seconds = 4, every: seconds, &block)
      unless block
        raise Messages.error(ArgumentError, :need_block, word: :animate,
                                                         example: "animate(4) { |picture, t| picture.rotate(t * 360) }")
      end

      period = Motion.seconds(every, :animate, :every, "animate(4) { |picture, t| picture.rotate(t * 360) }")
      Motion.word(self, period) { |art, t| block.call(art, t) }
    end

    # Only a picture in motion can be staggered: see Motion#one_by_one.
    def one_by_one(*, **)
      raise Messages.error(ArgumentError, :no_motion_word)
    end
  end

  class << self
    # 0 at the start of a loop, 1 halfway, 0 again at the end; smooth.
    def swell(phase) = (1 - Math.cos(2 * Math::PI * phase)) / 2

    # art.rb's versions are replaced (not wrapped) by the ones below.
    remove_method :art, :pair, :gather, :change

    # Pictures only. A Motion is a picture in motion, and is refused with a
    # hint to take one moment of it; things that become motions (a list
    # holding one, an object whose to_art answers one) answer that Motion.
    def art(object, as: nil)
      raise Motion.not_a_picture(object) if object.is_a?(Motion)

      Motion.reach(object, as:)
    end

    # The doors of art.rb, widened: when a picture meets a motion, the
    # answer is a motion that does the same at every moment.
    def pair(a, b, &block)
      Motion.combine([Motion.reach(a), Motion.reach(b)]) { |(x, y)| block.call(x, y) }
    end

    def gather(things, as: nil, &block)
      items = things.to_a
      return Motion.combine([as]) { |(shape)| gather(items, as: shape, &block) } if as.is_a?(Motion)

      Motion.combine(items.map { Motion.reach(_1, as:) }, &block)
    end

    def change(thing, &block)
      Motion.combine([Motion.reach(thing)]) { |(art)| block.call(art) }
    end
  end

  Messages.add(:motion_not_picture,
               en: "%{thing} is a picture in motion, not one still picture. Take the picture at one moment with at, like motion.at(0)",
               ja: "%{thing} は動いている絵で、止まった1枚の絵ではありません。ある時刻の絵は at で取り出せます。例：motion.at(0)")
  Messages.add(:need_positive,
               en: "%{word} needs %{name} to be more than 0 seconds, like %{example}. You gave %{got}.",
               ja: "%{word} の %{name} には 0 より大きい秒数を渡してください（いまは %{got}）。例：%{example}")
  Messages.add(:no_motion_word,
               en: "one_by_one staggers a motion word, so write it right after one (spin, pulse, sway ...), like dot.repeat(12).in_ring.pulse(every: 1).one_by_one",
               ja: "one_by_one は動きの言葉（spin、pulse、sway など）の直後に書いてください。例：dot.repeat(12).in_ring.pulse(every: 1).one_by_one")
  Messages.add(:no_reel,
               en: "saving a motion needs Asobi::Reel, which is not loaded. Use require \"asobi\", or save one moment: motion.at(0).save(\"still.svg\"). You gave %{path}.",
               ja: "動きを保存するには Asobi::Reel が必要ですが、読み込まれていません。require \"asobi\" を使うか、ある時刻の絵を保存してください（いまは %{path}）。例：motion.at(0).save(\"still.svg\")")
  Messages.add(:bad_motion_save,
               en: "Use motion.save(\"flower.html\") to save the animation or motion.at(0).save(\"still.svg\") to save one frame. You gave %{path}.",
               ja: "アニメーションの保存先には .html を指定してください（いまは %{path}）。例：motion.save(\"flower.html\")。静止画は motion.at(0).save(\"still.svg\") で保存できます。")
end
