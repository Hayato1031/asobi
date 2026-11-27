# ---- the playground's entry point (site/playground/runner.rb) ------------
module Asobi
  # What the web playground calls, once per edit: run the code the way the
  # live view does (Sketch.run resets the random call counter, so an edit
  # never re-scatters) and answer the Reel as a JSON string.
  #
  # In one step:   run(source, language)       the whole Reel
  # In two steps:  start(source, language)     the first Reel: for a motion a
  #                                            quick preview ("pending": true)
  #                finish                      the whole Reel of that motion
  #             or finish_some(seconds)        the same, a slice of about that
  #                                            many seconds at a time: nil until
  #                                            the whole Reel is ready
  #                drop                        give up the half-made whole Reel
  # Between the steps the page can stop when a newer edit is waiting.
  #
  # The playground has no files. It starts with one song: the loop the site
  # ships as assets/beat.wav (a copy of examples/reactions/beat.wav), so
  # play "beat.wav" plays that. The page adds the song files the person
  # chooses (offer_song); any other name is a teaching error.
  # The id is the file's own (Song id: SHA-256, first 12 characters), so the
  # song goes on while the code changes; site/build.rb checks it.
  # The src is from the site's root; the page puts its own root in front.
  Sketch.playground = {
    "beat.wav" => Song.new(path: "beat.wav", id: "3ff79180f05b", src: "assets/beat.wav")
  }.freeze

  module Web
    # In the playground, a song it does not have gets a message that says
    # which songs it has now and how to add one (the gem's own message says
    # your songs work only on your computer, which is not so here).
    module Songs
      def offered(name, songs, volume: 1)
        name = name.to_path if name.respond_to?(:to_path)
        unless name.is_a?(String) && songs.key?(name)
          raise Messages.error(ArgumentError, :play_choose_song,
                               got: name.inspect, songs: songs.keys.map(&:inspect).join(", "),
                               example: "play #{(songs.keys.last || "beat.wav").inspect}")
        end
        super
      end
    end
    Song.singleton_class.prepend(Songs)

    SONG_ID = /\A[0-9a-f]{12}\z/

    module_function

    def run(source, language)
      Asobi.language = language.to_s == "ja" ? :ja : :en
      safely(source) { Sketch.run(source.to_s, name: "play.rb") }
    end

    def start(source, language)
      Asobi.language = language.to_s == "ja" ? :ja : :en
      safely(source) { Sketch.run(source.to_s, name: "play.rb", preview: true) }
    end

    # Did start leave a motion for finish?
    def waiting? = Sketch.waiting?

    # nil when start already answered the whole Reel.
    def finish
      whole = Sketch.finish
      whole && JSON.generate(whole)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      JSON.generate(Reel.error("#{e.class}: #{e.message}"))
    end

    # One slice of finish: the whole Reel as JSON once it is ready, nil
    # while it is not (waiting? stays true), nil when nothing is waiting.
    def finish_some(seconds)
      whole = Sketch.finish_some(seconds.to_f)
      whole && JSON.generate(whole)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      Sketch.forget # nothing half-made is left behind
      JSON.generate(Reel.error("#{e.class}: #{e.message}"))
    end

    # A newer edit came: forget the motion waiting for finish.
    def drop = Sketch.forget

    # A song file the person chose on the page ("Choose song", or a file
    # dropped on the playground): from now on play "name" plays it, and
    # the songs offered before stay, so the code can switch between them.
    # Ruby never sees the file. The Reel names it "user/ID", and only the
    # page that was given the file turns that into the file (a link's code
    # can write "user/ID" too, but then nothing plays). id: 12 hex digits
    # the page made from the file, so the same file keeps the same id and
    # the song goes on while the code changes. A name that is not a plain
    # file name of a kind play takes, or an id that is not 12 hex digits,
    # is refused (false).
    def offer_song(name, id)
      name = name.to_s
      id = id.to_s
      return false unless song_name?(name) && SONG_ID.match?(id)

      songs = Sketch.playground.is_a?(Hash) ? Sketch.playground : {}
      Sketch.playground = songs.merge(name => Song.new(path: name, id:, src: "user/#{id}")).freeze
      true
    end

    # A plain file name (no folder, no line break or other control
    # character: playground.js takes out the same) of a kind play takes.
    def song_name?(name)
      name.valid_encoding? && !name.strip.empty? && name.size <= 255 && !name.match?(%r{[/\\\x00-\x1f\x7f]}) &&
        Song::KINDS.key?(File.extname(name).downcase)
    end

    def safely(source)
      JSON.generate(yield)
    rescue Exception => e # rubocop:disable Lint/RescueException -- the VM must survive anything a sketch does
      JSON.generate(Reel.error("#{e.class}: #{e.message}", code: source.to_s))
    end
  end

  # The button's name ("Choose song" / "曲を選ぶ") is the one on the page:
  # site/build.rb checks it is in this message.
  Messages.add(:play_choose_song,
               en: "The playground has no song %{got}. It can play %{songs} now, like %{example}. " \
                   "To play a song of your own, choose its file with the “Choose song” button or drop it on the playground. " \
                   "After the page reloads, choose it again.",
               ja: "遊び場に %{got} という曲はありません。いま流せる曲は %{songs} です。例：%{example}　" \
                   "自分の曲を流すには、「曲を選ぶ」ボタンでファイルを選ぶか、ファイルを遊び場にドロップしてください。" \
                   "ページを読み込み直したときは、もう一度選んでください。")
end
