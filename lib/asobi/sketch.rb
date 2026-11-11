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

  # show, and running a sketch file.
  #
  # What show does depends on where it runs:
  #   1. ASOBI_LIVE=0                          only remember (tests, CI)
  #   2. inside Sketch.evaluate (live server)  only remember
  #   3. a script run with plain `ruby x.rb`   remember; show it live after the script ends
  #   4. irb and friends                       start the live server, push on every show
  module Sketch
    Shown = Data.define(:thing, :on, :paper, :grain) do
      def initialize(thing:, on: :white, paper: nil, grain: nil) = super
    end

    @mutex = Mutex.new
    @shown = nil
    @evaluating = false
    @exit_hook = false
    @server = nil

    class << self
      # What the last show asked for (a Shown with thing, on, paper, grain), or nil.
      attr_reader :shown

      def forget = @shown = nil

      def evaluating? = @evaluating

      def show(picture, on: :white, paper: nil, grain: nil)
        # Fail on the line of the show, with a teaching message.
        Reel.motion?(picture) || Asobi.art(picture)
        Color.css(on)
        SVG.paper_size(paper) if paper
        SVG.grain_strength(grain)
        @shown = Shown.new(picture, on, paper, grain)

        if ENV["ASOBI_LIVE"] == "0" || @evaluating
          # only remember
        elsif (path = script_file)
          register_exit_hook(path)
        else
          push_to_server
        end
        picture
      end

      # The script being run by plain `ruby x.rb`, or nil (irb, ruby -e ...).
      def script_file
        return nil if defined?(::IRB) || defined?(::Pry)

        name = $PROGRAM_NAME.to_s
        return nil if name.empty? || name == "-e" || name == "-" || !File.file?(name)

        File.expand_path(name)
      end

      # Run a sketch file and answer its Reel. Never raises for mistakes in
      # the sketch: they come back as an error Reel.
      def evaluate(path)
        path = File.expand_path(path.to_s)
        begin
          code = File.read(path, encoding: "UTF-8")
        rescue SystemCallError
          return Reel.error(Messages.text(:sketch_unreadable, file: File.basename(path)))
        end
        run(code, name: path)
      end

      # Run a sketch given as a String (the web playground, the site builder)
      # and answer its Reel. Errors name `name` and the line, like a file.
      #   Asobi::Sketch.run("show circle\n", name: "play.rb")
      def run(source, name: "sketch.rb")
        code = source.to_s.dup.force_encoding(Encoding::UTF_8)
        @mutex.synchronize { run_now(code, name.to_s) }
      end

      # The Reel for whatever was shown last.
      def reel(code: nil)
        s = @shown
        Reel.of(s.thing, on: s.on, paper: s.paper, grain: s.grain, code:)
      end

      private

      def run_now(code, path)
        Random.reset_calls!
        @shown = nil
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

        begin
          reel(code:)
        rescue ScriptError, StandardError => e
          Reel.error(describe(e, path), code:)
        end
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
            Live.run(path, initial: reel(code: File.read(path, encoding: "UTF-8")))
          rescue Interrupt
            nil
          end
        end
      end

      def push_to_server
        require_relative "live"
        @server ||= Live.start(announce: true)
        @server.push(reel)
      end
    end
  end

  # Show a picture on screen. The last show wins.
  #   show flower
  #   show flower, on: :black
  #   show flower, paper: [800, 800]
  #   show flower, grain: true
  def self.show(picture, on: :white, paper: nil, grain: nil) = Sketch.show(picture, on:, paper:, grain:)

  # The word itself, available everywhere like puts.
  module ShowWord
    def show(picture, on: :white, paper: nil, grain: nil) = Asobi::Sketch.show(picture, on:, paper:, grain:)
    private :show
  end
end

Object.include(Asobi::ShowWord)
