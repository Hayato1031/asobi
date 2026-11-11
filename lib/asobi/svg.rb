# frozen_string_literal: true

module Asobi
  # Whole SVG documents. The look is ink on paper: shapes are black unless
  # they say otherwise, the page is white, and the picture fills the page
  # with a small margin.
  #
  # The pieces are separate so the browser player can use them too: frames
  # are fragments (art.svg) and share one viewBox (SVG.view).
  module SVG
    NAMESPACE = "http://www.w3.org/2000/svg"
    PIXELS = 512 # the larger side of a saved picture, when no paper is given

    module_function

    #   SVG.document(art)                              white page, auto margin
    #   SVG.document(art, on: :black)                  a black page
    #   SVG.document(art, on: nil)                     see-through
    #   SVG.document(art, paper: [800, 800])           centred on 800 x 800 paper
    #   SVG.document(art, grain: true)                 fine grain over it all
    def document(art, margin: nil, background: :white, on: background, paper: nil, grain: nil)
      art = Asobi.art(art)
      strength = grain_strength(grain)
      view = view(art.box(IDENTITY), margin:, paper:)
      open_tag(view, size: paper && paper_size(paper)) + background(view, on) + art.svg +
        (strength ? grain(view, strength) : "") + "</svg>\n"
    end

    # The viewBox [x, y, width, height] for a box (or a picture): the box
    # plus a margin, or the paper centred on the origin. An empty picture
    # gets a small square so the page is never zero-sized.
    def view(box_or_art = nil, margin: nil, paper: nil)
      if paper
        w, h = paper_size(paper)
        return [-w / 2.0, -h / 2.0, w, h]
      end

      box = box_or_art.is_a?(Box) || box_or_art.nil? ? box_or_art : Asobi.art(box_or_art).box(IDENTITY)
      box ||= Box.new(-10.0, -10.0, 10.0, 10.0)
      margin ||= [[box.width, box.height].max * 0.08, 2.0].max
      Check.number(margin, word: :to_svg, name: :margin, example: "to_svg(margin: 10)", min: 0)
      box.grow(margin).to_a
    end

    # The opening <svg> tag for a viewBox. +size+ is [width, height] in
    # pixels; by default the larger side is PIXELS.
    def open_tag(view, size: nil)
      _, _, w, h = view
      size ||= begin
        k = PIXELS / [w, h, 1e-9].max
        [w * k, h * k]
      end
      %(<svg xmlns="#{NAMESPACE}" viewBox="#{view.map { Asobi.fmt(_1) }.join(" ")}" ) +
        %(width="#{Asobi.fmt(size[0])}" height="#{Asobi.fmt(size[1])}" ) +
        %(stroke-linejoin="round" stroke-linecap="round">)
    end

    # A rectangle of colour covering the viewBox ("" when see-through).
    def background(view, color)
      paint = Color.css(color)
      return "" if %w[none transparent].include?(paint)

      x, y, w, h = view.map { Asobi.fmt(_1) }
      %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" fill="#{Asobi.escape(paint)}"/>)
    end

    def paper_size(paper)
      ok = paper.is_a?(Array) && paper.size == 2 && paper.all? { Check.number?(_1) && _1.positive? }
      raise Messages.error(ArgumentError, :bad_paper, got: paper.inspect) unless ok

      paper.map(&:to_f)
    end
  end
end

