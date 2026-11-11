# frozen_string_literal: true

module Asobi
  # Several pictures that are, together, one picture.
  #
  # It is Enumerable, so everything you know about collections applies
  # (each, select, each_slice, zip, count ...), and it is a picture, so
  # every word in Asobi::Art applies too.
  #
  # Moving, turning or resizing a Many does the same to each of its
  # pictures, so the answer is still a Many you can arrange. Colours given
  # to the whole Many are kept on the group (+style+), and do not override
  # colours given to the pictures inside it (as in SVG).
  Many = Data.define(:items, :style) do
    include Enumerable
    include Art
    include Node
    undef_method :with

    def initialize(items:, style: {})
      super(items: items.map { Asobi.art(_1) }.freeze, style: Asobi::Style.clean(style))
    end

    # A Many as it is; any other picture as a group of one.
    def self.of(art) = art.is_a?(Asobi::Many) ? art : new([art])

    def each(&) = items.each(&)
    def size = items.size
    def [](index) = items[index]
    def empty? = items.empty?

    def box(m)
      inner = Asobi::Box.union(items.map { _1.box(m) })
      inner = inner.grow(Asobi::Style.stroke_width(style) / 2.0 * m.stretch) if inner && Asobi::Style.stroked?(style)
      Asobi::Effects.grow(inner, style[:effects], m)
    end

    # The <defs> of the pictures inside are gathered to the front, once each.
    def svg
      inside = items.map(&:svg).join
      return "" if inside.empty?

      Asobi::Effects.render(style, inside, hoist: inside.include?("<defs>"), group: true) do
        Asobi::Box.union(items.map { _1.box(IDENTITY) })
      end
    end

    # --- arranging ---------------------------------------------------------
    # Each answers a new Many with the same pictures in new places.

    # Left to right, touching (or +gap+ apart), centred on the origin.
    def in_row(gap_ = nil, gap: gap_ || 0)
      Asobi::Check.number(gap, word: :in_row, name: :gap, example: "in_row(gap: 4)")
      line_up(gap.to_f, :x)
    end

    # Top to bottom.
    def in_column(gap_ = nil, gap: gap_ || 0)
      Asobi::Check.number(gap, word: :in_column, name: :gap, example: "in_column(gap: 4)")
      line_up(gap.to_f, :y)
    end

    # A table, filled row by row. Every cell is as big as the biggest
    # picture. Without columns:, the table is about as wide as it is tall.
    def in_grid(columns_ = nil, columns: columns_, gap: 0)
      columns ||= [Math.sqrt(size).ceil, 1].max
      columns = Asobi::Check.whole(columns, word: :in_grid, name: :columns, example: "in_grid(columns: 3)", min: 1)
      Asobi::Check.number(gap, word: :in_grid, name: :gap, example: "in_grid(columns: 3, gap: 4)")
      boxes = items.map { _1.box(IDENTITY) }
      found = boxes.compact
      cell_w = found.map(&:width).max.to_f + gap
      cell_h = found.map(&:height).max.to_f + gap
      used = [columns, size].min
      rows = (size / columns.to_f).ceil
      place do |art, _t, i|
        b = boxes[i]
        x = (i % columns - (used - 1) / 2.0) * cell_w
        y = (i / columns - (rows - 1) / 2.0) * cell_h
        b ? art.move(right: x - b.cx, down: y - b.cy) : art
      end
    end

    # Evenly around a circle, clockwise from the top. Without radius:, the
    # circle is just big enough that neighbours do not touch. With
    # facing_out: true each picture turns so its top points outwards.
    def in_ring(radius_ = nil, radius: radius_, facing_out: false)
      radius ||= auto_ring_radius
      Asobi::Check.number(radius, word: :in_ring, name: :radius, example: "in_ring(radius: 60)", min: 0)
      place do |art, t|
        angle = t * 360
        art = home(art)
        art = art.rotate(angle) if facing_out
        x, y = Asobi::Geometry.polar(radius, angle)
        art.move(right: x, down: y)
      end
    end

    # Turn each picture a little more than the last, around the centre.
    # (Move a petal off-centre, repeat it, fan it: a flower.) A fan of less
    # than a full turn is spread evenly and centred on straight up.
    def in_fan(over_ = nil, over: over_ || 360)
      Asobi::Check.number(over, word: :in_fan, name: :over, example: "in_fan(over: 180)")
      return self if empty?

      if over.abs >= 360 || size == 1
        place { |art, t| art.rotate(t * over) }
      else
        step = over.to_f / (size - 1)
        place { |art, _t, i| art.rotate(i * step - over / 2.0) }
      end
    end

    # A sunflower-seed spiral from the centre outwards. Without spacing:,
    # it is the size of the biggest picture: the closest neighbours (at the
    # centre) then just touch, and those further out have room to spare.
    def in_spiral(spacing_ = nil, spacing: spacing_)
      spacing ||= biggest_size
      Asobi::Check.number(spacing, word: :in_spiral, name: :spacing, example: "in_spiral(spacing: 8)", min: 0)
      golden = 180 * (3 - Math.sqrt(5)) # the golden angle, in degrees
      place do |art, _t, i|
        x, y = Asobi::Geometry.polar(spacing * Math.sqrt(i), i * golden)
        home(art).move(right: x, down: y)
      end
    end

    # Random places inside an area centred on the origin.
    #
    #   scattered                     an area chosen from count and size
    #   scattered(over: 200)          a 200 x 200 square
    #   scattered(over: [300, 100])   300 wide, 100 tall
    #   scattered(seed: 7)            the same picture every time, everywhere
    #
    # Without seed:, each run differs, but a run stays the same when the
    # live view evaluates the sketch again (see Asobi::Random).
    def scattered(over_ = nil, over: over_, seed: nil)
      w, h = scatter_area(over)
      random = Asobi::Random.generator(seed)
      place do |art|
        home(art).move(right: (random.rand - 0.5) * w, down: (random.rand - 0.5) * h)
      end
    end

    # Change each picture where it stands. The block gets the picture, then
    # t (0.0 for the first, approaching 1.0 for the last), then its number.
    #
    #   dot.repeat(12).in_ring.change_each { |one, t| one.grow(to: 1 + t) }
    def change_each(&block)
      unless block
        raise Asobi::Messages.error(ArgumentError, :need_block, word: :change_each,
                                    example: "change_each { |one, t, i| one.rotate(t * 90) }")
      end

      results = items.each_with_index.map { |art, i| block.call(art, i.fdiv(size), i) }
      kept = style
      Asobi.gather(results) { |arts| Asobi::Many.new(arts, kept) }
    end

    private

    def place
      Asobi::Many.new(items.each_with_index.map { |art, i| yield art, i.fdiv(size), i }, style)
    end

    def line_up(gap, axis)
      cursor = 0.0
      placed = items.map do |art|
        b = art.box(IDENTITY)
        next [art, false] unless b

        moved =
          if axis == :x
            art.move(right: cursor - b.x0, down: -b.cy)
          else
            art.move(right: -b.cx, down: cursor - b.y0)
          end
        cursor += (axis == :x ? b.width : b.height) + gap
        [moved, true]
      end
      half = [cursor - gap, 0.0].max / 2.0
      shifted = placed.map do |art, measured|
        next art unless measured

        axis == :x ? art.move(left: half) : art.move(up: half)
      end
      Asobi::Many.new(shifted, style)
    end

    # Arranging starts from scratch. Each picture is first brought home, the
    # middle of its box onto the origin, so that arranging a group that was
    # already arranged (a row made by to_art, say) gives the new arrangement
    # and not a mix of the two.
    def home(art)
      b = art.box(IDENTITY)
      return art unless b && (b.cx.abs > 1e-9 || b.cy.abs > 1e-9)

      art.move(left: b.cx, up: b.cy)
    end

    # How far a picture reaches from the origin, at most (its box corners).
    def reach(art)
      b = art.box(IDENTITY)
      return 0.0 unless b

      [[b.x0, b.y0], [b.x1, b.y0], [b.x0, b.y1], [b.x1, b.y1]].map { |x, y| Math.hypot(x, y) }.max
    end

    # Neighbours sit 2 * sin(180 / n) * radius apart; make that a little
    # more than the widest picture's reach on both sides.
    def auto_ring_radius
      r = items.map { reach(home(_1)) }.max.to_f
      return 0.0 if r.zero?
      return r * 1.1 if size <= 2

      [(2.2 * r) / (2 * Math.sin(Math::PI / size)), r * 1.1].max
    end

    def biggest_size
      sizes = items.filter_map { _1.box(IDENTITY) }.map { [_1.width, _1.height].max }
      sizes.max || 10.0
    end

    def scatter_area(over)
      if over.nil?
        side = biggest_size * 2 * Math.sqrt([size, 1].max)
        return [side, side]
      end

      w, h = over.is_a?(Array) ? over : [over, over]
      ok = (over.is_a?(Array) ? over.size == 2 : true) && [w, h].all? { Asobi::Check.number?(_1) && _1 >= 0 }
      raise Asobi::Messages.error(ArgumentError, :bad_area, got: over.inspect) unless ok

      [w.to_f, h.to_f]
    end
  end
end
