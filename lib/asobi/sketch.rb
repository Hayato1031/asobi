# frozen_string_literal: true

module Asobi
  # Plain sentences that are not errors (greetings, hints). They live apart
  # from Messages, whose every entry must teach with an example.
  module Say
    TEXTS = {}

    module_function

    def add(key, en:, ja:) = TEXTS[key] = { en:, ja: }
    def text(key, **vars) = format(TEXTS.fetch(key).fetch(Messages.language), **vars)
  end

  Messages.add(:sketch_no_show,
               en: "%{file} never calls show, so there is nothing to see yet. Add a line at the end, like:  show circle",
               ja: "%{file} に show がありません。最後に1行足してください。例：show circle")
  Say.add(:sketch_did_you_mean,
               en: " Did you mean: %{words}?",
               ja: " もしかして：%{words}")
  Messages.add(:sketch_unreadable,
               en: "asobi can't read %{file}. Check that the file exists, like:  asobi flower.rb",
               ja: "%{file} を読めません。ファイルがあるか確かめてください。例：asobi flower.rb")

  # show and play, and running a sketch file.
  #
  # What show does depends on where it runs:
  #   1. ASOBI_LIVE=0                          only remember (tests, CI)
  #   2. inside Sketch.evaluate (live server)  only remember
  #   3. a script run with plain `ruby x.rb`   remember; show it live after the script ends
  #   4. irb and friends                       start the live server, push on every show
  module Sketch
    Shown = Data.define(:thing, :on, :paper, :grain, :controls) do
      def initialize(thing:, on: :white, paper: nil, grain: nil, controls: true) = super

      # The options for Reel.of, Reel.steps and Reel.preview.
      def options = { on:, paper:, grain:, controls: }
    end

    @mutex = Mutex.new
    @shown = nil
    @song = nil # what the last play asked for (an Asobi::Song), or nil
    @playground = false
    @evaluating = false
    @waiting = nil # what finish will make: { shown:, song:, code:, path: } (and steps: once finish_some began), or nil
    @exit_hook = false
    @server = nil

    class << self
      # What the last show asked for (a Shown with thing, on, paper, grain, controls), or nil.
      attr_reader :shown

      # The song the last play asked for (an Asobi::Song), or nil. Every
      # run of a sketch starts without one, so taking out the play line
      # stops the song.
      attr_reader :song

      # The web playground, which has no files, sets this to the songs the
      # site ships (file name => Asobi::Song, like "beat.wav"): there, play
      # takes only those names and teaches that any other file works on
      # your computer. true means no songs at all. false everywhere else.
      attr_accessor :playground

      def forget
        @shown = nil
        @song = nil
        @waiting = nil
      end

      def evaluating? = @evaluating

      def show(picture, on: :white, paper: nil, grain: nil, controls: true)
        # Fail on the line of the show, with a teaching message.
        Reel.motion?(picture) || Asobi.art(picture)
        Color.css(on)
        SVG.paper_size(paper) if paper
        SVG.grain_strength(grain)
        Reel.controls(controls)
        @shown = Shown.new(picture, on, paper, grain, controls)

        if ENV["ASOBI_LIVE"] == "0" || @evaluating
          # only remember
        elsif (path = script_file)
          register_exit_hook(path)
        else
          push_to_server
        end
        picture
      end

      # Play a song while the sketch shows, round and round. The file is
      # found from the folder of the sketch file (the current folder when
      # there is none). One song per sketch: a later play replaces it. It
      # goes with what the sketch shows and with every .html it saves
      # afterwards (a saved .svg has no sound).
      def play(name, volume: 1)
        @song = if @playground
                  Song.offered(name, @playground.is_a?(Hash) ? @playground : {}, volume:)
                else
                  Song.open(name, volume:, from: folder_of_caller)
                end
        if !@evaluating && ENV["ASOBI_LIVE"] != "0" && @server && @shown
          push_to_server # irb: what shows now gets the song
        end
        nil
      end

      # The script being run by plain `ruby x.rb`, or nil (irb, ruby -e ...).
      def script_file
        return nil if defined?(::IRB) || defined?(::Pry)

        name = $PROGRAM_NAME.to_s
        return nil if name.empty? || name == "-e" || name == "-" || !File.file?(name)

        File.expand_path(name)
      end

      # Run a sketch file and answer its Reel. Never raises for mistakes in
      # the sketch: they come back as an error Reel. preview: as for run.
      def evaluate(path, preview: false)
        path = File.expand_path(path.to_s)
        begin
          code = File.read(path, encoding: "UTF-8")
        rescue SystemCallError
          return Reel.error(Messages.text(:sketch_unreadable, file: File.basename(path)))
        end
        run(code, name: path, preview:)
      end

      # Run a sketch given as a String (the web playground, the site builder)
      # and answer its Reel. Errors name `name` and the line, like a file.
      #   Asobi::Sketch.run("show circle\n", name: "play.rb")
      #
      # A motion can take seconds to become a whole Reel. With preview: true
      # a motion answers a quick preview instead (Reel.preview: one frame,
      # "pending" => true), and finish then makes the whole Reel. The
      # sketch itself runs only once.
      #   first = Asobi::Sketch.run(source, name: "play.rb", preview: true)
      #   whole = Asobi::Sketch.finish if first["pending"]
      def run(source, name: "sketch.rb", preview: false)
        code = source.to_s.dup.force_encoding(Encoding::UTF_8)
        @mutex.synchronize { run_now(code, name.to_s, preview:) }
      end

      # Is a motion waiting for finish?
      def waiting? = !@waiting.nil?

      # The whole Reel of the motion whose preview run (or evaluate) just
      # answered, or nil when nothing is waiting. Never raises for mistakes
      # in the sketch: they come back as an error Reel.
      def finish
        @mutex.synchronize do
          waiting = @waiting
          @waiting = nil
          next nil unless waiting

          shown = waiting[:shown]
          guarded(waiting[:path], waiting[:code]) do
            Reel.of(shown.thing, **shown.options, code: waiting[:code], song: waiting[:song])
          end
        end
      end

      # finish, a little at a time: works for about +seconds+, then answers
      # nil while the whole Reel is not ready yet (waiting? stays true: call
      # it again). At the end it answers the whole Reel (the same as finish
      # would) or an error Reel, and nothing is waiting any more. The web
      # playground uses it so that a newer edit can stop a long build.
      #   whole = Asobi::Sketch.finish_some(0.08) while Asobi::Sketch.waiting?
      # To give up halfway, forget: the half-made Reel goes with it.
      def finish_some(seconds)
        @mutex.synchronize do
          waiting = @waiting
          next nil unless waiting

          shown = waiting[:shown]
          whole = guarded(waiting[:path], waiting[:code]) do
            waiting[:steps] ||= Reel.steps(shown.thing, **shown.options, code: waiting[:code], song: waiting[:song])
            waiting[:steps].step(seconds)
          end
          @waiting = nil if whole
          whole
        end
      end

      # The Reel for whatever was shown last (with the song, if any).
      def reel(code: nil)
        s = @shown
        Reel.of(s.thing, **s.options, code:, song: @song)
      end

      private

      def run_now(code, path, preview: false)
        Random.reset_calls!
        @waiting = nil
        @shown = nil
        @song = nil
        @evaluating = true
        begin
          # Like load(path, true): the sketch runs on a fresh "main" of its
          # own, so its classes, constants and methods never leak into Object.
          main = Object.new
          def main.inspect = "main"
          def main.to_s = "main"
          @main = main
          main.instance_eval(code, path, 1)
        rescue SystemExit
          # a sketch that says exit still gets to show what it showed
        rescue ScriptError, StandardError => e
          return Reel.error(describe(e, path), code:)
        ensure
          @evaluating = false
        end

        return Reel.error(Messages.text(:sketch_no_show, file: File.basename(path)), code:) unless @shown
        return first_reel(code, path) if preview

        guarded(path, code) { reel(code:) }
      end

      # The first Reel to show for what was shown last. A still picture is
      # already whole. A motion gets a quick preview, and is remembered
      # (in @waiting) so that finish can make its whole Reel.
      def first_reel(code, path)
        shown = @shown
        return guarded(path, code) { reel(code:) } unless Reel.motion?(shown.thing)

        song = @song
        first = guarded(path, code) do
          Reel.preview(shown.thing, **shown.options, code:, song:)
        end
        @waiting = { shown:, song:, code:, path: } unless first["error"]
        first
      end

      # The block's Reel, or an error Reel if the sketch's own code fails
      # while the pictures are being made.
      def guarded(path, code)
        yield
      rescue ScriptError, StandardError => e
        Reel.error(describe(e, path), code:)
      end

      # "flower.rb:4  undefined local variable or method 'petl' ..."
      def describe(error, path)
        name = File.basename(path)
        message = error.message.to_s.gsub(path, name)
        # the sketch's own "main" reads as main, like the top level of a file
        message = message.sub(/ for (?:an instance of Object|#<Object:0x\h+>)/, " for main") if error.respond_to?(:receiver) && (error.receiver.equal?(@main) rescue false)
        if error.is_a?(SyntaxError)
          lines = message.lines.map(&:rstrip).reject(&:empty?).first(4)
          lines[0] = "#{name}: #{lines[0]}" unless lines[0].to_s.start_with?("#{name}:")
          return lines.join("\n")
        end

        line = line_in(error, path)
        head = message.lines.first.to_s.strip
        text = line ? "#{name}:#{line}  #{head}" : head
        text + suggestion(error)
      end

      def line_in(error, path)
        spot = (error.backtrace_locations || []).find { _1.absolute_path == path || _1.path == path }
        spot&.lineno
      end

      def suggestion(error)
        return "" unless error.respond_to?(:corrections)

        words = error.corrections.first(3).map(&:to_s)
        words.empty? ? "" : Say.text(:sketch_did_you_mean, words: words.join(", "))
      rescue StandardError
        ""
      end

      def register_exit_hook(path)
        return if @exit_hook

        @exit_hook = true
        at_exit do
          failure = $!
          next if failure && !(failure.is_a?(SystemExit) && failure.success?)

          begin
            require_relative "live"
            code = File.read(path, encoding: "UTF-8")
            first = @mutex.synchronize { first_reel(code, path) }
            Live.run(path, initial: first) # a preview first; Live.run asks finish for the rest
          rescue Interrupt
            nil
          end
        end
      end

      # irb: a quick preview of a motion first, then the whole Reel.
      def push_to_server
        require_relative "live"
        @server ||= Live.start(announce: true)
        shown = @shown
        first = Reel.preview(shown.thing, **shown.options, song: @song)
        @server.push(first) if first
        @server.push(reel)
      end

      # The folder of the file whose code called play (the sketch), or the
      # current folder when that code is not in a file (irb, a String run
      # by Sketch.run).
      def folder_of_caller
        spot = caller_locations.find { !(_1.absolute_path || _1.path).to_s.start_with?("#{__dir__}/") }
        file = spot && (spot.absolute_path || spot.path)
        file && File.file?(file) ? File.dirname(File.expand_path(file)) : Dir.pwd
      end
    end
  end

  # Show a picture on screen. The last show wins.
  #   show flower
  #   show flower, on: :black
  #   show flower, paper: [800, 800]
  #   show flower, grain: true
  #   show flower, controls: false     never show the record / code buttons
  def self.show(picture, on: :white, paper: nil, grain: nil, controls: true)
    Sketch.show(picture, on:, paper:, grain:, controls:)
  end

  # Play a song while the sketch shows (see Sketch.play).
  #   play "song.mp3"
  #   play "song.mp3", volume: 0.5
  def self.play(name, volume: 1) = Sketch.play(name, volume:)

  # The word itself, available everywhere like puts.
  module ShowWord
    def show(picture, on: :white, paper: nil, grain: nil, controls: true)
      Asobi::Sketch.show(picture, on:, paper:, grain:, controls:)
    end
    private :show
  end

  # play, available everywhere like show.
  module PlayWord
    def play(name, volume: 1) = Asobi::Sketch.play(name, volume:)
    private :play
  end
end

Object.include(Asobi::ShowWord)
Object.include(Asobi::PlayWord)
