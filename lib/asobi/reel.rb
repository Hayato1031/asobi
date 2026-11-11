# frozen_string_literal: true

require "json"

module Asobi
  # The reel is what the browser plays (DESIGN.md section 9): a list of SVG
  # fragments, how fast to play them, the viewBox, the background colour and
  # (for the live view) the code and any error.
  #
  # Pure Ruby on purpose: no sockets, threads or file watching, so it also
  # runs inside ruby.wasm.
  module Reel
    MAX_FRAMES = 900
    PLAYER = File.join(__dir__, "web", "player.js")

    module_function

    # A Hash that JSON.generate turns into the Reel contract.
    #
    #   Reel.of(flower)                         one frame, fps 1
    #   Reel.of(flower.spin(every: 4), fps: 30) 120 frames
    #   Reel.of(flower, grain: true)            fine grain on every frame
    #
    # Grain is a small constant fragment (a noise filter and one rectangle
    # over the view) added to the end of every frame, so the player needs
    # nothing new and the grain stays still while the picture moves.
    def of(thing, fps: 30, on: :white, paper: nil, code: nil, grain: nil)
      background = Color.css(on)
      strength = SVG.grain_strength(grain)
      if motion?(thing)
        frames, fps = motion_frames(thing, fps)
        boxes = frames.map { |art| art.box(IDENTITY) }
        svgs = frames.map(&:svg)
        box = Box.union(boxes)
      else
        art = Asobi.art(thing)
        svgs = [art.svg]
        fps = 1
        box = art.box(IDENTITY)
      end
      view = SVG.view(box, paper:).map { _1.to_f.round(3) }
      if strength
        noise = SVG.grain(view, strength)
        svgs = svgs.map { _1 + noise }
      end
      { "frames" => svgs, "fps" => fps, "view" => view, "background" => background, "code" => code, "error" => nil }
    end

    # What the screen shows when the sketch is broken.
    def error(message, code: nil) = { "error" => message.to_s, "code" => code }

    # A complete page that plays the reel by itself, full window.
    def html(thing, title: "asobi", **options)
      reel = thing.is_a?(Hash) && thing.key?("frames") ? thing : of(thing, **options)
      page(reel, title)
    end

    def save(thing, path, **options)
      File.write(path.to_s, html(thing, **options), encoding: "UTF-8")
      path
    end

    # The player program, safe to put between <script> tags.
    def player_js = File.read(PLAYER, encoding: "UTF-8").gsub("</script", "<\\/script")

    # JSON that can sit inside a <script> tag: "<" never appears raw.
    def script_json(data) = JSON.generate(data).gsub("<", "\\u003c")

    def motion?(thing) = thing.respond_to?(:at) && thing.respond_to?(:every)

    # One loop of a motion: [pictures, fps]. The pictures are spread evenly
    # over exactly one loop (frame i is at every * i / count seconds, as in
    # Motion#frames), so the last frame leads straight back to the first.
    # The fps reported is count / every: an Integer when it is whole, else a
    # Float. Never more than MAX_FRAMES; a longer loop gets a lower fps.
    def motion_frames(motion, fps)
      fps = Check.whole(fps, word: :save, name: :fps, example: "save(\"flower.html\", fps: 30)", min: 1)
      every = Check.number(motion.every, word: :every, name: :every, example: "spin(every: 4)", min: 0)
      return [[Asobi.art(motion.at(0))], 1] unless every.positive?

      count = ((every * fps).round).clamp(1, MAX_FRAMES)
      frames = Array.new(count) { |i| Asobi.art(motion.at(every * i / count)) }
      rate = count / every
      [frames, (rate - rate.round).abs < 1e-9 ? rate.round : rate]
    end

    def page(reel, title)
      <<~HTML
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{Asobi.escape(title)}</title>
        <style>
          html, body { margin: 0; height: 100%; overflow: hidden; }
          #stage { position: fixed; inset: 0; }
        </style>
        </head>
        <body>
        <div id="stage"></div>
        <script>#{player_js}</script>
        <script>
          AsobiPlayer.mount(document.getElementById("stage")).update(#{script_json(reel)});
        </script>
        </body>
        </html>
      HTML
    end
  end

  Art::SAVERS[".html"] = ->(art, path, **options) { Reel.save(art, path, **options) }
end
