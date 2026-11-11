# frozen_string_literal: true

module Asobi
  # 2D affine transform:  x' = a*x + c*y + e,  y' = b*x + d*y + f
  #
  # Coordinates are SVG's: x to the right, y downwards. With y pointing down
  # the usual rotation matrix turns things clockwise, which is what
  # rotate(45) promises.
  Affine = Data.define(:a, :b, :c, :d, :e, :f) do
    def self.translate(x, y) = new(1.0, 0.0, 0.0, 1.0, x.to_f, y.to_f)
    def self.scale(sx, sy = sx) = new(sx.to_f, 0.0, 0.0, sy.to_f, 0.0, 0.0)

    # Clockwise, in degrees. Quarter turns are exact, so rotate(90) four
    # times gives back exactly the same picture.
    def self.rotate(degrees)
      radians = degrees * Math::PI / 180
      cos = Asobi::Affine.tidy(Math.cos(radians))
      sin = Asobi::Affine.tidy(Math.sin(radians))
      new(cos, sin, -sin, cos, 0.0, 0.0)
    end

    def self.tidy(value) = value.abs < 1e-12 ? 0.0 : value

    # Composition: (self * other) applies +other+ first, then +self+.
    def *(other)
      Affine.new(
        a * other.a + c * other.b,
        b * other.a + d * other.b,
        a * other.c + c * other.d,
        b * other.c + d * other.d,
        a * other.e + c * other.f + e,
        b * other.e + d * other.f + f
      )
    end

    def apply(x, y) = [a * x + c * y + e, b * x + d * y + f]

    # Only the turning and stretching part (no moving): for directions.
    def linear = Affine.new(a, b, c, d, 0.0, 0.0)

    # The linear part undone (the identity when it can't be undone).
    def inverse_linear
      det = a * d - b * c
      return IDENTITY if det.abs < 1e-12

      Affine.new(d / det, -b / det, -c / det, a / det, 0.0, 0.0)
    end

    # How much this transform stretches lengths, on average (for strokes).
    def stretch = Math.sqrt((a * d - b * c).abs)

    def identity? = self == IDENTITY
    def translation? = a == 1.0 && b.zero? && c.zero? && d == 1.0
  end

  IDENTITY = Affine.new(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

  # Axis-aligned bounding box, in picture coordinates (y down).
  Box = Data.define(:x0, :y0, :x1, :y1) do
    def self.around(points)
      xs = points.map(&:first)
      ys = points.map(&:last)
      new(xs.min.to_f, ys.min.to_f, xs.max.to_f, ys.max.to_f)
    end

    # The box around a rectangle w x h centred on the origin, transformed.
    def self.of_rect(w, h, m)
      x = w / 2.0
      y = h / 2.0
      around([[-x, -y], [x, -y], [x, y], [-x, y]].map { m.apply(*_1) })
    end

    def self.union(boxes)
      boxes = boxes.compact
      return nil if boxes.empty?

      new(boxes.map(&:x0).min, boxes.map(&:y0).min, boxes.map(&:x1).max, boxes.map(&:y1).max)
    end

    def width = x1 - x0
    def height = y1 - y0
    def cx = (x0 + x1) / 2.0
    def cy = (y0 + y1) / 2.0
    def grow(n) = Box.new(x0 - n, y0 - n, x1 + n, y1 + n)

    # Strictly overlapping (touching edges do not count).
    def overlap?(other) = x0 < other.x1 && other.x0 < x1 && y0 < other.y1 && other.y0 < y1

    # [x, y, width, height], the order SVG's viewBox uses.
    def to_a = [x0, y0, width, height]
  end

  module Geometry
    module_function

    # The extent of a cubic Bézier along one axis: its end points plus any
    # turning points in between. p0..p3 are numbers (one coordinate).
    def cubic_extent(p0, p1, p2, p3)
      values = [p0, p3]
      # Derivative / 3 is a quadratic  qa t^2 + qb t + qc
      qa = -p0 + 3 * p1 - 3 * p2 + p3
      qb = 2 * (p0 - 2 * p1 + p2)
      qc = p1 - p0
      roots =
        if qa.abs < 1e-12
          qb.abs < 1e-12 ? [] : [-qc / qb]
        else
          disc = qb * qb - 4 * qa * qc
          disc.negative? ? [] : [(-qb + Math.sqrt(disc)) / (2 * qa), (-qb - Math.sqrt(disc)) / (2 * qa)]
        end
      roots.each do |t|
        next unless t > 0 && t < 1

        u = 1 - t
        values << u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
      end
      values.minmax
    end

    # A point at +distance+ from the origin, +degrees+ clockwise from straight up.
    def polar(distance, degrees)
      radians = degrees * Math::PI / 180
      [Affine.tidy(distance * Math.sin(radians)), Affine.tidy(-distance * Math.cos(radians))]
    end
  end
end
