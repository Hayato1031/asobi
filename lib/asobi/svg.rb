# frozen_string_literal: true

module Asobi
  # The SVG renderer: it follows a drawing (lib/asobi/drawing.rb) and writes
  # SVG. All the SVG in asobi is in this file.
  #
  # Whole documents look like ink on paper: shapes are black unless they say
  # otherwise, the page is white, and the picture fills the page with a
  # small margin.
  #
  # The pieces are separate so the browser player can use them too: frames
  # are fragments (SVG.fragment, or art.svg) and share one viewBox (SVG.view).
  module SVG
    NAMESPACE = "http://www.w3.org/2000/svg"
    PIXELS = 512 # the larger side of a saved picture, when no paper is given

    module_function

    #   SVG.document(art)                              white page, auto margin
    #   SVG.document(art, on: :black)                  a black page
    #   SVG.document(art, on: nil)                     see-through
    #   SVG.document(art, paper: [800, 800])           centred on 800 x 800 paper
    #   SVG.document(art, grain: true)                 fine grain over it all
    #
    # Boxes and SVG already worked out while writing it are reused, then
    # forgotten (see Asobi::Memo).
    def document(art, margin: nil, background: :white, on: background, paper: nil, grain: nil)
      art = Asobi.art(art)
      Memo.during { page(Drawing.page(art, margin:, on:, paper:, grain:)) }
    end

    # The document for a page from Drawing.page.
    def page(page)
      view = page[:view]
      open_tag(view, size: page[:paper]) + background(view, page[:background]) + fragment(page[:picture]) +
        (page[:grain] ? grain(view, page[:grain]) : "") + "</svg>\n"
    end

    # The SVG of one picture, without the <svg> tag around it (what a frame
    # of a reel is).
    #
    # Inside Memo.during, the SVG written for a picture object is written
    # down and handed back the next time the same object is asked for: a
    # trail draws the same pictures frame after frame, and a firework
    # repeats one spark a thousand times. The string is frozen, because the
    # same one is handed out every time.
    def fragment(node) = Memo.recall(:svg, node) { Drawing.draw(node, Writer).freeze }

    # The viewBox [x, y, width, height] for a box (or a picture): the box
    # plus a margin, or the paper centred on the origin (see Drawing.view).
    def view(box_or_art = nil, margin: nil, paper: nil) = Drawing.view(box_or_art, margin:, paper:)

    def paper_size(paper) = Drawing.paper_size(paper)
    def grain_strength(grain) = Drawing.grain_strength(grain)

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
        %(stroke-linejoin="#{Drawing::LINE_JOIN}" stroke-linecap="#{Drawing::LINE_CAP}">)
    end

    # A rectangle of colour covering the viewBox ("" when see-through).
    def background(view, color)
      paint = Color.css(color)
      return "" if %w[none transparent].include?(paint)

      x, y, w, h = view.map { Asobi.fmt(_1) }
      %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" fill="#{Asobi.escape(paint)}"/>)
    end
  end

  module SVG
    # The painter that writes SVG (see Asobi::Drawing for what each method
    # is asked to draw). Each method answers an SVG fragment.
    #
    # SVG's own defaults are asobi's (black fill, no line, line width 1), so
    # nothing is written for them, and a colour on a <g> is inherited by
    # what is inside it, as the drawing asks.
    #
    # Gradients, filters and masks are definitions: each is written inside
    # the picture's own SVG as <defs>, with an id made from its content, so
    # a fragment is complete by itself, equal pictures give equal SVG, and
    # the same definition twice on one page is harmless. A group gathers
    # the <defs> of everything inside it to its start, once each.
    module Writer
      DEFS = %r{<defs>(.*?)</defs>}m
      LETTERS = { move: "M", line: "L", cubic: "C", close: "Z" }.freeze
      ATTRIBUTES = { fill: "fill", stroke: "stroke", stroke_width: "stroke-width", opacity: "opacity" }.freeze

      module_function

      # --- shapes --------------------------------------------------------------

      def circle(r) = %(<circle r="#{Asobi.fmt(r)}"/>)
      def ellipse(rx, ry) = %(<ellipse rx="#{Asobi.fmt(rx)}" ry="#{Asobi.fmt(ry)}"/>)

      def rect(x, y, width, height)
        %(<rect x="#{Asobi.fmt(x)}" y="#{Asobi.fmt(y)}" ) +
          %(width="#{Asobi.fmt(width)}" height="#{Asobi.fmt(height)}"/>)
      end

      def path(commands, fill_rule)
        d = commands.map { |name, *n| [LETTERS[name], *n.map { Asobi.fmt(_1) }].join(" ") }.join(" ")
        rule = fill_rule == :evenodd ? %( fill-rule="evenodd") : ""
        %(<path d="#{d}"#{rule}/>)
      end

      # Centred both ways; spaces kept as written.
      def text(string, size, font)
        %(<text text-anchor="middle" dominant-baseline="central" xml:space="preserve" ) +
          %(font-family="#{Asobi.escape(font)}" font-size="#{Asobi.fmt(size)}">) +
          "#{Asobi.escape(string)}</text>"
      end

      def nothing = ""

      # --- putting together ------------------------------------------------------

      def transformed(matrix, part)
        inner = SVG.fragment(part)
        return "" if inner.empty?

        t =
          if matrix.translation?
            "translate(#{Asobi.fmt(matrix.e)} #{Asobi.fmt(matrix.f)})"
          else
            "matrix(#{[matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].map { Asobi.fmt(_1) }.join(" ")})"
          end
        %(<g transform="#{t}">#{inner}</g>)
      end

      def styled(style, part) = render(style, SVG.fragment(part))

      # Inside a reel, a marker where the part goes (the reel carries its
      # frames, and the player puts the right one in). Anywhere else, the
      # part at rest.
      def reacting(reaction)
        id = Parts.id_for(reaction)
        id ? Parts.marker(id) : SVG.fragment(reaction.rest)
      end

      # The <defs> of the pictures inside are gathered to the front, once each.
      def group(style, parts)
        inside = parts.map { SVG.fragment(_1) }.join
        return "" if inside.empty?

        render(style, inside, hoist: inside.include?("<defs>"))
      end

      # --- styles and effects ----------------------------------------------------

      # +inside+ (SVG) drawn in +style+. With +hoist+, the <defs> inside are
      # gathered to the front.
      def render(style, inside, hoist: false)
        plain = !style.key?(:effects) && !style[:fill].is_a?(Hash) && !style[:stroke].is_a?(Hash)
        return "<g#{attributes(style)}>#{inside}</g>" if plain && !hoist

        defs = []
        if hoist
          defs.concat(inside.scan(DEFS).flatten)
          inside = inside.gsub(DEFS, "")
        end

        urls = {}.compare_by_identity
        [style[:fill], style[:stroke]].each do |paint|
          next unless paint.is_a?(Hash)

          body = gradient(paint)
          urls[paint] = SVG.id_for(body)
          defs << SVG.with_id(body, urls[paint])
        end
        out =
          if style[:sheet]
            through_window(style, inside, urls, defs)
          elsif !paint?(style)
            inside
          else
            "<g#{attributes(style, urls)}>#{inside}</g>"
          end

        style[:effects]&.each do |effect|
          body, attribute, extra = definition(effect)
          defs.concat(extra) if extra
          id = SVG.id_for(body)
          defs << SVG.with_id(body, id)
          out = %(<g #{attribute}="url(##{id})">#{out}</g>)
        end
        out = %(<g style="mix-blend-mode:#{style[:blend]}">#{out}</g>) if style[:blend]
        list = defs.uniq
        list.empty? ? out : "<defs>#{list.join}</defs>#{out}"
      end

      # Does the style give any colour, line or opacity?
      def paint?(style) = style.key?(:fill) || style.key?(:stroke) || style.key?(:stroke_width) || style.key?(:opacity)

      # SVG attributes for the colours, lines and opacity of a style. +urls+
      # gives the id of each gradient.
      def attributes(style, urls = nil)
        text = +""
        style.each do |key, value|
          name = ATTRIBUTES[key]
          next unless name

          written =
            case value
            when Numeric then Asobi.fmt(value)
            when Hash then "url(##{urls.fetch(value)})"
            else Asobi.escape(value)
            end
          text << %( #{name}="#{written}")
        end
        text
      end

      # A gradient from the drawing, as <linearGradient> or
      # <radialGradient>, without its id.
      def gradient(paint)
        from, to = paint[:colors]
        stops = %(<stop offset="0" stop-color="#{Asobi.escape(from)}"/>) +
                %(<stop offset="1" stop-color="#{Asobi.escape(to)}"/>)
        if paint[:gradient] == "radial"
          return %(<radialGradient gradientUnits="userSpaceOnUse" cx="#{Asobi.fmt(paint[:cx])}" cy="#{Asobi.fmt(paint[:cy])}" ) +
                 %(r="#{Asobi.fmt(paint[:r])}">#{stops}</radialGradient>)
        end

        %(<linearGradient gradientUnits="userSpaceOnUse" x1="#{Asobi.fmt(paint[:x1])}" y1="#{Asobi.fmt(paint[:y1])}" ) +
          %(x2="#{Asobi.fmt(paint[:x2])}" y2="#{Asobi.fmt(paint[:y2])}">#{stops}</linearGradient>)
      end

      # A group's gradient as one sheet: a rectangle of gradient seen through
      # the group's own shape (a mask). Inside the mask only the shape counts,
      # so every gradient there is drawn plain black.
      def through_window(style, inside, urls, defs)
        sheet = style[:sheet]
        box = sheet[:box]
        box = box.grow([box.width, box.height].max * 0.01 + 0.5)
        solid = {}
        style.each do |key, value|
          next if key == :opacity || !ATTRIBUTES.key?(key)

          solid[key] = value.is_a?(Hash) ? "black" : value
        end
        mask = %(<mask maskUnits="userSpaceOnUse" style="mask-type:alpha" #{region(box)}>) +
               %(<g#{attributes(solid)}>#{inside}</g></mask>)
        id = SVG.id_for(mask)
        defs << SVG.with_id(mask, id)
        fade = style[:opacity] ? %( opacity="#{Asobi.fmt(style[:opacity])}") : ""
        %(<rect #{region(box)} fill="url(##{urls.fetch(style[sheet[:paint]])})" mask="url(##{id})"#{fade}/>)
      end

      # [definition without id, the attribute that uses it, other <defs> it
      # needs] for one effect from the drawing.
      def definition(effect)
        if effect[:effect] == "clip"
          window = SVG.fragment(effect[:window])
          inner_defs = window.scan(DEFS).flatten
          window = window.gsub(DEFS, "")
          b = effect[:window_box]
          b = b.grow([b.width, b.height].max * 0.05 + 1)
          mask = %(<mask maskUnits="userSpaceOnUse" style="mask-type:alpha" #{region(b)}>#{window}</mask>)
          return [mask, "mask", inner_defs]
        end

        area = effect[:area]
        area = area.grow([area.width, area.height].max * 0.05 + 2)
        primitives =
          case effect[:effect]
          when "glow"
            sigma = effect[:size] / 2.0
            tint = effect[:color] ? %(<feFlood flood-color="#{Asobi.escape(effect[:color])}"/><feComposite in2="b" operator="in" result="b"/>) : ""
            %(<feGaussianBlur in="SourceGraphic" stdDeviation="#{Asobi.fmt(sigma)}" result="b"/>#{tint}) +
              %(<feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>)
          when "blur"
            %(<feGaussianBlur in="SourceGraphic" stdDeviation="#{Asobi.fmt(effect[:amount])}"/>)
          when "shadow"
            %(<feGaussianBlur in="SourceAlpha" stdDeviation="#{Asobi.fmt(effect[:blur] / 2.0)}"/>) +
              %(<feOffset dx="#{Asobi.fmt(effect[:right])}" dy="#{Asobi.fmt(effect[:down])}" result="o"/>) +
              %(<feFlood flood-color="#{Asobi.escape(effect[:color])}" flood-opacity="#{Asobi.fmt(effect[:opacity])}"/>) +
              %(<feComposite in2="o" operator="in"/>) +
              %(<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>)
          end
        [%(<filter filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB" #{region(area)}>#{primitives}</filter>), "filter"]
      end

      def region(b)
        %(x="#{Asobi.fmt(b.x0)}" y="#{Asobi.fmt(b.y0)}" width="#{Asobi.fmt([b.width, 0.001].max)}" height="#{Asobi.fmt([b.height, 0.001].max)}")
      end
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
    end
  end
end
