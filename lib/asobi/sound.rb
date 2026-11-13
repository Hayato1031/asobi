# frozen_string_literal: true

module Asobi
  # The sounds asobi makes (DESIGN.md sections 8 and 9). Two kinds, and
  # both are made in the browser: no Ruby runs while they play.
  #
  #   play "song.mp3"                          a song from a file (Asobi::Song),
  #                                            one per sketch, round and round
  #   dot.pulse.when_clicked.sounding(:pop)    an effect sound, made by the
  #                                            player itself: no file
  #
  # Not in this version: a sound on a motion the clock turns
  # (flower.pulse.sounding(:kick)), your own files as effect sounds, a
  # volume for each effect sound, more than one song.
  module Sounds
    # The effect sounds the player knows by name.
    NAMES = %w[pop kick snare hat clap bell].freeze
    # A note: a letter, maybe s (sharp) or b (flat), then an octave 1-7.
    NOTE = /\A([a-g])([sb]?)([1-7])\z/
    # Semitones above C in the same octave.
    STEPS = { "c" => 0, "d" => 2, "e" => 4, "f" => 5, "g" => 7, "a" => 9, "b" => 11 }.freeze

    module_function

    # One of NAMES (a String), or a note as a MIDI note number (an Integer:
    # :c4 is 60, :a4 is 69), or a teaching error.
    #
    #   Sounds.of(:pop)    # => "pop"
    #   Sounds.of(:cs4)    # => 61   (C sharp 4)
    #   Sounds.of("Bb3")   # => 58   (B flat 3; a capital or small letter, # for sharp)
    def of(sound)
      name = sound.to_s.downcase.tr("#", "s") if sound.is_a?(Symbol) || sound.is_a?(String)
      return name if NAMES.include?(name)

      found = NOTE.match(name.to_s)
      raise Messages.error(ArgumentError, :bad_sound, got: sound.inspect, names: Reactions.list(NAMES)) unless found

      letter, sign, octave = found.captures
      12 * (octave.to_i + 1) + STEPS.fetch(letter) + { "s" => 1, "b" => -1 }.fetch(sign, 0)
    end
  end

  # A song asobi plays while a sketch shows (play "song.mp3"): which file,
  # what is in it, and how loud. A plain value, like a picture.
  #
  #   path    the file, as a full path
  #   id      the first 12 hex characters of the SHA-256 of its bytes (the
  #           player uses it to know "the same song as before")
  #   volume  0..1
  #
  #   src     where a page finds it, or nil for the live view's "/song/ID".
  #           The website sets it: its pages and its playground play the
  #           copy the site ships ("assets/beat.wav", from the site's root).
  #
  # The Reel carries it as { "id" => ..., "src" => ..., "volume" => ... }
  # (see Song#entry): src is "/song/ID" for the live view, which serves the
  # file there, and the whole file as a data URI in a saved .html page.
  Song = Data.define(:path, :id, :volume, :src) do
    def initialize(path:, id:, volume: 1, src: nil) = super

    def inspect = "#<Asobi::Song #{File.basename(path)} #{id}#{" volume: #{volume}" unless volume == 1}>"
    alias_method :to_s, :inspect

    # The audio MIME type, from the file's kind.
    def type = Song::KINDS.fetch(File.extname(path).downcase)

    # Where the page finds it: src, or where the live view serves it.
    def url = src || "/song/#{id}"

    # The song as the Reel carries it. The volume is left out when it is 1.
    def entry(src = url)
      out = { "id" => id, "src" => src }
      out["volume"] = volume unless volume == 1
      out
    end

    # The whole file as a data URI, to put inside a saved page, or a
    # teaching error when it is too big for that.
    def data_uri
      size = File.size(path)
      if size > Song::EMBED_LIMIT
        raise Messages.error(ArgumentError, :song_too_big, file: File.basename(path),
                                                           size: format("%.1f", size / 1024.0 / 1024))
      end

      "data:#{type};base64,#{[File.binread(path)].pack("m0")}"
    end
  end

  class Song
    # The kinds of file play takes, and their MIME types.
    KINDS = {
      ".mp3" => "audio/mpeg", ".wav" => "audio/wav", ".m4a" => "audio/mp4", ".aac" => "audio/aac",
      ".ogg" => "audio/ogg", ".oga" => "audio/ogg", ".opus" => "audio/ogg", ".flac" => "audio/flac",
      ".webm" => "audio/webm"
    }.freeze
    # The biggest song a saved .html page takes inside it (20 MB).
    EMBED_LIMIT = 20 * 1024 * 1024
    # What play says when the song comes before the file name.
    EXAMPLE = "play \"song.mp3\""

    @mutex = Mutex.new
    @known = {} # id => path: every song a sketch named in play (the live view serves only these)
    @ids = {}   # [path, mtime, size] => id, so a long song is read once, not on every save

    class << self
      # The song +name+ names, as play takes it: the file +name+ (relative
      # to the folder +from+), at +volume+. Checks everything at once and
      # answers a teaching error for a mistake. The song is remembered, so
      # the live view may serve it (Song.find).
      def open(name, volume: 1, from: Dir.pwd)
        name = name.to_path if name.respond_to?(:to_path)
        unless name.is_a?(String) && !name.strip.empty?
          raise Messages.error(ArgumentError, :play_needs_file, got: name.inspect)
        end
        unless KINDS.key?(File.extname(name).downcase)
          raise Messages.error(ArgumentError, :play_kind, got: name.inspect, kinds: KINDS.keys.join(" "))
        end

        level = Check.number(volume, word: :play, name: :volume, example: "#{EXAMPLE}, volume: 0.5", min: 0, max: 1)
        path = File.expand_path(name, from)
        raise Messages.error(ArgumentError, :play_missing, file: name.inspect, folder: from) unless File.file?(path)

        song = new(path:, id: id_of(path), volume: level)
        @mutex.synchronize { @known[song.id] = path }
        song
      end

      # The song +name+ names in the web playground, which has no files:
      # one of +songs+ (file name => Song, the songs the site ships), at
      # +volume+, or a teaching error that names them.
      def offered(name, songs, volume: 1)
        name = name.to_path if name.respond_to?(:to_path)
        song = songs[name] if name.is_a?(String)
        unless song
          list = songs.keys.map { "\"#{_1}\"" }.join(", ")
          raise Messages.error(ArgumentError, :play_in_playground, songs: list, example: songs.keys.first || "beat.wav")
        end

        level = Check.number(volume, word: :play, name: :volume, example: "play \"#{name}\", volume: 0.5", min: 0, max: 1)
        song.with(volume: level)
      end

      # The file of a song a sketch named in play, by its id; nil for any
      # other id. Never a path taken from anywhere else.
      def find(id) = @mutex.synchronize { @known[id] }

      private

      def id_of(path)
        stat = File.stat(path)
        key = [path, stat.mtime, stat.size]
        @mutex.synchronize { @ids[key] } || begin
          require "digest"
          id = Digest::SHA256.file(path).hexdigest[0, 12]
          @mutex.synchronize { @ids[key] = id }
        end
      end
    end
  end

  Messages.add(:play_needs_file,
               en: "play needs the name of a sound file, like play \"song.mp3\". You gave %{got}.",
               ja: "play には音のファイルの名前を渡してください（いまは %{got}）。例：play \"song.mp3\"")
  Messages.add(:play_kind,
               en: "play can play these kinds of file: %{kinds}, like play \"song.mp3\". You gave %{got}.",
               ja: "play で流せるファイルの種類は %{kinds} です（いまは %{got}）。例：play \"song.mp3\"")
  Messages.add(:play_missing,
               en: "play can't find %{file} in %{folder}. Put the file next to the sketch, like play \"song.mp3\"",
               ja: "%{folder} に %{file} が見つかりません。ファイルをスケッチと同じフォルダに置いてください。例：play \"song.mp3\"")
  Messages.add(:song_too_big,
               en: "%{file} is %{size} MB, too big to put inside a saved page (20 MB at most). " \
                   "Use a shorter or more compressed file, like play \"song.mp3\" with an mp3 at 128 kbps.",
               ja: "%{file} は %{size} MB あり、保存するページに入れるには大きすぎます（20 MB まで）。" \
                   "短いファイルか、もっと圧縮したファイルにしてください。例：128 kbps の mp3 にして play \"song.mp3\"")
  Messages.add(:play_in_playground,
               en: "The playground has only one song to play: %{songs}, like play \"%{example}\". " \
                   "Your own songs work when you run asobi on your computer: put the file next to the sketch, like:  asobi music.rb",
               ja: "遊び場で流せる曲は %{songs} だけです。例：play \"%{example}\"　" \
                   "自分の曲は、asobi を自分のパソコンで動かすと流せます。ファイルをスケッチと同じフォルダに置いてください。例：asobi music.rb")
  Messages.add(:bad_sound,
               en: "sounding knows %{names}, and notes: a letter a-g, then s (sharp) or b (flat) if you like, then an octave 1-7, " \
                   "like sounding(:pop), sounding(:c4), sounding(:cs4) or sounding(\"Bb3\"). You gave %{got}.",
               ja: "sounding で鳴らせるのは %{names} と音の高さです（いまは %{got}）。音の高さは a〜g の文字、" \
                   "好みで s（シャープ）か b（フラット）、そして 1〜7 のオクターブ。例：sounding(:pop)、sounding(:c4)、sounding(:cs4)、sounding(\"Bb3\")")
  Messages.add(:sounding_on_by,
               en: "by(%{from}) follows a value, so there is no moment to play a sound at. Make a sound when something happens, " \
                   "like dot.pulse.when_clicked.sounding(:pop) or dot.pulse.on_beat.sounding(:kick)",
               ja: "by(%{from}) は値を追うので、音を鳴らす瞬間がありません。何かが起きたときに鳴らしてください。" \
                   "例：dot.pulse.when_clicked.sounding(:pop)、dot.pulse.on_beat.sounding(:kick)")
  Messages.add(:sounding_needs_reaction,
               en: "sounding plays a sound when a reaction happens, so write it right after a reaction word " \
                   "(when_clicked, while_hovered, when_pressed, on_beat), like dot.pulse.when_clicked.sounding(:pop)",
               ja: "sounding は反応したときに音を鳴らす言葉です。反応の言葉（when_clicked、while_hovered、when_pressed、on_beat）の" \
                   "すぐ後ろに書いてください。例：dot.pulse.when_clicked.sounding(:pop)")
end
