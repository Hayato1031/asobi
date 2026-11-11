# frozen_string_literal: true

module Asobi
  # Every message a person might read, in English and Japanese.
  #
  # Errors are teachers: each one says what is wrong and shows a line of
  # code that would work. The language follows the computer (LC_ALL, then
  # LC_MESSAGES, then LANG) unless you choose one with Asobi.language = :ja.
  module Messages
    TEXTS = {
      not_art: {
        en: "%{thing} can't become a picture yet. Give its class a to_art method, like:  def to_art = circle(radius: 10)",
        ja: "%{thing} はまだ絵になれません。そのクラスに to_art を書いてください。例：def to_art = circle(radius: 10)"
      },
      to_art_loop: {
        en: "to_art of %{thing} never answered a picture. Make to_art return a picture, like:  def to_art = circle(radius: 10)",
        ja: "%{thing} の to_art が絵を返しませんでした。to_art では絵を返してください。例：def to_art = circle(radius: 10)"
      },
      need_number: {
        en: "%{word} needs a number for %{name}, like %{example}. You gave %{got}.",
        ja: "%{word} の %{name} には数を渡してください（いまは %{got}）。例：%{example}"
      },
      need_at_least: {
        en: "%{word} needs %{name} to be %{min} or more, like %{example}. You gave %{got}.",
        ja: "%{word} の %{name} には %{min} 以上の数を渡してください（いまは %{got}）。例：%{example}"
      },
      need_between: {
        en: "%{word} needs %{name} to be from %{min} to %{max}, like %{example}. You gave %{got}.",
        ja: "%{word} の %{name} には %{min} から %{max} までの数を渡してください（いまは %{got}）。例：%{example}"
      },
      need_whole: {
        en: "%{word} needs a whole number of %{name} (%{min} or more), like %{example}. You gave %{got}.",
        ja: "%{word} の %{name} には %{min} 以上の整数を渡してください（いまは %{got}）。例：%{example}"
      },
      bad_color: {
        en: "%{got} is not a colour asobi knows%{hint}. Use a CSS colour name or a colour code, like colored(:crimson) or colored(\"#ff0066\").",
        ja: "%{got} は知らない色です%{hint}。CSS の色の名前か色のコードを渡してください。例：colored(:crimson)、colored(\"#ff0066\")"
      },
      did_you_mean: {
        en: " (did you mean :%{name}?)",
        ja: "（:%{name} のことですか？）"
      },
      bad_point: {
        en: "path needs points as [x, y] pairs of numbers, like path([0, 0], [40, -30], [80, 0]). You gave %{got}.",
        ja: "path の点は数2つの組 [x, y] で渡してください（いまは %{got}）。例：path([0, 0], [40, -30], [80, 0])"
      },
      few_points: {
        en: "path needs at least 2 points, like path([0, 0], [40, -30]). You gave %{got}.",
        ja: "path には点を2つ以上渡してください（いまは %{got} 個）。例：path([0, 0], [40, -30])"
      },
      bad_area: {
        en: "scattered needs an area as a number or [width, height], like scattered(over: 200) or scattered(over: [300, 100]). You gave %{got}.",
        ja: "scattered の over には数か [横, 縦] を渡してください（いまは %{got}）。例：scattered(over: 200)、scattered(over: [300, 100])"
      },
      bad_seed: {
        en: "seed needs a whole number, like scattered(seed: 7). You gave %{got}.",
        ja: "seed には整数を渡してください（いまは %{got}）。例：scattered(seed: 7)"
      },
      bad_save: {
        en: "save can write %{kinds} files, like save(\"flower.svg\"). You gave %{got}.",
        ja: "save で書き出せるのは %{kinds} です（いまは %{got}）。例：save(\"flower.svg\")"
      },
      need_block: {
        en: "%{word} needs a block that changes one picture, like %{example}",
        ja: "%{word} には1つの絵を変えるブロックを付けてください。例：%{example}"
      },
      endless: {
        en: "%{got} never ends, so it can't become a picture. Give the range an end, like (1..10).to_art",
        ja: "%{got} は終わりがないので絵にできません。終わりのある範囲にしてください。例：(1..10).to_art"
      },
      bad_paper: {
        en: "paper needs [width, height], like paper: [800, 800]. You gave %{got}.",
        ja: "paper には [横, 縦] を渡してください（いまは %{got}）。例：paper: [800, 800]"
      },
      bad_language: {
        en: "the language can be :en or :ja, like Asobi.language = :ja. You gave %{got}.",
        ja: "言語は :en か :ja を選んでください（いまは %{got}）。例：Asobi.language = :ja"
      }
    }

    LANGUAGES = %i[en ja].freeze

    module_function

    # The language chosen with Asobi.language=, or else the computer's.
    def language = @language || detect

    def language=(value)
      if value.nil?
        @language = nil
        return
      end
      lang = value.to_s.downcase[0, 2].to_sym if value.respond_to?(:to_s)
      raise ArgumentError, text(:bad_language, got: value.inspect) unless LANGUAGES.include?(lang)

      @language = lang
    end

    # LC_ALL wins over LC_MESSAGES, which wins over LANG; the first one that
    # is set decides.
    def detect(env = ENV)
      setting = %w[LC_ALL LC_MESSAGES LANG].map { env[_1] }.find { _1 && !_1.empty? }
      setting.to_s.downcase.start_with?("ja") ? :ja : :en
    end

    # Other files bring their own messages:
    #   Asobi::Messages.add(:need_motion, en: "...", ja: "...")
    def add(key, en:, ja:)
      TEXTS[key] = { en:, ja: }
    end

    def text(key, **vars)
      table = TEXTS.fetch(key)
      format(table.fetch(language), **vars)
    end

    # An exception carrying a message in the current language.
    def error(klass, key, **vars) = klass.new(text(key, **vars))
  end

  def self.language = Messages.language
  def self.language=(value)
    Messages.language = value
  end

  # Checks for numbers given to the words. Each answers the value as a Float
  # (or Integer for whole) or raises a teaching error.
  module Check
    module_function

    def number?(value) = value.is_a?(Numeric) && value.real? && value.finite?

    def number(value, word:, name:, example:, min: nil, max: nil)
      raise Messages.error(TypeError, :need_number, **talk(value, word, name, example)) unless number?(value)

      if min && max && !(min..max).cover?(value)
        raise Messages.error(ArgumentError, :need_between, min:, max:, **talk(value, word, name, example))
      end
      if min && value < min
        raise Messages.error(ArgumentError, :need_at_least, min:, **talk(value, word, name, example))
      end

      value.to_f
    end

    def whole(value, word:, name:, example:, min: 0)
      ok = number?(value) && value == value.round && value >= min
      raise Messages.error(ArgumentError, :need_whole, min:, **talk(value, word, name, example)) unless ok

      value.round
    end

    def talk(value, word, name, example) = { word:, name:, example:, got: value.inspect }
  end
end
