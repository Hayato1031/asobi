# frozen_string_literal: true

module Asobi
  # The drawing: what a renderer has to do to draw a picture, with nothing
  # left to work out.
  #
  # There are three layers:
  #
  #   the picture   Circle, Many, Styled ... (nodes.rb, many.rb): what it is
  #                 and how big it is. Knows nothing about drawing.
  #   the drawing   this file: the picture as drawing instructions, every
  #                 asobi rule already applied (where a gradient starts and
  #                 ends, which box an effect covers, blend goes outermost).
  #   renderers     SVG (svg.rb) today; a Canvas or WebGL player later. They
  #                 follow the instructions and add their own technique.
  #
  # So two renderers never disagree about a rule: the rule is applied here,
  # once, and they only see its result.
  #
  # == Two forms of the same instructions
  #
  # 1. Step by step (fast, for Ruby renderers). Drawing.draw(picture, painter)
  #    looks at one picture and calls ONE method of +painter+:
  #
  #      painter.circle(r)                    a circle of radius r
  #      painter.ellipse(rx, ry)              an ellipse with radii rx and ry
  #      painter.rect(x, y, width, height)    a rectangle; x, y is its top-left
  #                                           corner (it is centred on the origin)
  #      painter.path(commands, fill_rule)    see Asobi::Path (:nonzero or :evenodd)
  #      painter.text(string, size, font)     words, centred on the origin both ways
  #      painter.nothing                      draws nothing (Space, or a picture
  #                                           clipped by a window that shows nothing)
  #      painter.transformed(matrix, part)    +part+ under an Affine (six numbers)
  #      painter.styled(style, part)          +part+ in a style (see below)
  #      painter.group(style, parts)          +parts+ in order, the last on top,
  #                                           together in a style
  #      painter.reacting(reaction)           a part whose frames something
  #                                           else turns (see "Reacting parts")
  #
  #    A +part+ is a picture again: the painter draws it by handing it back
  #    to Drawing.draw (or to its own memory of parts it already drew, as
  #    SVG does). Whatever the painter's methods answer, Drawing.draw answers.
  #
  # 2. As data (for anything else, e.g. a browser). Drawing.data(picture)
  #    and Drawing.of(picture) answer the same instructions as plain Hashes,
  #    Arrays, Strings, numbers, true/false and nil, ready for JSON.generate.
  #    It is made by one more painter, Recorder, below:
  #
  #      { "shape" => "circle", "r" => 5.0 }
  #      { "transform" => [a, b, c, d, e, f], "draw" => {...} }
  #      { "style" => {...}, "draw" => {...} }
  #      { "group" => [{...}, ...], "style" => {...} }
  #      { "reacting" => { "turn" => "click", "sound" => "pop" }, "fps" => 30, "frames" => [{...}, ...] }
  #
  # == Shapes and transforms
  #
  # Every shape is drawn around the origin, x to the right and y DOWN.
  # Moving it is a transform: x' = a*x + c*y + e, y' = b*x + d*y + f
  # (the order of the six numbers in the data form: a, b, c, d, e, f).
  #
  # == Style
  #
  # A style is a Hash with any of these (missing means "as around it"):
  #
  #   :fill, :stroke   a CSS colour String ("crimson", "#ff0066", "none"), or
  #                    a gradient Hash (see Drawing.gradient)
  #   :stroke_width    a number, in the picture's own lengths
  #   :opacity         0..1 for the whole group: drawn as one layer, then
  #                    faded (overlapping parts inside do not show through
  #                    each other)
  #   :effects         an Array of effects to apply, first one innermost
  #                    (see Drawing.effect). Present, maybe empty, whenever
  #                    the picture was given effects.
  #   :blend           how the finished group mixes with what is under it
  #                    ("screen", "multiply" ...). Always the outermost step.
  #   :sheet           only on a group with a gradient: { paint:, box: }.
  #                    The gradient (the group's :fill, or else its :stroke,
  #                    as +paint+ says) is drawn ONCE, as one sheet over +box+,
  #                    seen only where the group's shapes are. The shapes
  #                    give only where they are, not their colour: even a
  #                    shape with a colour of its own shows the sheet.
  #
  # A group with a style is drawn in this order, each step around the last:
  #
  #   1. its parts, in its colours (or as the :sheet)
  #   2. :opacity, fading that layer
  #   3. each of :effects, in order (a glow glows around the faded layer)
  #   4. :blend, mixing the result into what is under it
  #
  # Every number in a style (line widths, effect sizes, shadow offsets,
  # boxes, gradient points) is in the picture's own coordinates where the
  # style sits: inside a transform that doubles everything, a blur of 2
  # looks like a blur of 4, and a shadow "2 down" turns when the picture
  # turns. A renderer that works in pixels converts them with the
  # transform it is under at that point.
  #
  # Colours are inherited, as in SVG and in a Canvas save/restore: a shape
  # without a fill of its own uses the nearest fill around it, and the same
  # for stroke and stroke_width. With none at all: DEFAULTS (black fill, no
  # line, line width 1). A colour inside is never overridden by one outside.
  # Opacity is not inherited but multiplies: each group is its own layer.
  #
  # The drawing keeps the style on the group instead of copying the colour
  # down to every shape. That is how the picture is built (DESIGN section
  # 5), it is how SVG and Canvas both work, and it lets a renderer reuse a
  # part it already drew (a trail reuses whole pictures from earlier frames).
  #
  # Lines are always joined and capped round (LINE_JOIN, LINE_CAP).
  #
  # == Reacting parts
  #
  # A reacting part (Asobi::Reaction: flower.pulse.when_clicked) is a short
  # strip of frames drawn ahead of time, and something other than the clock
  # (a click, the pointer, a beat ...) picks which one shows. The painter
  # gets the Reaction itself and asks it:
  #
  #   Drawing.turn(reaction)     who turns the frames: { turn: "click" },
  #                              { turn: "key", key: "a" },
  #                              { turn: "value", from: "mic", what: "low" } ...
  #                              and what it sounds when it starts to play:
  #                              { turn: "click", sound: "pop" },
  #                              { turn: "key", key: "a", note: 60 }
  #                              (the same fields as a part of a reel)
  #   reaction.moments(fps)      [the seconds of each frame, how fast to play
  #                              them (nil for "value")]
  #   reaction.picture_at(s)     the picture of one frame (a part to draw)
  #   reaction.rest              the first frame: the picture at rest
  #
  # A painter that cannot play parts draws reaction.rest in its place, and
  # so does SVG outside a reel (a saved .svg). Inside a reel, SVG writes a
  # marker and the reel carries the part's frames (see Asobi::Reel). In the
  # data form the frames are drawn out in full, at 30 a second.
  module Drawing
    DEFAULTS = { fill: "black", stroke: "none", stroke_width: 1.0, opacity: 1.0 }.freeze
    LINE_JOIN = "round"
    LINE_CAP = "round"
    FONT = "sans-serif" # text without a font of its own
    NO_BOX = Box.new(-1.0, -1.0, 1.0, 1.0) # what a gradient spans on an empty picture

    module_function

    # Hand one picture to +painter+ (see above). The most common kinds come
    # first, because this is asked for every part of every frame.
    def draw(node, painter)
      case node
      when Transformed then painter.transformed(node.matrix, node.art)
      when Styled
        look = style(node.style) { node.art.box(IDENTITY) }
        look ? painter.styled(look, node.art) : painter.nothing
      when Many
        look = style(node.style, group: true) { Box.union(node.items.map { _1.box(IDENTITY) }) }
        look ? painter.group(look, node.items) : painter.nothing
      when Path then painter.path(node.commands, node.fill_rule)
      when Circle then painter.circle(node.r)
      when Ellipse then painter.ellipse(node.rx, node.ry)
      when Rect then painter.rect(-node.w / 2.0, -node.h / 2.0, node.w, node.h)
      when Text then painter.text(node.string, node.size, node.font || FONT)
      when Space then painter.nothing
      when Reaction then painter.reacting(node)
      else raise ArgumentError, "asobi does not know how to draw #{node.inspect}"
      end
    end

    # A picture's style as the drawing gives it. A plain style (colours,
    # lines, opacity) is already that, and is handed over as it is. One with
    # gradients or effects is worked out against the box of what is inside
    # (the block answers it; nil when there is nothing to see).
    #
    # Answers nil when the picture is clipped by a window that shows nothing:
    # then nothing at all is drawn, as its box (nil) already says.
    def style(style, group: false)
      return style if Style.plain?(style)

      box = yield
      out = {}
      style.each do |key, value|
        next if key == :effects

        out[key] = value.is_a?(Gradient) ? gradient(value, box) : value
      end
      if group && box && (out[:fill].is_a?(Hash) || out[:stroke].is_a?(Hash))
        area = Style.stroked?(style) ? box.grow(Style.stroke_width(style) / 2.0) : box
        out[:sheet] = { paint: out[:fill].is_a?(Hash) ? :fill : :stroke, box: area }
      end
      return nil if style[:effects] && !effects(out, style, box)

      out
    end

    # The effects of +style+, worked out one by one into +out+. Each one
    # covers the box of everything before it (the picture, its line, and
    # the effects already applied). An effect on a picture with nothing to
    # see is left out. Answers false when a clip's window shows nothing (so
    # nothing at all is drawn), true otherwise.
    def effects(out, style, box)
      current = box
      current = current.grow(Style.stroke_width(style) / 2.0) if current && Style.stroked?(style)
      list = []
      blend = nil
      style[:effects].each do |key, value|
        if key == :blend
          blend = value
          next
        end
        next unless current

        entry, current = effect(key, value, current)
        return false unless entry

        list << entry
      end
      out[:effects] = list
      out[:blend] = blend if blend && blend != "normal"
      true
    end

    # [one effect as the drawing gives it, the box after it] on a picture
    # whose box (with everything applied so far) is +box+. Every effect
    # says its +box+ and the +area+ it may paint (box plus what it spills).
    #
    #   { effect: "glow", size:, color: }             color nil: the picture's own
    #   { effect: "blur", amount: }
    #   { effect: "shadow", right:, down:, blur:, color:, opacity: }
    #   { effect: "clip", window: picture, window_box: }   only what shows through
    #                                                      the window's shapes
    #
    # A clip whose window shows nothing (no box) answers no entry: the
    # picture is then drawn as nothing at all (see Drawing.style).
    #
    # Sizes are lengths in the picture (a blur of 2 is a Gaussian with a
    # standard deviation of 2; a glow of size 4 is the picture blurred by
    # 2, twice over it, then the sharp picture on top).
    def effect(key, value, box)
      after = Effects.grow(box, { key => value }, IDENTITY)
      entry =
        case key
        when :glow then { effect: "glow", size: value[:size], color: value[:color] }
        when :blur then { effect: "blur", amount: value }
        when :shadow then { effect: "shadow", **value }
        when :clip
          window_box = value.box(IDENTITY)
          window_box && { effect: "clip", window: value, window_box: }
        end
      if entry
        entry[:box] = box
        entry[:area] = after
      end
      [entry, after]
    end

    # Who turns the frames of a reacting part, and what it sounds: a named
    # sound (sound:) or a MIDI note number (note:), never both, nothing
    # when it is silent (see "Reacting parts" above).
    def turn(reaction)
      out = { turn: reaction.turn }
      out[:key] = reaction.key if reaction.key
      out[:from] = reaction.from if reaction.from
      out[:what] = reaction.what if reaction.what
      case reaction.sound
      when String then out[:sound] = reaction.sound
      when Integer then out[:note] = reaction.sound
      end
      out
    end

    # A gradient laid over +box+ (in the coordinates of the picture it
    # paints): from one colour to the other.
    #
    #   { gradient: "linear", x1:, y1:, x2:, y2:, colors: [from, to] }
    #       from colour 1 at (x1, y1) to colour 2 at (x2, y2), unchanging
    #       across the flow
    #   { gradient: "radial", cx:, cy:, r:, colors: [from, to] }
    #       from colour 1 at the centre to colour 2 at radius r
    #
    # Past either end, the end colour carries on.
    def gradient(g, box)
      box ||= NO_BOX
      if g.around
        r = [[box.width, box.height].max / 2.0, 1e-3].max
        return { gradient: "radial", cx: box.cx, cy: box.cy, r:, colors: [g.from, g.to] }
      end

      radians = g.angle * Math::PI / 180
      dx = Affine.tidy(-Math.sin(radians))
      dy = Affine.tidy(Math.cos(radians))
      half = (dx.abs * box.width + dy.abs * box.height) / 2.0
      if half < 1e-6 # a flat line across the flow: let it flow along the line
        dx, dy = box.width >= box.height ? [1.0, 0.0] : [0.0, 1.0]
        half = [box.width, box.height].max / 2.0
        half = 1.0 if half < 1e-6
      end
      { gradient: "linear", x1: box.cx - dx * half, y1: box.cy - dy * half,
        x2: box.cx + dx * half, y2: box.cy + dy * half, colors: [g.from, g.to] }
    end

    # --- the page ------------------------------------------------------------

    # Everything about drawing +art+ as a whole page:
    #
    #   view        [x, y, width, height] of the picture to show
    #   paper       [width, height] in pixels, or nil (the renderer chooses)
    #   background  a CSS colour, or nil for see-through
    #   grain       fine grain over the page, its strength 0..1, or nil
    #   picture     the picture (its drawing, in the data form)
    #
    # and the rules that hold everywhere: line_join, line_cap, defaults.
    # Options as for to_svg: margin:, on:, paper:, grain:.
    def page(art, margin: nil, on: :white, paper: nil, grain: nil)
      strength = grain_strength(grain)
      view = view(art.box(IDENTITY), margin:, paper:)
      size = paper && paper_size(paper)
      background = Color.css(on)
      background = nil if %w[none transparent].include?(background)
      { view:, paper: size, background:, grain: strength,
        line_join: LINE_JOIN, line_cap: LINE_CAP, defaults: DEFAULTS, picture: art }
    end

    # The view [x, y, width, height] for a box (or a picture): the box plus
    # a margin, or the paper centred on the origin. An empty picture gets a
    # small square so the page is never zero-sized.
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

    def paper_size(paper)
      ok = paper.is_a?(Array) && paper.size == 2 && paper.all? { Check.number?(_1) && _1.positive? }
      raise Messages.error(ArgumentError, :bad_paper, got: paper.inspect) unless ok

      paper.map(&:to_f)
    end

    # true is 0.12; false or nil is none; a number from 0 to 1.
    def grain_strength(grain)
      return nil if grain.nil? || grain == false
      return 0.12 if grain == true

      Check.number(grain, word: :grain, name: :grain, example: "show flower, grain: 0.3", min: 0, max: 1)
      grain.zero? ? nil : grain.to_f
    end

    # --- the data form -------------------------------------------------------

    # The whole page as plain data, for JSON.generate (options as for page).
    #
    #   JSON.generate(Asobi::Drawing.of(flower, on: :black))
    def of(art, **options) = plain(page(Asobi.art(art), **options))

    # One picture's drawing as plain data. While a reel or document is being
    # built (Memo.during), a picture object already recorded is answered
    # from the notes, so a part shared by many frames is recorded once.
    def data(node) = Memo.recall(:drawing, node) { draw(node, Recorder) }

    # Any value of the step-by-step form as plain data: Symbol keys and
    # names become Strings, a Box becomes [x, y, width, height], an Affine
    # its six numbers, and a picture its drawing.
    def plain(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, plain(v)] }
      when Array then value.map { plain(_1) }
      when Symbol then value.to_s
      when Box then value.to_a
      when Affine then [value.a, value.b, value.c, value.d, value.e, value.f]
      when Node then data(value)
      else value
      end
    end

    # The painter that writes the data form down.
    module Recorder
      module_function

      def circle(r) = { "shape" => "circle", "r" => r }
      def ellipse(rx, ry) = { "shape" => "ellipse", "rx" => rx, "ry" => ry }
      def rect(x, y, width, height) = { "shape" => "rect", "x" => x, "y" => y, "width" => width, "height" => height }

      def path(commands, fill_rule)
        { "shape" => "path", "commands" => Drawing.plain(commands), "fill_rule" => fill_rule.to_s }
      end

      def text(string, size, font)
        { "shape" => "text", "text" => string, "size" => size, "font" => font, "origin" => "center" }
      end

      def nothing = { "shape" => "nothing" }
      def transformed(matrix, part) = { "transform" => Drawing.plain(matrix), "draw" => Drawing.data(part) }
      def styled(style, part) = { "style" => Drawing.plain(style), "draw" => Drawing.data(part) }
      def group(style, parts) = { "group" => parts.map { Drawing.data(_1) }, "style" => Drawing.plain(style) }

      # Every frame drawn out, at 30 a second (the first is the rest picture).
      def reacting(reaction)
        seconds, fps = reaction.moments
        out = { "reacting" => Drawing.plain(Drawing.turn(reaction)) }
        out["fps"] = fps if fps
        out["frames"] = seconds.map { Drawing.data(reaction.picture_at(_1)) }
        out
      end
    end
  end
end
