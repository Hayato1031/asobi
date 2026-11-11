# frozen_string_literal: true

module Asobi
  # Colours are plain values: a CSS colour name as a Symbol (:crimson), or a
  # String such as "#ff0066", "hsl(200, 70%, 50%)" or "rgb(10, 20, 30)".
  # This module checks them, turns them into SVG paint, and mixes them.
  module Color
    # The CSS named colours (CSS Color Module Level 4), name => [r, g, b].
    NAMES = {
      "aliceblue" => [240, 248, 255], "antiquewhite" => [250, 235, 215], "aqua" => [0, 255, 255],
      "aquamarine" => [127, 255, 212], "azure" => [240, 255, 255], "beige" => [245, 245, 220],
      "bisque" => [255, 228, 196], "black" => [0, 0, 0], "blanchedalmond" => [255, 235, 205],
      "blue" => [0, 0, 255], "blueviolet" => [138, 43, 226], "brown" => [165, 42, 42],
      "burlywood" => [222, 184, 135], "cadetblue" => [95, 158, 160], "chartreuse" => [127, 255, 0],
      "chocolate" => [210, 105, 30], "coral" => [255, 127, 80], "cornflowerblue" => [100, 149, 237],
      "cornsilk" => [255, 248, 220], "crimson" => [220, 20, 60], "cyan" => [0, 255, 255],
      "darkblue" => [0, 0, 139], "darkcyan" => [0, 139, 139], "darkgoldenrod" => [184, 134, 11],
      "darkgray" => [169, 169, 169], "darkgreen" => [0, 100, 0], "darkgrey" => [169, 169, 169],
      "darkkhaki" => [189, 183, 107], "darkmagenta" => [139, 0, 139], "darkolivegreen" => [85, 107, 47],
      "darkorange" => [255, 140, 0], "darkorchid" => [153, 50, 204], "darkred" => [139, 0, 0],
      "darksalmon" => [233, 150, 122], "darkseagreen" => [143, 188, 143], "darkslateblue" => [72, 61, 139],
      "darkslategray" => [47, 79, 79], "darkslategrey" => [47, 79, 79], "darkturquoise" => [0, 206, 209],
      "darkviolet" => [148, 0, 211], "deeppink" => [255, 20, 147], "deepskyblue" => [0, 191, 255],
      "dimgray" => [105, 105, 105], "dimgrey" => [105, 105, 105], "dodgerblue" => [30, 144, 255],
      "firebrick" => [178, 34, 34], "floralwhite" => [255, 250, 240], "forestgreen" => [34, 139, 34],
      "fuchsia" => [255, 0, 255], "gainsboro" => [220, 220, 220], "ghostwhite" => [248, 248, 255],
      "gold" => [255, 215, 0], "goldenrod" => [218, 165, 32], "gray" => [128, 128, 128],
      "green" => [0, 128, 0], "greenyellow" => [173, 255, 47], "grey" => [128, 128, 128],
      "honeydew" => [240, 255, 240], "hotpink" => [255, 105, 180], "indianred" => [205, 92, 92],
      "indigo" => [75, 0, 130], "ivory" => [255, 255, 240], "khaki" => [240, 230, 140],
      "lavender" => [230, 230, 250], "lavenderblush" => [255, 240, 245], "lawngreen" => [124, 252, 0],
      "lemonchiffon" => [255, 250, 205], "lightblue" => [173, 216, 230], "lightcoral" => [240, 128, 128],
      "lightcyan" => [224, 255, 255], "lightgoldenrodyellow" => [250, 250, 210], "lightgray" => [211, 211, 211],
      "lightgreen" => [144, 238, 144], "lightgrey" => [211, 211, 211], "lightpink" => [255, 182, 193],
      "lightsalmon" => [255, 160, 122], "lightseagreen" => [32, 178, 170], "lightskyblue" => [135, 206, 250],
      "lightslategray" => [119, 136, 153], "lightslategrey" => [119, 136, 153], "lightsteelblue" => [176, 196, 222],
      "lightyellow" => [255, 255, 224], "lime" => [0, 255, 0], "limegreen" => [50, 205, 50],
      "linen" => [250, 240, 230], "magenta" => [255, 0, 255], "maroon" => [128, 0, 0],
      "mediumaquamarine" => [102, 205, 170], "mediumblue" => [0, 0, 205], "mediumorchid" => [186, 85, 211],
      "mediumpurple" => [147, 112, 219], "mediumseagreen" => [60, 179, 113], "mediumslateblue" => [123, 104, 238],
      "mediumspringgreen" => [0, 250, 154], "mediumturquoise" => [72, 209, 204], "mediumvioletred" => [199, 21, 133],
      "midnightblue" => [25, 25, 112], "mintcream" => [245, 255, 250], "mistyrose" => [255, 228, 225],
      "moccasin" => [255, 228, 181], "navajowhite" => [255, 222, 173], "navy" => [0, 0, 128],
      "oldlace" => [253, 245, 230], "olive" => [128, 128, 0], "olivedrab" => [107, 142, 35],
      "orange" => [255, 165, 0], "orangered" => [255, 69, 0], "orchid" => [218, 112, 214],
      "palegoldenrod" => [238, 232, 170], "palegreen" => [152, 251, 152], "paleturquoise" => [175, 238, 238],
      "palevioletred" => [219, 112, 147], "papayawhip" => [255, 239, 213], "peachpuff" => [255, 218, 185],
      "peru" => [205, 133, 63], "pink" => [255, 192, 203], "plum" => [221, 160, 221],
      "powderblue" => [176, 224, 230], "purple" => [128, 0, 128], "rebeccapurple" => [102, 51, 153],
      "red" => [255, 0, 0], "rosybrown" => [188, 143, 143], "royalblue" => [65, 105, 225],
      "saddlebrown" => [139, 69, 19], "salmon" => [250, 128, 114], "sandybrown" => [244, 164, 96],
      "seagreen" => [46, 139, 87], "seashell" => [255, 245, 238], "sienna" => [160, 82, 45],
      "silver" => [192, 192, 192], "skyblue" => [135, 206, 235], "slateblue" => [106, 90, 205],
      "slategray" => [112, 128, 144], "slategrey" => [112, 128, 144], "snow" => [255, 250, 250],
      "springgreen" => [0, 255, 127], "steelblue" => [70, 130, 180], "tan" => [210, 180, 140],
      "teal" => [0, 128, 128], "thistle" => [216, 191, 216], "tomato" => [255, 99, 71],
      "turquoise" => [64, 224, 208], "violet" => [238, 130, 238], "wheat" => [245, 222, 179],
      "white" => [255, 255, 255], "whitesmoke" => [245, 245, 245], "yellow" => [255, 255, 0],
      "yellowgreen" => [154, 205, 50]
    }.freeze

    NUMBER = /\s*(-?\d+(?:\.\d+)?|-?\.\d+)\s*/
    HEX = /\A#(\h{3}|\h{4}|\h{6}|\h{8})\z/
    HSL = /\Ahsla?\(#{NUMBER}(?:deg)?,#{NUMBER}%,#{NUMBER}%(?:,#{NUMBER}(%?))?\)\z/i
    RGB = /\Argba?\(#{NUMBER}(%?),#{NUMBER}(%?),#{NUMBER}(%?)(?:,#{NUMBER}(%?))?\)\z/i

    module_function

    # SVG paint for a colour value: "crimson", "#ff0066", "none" ...
    # Unknown colours raise a teaching error.
    def css(value)
      return "none" if value.nil? || value == false

      name = value.to_s.strip
      key = name.downcase.delete("_ ")
      return key if NAMES.key?(key) || %w[none transparent currentcolor].include?(key)
      return name if value.is_a?(String) && rgba(name)

      hint = suggestion(key)
      raise Messages.error(ArgumentError, :bad_color, got: value.inspect, hint:)
    end

    # [r, g, b, alpha] with r, g, b in 0..255 and alpha in 0..1, or nil.
    def rgba(value)
      text = value.to_s.strip
      key = text.downcase.delete("_ ")
      return [*NAMES[key], 1.0] if NAMES.key?(key)
      return [0, 0, 0, 0.0] if key == "transparent"

      if (m = HEX.match(text))
        digits = m[1]
        digits = digits.chars.map { _1 * 2 }.join if digits.size <= 4
        values = digits.scan(/../).map { _1.to_i(16) }
        return [*values[0, 3], values.size == 4 ? values[3] / 255.0 : 1.0]
      end
      if (m = HSL.match(text))
        r, g, b = hsl_to_rgb(m[1].to_f, m[2].to_f, m[3].to_f)
        return [r, g, b, alpha(m[4], m[5])]
      end
      if (m = RGB.match(text))
        r, g, b = [[m[1], m[2]], [m[3], m[4]], [m[5], m[6]]].map do |number, percent|
          (percent == "%" ? number.to_f * 2.55 : number.to_f).clamp(0, 255).round
        end
        return [r, g, b, alpha(m[7], m[8])]
      end
      nil
    end

    # [r, g, b] (0..255), or nil for "none".
    def rgb(value) = rgba(css(value))&.first(3)

    # Halfway between two colours is mix(a, b, 0.5). Answers "#rrggbb", or
    # "rgba(...)" when either colour is see-through.
    def mix(from, to, t)
      a = rgba(css(from)) || raise(Messages.error(ArgumentError, :bad_color, got: from.inspect, hint: ""))
      b = rgba(css(to)) || raise(Messages.error(ArgumentError, :bad_color, got: to.inspect, hint: ""))
      t = t.to_f.clamp(0.0, 1.0)
      r, g, bl, al = a.zip(b).map { |x, y| x + (y - x) * t }
      return format("#%02x%02x%02x", r.round, g.round, bl.round) if al >= 1.0

      "rgba(#{r.round}, #{g.round}, #{bl.round}, #{Asobi.fmt(al)})"
    end

    # hue in degrees (0..360), saturation and lightness in 0..100.
    def hsl(hue, saturation = 70, lightness = 50)
      %w[hue saturation lightness].zip([hue, saturation, lightness]).each do |name, v|
        Check.number(v, word: :hsl, name:, example: "hsl(200, 70, 50)")
      end
      h = Asobi.fmt(hue % 360)
      s = Asobi.fmt(saturation.clamp(0, 100))
      l = Asobi.fmt(lightness.clamp(0, 100))
      "hsl(#{h}, #{s}%, #{l}%)"
    end

    # 0 is black, 100 is white.
    def gray(lightness = 50)
      Check.number(lightness, word: :gray, name: :lightness, example: "gray(80)")
      hsl(0, 0, lightness)
    end

    def hsl_to_rgb(h, s, l)
      h = (h % 360) / 360.0
      s = (s / 100.0).clamp(0.0, 1.0)
      l = (l / 100.0).clamp(0.0, 1.0)
      return [(l * 255).round] * 3 if s.zero?

      q = l < 0.5 ? l * (1 + s) : l + s - l * s
      p = 2 * l - q
      [h + 1 / 3.0, h, h - 1 / 3.0].map do |t|
        t += 1 if t.negative?
        t -= 1 if t > 1
        v =
          if t < 1 / 6.0 then p + (q - p) * 6 * t
          elsif t < 1 / 2.0 then q
          elsif t < 2 / 3.0 then p + (q - p) * (2 / 3.0 - t) * 6
          else p
          end
        (v * 255).round
      end
    end

    def alpha(number, percent)
      return 1.0 unless number

      (percent == "%" ? number.to_f / 100 : number.to_f).clamp(0.0, 1.0)
    end

    def suggestion(key)
      return "" if key.empty? || !defined?(DidYouMean::SpellChecker)

      found = DidYouMean::SpellChecker.new(dictionary: NAMES.keys).correct(key).first
      found ? Messages.text(:did_you_mean, name: found) : ""
    end
  end
end

module Asobi
  # A gradient, used as a colour:  colored(from: :gold, to: :crimson).
  #
  # +angle+ is in degrees, clockwise: 0 flows from top to bottom, 90 from
  # right to left (the gradient turned a quarter clockwise). +around+ makes
  # it flow from the centre outwards instead. Where it starts and ends is
  # worked out when drawing, from the box of the picture it paints.
  Gradient = Data.define(:from, :to, :angle, :around) do
    def self.make(from, to, angle, around)
      Asobi::Check.number(angle, word: :colored, name: :angle, example: "colored(from: :gold, to: :crimson, angle: 90)")
      new(Asobi::Color.css(from), Asobi::Color.css(to), Asobi::Gradient.tidy(angle.to_f % 360), around ? true : false)
    end

    def self.tidy(degrees)
      rounded = degrees.round(9)
      rounded = 0.0 if rounded.zero? || rounded == 360.0
      rounded
    end

    # The same gradient seen through +matrix+ (only its turning and
    # stretching matter).
    def through(matrix)
      return self if around

      radians = angle * Math::PI / 180
      x, y = matrix.linear.apply(-Math.sin(radians), Math.cos(radians))
      return self if x.abs < 1e-12 && y.abs < 1e-12

      turned = Math.atan2(-x, y) * 180 / Math::PI
      with(angle: Asobi::Gradient.tidy(turned % 360))
    end

    # The <linearGradient> or <radialGradient> for a Box (in the
    # coordinates of the picture it paints), without its id.
    def definition(box)
      stops = %(<stop offset="0" stop-color="#{Asobi.escape(from)}"/>) +
              %(<stop offset="1" stop-color="#{Asobi.escape(to)}"/>)
      box ||= Asobi::Box.new(-1.0, -1.0, 1.0, 1.0)
      if around
        r = [[box.width, box.height].max / 2.0, 1e-3].max
        return %(<radialGradient gradientUnits="userSpaceOnUse" cx="#{Asobi.fmt(box.cx)}" cy="#{Asobi.fmt(box.cy)}" ) +
               %(r="#{Asobi.fmt(r)}">#{stops}</radialGradient>)
      end

      radians = angle * Math::PI / 180
      dx = Asobi::Affine.tidy(-Math.sin(radians))
      dy = Asobi::Affine.tidy(Math.cos(radians))
      half = (dx.abs * box.width + dy.abs * box.height) / 2.0
      if half < 1e-6 # a flat line across the flow: let it flow along the line
        dx, dy = box.width >= box.height ? [1.0, 0.0] : [0.0, 1.0]
        half = [box.width, box.height].max / 2.0
        half = 1.0 if half < 1e-6
      end
      x1, y1 = box.cx - dx * half, box.cy - dy * half
      x2, y2 = box.cx + dx * half, box.cy + dy * half
      %(<linearGradient gradientUnits="userSpaceOnUse" x1="#{Asobi.fmt(x1)}" y1="#{Asobi.fmt(y1)}" ) +
        %(x2="#{Asobi.fmt(x2)}" y2="#{Asobi.fmt(y2)}">#{stops}</linearGradient>)
    end
  end
end
