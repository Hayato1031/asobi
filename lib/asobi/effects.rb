# frozen_string_literal: true

module Asobi
  # What the effects (glow, blur, shadow, clip, blend) mean, whatever draws
  # them: how they are stored on a picture, how they move with it, and how
  # far they reach outside it. How to draw them is each renderer's business
  # (lib/asobi/svg.rb draws them with SVG filters and masks).
  #
  # An effect lives in a style under :effects, an ordered Hash:
  #   glow:   { size:, color: }   color nil: the picture's own colours
  #   blur:   amount
  #   shadow: { right:, down:, blur:, color:, opacity: }
  #   clip:   a picture (the window, in the same coordinates)
  #   blend:  "screen", "multiply" ...
  #
  # The order of the Hash is the order they were written in: the first one
  # is applied first (innermost), except blend, which is always outermost.
  module Effects
    BLENDS = %w[normal screen multiply overlay lighten darken difference].freeze

    module_function

    # +effects+ with +key+ set to +value+ (moved to the end: it is the
    # latest word).
    def put(effects, key, value) = (effects || {}).reject { |k, _| k == key }.merge(key => value).freeze

    # +node+ without the effect +key+ wherever it sits directly on it (not
    # inside a Many): so the same effect given again replaces the old one.
    def strip(node, key)
      case node
      when Transformed then Transformed.new(strip(node.art, key), node.matrix)
      when Styled
        effects = node.style[:effects]
        return node unless effects

        inner = strip(node.art, key)
        rest = effects.reject { |k, _| k == key }
        style = rest.empty? ? node.style.except(:effects) : node.style.merge(effects: rest.freeze)
        style.empty? ? inner : Styled.new(inner, style)
      else node
      end
    end

    # The effects of a Many after its pictures are moved by +matrix+.
    def transform(effects, matrix)
      k = matrix.stretch
      effects.to_h do |key, value|
        changed =
          case key
          when :glow then value.merge(size: value[:size] * k)
          when :blur then value * k
          when :shadow
            right, down = matrix.linear.apply(value[:right], value[:down])
            value.merge(right: right, down: down, blur: value[:blur] * k)
          when :clip then Asobi.transform(value, matrix)
          else value
          end
        [key, changed.frozen? ? changed : changed.freeze]
      end.freeze
    end

    # How far each effect reaches outside the picture.
    def spill(key, value)
      case key
      when :glow then value[:size] * 1.5
      when :blur then value * 3.0
      when :shadow then value[:blur] * 1.5
      else 0.0
      end
    end

    # The box of a picture with its effects, given its plain box under m.
    def grow(box, effects, m)
      return box unless effects

      effects.each do |key, value|
        break if box.nil?

        box =
          case key
          when :glow, :blur then box.grow(spill(key, value) * m.stretch)
          when :shadow
            dx, dy = m.linear.apply(value[:right], value[:down])
            moved = Box.new(box.x0 + dx, box.y0 + dy, box.x1 + dx, box.y1 + dy).grow(spill(key, value) * m.stretch)
            Box.union([box, moved])
          when :clip then intersect(box, value.box(m))
          else box
          end
      end
      box
    end

    # Where two boxes overlap (nil when they do not, or either is nil).
    def intersect(a, b)
      return nil unless a && b

      x0 = [a.x0, b.x0].max
      y0 = [a.y0, b.y0].max
      x1 = [a.x1, b.x1].min
      y1 = [a.y1, b.y1].min
      x0 > x1 || y0 > y1 ? nil : Box.new(x0, y0, x1, y1)
    end
  end
end
