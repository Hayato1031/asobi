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
    #   Reel.of(flower, controls: false)        the player never shows its buttons
    #   Reel.of(flower, song: song)             with a song (an Asobi::Song, made by play)
    #
    # Grain is a small constant fragment (a noise filter and one rectangle
    # over the view) added to the end of every frame, so the player needs
    # nothing new and the grain stays still while the picture moves.
    #
    # While one reel is built, boxes, SVG and trail moments that were
    # already worked out are reused, then forgotten (see Asobi::Memo).
    #
    # Reacting parts (flower.pulse.when_clicked) are not drawn into the
    # frames. Each frame holds a marker <!--asobi:p1--> where a part goes,
    # and "parts" holds each part's own frames and who turns them:
    #
    #   "parts" => { "p1" => { "frames" => [...], "fps" => 30, "turn" => "click" },
    #                "p2" => { "frames" => [...], "turn" => "value", "from" => "mouse_x" } }
    #
    # Equal parts share one id; a part's frames may hold markers of other
    # parts. With no reacting part there is no "parts" at all, and the reel
    # is exactly what it always was. (See Asobi::Parts and DESIGN.md
    # section 9.) A part that makes a sound says so with "sound" => "pop"
    # or "note" => 60.
    #
    # With a song there is "song" => { "id" => ..., "src" => "/song/ID" }
    # (and "volume" when it is not 1): the live view serves the file at src.
    # A saved page puts the whole file there instead (see Reel.html).
    # Without one there is no "song" at all.
    def of(thing, **options) = Memo.during { build(thing, **options) }

    # Reel.of itself, without the Memo around it: all the steps at once.
    def build(thing, **options) = Steps.new(thing, **options).step

    # Reel.of, a little at a time. The web playground builds a motion's
    # whole reel this way, so that between two pieces it can notice a
    # newer edit and stop. Same options as Reel.of.
    #
    #   steps = Reel.steps(flower.spin(every: 4))
    #   reel = steps.step(0.08) until steps.done?   # about 80 ms of work per call
    #   reel == Reel.of(flower.spin(every: 4))      # => true, byte for byte
    #
    # Reuse (Asobi::Memo) spans the whole build: the steps keep their own
    # notes from one call to the next. Dropping the steps object drops
    # the notes too.
    def steps(thing, **options) = Steps.new(thing, **options)

    # The work of one reel, done in the same order as always: every
    # picture, then every box, then every SVG, then the reel itself.
    # step(seconds) works until about that much time has passed (always
    # at least one piece), then answers the reel, or nil if it is not
    # ready yet. step without seconds does everything.
    class Steps
      def initialize(thing, fps: 30, on: :white, paper: nil, code: nil, grain: nil, controls: true, song: nil)
        @background = Color.css(on)
        @strength = SVG.grain_strength(grain)
        @paper = paper
        @code = code
        @controls = Reel.controls(controls)
        @song = Reel.song(song)
        @part_fps = fps
        if Reel.motion?(thing)
          @motion = thing
          @moments, @fps = Reel.moments(thing, fps)
          @pictures = []
        else
          @motion = nil
          @moments = []
          @fps = 1
          @pictures = [Asobi.art(thing)]
        end
        @boxes = []
        @svgs = []
        @notes = {} # Memo notes kept for the whole build
        @parts = Parts::Collection.new # the reacting parts found so far
        @built = {} # id => the part's finished Hash
        @part = nil # the part being built: { seconds:, fps:, pictures:, svgs: }
        @reel = nil
      end

      def done? = !@reel.nil?

      def step(seconds = nil)
        return @reel if @reel

        stop = seconds && now + seconds
        Memo.during(@notes) do
          Parts.during(@parts) do
            until @reel
              work_once
              break if stop && now >= stop
            end
          end
        end
        @notes = @parts = nil if @reel # finished: let the notes go now
        @reel
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # One small piece of work: one picture, one box or one SVG (of the
      # reel, then of each reacting part found while writing them).
      def work_once
        if @pictures.size < @moments.size
          @pictures << Asobi.art(@motion.at(@moments[@pictures.size]))
        elsif @boxes.size < @pictures.size
          @boxes << @pictures[@boxes.size].box(IDENTITY)
        elsif @svgs.size < @pictures.size
          @svgs << @pictures[@svgs.size].svg
        elsif @built.size < @parts.size
          work_on_part(@parts.list[@built.size])
        else
          @reel = finished_reel
        end
      end

      # One picture or one SVG of a reacting part, or its finished Hash.
      # Writing its frames may find new parts (parts inside parts): they
      # join the end of the list and are built in their turn.
      def work_on_part(reaction)
        unless @part
          seconds, fps = reaction.moments(@part_fps)
          @part = { seconds:, fps:, pictures: [], svgs: [] }
        end
        pictures = @part[:pictures]
        svgs = @part[:svgs]
        if pictures.size < @part[:seconds].size
          pictures << reaction.picture_at(@part[:seconds][pictures.size])
        elsif svgs.size < pictures.size
          svgs << pictures[svgs.size].svg
        else
          @built["p#{@built.size + 1}"] = part_reel(reaction, svgs, @part[:fps])
          @part = nil
        end
      end

      # One part as the reel carries it: frames, fps (not for a value),
      # then who turns them.
      def part_reel(reaction, svgs, fps)
        out = { "frames" => svgs }
        out["fps"] = fps if fps
        Drawing.turn(reaction).each { |name, value| out[name.to_s] = value }
        out
      end

      def finished_reel
        box = @motion ? Box.union(@boxes) : @boxes.first
        view = SVG.view(box, paper: @paper).map { _1.to_f.round(3) }
        svgs = @svgs
        if @strength
          noise = SVG.grain(view, @strength)
          svgs = svgs.map { _1 + noise }
        end
        reel = { "frames" => svgs, "fps" => @fps, "view" => view, "background" => @background, "code" => @code,
                 "error" => nil }
        reel["controls"] = false unless @controls
        reel["song"] = @song if @song
        reel["parts"] = @built unless @built.empty?
        reel
      end
    end

    # How many moments of a motion the preview looks at to guess the room
    # the whole loop needs. Few, so the preview is quick.
    PREVIEW_MOMENTS = 8

    # A quick first look at a motion, to show while the whole reel is still
    # being made (it can take seconds). Same options as Reel.of.
    #
    #   Reel.preview(flower.spin(every: 4))
    #   # => { "frames" => [<the picture at 0 seconds>], "pending" => true, ... }
    #
    # - One frame: the picture at 0 seconds, exactly the first frame of the
    #   whole reel.
    # - "pending" => true says "the motion is still on its way".
    # - "fps" is what the whole reel will have.
    # - "view" is a guess, so the picture does not jump in size when the
    #   whole reel arrives: the room taken by a few moments spread over the
    #   loop (or the paper, when there is one). Those moments are frames of
    #   the whole reel, so the guess is never bigger than the real view.
    # - Never "parts": a reacting part is drawn in place, at rest.
    # - The "song", when there is one, so the music can start (or go on)
    #   before the motion is ready.
    #
    # A still picture has nothing to wait for: the answer is nil.
    #
    # Like Reel.of, it reuses what it has already worked out while it runs
    # (see Asobi::Memo).
    def preview(thing, **options) = motion?(thing) ? Memo.during { build_preview(thing, **options) } : nil

    # Reel.preview itself, without the Memo around it.
    def build_preview(thing, fps: 30, on: :white, paper: nil, code: nil, grain: nil, controls: true, song: nil)
      background = Color.css(on)
      strength = SVG.grain_strength(grain)
      shows_controls = Reel.controls(controls)
      song = Reel.song(song)

      # The same loop as Reel.moments: frame i is at every * i / count seconds.
      fps = Check.whole(fps, word: :save, name: :fps, example: "save(\"flower.html\", fps: 30)", min: 1)
      every = Check.number(thing.every, word: :every, name: :every, example: "spin(every: 4)", min: 0)
      count = every.positive? ? ((every * fps).round).clamp(1, MAX_FRAMES) : 1
      rate = every.positive? ? count / every : 1
      rate = rate.round if (rate - rate.round).abs < 1e-9

      first = Asobi.art(thing.at(0))
      box = first.box(IDENTITY)
      if paper.nil? && count > 1
        # Frame numbers spread evenly over the loop, like 0, 15, 30 ... of 120.
        moments = Array.new(PREVIEW_MOMENTS) { |k| k * count / PREVIEW_MOMENTS }.uniq - [0]
        boxes = moments.map { |i| Asobi.art(thing.at(every * i / count)).box(IDENTITY) }
        box = Box.union([box, *boxes])
      end

      view = SVG.view(box, paper:).map { _1.to_f.round(3) }
      svg = first.svg
      svg += SVG.grain(view, strength) if strength
      reel = { "frames" => [svg], "fps" => rate, "view" => view, "background" => background, "code" => code,
               "error" => nil, "pending" => true }
      reel["controls"] = false unless shows_controls
      reel["song"] = song if song
      reel
    end

    # true or false (nil counts as true: the buttons show), or a teaching error.
    def controls(value)
      return true if value.nil?
      raise Messages.error(ArgumentError, :bad_controls, got: value.inspect) unless [true, false].include?(value)

      value
    end

    # The "song" of a reel for an Asobi::Song (as the live view serves it),
    # or nil for no song.
    def song(song)
      return nil if song.nil?
      raise ArgumentError, "song: takes the Asobi::Song that play makes, not #{song.inspect}" unless song.is_a?(Song)

      song.entry
    end

    # What the screen shows when the sketch is broken.
    def error(message, code: nil) = { "error" => message.to_s, "code" => code }

    # A complete page that plays the reel by itself, full window. With a
    # song (song: an Asobi::Song), the whole file goes inside the page, so
    # the page plays it anywhere; a song over Song::EMBED_LIMIT is a
    # teaching error.
    def html(thing, title: "asobi", song: nil, **options)
      src = Reel.song(song) && song.data_uri # the song is checked before the work of the reel
      reel = thing.is_a?(Hash) && thing.key?("frames") ? thing : of(thing, song:, **options)
      reel = reel.merge("song" => song.entry(src)) if song
      page(reel, title)
    end

    # Write the page of Reel.html to +path+. Unless song: says otherwise, a
    # sketch's song (play "song.mp3", see Asobi::Sketch.song) goes with it:
    # every .html a sketch saves after its play line plays the song.
    def save(thing, path, **options)
      options = { song: Reel.sketch_song }.merge(options)
      File.write(path.to_s, html(thing, **options), encoding: "UTF-8")
      path
    end

    # The song the sketch running now asked for, or nil.
    def sketch_song = defined?(Asobi::Sketch) && Asobi::Sketch.respond_to?(:song) ? Asobi::Sketch.song : nil

    # The player program, safe to put between <script> tags.
    def player_js = File.read(PLAYER, encoding: "UTF-8").gsub("</script", "<\\/script")

    # JSON that can sit inside a <script> tag: "<" never appears raw.
    def script_json(data) = JSON.generate(data).gsub("<", "\\u003c")

    def motion?(thing) = thing.respond_to?(:at) && thing.respond_to?(:every)

    # The moments of one loop of a motion: [seconds of each frame, fps].
    # They are spread evenly over exactly one loop (frame i is at
    # every * i / count seconds, as in Motion#frames), so the last frame
    # leads straight back to the first. The fps reported is count / every:
    # an Integer when it is whole, else a Float. Never more than
    # MAX_FRAMES; a longer loop gets a lower fps.
    def moments(motion, fps)
      fps = Check.whole(fps, word: :save, name: :fps, example: "save(\"flower.html\", fps: 30)", min: 1)
      every = Check.number(motion.every, word: :every, name: :every, example: "spin(every: 4)", min: 0)
      return [[0], 1] unless every.positive?

      count = ((every * fps).round).clamp(1, MAX_FRAMES)
      rate = count / every
      [Array.new(count) { |i| every * i / count }, (rate - rate.round).abs < 1e-9 ? rate.round : rate]
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

  Messages.add(:bad_controls,
               en: "controls can be true or false, like show flower, controls: false. You gave %{got}.",
               ja: "controls には true か false を渡してください（いまは %{got}）。例：show flower, controls: false")

  Art::SAVERS[".html"] = ->(art, path, **options) { Reel.save(art, path, **options) }
end
