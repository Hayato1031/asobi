# frozen_string_literal: true

module Asobi
  # Asobi::Art is to pictures what Enumerable is to collections.
  #
  # Enumerable asks you for one method, +each+, and gives you everything
  # else. Asobi::Art asks you for one method, +to_art+, and gives you every
  # word in this module:
  #
  #   class Flower
  #     include Asobi::Art
  #     def to_art = ellipse(width: 12, height: 32).move(up: 22).repeat(8).in_fan
  #   end
  #
  #   Flower.new.rotate(15).colored(:crimson).save("flower.svg")
  #
  # Every word answers a new picture. Nothing is drawn "onto" anything, and
  # no picture is ever changed in place.
  module Art
    # The shape words (circle, rect ...) are available, privately, inside
    # any class that includes Art, even without require "asobi".
    include Shapes
    private(*Shapes::WORDS)

    # Where save sends each kind of file. Later parts of asobi add more
    # (".html" for motion), as  Asobi::Art::SAVERS[".html"] = ->(art, path, **options) { ... }
    SAVERS = {
      ".svg" => ->(art, path, **options) { File.write(path, SVG.document(Asobi.art(art), **options)) }
    }

    # --- combining ---------------------------------------------------------

    # This picture on top of +other+.
    def on(other) = Asobi.pair(self, other) { |a, b| Many.new([b, a]) }

    # +other+ on top of this picture.
    def under(other) = Asobi.pair(self, other) { |a, b| Many.new([a, b]) }

    # a + b is a.under(b): what you write later lies on top.
    def +(other) = under(other)

    # Copies in the same place, until you arrange them.  a * 12
    def repeat(count = 2, times: count)
      n = Check.whole(times, word: :repeat, name: :times, example: "repeat(12)")
      Asobi.change(self) { |art| Many.new(Array.new(n, art)) }
    end

    def *(count) = repeat(count)

    # Side by side, this one on the left.
    def beside(other, gap: 0)
      Check.number(gap, word: :beside, name: :gap, example: "a.beside(b, gap: 4)")
      Asobi.pair(self, other) { |a, b| Many.new([a, b]).in_row(gap:) }
    end

    # Stacked, this one on top.
    def above(other, gap: 0)
      Check.number(gap, word: :above, name: :gap, example: "a.above(b, gap: 4)")
      Asobi.pair(self, other) { |a, b| Many.new([a, b]).in_column(gap:) }
    end

    # --- changing ----------------------------------------------------------
    # Every change happens around the origin (the centre of a fresh shape).

    def move(right: 0, left: 0, up: 0, down: 0)
      { right:, left:, up:, down: }.each do |name, v|
        Check.number(v, word: :move, name:, example: "move(right: 10, up: 5)")
      end
      Asobi.change(self) { |art| Asobi.transform(art, Affine.translate(right - left, down - up)) }
    end

    # Clockwise, in degrees.  rotate(45), rotate(0.25.turn)
    def rotate(degrees = 45)
      Check.number(degrees, word: :rotate, name: :degrees, example: "rotate(45)")
      Asobi.change(self) { |art| Asobi.transform(art, Affine.rotate(degrees)) }
    end

    # scale(2), or scale(width: 2, height: 1) to stretch one way only.
    def scale(factor = nil, width: nil, height: nil)
      factor = 2 if factor.nil? && width.nil? && height.nil?
      w = width || factor || 1
      h = height || factor || 1
      Check.number(w, word: :scale, name: :width, example: "scale(width: 2, height: 1)")
      Check.number(h, word: :scale, name: :height, example: "scale(width: 2, height: 1)")
      Asobi.change(self) { |art| Asobi.transform(art, Affine.scale(w, h)) }
    end

    def grow(amount = nil, to: amount || 2)
      Check.number(to, word: :grow, name: :to, example: "grow(to: 2)")
      scale(to)
    end

    def shrink(amount = nil, to: amount || 0.5)
      Check.number(to, word: :shrink, name: :to, example: "shrink(to: 0.5)")
      scale(to)
    end

    # Left becomes right.
    def mirror = scale(width: -1, height: 1)

    # Top becomes bottom.
    def flip = scale(width: 1, height: -1)

    # --- colouring ---------------------------------------------------------

    # One colour paints the picture. Several colours on a Many go round its
    # pictures in turn; on a single picture the first one is used.
    #
    # With from: or to: (or angle:, around:) it is a gradient instead:
    #
    #   colored(from: :gold, to: :crimson)            top to bottom
    #   colored(from: :gold, to: :crimson, angle: 90) turned 90 degrees clockwise
    #   colored(from: :white, to: :navy, around: true) from the centre outwards
    #   colored(:gold, :crimson, around: true)        the two colours, as from and to
    #
    # A missing from is crimson and a missing to is navy. On a Many the
    # gradient flows once across the whole group. It belongs to the
    # picture: move, turn or resize the picture and the gradient goes along.
    def colored(*colors, from: nil, to: nil, angle: nil, around: nil)
      if [from, to, angle, around].any? { !_1.nil? }
        gradient = Gradient.make(from || colors[0] || :crimson, to || colors[1] || :navy, angle || 0, around || false)
        return Asobi.change(self) { |art| Asobi.paint(art, [gradient]) }
      end

      colors = [:crimson] if colors.empty?
      paints = colors.map { Color.css(_1) }
      Asobi.change(self) { |art| Asobi.paint(art, paints) }
    end

    # No fill, just the line.
    def outlined(color = :black, width: 1)
      line = Color.css(color)
      Check.number(width, word: :outlined, name: :width, example: "outlined(:black, width: 1)", min: 0)
      Asobi.change(self) { |art| Asobi.restyle(art) { |s| s.merge(fill: "none", stroke: line, stroke_width: width.to_f) } }
    end

    # Keep the fill, add a line around it.
    def stroke(color = :black, width: 1)
      line = Color.css(color)
      Check.number(width, word: :stroke, name: :width, example: "stroke(:black, width: 1)", min: 0)
      Asobi.change(self) { |art| Asobi.restyle(art) { |s| s.merge(stroke: line, stroke_width: width.to_f) } }
    end

    # 0 is invisible, 1 is solid.
    def opacity(value = 0.5)
      Check.number(value, word: :opacity, name: :value, example: "opacity(0.5)", min: 0, max: 1)
      Asobi.change(self) { |art| Asobi.restyle(art) { |s| s.merge(opacity: value.to_f) } }
    end

    # --- effects -----------------------------------------------------------
    # Sizes are lengths in the picture, so effects grow and shrink with it.
    # The same effect given again replaces the old one.

    # A soft light around the edges, +size+ wide, in the picture's own
    # colours (or in +color+).  glowing, glowing(8), glowing(color: :gold)
    def glowing(size_ = nil, size: size_ || 4, color: nil)
      Check.number(size, word: :glowing, name: :size, example: "glowing(size: 4)", min: 0)
      paint = color.nil? ? nil : Color.css(color)
      Asobi.change(self) { |art| Asobi.affect(art, :glow, { size: size.to_f, color: paint }.freeze) }
    end

    # Out of focus.  blurred, blurred(4)
    def blurred(amount_ = nil, amount: amount_ || 2)
      Check.number(amount, word: :blurred, name: :amount, example: "blurred(amount: 2)", min: 0)
      Asobi.change(self) { |art| Asobi.affect(art, :blur, amount.to_f) }
    end

    # How the picture mixes with what lies under it:
    # :screen (lighter where they overlap), :multiply (darker), :overlay,
    # :lighten, :darken, :difference, :normal.
    def blended(mode = :screen)
      name = mode.to_s.downcase
      unless (mode.is_a?(Symbol) || mode.is_a?(String)) && Effects::BLENDS.include?(name)
        raise Messages.error(ArgumentError, :bad_blend, got: mode.inspect,
                                                       modes: Effects::BLENDS.map { ":#{_1}" }.join(", "))
      end

      Asobi.change(self) { |art| Asobi.affect(art, :blend, name.freeze) }
    end

    # A soft shadow, +down+ and +right+ from the picture.
    def shadowed(down_ = nil, down: down_ || 2, right: 0, blur: 3, color: :black, opacity: 0.4)
      example = "shadowed(down: 2, right: 0, blur: 3)"
      Check.number(down, word: :shadowed, name: :down, example:)
      Check.number(right, word: :shadowed, name: :right, example:)
      Check.number(blur, word: :shadowed, name: :blur, example:, min: 0)
      Check.number(opacity, word: :shadowed, name: :opacity, example: "shadowed(opacity: 0.4)", min: 0, max: 1)
      shade = { right: right.to_f, down: down.to_f, blur: blur.to_f, color: Color.css(color), opacity: opacity.to_f }.freeze
      Asobi.change(self) { |art| Asobi.affect(art, :shadow, shade) }
    end

    # Only what shows through +shape+, as if through a window. The shape is
    # used where it is.  flower.clipped_by(circle(20))
    # Without a shape: a round window 0.8 of the picture's narrower side across.
    def clipped_by(shape = nil)
      if shape.nil? # a round window, 0.8 of the narrower side across
        box = defined?(Motion) ? Motion.extent(self) : Asobi.art(self).box(IDENTITY)
        box ||= Box.new(-10.0, -10.0, 10.0, 10.0)
        shape = Asobi.transform(Asobi.circle(radius: [[box.width, box.height].min * 0.4, 0.001].max),
                                Affine.translate(box.cx, box.cy))
      end
      Asobi.pair(self, shape) { |art, window| Asobi.affect(art, :clip, window) }
    end

    # Earlier moments drawn under a moving picture, fainter and fainter.
    # A still picture has no past: it stays as it is.
    def trail(count_ = nil, count: count_ || 5, gap: nil)
      n = Check.whole(count, word: :trail, name: :count, example: "trail(count: 5, gap: 0.05)", min: 1)
      Check.number(gap, word: :trail, name: :gap, example: "trail(count: 5, gap: 0.05)", min: 0) unless gap.nil?
      return self unless defined?(Motion)

      found = Motion.reach(self)
      found.is_a?(Motion) ? found.trail(count: n, gap:) : self
    end

    # --- arranging ---------------------------------------------------------
    # The words of Asobi::Many work on every picture: a single picture is a
    # group of one, so circle.in_ring or heart.scattered just work.
    ARRANGING = %i[in_row in_column in_grid in_ring in_fan in_spiral scattered change_each].freeze

    ARRANGING.each do |word|
      define_method(word) do |*args, **options, &block|
        Asobi.change(self) { |art| Many.of(art).public_send(word, *args, **options, &block) }
      end
    end

    # --- measuring ---------------------------------------------------------

    def bounds = Asobi.art(self).box(IDENTITY) || Box.new(0.0, 0.0, 0.0, 0.0)
    def width = bounds.width
    def height = bounds.height

    # --- leaving Ruby ------------------------------------------------------

    def to_svg(**options) = SVG.document(Asobi.art(self), **options)

    def save(path, **options)
      saver = SAVERS[File.extname(path.to_s).downcase]
      unless saver
        raise Messages.error(ArgumentError, :bad_save, got: path.inspect, kinds: SAVERS.keys.join(" / "))
      end

      saver.call(self, path.to_s, **options)
      path
    end
  end

  # Marker for the built-in picture values. Each answers box(affine) (its
  # bounding box under a transform, or nil when empty) and svg (a fragment).
  module Node
    def to_art = self
  end

  class << self
    # Ask anything to become a picture.
    #
    #   Asobi.art(8)                       a disc of radius 8
    #   Asobi.art([3, 1, 4], as: star)     three stars in a row
    #   Asobi.art(planet)                  whatever planet.to_art answers
    def art(object, as: nil)
      original = object
      16.times do
        return object if object.is_a?(Node)

        built_in = Convert.call(object, as)
        return built_in if built_in
        raise Messages.error(TypeError, :not_art, thing: describe(original)) unless object.respond_to?(:to_art)

        object = object.to_art
      end
      raise Messages.error(TypeError, :to_art_loop, thing: describe(original))
    end

    # The one door every two-picture word goes through (on, under, +,
    # beside, above). Later parts of asobi widen it to pictures in motion.
    def pair(a, b) = yield(art(a), art(b))

    # The one door every list of things goes through on its way to becoming
    # pictures (Array, Range and Hash to_art, change_each ...).
    def gather(things, as: nil) = yield(things.to_a.map { art(_1, as:) })

    # The one door every one-picture word (move, colored, repeat ...) goes
    # through.
    def change(thing) = yield(art(thing))

    # --- building blocks for the words -------------------------------------

    # Apply an affine transform. A Many passes it on to each of its
    # pictures, so it stays a Many you can still arrange; its own effects
    # and gradient are moved, turned and resized to match.
    def transform(node, matrix)
      case node
      when Many then Many.new(node.items.map { transform(_1, matrix) }, Style.transform(node.style, matrix))
      when Transformed
        combined = matrix * node.matrix
        combined.identity? ? node.art : Transformed.new(node.art, combined)
      else
        matrix.identity? ? node : Transformed.new(node, matrix)
      end
    end

    # Change the style of a picture. The block gets the current style Hash
    # and answers the new one. Styling the same picture again replaces what
    # was there: the latest word wins.
    def restyle(node, &edit)
      case node
      when Transformed then Transformed.new(restyle(node.art, &edit), node.matrix)
      when Styled
        # Effects put around a moved picture stay outside; colours go in.
        return Styled.new(restyle(node.art, &edit), node.style) if Style.effects_only?(node.style)

        Styled.new(node.art, edit.call(node.style))
      when Many then Many.new(node.items, edit.call(node.style))
      else Styled.new(node, edit.call({}))
      end
    end

    # Paint with one colour, or (on a Many) cycle several over its pictures.
    # A picture that is only a line (fill: none) gets its line recoloured.
    def paint(node, colors)
      case node
      when Transformed
        # A gradient keeps the direction it was given as seen from outside.
        inside = colors.map { _1.is_a?(Gradient) ? _1.through(node.matrix.inverse_linear) : _1 }
        Transformed.new(paint(node.art, inside), node.matrix)
      when Styled
        return Styled.new(paint(node.art, colors), node.style) if Style.effects_only?(node.style)

        restyle(node) { |s| Style.paint(s, colors.first) }
      when Many
        return restyle(node) { |s| Style.paint(s, colors.first) } if colors.size == 1

        items = node.items.each_with_index.map { |item, i| paint(item, [colors[i % colors.size]]) }
        Many.new(items, node.style)
      else
        restyle(node) { |s| Style.paint(s, colors.first) }
      end
    end

    # Put an effect (:glow, :blur, :shadow, :clip, :blend) on a picture. The
    # same effect again replaces the old one.
    def affect(node, key, value)
      case node
      when Many then Many.new(node.items, node.style.merge(effects: Effects.put(node.style[:effects], key, value)))
      when Styled
        Styled.new(Effects.strip(node.art, key), node.style.merge(effects: Effects.put(node.style[:effects], key, value)))
      else Styled.new(Effects.strip(node, key), { effects: Effects.put(nil, key, value) })
      end
    end

    # Numbers as SVG likes them: short, no trailing zeros, never "-0".
    def fmt(number)
      rounded = number.to_f.round(3)
      rounded = 0.0 if rounded.zero?
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
    end

    def escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    private

    def describe(object)
      text = object.inspect
      text = "#{text[0, 40]}..." if text.size > 43
      "#{text} (#{object.class})"
    end
  end

  # Styles are small frozen Hashes: :fill, :stroke, :stroke_width, :opacity,
  # and :effects (an ordered Hash of glow, blur, shadow, clip, blend). Fill
  # and stroke are CSS colour strings or a Gradient.
  module Style
    ORDER = %i[fill stroke stroke_width opacity effects].freeze
    PAINT = %i[fill stroke stroke_width opacity].freeze

    module_function

    def clean(style) = style.slice(*ORDER).sort_by { ORDER.index(_1.first) }.to_h.freeze

    # Colour a picture: its fill, or its line when it has no fill.
    def paint(style, color)
      if style[:fill] == "none" && style[:stroke] && style[:stroke] != "none"
        style.merge(stroke: color)
      else
        style.merge(fill: color)
      end
    end

    def stroked?(style) = style[:stroke] && style[:stroke] != "none"
    def stroke_width(style) = style[:stroke_width] || 1.0
    def effects_only?(style) = style.key?(:effects) && (style.keys & PAINT).empty?
    def plain?(style) = !style.key?(:effects) && style.values.none?(Gradient)

    # The style after the picture it belongs to is moved by +matrix+ (used
    # by a Many, whose pictures are moved one by one).
    def transform(style, matrix)
      return style if plain?(style)

      changed = style.to_h do |key, value|
        case value
        when Gradient then [key, value.through(matrix)]
        else [key, key == :effects ? Effects.transform(value, matrix) : value]
        end
      end
      changed.freeze
    end

    # SVG attributes. +urls+ gives the id for each Gradient.
    def attributes(style, urls = {})
      style.filter_map do |key, value|
        next if key == :effects

        text =
          case value
          when Numeric then Asobi.fmt(value)
          when Gradient then "url(##{urls.fetch(value)})"
          else Asobi.escape(value)
          end
        %( #{key.to_s.tr("_", "-")}="#{text}")
      end.join
    end
  end
end

module Asobi
  # How Ruby's own objects become pictures (DESIGN §7). This lives here,
  # not in core_ext, so that require "asobi/pure" can do Asobi.art(8)
  # without touching Integer.
  module Convert
    GAP = 4

    module_function

    # A picture, or nil when +object+ is not one of Ruby's own kinds.
    def call(object, as)
      case object
      when nil then Asobi.nothing
      when Numeric then object.real? ? number(object, as) : nil
      when String then Asobi.text(object)
      when Symbol then Asobi.text(object.to_s)
      when Array then sequence(object, as)
      when Range then sequence(range_items(object), as)
      when Hash then table(object, as)
      end
    end

    # A size: a disc of that radius, or +as+ resized so that half of its
    # larger side is that size. Negative: the same, as a line only.
    def number(n, as)
      Check.number(n, word: :to_art, name: :number, example: "8.to_art")
      return Asobi.nothing if n.zero?

      size = n.abs.to_f
      picture =
        if as.nil?
          Asobi.circle(radius: size)
        else
          shape = Asobi.art(as)
          box = shape.box(IDENTITY)
          half = box && [box.width, box.height].max / 2.0
          half && half.positive? ? shape.scale(size / half) : shape
        end
      n.negative? ? picture.outlined : picture
    end

    # Side by side with a small gap; a list of lists becomes stacked rows.
    def sequence(items, as)
      Asobi.gather(items, as:) do |arts|
        many = Many.new(arts)
        items.any?(Array) ? many.in_column(gap: GAP) : many.in_row(gap: GAP)
      end
    end

    # One row per pair, "key beside value", stacked.
    def table(hash, as)
      Asobi.gather(hash.to_a.flatten(1), as:) do |arts|
        rows = arts.each_slice(2).map { |key, value| Many.new([key, value]).in_row(gap: GAP) }
        Many.new(rows).in_column(gap: GAP)
      end
    end

    def range_items(range)
      if range.end.nil? || range.begin.nil? || (range.end.is_a?(Float) && range.end.infinite?)
        raise Messages.error(ArgumentError, :endless, got: range.inspect)
      end

      range.to_a
    rescue TypeError
      raise Messages.error(ArgumentError, :endless, got: range.inspect)
    end
  end
end

Asobi::Messages.add(:bad_blend,
                    en: "blended can mix in these ways: %{modes}, like blended(:screen). You gave %{got}.",
                    ja: "blended の混ざり方は %{modes} から選んでください（いまは %{got}）。例：blended(:screen)")