module Asobi
  # Effects (glow, blur, shadow, clip, blend), drawn with SVG filters,
  # masks and mix-blend-mode.
  #
  # An effect lives in a style under :effects, an ordered Hash:
  #   glow:   { size:, color: }   color nil: the picture's own colours
  #   blur:   amount
  #   shadow: { right:, down:, blur:, color:, opacity: }
  #   clip:   a picture (the window, in the same coordinates)
  #   blend:  "screen", "multiply" ...
  #
  # Every definition (<filter>, <mask>, gradient) is written inside the
  # picture's own SVG as <defs>, with an id made from its content, so a
  # fragment is complete by itself, equal pictures give equal SVG, and the
  # same definition twice on one page is harmless. A Many gathers the
  # <defs> of everything inside it to its start, once each.
  module Effects
    BLENDS = %w[normal screen multiply overlay lighten darken difference].freeze
    DEFS = %r{<defs>(.*?)</defs>}m

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

    def intersect(a, b)
      return nil unless a && b

      x0 = [a.x0, b.x0].max
      y0 = [a.y0, b.y0].max
      x1 = [a.x1, b.x1].min
      y1 = [a.y1, b.y1].min
      x0 > x1 || y0 > y1 ? nil : Box.new(x0, y0, x1, y1)
    end

    # The SVG for a picture drawn with +style+: +inside+ is the SVG of what
    # it contains, +box+ (a block, asked only when needed) its plain box.
    # With +hoist+, the <defs> inside are gathered to the front.
    #
    # A gradient on a group (+group+) is drawn once across the whole group:
    # a rectangle of gradient seen through the group's own shape (a mask),
    # because SVG would otherwise start the gradient again in every
    # moved or turned picture inside. Pictures inside the group then take
    # the gradient too, even ones with colours of their own.
    def render(style, inside, hoist: false, group: false, &box)
      if Style.plain?(style) && !hoist
        return "<g#{Style.attributes(style)}>#{inside}</g>"
      end

      defs = []
      if hoist
        defs.concat(inside.scan(DEFS).flatten)
        inside = inside.gsub(DEFS, "")
      end
      plain_box = nil
      measured = -> { plain_box ||= [box.call] }

      urls = {}
      style.each_value do |value|
        next unless value.is_a?(Gradient)

        body = value.definition(measured.call.first)
        urls[value] = SVG.id_for(body)
        defs << SVG.with_id(body, urls[value])
      end
      out =
        if group && urls.any? && measured.call.first
          through_window(style, inside, urls, measured.call.first, defs)
        elsif style.except(:effects).empty?
          inside
        else
          "<g#{Style.attributes(style, urls)}>#{inside}</g>"
        end

      effects = style[:effects] || {}
      current = measured.call.first if effects.any?
      current = current.grow(Style.stroke_width(style) / 2.0) if current && Style.stroked?(style)
      blend = nil
      effects.each do |key, value|
        if key == :blend
          blend = value
          next
        end
        next unless current

        body, attribute, extra = definition(key, value, current)
        if body
          defs.concat(extra) if extra
          id = SVG.id_for(body)
          defs << SVG.with_id(body, id)
          out = %(<g #{attribute}="url(##{id})">#{out}</g>)
        end
        current = grow(current, { key => value }, IDENTITY)
      end
      out = %(<g style="mix-blend-mode:#{blend}">#{out}</g>) if blend && blend != "normal"
      list = defs.uniq
      list.empty? ? out : "<defs>#{list.join}</defs>#{out}"
    end

    # The group drawn as its gradient, seen through the group's shape.
    def through_window(style, inside, urls, box, defs)
      box = box.grow(Style.stroke_width(style) / 2.0) if Style.stroked?(style)
      box = box.grow([box.width, box.height].max * 0.01 + 0.5)
      gradient = style[:fill].is_a?(Gradient) ? style[:fill] : style[:stroke]
      solid = style.except(:effects, :opacity).to_h { |k, v| [k, v.is_a?(Gradient) ? "black" : v] }
      mask = %(<mask maskUnits="userSpaceOnUse" style="mask-type:alpha" #{region(box)}>) +
             %(<g#{Style.attributes(solid)}>#{inside}</g></mask>)
      id = SVG.id_for(mask)
      defs << SVG.with_id(mask, id)
      fade = style[:opacity] ? %( opacity="#{Asobi.fmt(style[:opacity])}") : ""
      %(<rect #{region(box)} fill="url(##{urls.fetch(gradient)})" mask="url(##{id})"#{fade}/>)
    end

    # [definition without id, the attribute that uses it, other <defs> it
    # needs] for one effect
    # on a picture whose box is +box+.
    def definition(key, value, box)
      if key == :clip
        window = value.svg
        inner_defs = window.scan(DEFS).flatten
        window = window.gsub(DEFS, "")
        b = value.box(IDENTITY)
        return [nil, nil] unless b

        b = b.grow([b.width, b.height].max * 0.05 + 1)
        mask = %(<mask maskUnits="userSpaceOnUse" style="mask-type:alpha" #{region(b)}>#{window}</mask>)
        return [mask, "mask", inner_defs]
      end

      area = grow(box, { key => value }, IDENTITY)
      area = area.grow([area.width, area.height].max * 0.05 + 2)
      primitives =
        case key
        when :glow
          sigma = value[:size] / 2.0
          tint = value[:color] ? %(<feFlood flood-color="#{Asobi.escape(value[:color])}"/><feComposite in2="b" operator="in" result="b"/>) : ""
          %(<feGaussianBlur in="SourceGraphic" stdDeviation="#{Asobi.fmt(sigma)}" result="b"/>#{tint}) +
            %(<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>)
        when :blur
          %(<feGaussianBlur in="SourceGraphic" stdDeviation="#{Asobi.fmt(value)}"/>)
        when :shadow
          %(<feGaussianBlur in="SourceAlpha" stdDeviation="#{Asobi.fmt(value[:blur] / 2.0)}"/>) +
            %(<feOffset dx="#{Asobi.fmt(value[:right])}" dy="#{Asobi.fmt(value[:down])}" result="o"/>) +
            %(<feFlood flood-color="#{Asobi.escape(value[:color])}" flood-opacity="#{Asobi.fmt(value[:opacity])}"/>) +
            %(<feComposite in2="o" operator="in"/>) +
            %(<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>)
        end
      [%(<filter filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB" #{region(area)}>#{primitives}</filter>), "filter"]
    end

    def region(b)
      %(x="#{Asobi.fmt(b.x0)}" y="#{Asobi.fmt(b.y0)}" width="#{Asobi.fmt([b.width, 0.001].max)}" height="#{Asobi.fmt([b.height, 0.001].max)}")
    end
  end

  module SVG
    MASK64 = (1 << 64) - 1
    FNV_PRIME = 0x100000001b3
    @ids = {}

    class << self
      # An id made from the definition itself (FNV-1a, 64 bits): equal
      # definitions get equal ids, different ones (practically) never do.
      def id_for(body)
        @ids.clear if @ids.size > 4096
        @ids[body] ||= begin
          h = 0xcbf29ce484222325
          body.each_byte { |b| h = ((h ^ b) * FNV_PRIME) & MASK64 }
          "asobi-#{h.to_s(36)}"
        end
      end

      # The definition with its id in the opening tag.
      def with_id(body, id) = body.sub(/\A<(\w+)/) { %(<#{$1} id="#{id}") }

      # Fine grain over the whole view (+strength+ 0..1), the same each
      # time: a small fragment to put after the picture.
      def grain(view, strength)
        x, y, w, h = view
        frequency = 0.9 * 600 / [w, h, 1e-9].max
        # Dark specks where the noise is high and light specks where it is
        # low, so the page keeps its colour on average, light or dark.
        k = strength * 4
        up = Asobi.fmt(k)
        down = Asobi.fmt(-k)
        half = Asobi.fmt(k / 2)
        body = %(<filter x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">) +
               %(<feTurbulence type="fractalNoise" baseFrequency="#{Asobi.fmt(frequency.round(4))}" numOctaves="2" seed="7" stitchTiles="stitch" result="n"/>) +
               %(<feColorMatrix in="n" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 #{up} 0 0 0 -#{half}" result="d"/>) +
               %(<feColorMatrix in="n" values="0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 #{down} 0 0 0 #{half}" result="l"/>) +
               %(<feMerge><feMergeNode in="d"/><feMergeNode in="l"/></feMerge></filter>)
        id = id_for(body)
        # Three views wide and tall: when the window's shape differs from the
        # picture's, a browser leaves bars beside it, and those need grain
        # too. Whatever falls outside the page is simply not drawn.
        %(<defs>#{with_id(body, id)}</defs><rect x="#{Asobi.fmt(x - w)}" y="#{Asobi.fmt(y - h)}" ) +
          %(width="#{Asobi.fmt(w * 3)}" height="#{Asobi.fmt(h * 3)}" filter="url(##{id})" style="pointer-events:none"/>)
      end

      # true is 0.12; false or nil is none; a number from 0 to 1.
      def grain_strength(grain)
        return nil if grain.nil? || grain == false
        return 0.12 if grain == true

        Check.number(grain, word: :grain, name: :grain, example: "show flower, grain: 0.3", min: 0, max: 1)
        grain.zero? ? nil : grain.to_f
      end
    end
  end
end
