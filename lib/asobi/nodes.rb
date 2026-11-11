# frozen_string_literal: true

module Asobi
  # The picture values themselves. Each is an immutable Data value centred
  # on the origin, and answers:
  #
  #   box(m)  the bounding Box once transformed by Affine m (nil if empty)
  #   svg     an SVG fragment, without the outer <svg> tag
  #
  # Data's own +with+ is removed: asobi has no word "with" (DESIGN §5).
  module Picture
    def self.define(*fields, &)
      Data.define(*fields) do
        include Art
        include Node
        undef_method :with
        class_eval(&)
      end
    end
  end

  Circle = Picture.define(:r) do
    def box(m) = Asobi::Ellipse.box_of(r, r, m)
    def svg = %(<circle r="#{Asobi.fmt(r)}"/>)
  end

  Ellipse = Picture.define(:rx, :ry) do
    # Exact box of a transformed ellipse.
    def self.box_of(rx, ry, m)
      hx = Math.hypot(m.a * rx, m.c * ry)
      hy = Math.hypot(m.b * rx, m.d * ry)
      Asobi::Box.new(m.e - hx, m.f - hy, m.e + hx, m.f + hy)
    end

    def box(m) = Asobi::Ellipse.box_of(rx, ry, m)
    def svg = %(<ellipse rx="#{Asobi.fmt(rx)}" ry="#{Asobi.fmt(ry)}"/>)
  end

  Rect = Picture.define(:w, :h) do
    def box(m) = Asobi::Box.of_rect(w, h, m)

    def svg
      %(<rect x="#{Asobi.fmt(-w / 2.0)}" y="#{Asobi.fmt(-h / 2.0)}" ) +
        %(width="#{Asobi.fmt(w)}" height="#{Asobi.fmt(h)}"/>)
    end
  end

  # Words, centred on the origin. The box is an estimate: about 0.6 of the
  # size per Latin letter, a full size per wide (e.g. Japanese) character.
  Text = Picture.define(:string, :size, :font) do
    def initialize(string:, size: 16.0, font: nil)
      super(string: string.to_s.dup.freeze, size: size.to_f, font: font&.to_s&.freeze)
    end

    def estimated_width
      string.each_char.sum { |ch| ch.ascii_only? ? 0.6 : 1.0 } * size
    end

    def box(m) = string.empty? ? nil : Asobi::Box.of_rect(estimated_width, size * 1.2, m)

    def svg
      %(<text text-anchor="middle" dominant-baseline="central" xml:space="preserve" ) +
        %(font-family="#{Asobi.escape(font || "sans-serif")}" font-size="#{Asobi.fmt(size)}">) +
        "#{Asobi.escape(string)}</text>"
    end
  end

  # Invisible, but takes up room. Useful as a gap in a row.
  Space = Picture.define(:w, :h) do
    def box(m) = Asobi::Box.of_rect(w, h, m)
    def svg = ""
  end

  # Any outline made of straight and curved pieces, possibly several of them
  # (a ring is two circles with fill_rule: :evenodd, so the hole is clear).
  #
  # +commands+ is a list of
  #   [:move, x, y]                          start a new piece here
  #   [:line, x, y]                          straight to (x, y)
  #   [:cubic, x1, y1, x2, y2, x, y]         cubic Bézier to (x, y)
  #   [:close]                               straight back to the piece's start
  #
  # Build one with Path.new(commands: [...], fill_rule: :nonzero), or with
  # the helpers Path.build { |pen| ... }, Path.polyline and Path.smooth.
  # A Path is filled (black) unless styled; open lines are given
  # outlined(:black) by the shape words.
  Path = Picture.define(:commands, :fill_rule) do
    def initialize(commands:, fill_rule: :nonzero)
      clean = commands.map do |command|
        name, *numbers = command
        name = name.to_sym
        unless Asobi::Path::ARITY[name] == numbers.size && numbers.all?(Numeric)
          raise ArgumentError, "Path command #{command.inspect} is not one of " \
                               "[:move, x, y], [:line, x, y], [:cubic, x1, y1, x2, y2, x, y], [:close]"
        end
        [name, *numbers.map(&:to_f)].freeze
      end
      unless %i[nonzero evenodd].include?(fill_rule.to_sym)
        raise ArgumentError, "fill_rule is :nonzero or :evenodd (got #{fill_rule.inspect})"
      end

      super(commands: clean.freeze, fill_rule: fill_rule.to_sym)
    end

    # Straight lines through [x, y] points.
    def self.polyline(points, closed: false, fill_rule: :nonzero)
      first, *rest = points
      commands = [[:move, *first], *rest.map { [:line, *_1] }]
      commands << [:close] if closed
      new(commands:, fill_rule:)
    end

    # A smooth curve through every point (Catmull-Rom, drawn as cubic
    # Béziers). Closed curves wrap around smoothly too.
    def self.smooth(points, closed: false, fill_rule: :nonzero)
      return polyline(points, closed:, fill_rule:) if points.size < 3

      n = points.size
      at = closed ? ->(i) { points[i % n] } : ->(i) { points[i.clamp(0, n - 1)] }
      commands = [[:move, *points[0]]]
      (closed ? n : n - 1).times do |i|
        p0, p1, p2, p3 = at.(i - 1), at.(i), at.(i + 1), at.(i + 2)
        c1 = [p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0]
        c2 = [p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0]
        commands << [:cubic, *c1, *c2, *p2]
      end
      commands << [:close] if closed
      new(commands:, fill_rule:)
    end

    #   Path.build(fill_rule: :evenodd) do |pen|
    #     pen.move(0, -10).curve(5, -10, 10, -5, 10, 0).line(0, 10).close
    #   end
    def self.build(fill_rule: :nonzero)
      pen = Asobi::Path::Pen.new
      yield pen
      new(commands: pen.commands, fill_rule:)
    end

    def closed? = commands.any? { _1.first == :close }

    # Exact box, curves included: an affine image of a Bézier is the Bézier
    # of the transformed control points.
    def box(m)
      return nil if commands.empty?

      xs = []
      ys = []
      current = [0.0, 0.0]
      commands.each do |name, *n|
        case name
        when :move, :line
          current = m.apply(n[0], n[1])
          xs << current[0]
          ys << current[1]
        when :cubic
          c1 = m.apply(n[0], n[1])
          c2 = m.apply(n[2], n[3])
          to = m.apply(n[4], n[5])
          xs.concat(Asobi::Geometry.cubic_extent(current[0], c1[0], c2[0], to[0]))
          ys.concat(Asobi::Geometry.cubic_extent(current[1], c1[1], c2[1], to[1]))
          current = to
        end
      end
      Asobi::Box.new(xs.min, ys.min, xs.max, ys.max)
    end

    def svg
      letters = { move: "M", line: "L", cubic: "C", close: "Z" }
      d = commands.map { |name, *n| [letters[name], *n.map { Asobi.fmt(_1) }].join(" ") }.join(" ")
      rule = fill_rule == :evenodd ? %( fill-rule="evenodd") : ""
      %(<path d="#{d}"#{rule}/>)
    end
  end

  class Path
    ARITY = { move: 2, line: 2, cubic: 6, close: 0 }.freeze

    # Collects path commands for Path.build.
    class Pen
      attr_reader :commands

      def initialize = @commands = []
      def move(x, y) = add(:move, x, y)
      def line(x, y) = add(:line, x, y)
      def curve(x1, y1, x2, y2, x, y) = add(:cubic, x1, y1, x2, y2, x, y)
      def close = add(:close)

      private

      def add(*command)
        @commands << command
        self
      end
    end
  end

  # A picture with colours, lines or opacity. Built by Asobi.restyle.
  Styled = Picture.define(:art, :style) do
    def initialize(art:, style:)
      super(art:, style: Asobi::Style.clean(style))
    end

    def box(m)
      inner = art.box(m)
      inner = inner.grow(Asobi::Style.stroke_width(style) / 2.0 * m.stretch) if inner && Asobi::Style.stroked?(style)
      Asobi::Effects.grow(inner, style[:effects], m)
    end

    def svg = Asobi::Effects.render(style, art.svg) { art.box(IDENTITY) }
  end

  # A picture moved, turned or resized. Built by Asobi.transform.
  Transformed = Picture.define(:art, :matrix) do
    def box(m) = art.box(m * matrix)

    def svg
      inner = art.svg
      return "" if inner.empty?

      t =
        if matrix.translation?
          "translate(#{Asobi.fmt(matrix.e)} #{Asobi.fmt(matrix.f)})"
        else
          "matrix(#{matrix.to_h.values.map { Asobi.fmt(_1) }.join(" ")})"
        end
      %(<g transform="#{t}">#{inner}</g>)
    end
  end
end
