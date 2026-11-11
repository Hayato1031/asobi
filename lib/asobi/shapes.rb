# frozen_string_literal: true

module Asobi
  # The words that make shapes. Each answers a picture centred on the
  # origin; none of them draws anything. Every number may be left out, and
  # the first one may be given without its name:
  #
  #   circle                  radius 10
  #   circle(radius: 12)      or, once you know it,  circle(12)
  #
  # With require "asobi" they work everywhere, like puts. With
  # require "asobi/pure" write Asobi.circle(...).
  module Shapes
    def circle(radius_ = nil, radius: radius_ || 10)
      Circle.new(Shapes.size(radius, :circle, :radius, "circle(radius: 10)"))
    end

    def ellipse(width_ = nil, height_ = nil, width: width_ || 30, height: height_ || 20)
      w = Shapes.size(width, :ellipse, :width, "ellipse(width: 30, height: 20)")
      h = Shapes.size(height, :ellipse, :height, "ellipse(width: 30, height: 20)")
      Ellipse.new(w / 2.0, h / 2.0)
    end

    def rect(width_ = nil, height_ = nil, width: width_ || 30, height: height_ || 20)
      w = Shapes.size(width, :rect, :width, "rect(width: 30, height: 20)")
      h = Shapes.size(height, :rect, :height, "rect(width: 30, height: 20)")
      Rect.new(w, h)
    end

    def square(size_ = nil, size: size_ || 20)
      s = Shapes.size(size, :square, :size, "square(size: 20)")
      Rect.new(s, s)
    end

    # Equilateral, pointing up; +size+ is the length of a side. Centred on
    # its bounding box, so it lines up with other shapes.
    def triangle(size_ = nil, size: size_ || 20)
      s = Shapes.size(size, :triangle, :size, "triangle(size: 20)")
      h = s * Math.sqrt(3) / 2
      Path.polyline([[0.0, -h / 2], [s / 2.0, h / 2], [-s / 2.0, h / 2]], closed: true)
    end

    # +sides+ equal sides, one corner pointing straight up.
    def polygon(sides_ = nil, radius_ = nil, sides: sides_ || 6, radius: radius_ || 10)
      n = Check.whole(sides, word: :polygon, name: :sides, example: "polygon(sides: 6)", min: 3)
      r = Shapes.size(radius, :polygon, :radius, "polygon(sides: 6, radius: 10)")
      Path.polyline(Array.new(n) { |i| Geometry.polar(r, i * 360.0 / n) }, closed: true)
    end

    def star(points_ = nil, radius_ = nil, points: points_ || 5, radius: radius_ || 10, inner: nil)
      n = Check.whole(points, word: :star, name: :points, example: "star(points: 5)", min: 2)
      r = Shapes.size(radius, :star, :radius, "star(points: 5, radius: 10)")
      inner = Shapes.size(inner || r * 0.45, :star, :inner, "star(radius: 10, inner: 4)")
      corners = Array.new(n * 2) { |i| Geometry.polar(i.even? ? r : inner, i * 180.0 / n) }
      Path.polyline(corners, closed: true)
    end

    # A straight black line lying flat.
    def line(length_ = nil, length: length_ || 20)
      l = Shapes.size(length, :line, :length, "line(length: 20)")
      Path.polyline([[-l / 2, 0.0], [l / 2, 0.0]]).outlined(:black, width: 1)
    end

    def text(string = "asobi", size: 16, font: nil)
      Text.new(string.to_s, Shapes.size(size, :text, :size, "text(\"ruby\", size: 16)"), font)
    end

    # Joins the points in order, centred on the origin.
    #   path([0, 0], [40, -30], [80, 0])                 an open line
    #   path([0, 0], [40, -30], [80, 0], closed: true)   a filled shape
    #   path(..., smooth: true)                          a smooth curve
    def path(*points, closed: false, smooth: false)
      points = points.first if points.size == 1 && points.first.is_a?(Array) && points.first.first.is_a?(Array)
      points = [[0, 0], [40, -30], [80, 0]] if points.empty?
      points = Shapes.points(points)
      cx = (points.map(&:first).minmax.sum) / 2.0
      cy = (points.map(&:last).minmax.sum) / 2.0
      points = points.map { |x, y| [x - cx, y - cy] }
      shape = smooth ? Path.smooth(points, closed:) : Path.polyline(points, closed:)
      closed ? shape : shape.outlined(:black, width: 1)
    end

    # A piece of a circle, drawn as a line. Angles are in degrees: 0 is
    # straight up, and they grow clockwise, so 0 to 180 is the right half.
    # Centred on the middle of its circle, so arcs of one circle line up.
    #   arc                          the right half of a circle
    #   arc(30, from: 90, to: 360)   three quarters
    #   arc(from: 0, to: 360)        a whole circle (as a line)
    def arc(radius_ = nil, radius: radius_ || 20, from: 0, to: 180)
      r = Shapes.size(radius, :arc, :radius, "arc(radius: 20, from: 0, to: 180)")
      a = Check.number(from, word: :arc, name: :from, example: "arc(from: 0, to: 180)")
      b = Check.number(to, word: :arc, name: :to, example: "arc(from: 0, to: 180)")
      Path.build do |pen|
        pen.move(*Geometry.polar(r, a))
        Shapes.arc_to(pen, 0.0, 0.0, r, a, b)
      end.outlined(:black, width: 1)
    end

    # A smooth line lying flat: +waves+ full ups and downs across +length+,
    # +height+ from the top of a crest to the bottom of a trough.
    def wave(length_ = nil, height_ = nil, waves_ = nil,
             length: length_ || 100, height: height_ || 10, waves: waves_ || 3)
      example = "wave(length: 100, height: 10, waves: 3)"
      l = Shapes.size(length, :wave, :length, example)
      h = Shapes.size(height, :wave, :height, example)
      w = Check.number(waves, word: :wave, name: :waves, example:, min: 0)
      halves = [(w * 2).round, 1].max
      step = l / halves
      amp = h / 2.0
      Path.build do |pen|
        pen.move(-l / 2, 0.0)
        halves.times do |i|
          x0 = -l / 2 + i * step
          y = (i.even? ? -1 : 1) * amp * 4.0 / 3
          pen.curve(x0 + step * 0.4244, y, x0 + step * 0.5756, y, x0 + step, 0.0)
        end
      end.outlined(:black, width: 1)
    end

    # A doughnut; the hole really is a hole, so what is behind shows through.
    def ring(radius_ = nil, thickness_ = nil, radius: radius_ || 20, thickness: thickness_ || 4)
      example = "ring(radius: 20, thickness: 4)"
      r = Shapes.size(radius, :ring, :radius, example)
      t = Shapes.size(thickness, :ring, :thickness, example)
      return Circle.new(r) if t >= r

      Path.build(fill_rule: :evenodd) do |pen|
        [r, r - t].each do |radius_here|
          pen.move(0.0, -radius_here)
          Shapes.arc_to(pen, 0.0, 0.0, radius_here, 0, 360)
          pen.close
        end
      end
    end

    # +size+ is the width of the whole heart.
    def heart(size_ = nil, size: size_ || 20)
      s = Shapes.size(size, :heart, :size, "heart(size: 20)")
      half = [
        [0.0, 0.95], [-0.2, 0.75, -1.0, 0.25, -1.0, -0.28],
        [-1.0, -0.72, -0.68, -0.95, -0.38, -0.95],
        [-0.18, -0.95, -0.05, -0.82, 0.0, -0.62]
      ]
      Shapes.fit(Shapes.mirrored(half), width: s)
    end

    # A leaf that starts at the origin and grows straight up, so
    # petal.repeat(8).in_fan is already a flower.
    def petal(length_ = nil, width_ = nil, length: length_ || 20, width: width_ || 10)
      example = "petal(length: 20, width: 10)"
      l = Shapes.size(length, :petal, :length, example)
      w = Shapes.size(width, :petal, :width, example)
      raw = Path.build do |pen|
        pen.move(0.0, 0.0)
        pen.curve(-1.0, -0.15, -0.8, -0.75, 0.0, -1.0)
        pen.curve(0.8, -0.75, 1.0, -0.15, 0.0, 0.0)
        pen.close
      end
      box = raw.box(IDENTITY)
      Shapes.map_path(raw) { |x, y| [x * w / box.width, y * l] }
    end

    # A crescent opening to the right; +size+ is its height.
    def moon(size_ = nil, size: size_ || 20)
      s = Shapes.size(size, :moon, :size, "moon(size: 20)")
      d = 0.45
      inner = 0.8
      x = (d * d + 1 - inner * inner) / (2 * d) # where the two circles cross
      tip = Math.asin(x) * 180 / Math::PI
      back = Math.asin((x - d) / inner) * 180 / Math::PI
      raw = Path.build do |pen|
        pen.move(*Geometry.polar(1.0, tip))
        Shapes.arc_to(pen, 0.0, 0.0, 1.0, tip, -180 - tip)
        Shapes.arc_to(pen, d, 0.0, inner, 180 - back, 360 + back)
        pen.close
      end
      Shapes.fit(raw.commands, height: s)
    end

    # A water drop, point up; +size+ is its height.
    def drop(size_ = nil, size: size_ || 20)
      s = Shapes.size(size, :drop, :size, "drop(size: 20)")
      raw = Path.build do |pen|
        pen.move(0.0, -1.0)
        pen.curve(0.1, -0.65, 0.7, -0.3, 0.7, 0.3)
        Shapes.arc_to(pen, 0.0, 0.3, 0.7, 90, 270)
        pen.curve(-0.7, -0.3, -0.1, -0.65, 0.0, -1.0)
        pen.close
      end
      Shapes.fit(raw.commands, height: s)
    end

    # One outline of soft bumps over a flat bottom; +size+ is its width.
    def cloud(size_ = nil, size: size_ || 30)
      s = Shapes.size(size, :cloud, :size, "cloud(size: 30)")
      Shapes.fit(Shapes.cloud_outline(Shapes::CLOUD_BUMPS), width: s)
    end

    # Invisible, but takes up room.
    def space(width_ = nil, height_ = nil, width: width_ || 10, height: height_ || width)
      w = Shapes.size(width, :space, :width, "space(width: 10)")
      h = Shapes.size(height, :space, :height, "space(width: 10, height: 20)")
      Space.new(w, h)
    end

    # The empty picture.
    def nothing = Many.new([])

    # hue in degrees (0..360), saturation and lightness 0..100.
    def hsl(hue = 0, saturation = 70, lightness = 50) = Color.hsl(hue, saturation, lightness)

    # 0 is black, 100 is white.
    def gray(lightness = 50) = Color.gray(lightness)

    WORDS = instance_methods(false).freeze

    # Circles [x, y, radius] for cloud, left to right, all resting on y = 0.
    CLOUD_BUMPS = [[-0.62, -0.3, 0.3], [-0.2, -0.45, 0.45], [0.3, -0.38, 0.38], [0.68, -0.28, 0.28]].freeze

    # Adds the arc of a circle (centre cx, cy) from one angle to another as
    # cubic curves of at most 90 degrees each. The pen must already be at
    # the start.
    def self.arc_to(pen, cx, cy, r, from, to)
      span = (to - from).to_f
      pieces = [(span.abs / 90.0 - 1e-9).ceil, 1].max
      theta = span / pieces * Math::PI / 180
      k = 4.0 / 3 * Math.tan(theta / 4)
      pieces.times do |i|
        a0 = (from + span / pieces * i) * Math::PI / 180
        a1 = a0 + theta
        pen.curve(cx + r * (Math.sin(a0) + k * Math.cos(a0)), cy + r * (-Math.cos(a0) + k * Math.sin(a0)),
                  cx + r * (Math.sin(a1) - k * Math.cos(a1)), cy + r * (-Math.cos(a1) - k * Math.sin(a1)),
                  cx + r * Math.sin(a1), cy - r * Math.cos(a1))
      end
    end

    # The left half of a symmetric outline, given as [x, y] (move) and
    # [c1x, c1y, c2x, c2y, x, y] (curve) from the bottom up to the middle
    # top, becomes the whole outline.
    def self.mirrored(half)
      move, *curves = half
      [[:move, *move]] + curves.map { [:cubic, *_1] } + mirror_tail(curves, move) + [[:close]]
    end

    def self.mirror_tail(curves, move)
      pts = [move, *curves.map { _1[-2, 2] }]
      curves.each_index.reverse_each.map do |i|
        c = curves[i]
        [:cubic, -c[2], c[3], -c[0], c[1], -pts[i][0], pts[i][1]]
      end
    end

    # Scales commands evenly to the given width or height and centres them
    # on the origin.
    def self.fit(commands, width: nil, height: nil)
      raw = Path.new(commands:, fill_rule: :nonzero)
      box = raw.box(IDENTITY)
      k = width ? width / box.width : height / box.height
      map_path(raw) { |x, y| [(x - box.cx) * k, (y - box.cy) * k] }
    end

    def self.map_path(path)
      commands = path.commands.map do |name, *n|
        [name, *n.each_slice(2).flat_map { |x, y| yield(x, y) }]
      end
      Path.new(commands:, fill_rule: path.fill_rule)
    end

    def self.cloud_outline(bumps)
      pen = Path::Pen.new
      cuts = bumps.each_cons(2).map { |a, b| upper_crossing(a, b) }
      bumps.each_with_index do |(cx, cy, r), i|
        from = i.zero? ? 180.0 : angle(cx, cy, *cuts[i - 1])
        to = i == bumps.size - 1 ? 180.0 : angle(cx, cy, *cuts[i])
        to += 360 while to <= from
        pen.move(*Geometry.polar(r, from).then { |x, y| [cx + x, cy + y] }) if i.zero?
        arc_to(pen, cx, cy, r, from, to)
      end
      pen.close
      pen.commands
    end

    def self.angle(cx, cy, x, y) = Math.atan2(x - cx, cy - y) * 180 / Math::PI

    def self.upper_crossing(a, b)
      dx = b[0] - a[0]
      dy = b[1] - a[1]
      d = Math.hypot(dx, dy)
      along = (a[2]**2 - b[2]**2 + d * d) / (2 * d)
      h = Math.sqrt([a[2]**2 - along**2, 0].max)
      [a[0] + (along * dx - h * dy) / d, a[1] + (along * dy + h * dx) / d].then do |p1|
        q = [a[0] + (along * dx + h * dy) / d, a[1] + (along * dy - h * dx) / d]
        p1[1] < q[1] ? p1 : q
      end
    end

    def self.size(value, word, name, example) = Check.number(value, word:, name:, example:, min: 0)

    def self.points(list)
      clean = list.map do |point|
        ok = point.is_a?(Array) && point.size == 2 && point.all? { Check.number?(_1) }
        raise Messages.error(ArgumentError, :bad_point, got: point.inspect) unless ok

        point.map(&:to_f)
      end
      raise Messages.error(ArgumentError, :few_points, got: clean.size) if clean.size < 2

      clean
    end
  end

  # Asobi.circle(...) and friends, for require "asobi/pure".
  extend Shapes
end
