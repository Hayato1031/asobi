# frozen_string_literal: true

# Builds the asobi website (DESIGN.md section 11): the documentation pages in
# English and Japanese, and the in-browser playground.
#
#   ruby -Ilib site/build.rb [--out _site] [--data site/data]
#   rake site
#
# Standard library only. Every code example on the site is run here, with the
# real library, and the build fails if any of them does not work: the docs
# never show a picture that the code would not make.
#
# Optional keys in site/data/home.yml (besides the fixed schema), all used
# only by the home page and all safe to leave out:
#
#   stage: [neon_flower, aurora]   ids from examples.yml. After hero_code, the
#                                  home stage plays these in turn, each one's
#                                  code typed over the picture first. Pick
#                                  pieces on a dark background (the stage is
#                                  dark). Without it the hero just plays.
#   steps:                         "one word at a time": a piece built up step
#     - word: petal                by step. Each step's code is a complete
#       code: |                    sketch (run at build time like any other
#         show petal               example); `word` must be in words.yml and
#                                  is the word that step adds. Without it the
#                                  strip is left out.
#   gallery: [flower, aurora]      ids from examples.yml shown as a glimpse of
#                                  the gallery (default: the first three).
#
# Decoration made by asobi itself (Decor below, drawn with the library at
# build time): the favicon, the registration mark on paper cards, the
# sketchbook grid behind the pages and the wave rule between sections.

require "erb"
require "yaml"
require "json"
require "fileutils"
require "optparse"
require "timeout"
require "open3"
require "rbconfig"
require "tmpdir"

ENV["ASOBI_LIVE"] = "0"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "asobi"

module AsobiSite
  ROOT = File.expand_path("..", __dir__)
  SITE = __dir__
  LIB = File.join(ROOT, "lib")
  TEMPLATES = File.join(SITE, "templates")
  ASSETS = File.join(SITE, "assets")
  PLAYGROUND = File.join(SITE, "playground")
  RUBYGEMS_URL = "https://rubygems.org/gems/asobi"
  GITHUB_URL = "https://github.com/Hayato1031/asobi"
  MARKER = ".asobi-site" # marks a directory this builder may wipe and rewrite

  class BuildError < StandardError; end

  # The one external resource of the whole site: ruby.wasm for the
  # playground, from the jsDelivr CDN, at a pinned version.
  # Docs: https://github.com/ruby/ruby.wasm/blob/main/docs/cheat_sheet.md
  RUBY_WASM_VERSION = "2.10.1"
  RUBY_WASM_RUBY = "@ruby/3.4-wasm-wasi" # Ruby 3.4 with the standard library (json, Data)
  RUBY_WASM_API = "@ruby/wasm-wasi"
  RUBY_WASM = {
    "api" => "https://cdn.jsdelivr.net/npm/#{RUBY_WASM_API}@#{RUBY_WASM_VERSION}/dist/browser.umd.js",
    "wasm" => "https://cdn.jsdelivr.net/npm/#{RUBY_WASM_RUBY}@#{RUBY_WASM_VERSION}/dist/ruby+stdlib.wasm"
  }.freeze

  LANGUAGES = { ja: "日本語", en: "English" }.freeze
  GROUPS = %w[shapes combine change color effect arrange to_art motion show].freeze
  PAGES = { "index" => :home, "guide" => :guide, "reference" => :reference,
            "examples" => :examples, "playground" => :playground }.freeze
  NAV = %w[guide reference examples playground].freeze
  RUN_TIMEOUT = 60 # seconds for one example at build time
  REEL_BUDGET = 1_500_000 # bytes of one example's reel (before gzip)

  # Every word of the page chrome, in both languages.
  UI = {
    en: {
      site: "asobi", skip: "Skip to content", menu: "Site",
      index: "Home", guide: "Getting started", reference: "Reference", examples: "Examples", playground: "Playground",
      language: "Language",
      play_now: "Play now", install: "Install", open_in_playground: "Open in playground",
      see_also: "See also", in_this_step: "Words in this step", contents: "Contents", words: "Words",
      picture: "Picture", picture_of: "Picture: %s", code: "Code",
      copy_link: "Copy link", copied: "Link copied", copy_failed: "Copy the address from the address bar",
      loading_ruby: "Loading Ruby…", ruby_ready: "Ruby is ready", running: "running…",
      ruby_failed: "Ruby could not be loaded. Check the connection and reload the page.",
      too_slow: "This sketch took more than %d seconds, so it was stopped. Is there a loop that never ends?",
      editor_hint: "Edit the code; the picture follows. Tab inserts two spaces. Press Esc, then Tab, to leave the editor.",
      words_hint: "Each word opens its reference in a new tab.",
      reset: "Start again",
      footer_playground: "Your sketch runs in your browser. Use “Copy link” to share it.",
      footer_license: "MIT License",
      view_gem: "View on RubyGems",
      watch_film: "Watch the film", film_info: "Short film · 32 seconds · Music",
      film_description: "Three numbers become three circles. A Flower object trades its petals for stars, then spins and leaves a trail of light.",
      contribute: "Help improve asobi",
      issue_invitation: "Found a bug? Share a sketch or the steps that reproduce it. For a feature idea, tell us what you’d like to draw or animate. English and Japanese are both welcome.",
      pr_invitation: "Fixes, examples and documentation are welcome too. Fork the repository, make your changes and open a pull request to main.",
      report_bug: "Report a bug", suggest_feature: "Suggest a feature", fork_repo: "Fork on GitHub",
      groups: { "shapes" => "Shapes", "combine" => "Combine", "change" => "Change", "color" => "Colour",
                "effect" => "Effects", "arrange" => "Arrange", "to_art" => "Objects as pictures", "motion" => "Motion", "show" => "Show" },
      creative_coding: "creative coding", chapters_count: "%02d chapters", pieces_count: "%02d pieces", groups_count: "%d groups",
      guide_lead: "From installing to your first moving picture, one small step at a time.",
      reference_lead: "Every word asobi knows. Each example runs; motions move.",
      examples_lead: "Finished pieces. Open any of them in the playground and change it.",
      playground_title: "Playground",
      get_started: "Get started", play: "Play", copy: "Copy", copied_short: "Copied",
      show_code: "Code", now_playing: "Now playing", live: "live", still: "still", frame: "frame",
      every: "every %ss", frames: "%d frames", stage_label: "A piece playing, with its code",
      philosophy: "What asobi believes", one_word: "One word at a time",
      one_word_lead: "Every step is a whole sketch. Add one word, and the picture answers.",
      step: "step", gallery_glimpse: "From the gallery", all_examples: "All examples",
      reference_way: "Every word, one page", reference_way_lead: "%d words in %d groups. Each one with a picture that runs.",
      words_count: "%d words", on_this_page: "On this page", file: "play.rb", words_jump: "Words",
      skip_editor: "Skip to the picture"
    },
    ja: {
      site: "asobi", skip: "本文へ移動", menu: "サイト",
      index: "トップ", guide: "はじめかた", reference: "リファレンス", examples: "見本集", playground: "遊び場",
      language: "表示言語",
      play_now: "遊んでみる", install: "インストール", open_in_playground: "遊び場で開く",
      see_also: "関連", in_this_step: "このステップの言葉", contents: "目次", words: "言葉",
      picture: "絵", picture_of: "絵：%s", code: "コード",
      copy_link: "リンクをコピー", copied: "リンクをコピーしました", copy_failed: "アドレスバーから URL をコピーしてください",
      loading_ruby: "Ruby を読み込み中…", ruby_ready: "Ruby の準備ができました", running: "実行中…",
      ruby_failed: "Ruby を読み込めませんでした。通信を確かめて、ページを読み込み直してください。",
      too_slow: "%d 秒以上かかったので止めました。終わらないくり返しがないか確かめてください。",
      editor_hint: "コードを書き換えると絵が変わります。Tab で空白2つ。エディタから出るには Esc のあと Tab。",
      words_hint: "言葉を選ぶと、そのリファレンスが新しいタブで開きます。",
      reset: "最初に戻す",
      footer_playground: "スケッチはブラウザで動きます。「リンクをコピー」で共有できます。",
      footer_license: "MIT ライセンス",
      view_gem: "RubyGems で見る",
      watch_film: "紹介映像を見る", film_info: "紹介映像 · 32秒 · 音楽あり",
      film_description: "3つの数字が3つの円に。Flower オブジェクトの花びらが星に変わり、回転しながら光の軌跡を描きます。",
      contribute: "asobi の改善に参加する",
      issue_invitation: "不具合を見つけたら、再現できるスケッチや手順を教えてください。機能の提案は「こんな絵を描きたい」「こんな動きを作りたい」からどうぞ。日本語・英語どちらも歓迎です。",
      pr_invitation: "コードの修正、作例の追加、ドキュメントの改善も歓迎します。リポジトリをフォークして変更を加え、main 宛てにプルリクエストを送ってください。",
      report_bug: "不具合を報告する", suggest_feature: "機能を提案する", fork_repo: "GitHub でフォークする",
      groups: { "shapes" => "形", "combine" => "合わせる", "change" => "変える", "color" => "色",
                "effect" => "効果", "arrange" => "並べる", "to_art" => "オブジェクトを絵に", "motion" => "動き", "show" => "画面に出す" },
      creative_coding: "クリエイティブコーディング", chapters_count: "全%d章", pieces_count: "全%d作品", groups_count: "%dグループ",
      guide_lead: "インストールから、動く絵ができるまで。一歩ずつ。",
      reference_lead: "asobi が知っているすべての言葉。どの例も実際に動き、動きの例は動いて見えます。",
      examples_lead: "完成した作品。どれも遊び場で開いて書き換えられます。",
      playground_title: "遊び場",
      get_started: "はじめる", play: "遊ぶ", copy: "コピー", copied_short: "コピーしました",
      show_code: "コード", now_playing: "再生中", live: "再生中", still: "静止画", frame: "コマ",
      every: "%s秒で1周", frames: "%dコマ", stage_label: "作品とそのコード",
      philosophy: "asobi の考え", one_word: "言葉をひとつずつ",
      one_word_lead: "どの段も、それだけで動くスケッチです。言葉をひとつ足すと、絵が答えます。",
      step: "ステップ", gallery_glimpse: "見本集から", all_examples: "見本集をすべて見る",
      reference_way: "すべての言葉を1ページに", reference_way_lead: "%d の言葉、%d のまとまり。どれにも動く絵が付いています。",
      words_count: "%d語", on_this_page: "このページ", file: "play.rb", words_jump: "言葉",
      skip_editor: "絵へ移動"
    }
  }.freeze

  PLAY_TIMEOUT = 15 # seconds before the playground gives up on a sketch

  module_function

  # ---- small helpers ------------------------------------------------------

  def h(text) = ERB::Util.html_escape(text.to_s)

  # Finished pieces (the gallery, the home page, the playground) show the
  # require line, so they can be copied into a file and run as they are.
  def display_code(code) = code.start_with?("require") ? code : "require \"asobi\"\n\n#{code}"

  # The playground link's fragment: base64url (no padding) of the UTF-8 code.
  def encode_code(code) = [code.to_s.encode(Encoding::UTF_8)].pack("m0").tr("+/", "-_").delete("=")

  def decode_code(text)
    s = text.to_s.tr("-_", "+/")
    s += "=" * ((4 - s.length % 4) % 4)
    s.unpack1("m0").force_encoding(Encoding::UTF_8)
  end

  # FNV-1a (32 bit) of the UTF-8 bytes: names a reel file. The playground
  # computes the same in JavaScript to find a pre-rendered picture.
  def code_key(code)
    hash = 0x811c9dc5
    code.to_s.encode(Encoding::UTF_8).each_byte { |b| hash = ((hash ^ b) * 0x01000193) & 0xffffffff }
    format("r%08x", hash)
  end

  # A stable anchor for a word: the word itself when it is a plain name,
  # otherwise a spelled-out version ("+" -> "op-plus").
  def anchor(word)
    w = word.to_s
    return w if w.match?(/\A[a-z_][a-z0-9_]*\z/)

    names = { "+" => "plus", "*" => "times", "?" => "-q", "!" => "-bang", "=" => "-eq", "-" => "minus",
              "/" => "slash", "|" => "bar", "<" => "lt", ">" => "gt", "[" => "at", "]" => "" }
    "op-" + w.chars.map { |c| c.match?(/[a-z0-9_]/i) ? c : names.fetch(c, "x") }.join
  end

  # ---- Ruby tinting ---------------------------------------------------------

  KEYWORDS = %w[def end do if elsif else unless while until case when then class module return yield
                begin rescue ensure self nil true false and or not in break next super loop lambda proc].freeze

  # Ruby code as HTML with <span class="t-..."> around comments (c), strings
  # (s), symbols and keyword labels (y), numbers (n), keywords (k),
  # constants (t) and asobi words (w; +fresh+ ones also get t-new). The text
  # stays exactly the code, so copying it copies the code.
  def highlight(code, words = [], fresh: [])
    require "strscan"
    scan = StringScanner.new(code.to_s)
    out = +""
    prev = ""
    tag = ->(cls, text) { out << %(<span class="#{cls}">#{h(text)}</span>) }
    until scan.eos?
      if scan.scan(/#[^\n]*/)
        tag.("t-c", scan.matched)
      elsif scan.scan(/"(?:\\.|[^"\\\n])*"?|'(?:\\.|[^'\\\n])*'?/)
        tag.("t-s", scan.matched)
      elsif !prev.match?(/[\w:\])]/) && scan.scan(/:[A-Za-z_]\w*[?!]?/)
        tag.("t-y", scan.matched)
      elsif scan.scan(/[A-Za-z_]\w*[?!]?:(?!:)/)
        tag.("t-y", scan.matched)
      elsif scan.scan(/\d[\d_]*(?:\.\d+)?/)
        tag.("t-n", scan.matched)
      elsif scan.scan(/[A-Z]\w*/)
        tag.("t-t", scan.matched)
      elsif scan.scan(/[a-z_]\w*[?!]?/)
        word = scan.matched
        if KEYWORDS.include?(word) then tag.("t-k", word)
        elsif fresh.include?(word) then tag.("t-w t-new", word)
        elsif words.include?(word) then tag.("t-w", word)
        else out << h(word)
        end
      else
        out << h(scan.getch)
      end
      prev = scan.matched.to_s[-1].to_s
    end
    out
  end

  # Light or dark: a picture on a light background is a sheet of paper on
  # the stage; a dark one is a screen.
  def light?(css)
    r, g, b = Asobi::Color.rgb(css)
    return true unless r

    lum = [r, g, b].map { |c| c /= 255.0; c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * lum[0] + 0.7152 * lum[1] + 0.0722 * lum[2]) > 0.4
  rescue StandardError
    true
  end

  # ---- data ---------------------------------------------------------------

  Snippet = Struct.new(:code, :file, :entry, :label, :result, keyword_init: true)
  Result = Struct.new(:key, :reel, keyword_init: true) do
    def moving? = reel["frames"].size > 1
  end

  # Reads and checks site/data/*.yml (or a fixture directory).
  class Content
    attr_reader :words, :guide, :examples, :home, :errors

    FILES = %w[words guide examples home].freeze

    def initialize(dir)
      @dir = dir
      @errors = []
      raw = FILES.to_h { |name| [name, read(name)] }
      @words = check_words(raw["words"])
      @guide = check_guide(raw["guide"])
      @examples = check_examples(raw["examples"])
      @home = check_home(raw["home"])
      check_links
      raise BuildError, "The site data has mistakes:\n" + @errors.map { "  - #{_1}" }.join("\n") unless @errors.empty?
    end

    def word_names = @words.map { _1["word"] }

    private

    def rel(name) = File.join(File.basename(@dir), "#{name}.yml").then { |r| @dir.start_with?(File.join(ROOT, "site")) ? "site/#{r}" : r }

    def read(name)
      path = File.join(@dir, "#{name}.yml")
      unless File.file?(path)
        @errors << "#{rel(name)}: file not found (#{path})"
        return nil
      end
      YAML.safe_load(File.read(path, encoding: "UTF-8"), aliases: true, filename: path)
    rescue Psych::Exception => e
      @errors << "#{rel(name)}: not valid YAML: #{e.message}"
      nil
    end

    def where(file, index, entry, key = nil)
      name = entry.is_a?(Hash) && (entry["word"] || entry["id"])
      at = name ? "entry #{index + 1} (#{name})" : "entry #{index + 1}"
      key ? "#{rel(file)}, #{at}, #{key}" : "#{rel(file)}, #{at}"
    end

    def list_of(file, value)
      return [] if value.nil?
      return value if value.is_a?(Array)

      @errors << "#{rel(file)}: should be a list (each entry starting with \"- \")"
      []
    end

    def require_keys(entry, keys, here)
      unless entry.is_a?(Hash)
        @errors << "#{here}: should be a map of keys, got #{entry.inspect[0, 60]}"
        return false
      end
      missing = keys.reject { |k| entry.key?(k) && !entry[k].nil? }
      missing.each { |k| @errors << "#{here}: missing required key \"#{k}\"" }
      missing.empty?
    end

    # A text map {en:, ja:}. Required texts need both languages; an optional
    # one with a single language shows that language on both sites.
    def text(value, here, required: true)
      if value.nil?
        @errors << "#{here}: missing required text" if required
        return nil
      end
      unless value.is_a?(Hash)
        @errors << "#{here}: should be a map like { en: \"...\", ja: \"...\" }"
        return nil
      end
      en, ja = value["en"], value["ja"]
      ok = ->(s) { s.is_a?(String) && !s.strip.empty? }
      if required
        @errors << "#{here}: missing \"en\"" unless ok.(en)
        @errors << "#{here}: missing \"ja\"" unless ok.(ja)
        return nil unless ok.(en) && ok.(ja)
      elsif !ok.(en) && !ok.(ja)
        @errors << "#{here}: has neither \"en\" nor \"ja\""
        return nil
      end
      { en: ok.(en) ? en : ja, ja: ok.(ja) ? ja : en }
    end

    def code(value, here)
      unless value.is_a?(String) && !value.strip.empty?
        @errors << "#{here}: code should be a non-empty block of Ruby"
        return nil
      end
      value.end_with?("\n") ? value : "#{value}\n"
    end

    def unique(list, key, file)
      list.group_by { _1[key] }.each do |name, same|
        @errors << "#{rel(file)}: #{key} \"#{name}\" is used #{same.size} times; each must be unique" if same.size > 1
      end
    end

    def check_words(raw)
      words = list_of("words", raw).each_with_index.filter_map do |e, i|
        here = where("words", i, e)
        next unless require_keys(e, %w[word group signature summary], here)

        unless GROUPS.include?(e["group"].to_s)
          @errors << "#{here}: unknown group \"#{e["group"]}\" (use one of: #{GROUPS.join(", ")})"
          next
        end
        examples = list_of("words", e["examples"]).each_with_index.filter_map do |ex, j|
          eh = "#{here}, example #{j + 1}"
          next unless require_keys(ex, %w[code], eh)

          { "code" => code(ex["code"], eh), "caption" => text(ex["caption"], "#{eh}, caption", required: false) }
        end
        see = e["see"].nil? ? [] : Array(e["see"]).map(&:to_s)
        { "word" => e["word"].to_s, "group" => e["group"].to_s, "signature" => e["signature"].to_s,
          "summary" => text(e["summary"], "#{here}, summary"),
          "details" => text(e["details"], "#{here}, details", required: false),
          "examples" => examples, "see" => see, "index" => i }
      end
      unique(words, "word", "words")
      words
    end

    def check_guide(raw)
      chapters = list_of("guide", raw).each_with_index.filter_map do |e, i|
        here = where("guide", i, e)
        next unless require_keys(e, %w[id title steps], here)

        steps = list_of("guide", e["steps"]).each_with_index.filter_map do |s, j|
          sh = "#{here}, step #{j + 1}"
          next unless require_keys(s, %w[text], sh)

          { "text" => text(s["text"], "#{sh}, text"),
            "code" => s["code"].nil? ? nil : code(s["code"], sh),
            "words" => s["words"].nil? ? [] : Array(s["words"]).map(&:to_s), "where" => sh }
        end
        { "id" => e["id"].to_s, "title" => text(e["title"], "#{here}, title"), "steps" => steps }
      end
      unique(chapters, "id", "guide")
      chapters
    end

    def check_examples(raw)
      list = list_of("examples", raw).each_with_index.filter_map do |e, i|
        here = where("examples", i, e)
        next unless require_keys(e, %w[id title code], here)

        { "id" => e["id"].to_s, "title" => text(e["title"], "#{here}, title"),
          "text" => text(e["text"], "#{here}, text", required: false), "code" => code(e["code"], here) }
      end
      unique(list, "id", "examples")
      list
    end

    def check_home(raw)
      return nil if raw.nil?

      here = rel("home")
      return nil unless require_keys(raw, %w[tagline philosophy hero_code install], here)

      lines = list_of("home", raw["philosophy"]).each_with_index.map { |l, i| text(l, "#{here}, philosophy line #{i + 1}") }
      steps = list_of("home", raw["steps"]).each_with_index.filter_map do |st, i|
        sh = "#{here}, steps, step #{i + 1}"
        next unless require_keys(st, %w[word code], sh)

        { "word" => st["word"].to_s, "code" => code(st["code"], sh), "text" => text(st["text"], "#{sh}, text", required: false), "where" => sh }
      end
      ids = ->(key) { raw[key].nil? ? nil : Array(raw[key]).map(&:to_s) }
      { "tagline" => text(raw["tagline"], "#{here}, tagline"), "philosophy" => lines,
        "hero_code" => code(raw["hero_code"], "#{here}, hero_code"), "install" => text(raw["install"], "#{here}, install"),
        "stage" => ids.("stage") || [], "gallery" => ids.("gallery"), "steps" => steps }
    end

    def check_links
      known = word_names
      if @home
        pieces = @examples.map { _1["id"] }
        (@home["stage"] + Array(@home["gallery"])).uniq.each do |id|
          @errors << "#{rel("home")}: stage/gallery names \"#{id}\", but examples.yml has no such id" unless pieces.include?(id)
        end
        @home["steps"].each do |st|
          @errors << "#{st["where"]}: word: #{st["word"]} is not a word in words.yml" unless known.include?(st["word"])
        end
      end
      @words.each do |w|
        (w["see"] - known).each { |s| @errors << "#{rel("words")}: \"#{w["word"]}\" says see: #{s}, but there is no word \"#{s}\"" }
      end
      @guide.each do |c|
        c["steps"].each do |s|
          (s["words"] - known).each { |x| @errors << "#{s["where"]}: words: #{x} is not a word in words.yml" }
        end
      end
    end
  end

  # ---- the browser bundle -------------------------------------------------

  # The library as ONE Ruby source for ruby.wasm: the files require "asobi"
  # loads, in load order, with require_relative and file-system lookups
  # taken out. live.rb (sockets, threads) never goes in.
  module Bundle
    VIRTUAL_LIB = "/asobi/lib"
    FORBIDDEN = [/require\s+["']socket["']/, /TCPServer/, /Thread\.new/].freeze

    module_function

    # The library files in the order require "asobi" loads them, found by
    # asking a fresh Ruby (so nothing this process loaded leaks in).
    def files
      script = 'require "asobi"; puts $LOADED_FEATURES.select { _1.start_with?(ARGV[0] + "/") }'
      out, err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, "-e", script, LIB)
      raise BuildError, "could not list the library files: #{err}" unless status.success?

      out.lines.map(&:chomp).reject { File.basename(_1) == "live.rb" }
    end

    def source
      parts = files.map do |path|
        rel = path.delete_prefix("#{LIB}/")
        "# ---- #{rel} " + "-" * [60 - rel.size, 4].max + "\n" + transform(File.read(path, encoding: "UTF-8"), rel)
      end
      prelude = <<~RUBY
        # frozen_string_literal: true
        # asobi #{Asobi::VERSION}, bundled for the browser (ruby.wasm) by site/build.rb.
        # Generated file: edit lib/ and rebuild instead.
        ENV["ASOBI_LIVE"] = "0" # show only remembers; nothing starts a server or opens a browser
      RUBY
      features = files.map { "#{VIRTUAL_LIB}/#{_1.delete_prefix("#{LIB}/")}" }
      epilogue = <<~RUBY
        # require "asobi" (and "asobi/pure") in a sketch: already loaded.
        $LOAD_PATH.unshift(#{VIRTUAL_LIB.dump})
        #{features.inspect}.each { |f| $LOADED_FEATURES << f unless $LOADED_FEATURES.include?(f) }
      RUBY
      text = prelude + parts.join("\n") + "\n" + epilogue + "\n" + File.read(File.join(PLAYGROUND, "runner.rb"), encoding: "UTF-8")
      check(text)
      text
    end

    def transform(code, rel)
      dir = File.dirname("#{VIRTUAL_LIB}/#{rel}")
      code = code.sub(/\A# frozen_string_literal: true\n/, "")
      # Parts loaded only when present on disk: already in the bundle.
      code = code.gsub(/^%w\[[^\]]*\]\.each do \|(\w+)\|\n(?:(?!^end$).*\n)*?^end\n/) do |block|
        block.include?("require") ? "# (optional parts: bundled above)\n" : block
      end
      code = code.gsub(/^(\s*)require_relative\s+["'][^"']+["']\s*$/) { "#{$1}nil # require_relative: bundled" }
      code.gsub("__dir__", dir.dump)
    end

    def check(text)
      bad = FORBIDDEN.select { text.match?(_1) }
      bad << /require_relative "/ if text.match?(/^\s*require_relative\s/)
      raise BuildError, "the browser bundle would contain #{bad.map(&:source).join(", ")}" unless bad.empty?
    end
  end

  # ---- decoration, drawn by asobi -------------------------------------------

  # The site's few ornaments are pictures made with the library itself.
  module Decor
    module_function

    def pictures
      a = Asobi
      plus = a.line(length: 5).outlined("#ffffff", width: 0.6) + a.line(length: 5).rotate(90).outlined("#ffffff", width: 0.6)
      {
        # a fan of petals: the browser-tab icon
        "favicon.svg" => [a.petal(length: 20, width: 9).repeat(6).in_fan.colored(:deeppink, :cyan), { margin: 2, background: :black }],
        # the registration mark pinned to the corners of paper cards
        "mark.svg" => [a.ring(radius: 5, thickness: 0.8).colored("#9a9aa6") + a.line(length: 18).outlined("#9a9aa6", width: 0.8) +
                       a.line(length: 18).rotate(90).outlined("#9a9aa6", width: 0.8), { margin: 0, background: nil }],
        # one tile of the sketchbook grid behind the pages
        "grid.svg" => [plus.opacity(0.07), { paper: [32, 32], background: nil }],
        # the wave rule between sections of the home page
        "wave.svg" => [a.wave(length: 480, height: 4, waves: 12).outlined("#3a3a46", width: 1.2), { margin: 2, background: nil }]
      }
    end

    def write(dir)
      pictures.each do |name, (art, options)|
        File.write(File.join(dir, name), Asobi::SVG.document(art, **options))
      end
    end
  end

  # ---- the build ----------------------------------------------------------

  class Builder
    attr_reader :content, :out

    def initialize(data: File.join(SITE, "data"), out: File.join(ROOT, "_site"), log: $stdout)
      @data = File.expand_path(data)
      @out = File.expand_path(out)
      @log = log
      @templates = {}
    end

    def build
      @warnings = []
      @content = Content.new(@data)
      snippets = collect
      run(snippets)
      prepare_out
      write_assets
      write_reels
      LANGUAGES.each_key { |lang| PAGES.each_key { |page| write_page(page, lang) } }
      say "built #{@out} (#{@results.size} pictures, #{@results.values.count(&:moving?)} moving)"
      @out
    end

    # Every piece of code on the site, with where it comes from.
    def collect
      list = []
      c = @content
      home = c.home
      list << Snippet.new(code: display_code(home["hero_code"]), file: "home.yml", entry: "hero_code", label: "home") if home
      c.guide.each do |ch|
        ch["steps"].each_with_index do |s, i|
          next unless s["code"]

          list << Snippet.new(code: s["code"], file: "guide.yml", entry: "#{ch["id"]}, step #{i + 1}", label: ch["id"])
        end
      end
      c.words.each do |w|
        w["examples"].each_with_index do |ex, i|
          list << Snippet.new(code: ex["code"], file: "words.yml", entry: "#{w["word"]}, example #{i + 1}", label: w["word"])
        end
      end
      c.examples.each do |ex|
        list << Snippet.new(code: display_code(ex["code"]), file: "examples.yml", entry: ex["id"], label: ex["id"])
      end
      home&.fetch("steps")&.each_with_index do |st, i|
        list << Snippet.new(code: st["code"], file: "home.yml", entry: "steps, step #{i + 1} (#{st["word"]})", label: "step_#{i + 1}")
      end
      list
    end

    def display_code(code) = AsobiSite.display_code(code)

    def run(snippets)
      @results = {}
      failures = []
      language = Asobi::Messages.instance_variable_get(:@language)
      Asobi.language = :en
      scratch = Dir.mktmpdir("asobi-site") # a sketch that saves a file saves it here, not in the project
      snippets.group_by(&:code).each do |code, same|
        first = same.first
        name = first.label.to_s.gsub(/[^\w]+/, "_") + ".rb"
        reel = begin
          Timeout.timeout(RUN_TIMEOUT) { Dir.chdir(scratch) { Asobi::Sketch.run(code, name:) } }
        rescue Timeout::Error
          Asobi::Reel.error("took longer than #{RUN_TIMEOUT} seconds")
        end
        if reel["error"]
          same.each { failures << [_1, reel["error"]] }
          next
        end
        reel = lighter(reel, code, same.first)
        key = AsobiSite.code_key(code)
        if (other = @results.values.find { _1.key == key })
          raise BuildError, "two different examples have the same picture key #{key}; change one of them slightly (#{other.reel["code"].lines.first})"
        end
        @results[code] = Result.new(key:, reel:)
        same.each { _1.result = @results[code] }
      end
      Asobi::Sketch.forget
      FileUtils.remove_entry(scratch)
      Asobi::Messages.instance_variable_set(:@language, language)
      return if failures.empty?

      lines = failures.map do |s, error|
        "#{s.file}, #{s.entry}:\n" + s.code.lines.map { "      | #{_1}" }.join.chomp + "\n    error: #{error.gsub("\n", "\n           ")}"
      end
      raise BuildError, "#{failures.size} example(s) do not run. The docs must never show code that fails:\n\n" +
                        lines.map { "  - #{_1}" }.join("\n\n")
    end

    def result_for(code) = @results.fetch(code)

    attr_reader :warnings

    # Pages must stay light. A motion whose reel is heavier than REEL_BUDGET
    # is drawn again at a lower fps (the picture is the same, the movement
    # less smooth), and the build says so.
    def lighter(reel, code, snippet)
      size = JSON.generate(reel).bytesize
      frames = reel["frames"].size
      return reel if size <= REEL_BUDGET || frames < 2

      shown = Asobi::Sketch.shown
      every = shown.thing.every.to_f
      fit = [(REEL_BUDGET * frames / size), 2].max
      fps = [(fit / every).floor, 1].max
      light = Asobi::Reel.of(shown.thing, fps:, on: shown.on, paper: shown.paper, grain: shown.grain, code:)
      (@warnings ||= []) << "#{snippet.file}, #{snippet.entry}: its reel was #{size / 1000} kB (#{frames} frames); " \
                            "drawn at #{light["frames"].size} frames (#{JSON.generate(light).bytesize / 1000} kB) instead. " \
                            "Fewer or simpler shapes, or a shorter every:, keep it smooth."
      say "warning: #{@warnings.last}"
      light
    end

    def prepare_out
      if File.exist?(@out)
        unless File.directory?(@out) && (Dir.empty?(@out) || File.exist?(File.join(@out, MARKER)))
          raise BuildError, "#{@out} exists and was not made by this builder; refusing to overwrite it"
        end
        FileUtils.rm_rf(Dir.glob(File.join(@out, "{*,.[!.]*}"), File::FNM_DOTMATCH))
      end
      FileUtils.mkdir_p(File.join(@out, "assets"))
      FileUtils.mkdir_p(File.join(@out, "reels"))
      FileUtils.mkdir_p(File.join(@out, "ja"))
      File.write(File.join(@out, MARKER), "built by site/build.rb; this directory is rewritten by every build\n")
      File.write(File.join(@out, ".nojekyll"), "")
    end

    def write_assets
      Dir.glob(File.join(ASSETS, "*")).each { FileUtils.cp(_1, File.join(@out, "assets")) }
      %w[ruby-engine.js ruby-worker.js].each { FileUtils.cp(File.join(PLAYGROUND, _1), File.join(@out, "assets")) }
      FileUtils.cp(Asobi::Reel::PLAYER, File.join(@out, "assets", "player.js"))
      Decor.write(File.join(@out, "assets"))
      ruby = Bundle.source
      File.write(File.join(@out, "assets", "asobi.rb"), ruby)
      File.write(File.join(@out, "assets", "asobi-ruby.js"),
                 "/* asobi #{Asobi::VERSION} for ruby.wasm, generated by site/build.rb (source: asobi.rb next to this file) */\n" \
                 "self.ASOBI_RUBY = #{JSON.generate(ruby).gsub("</", "<\\/")};\n")
    end

    # One small script per picture: it registers itself when loaded, so it
    # works from file:// as well as from a server (no fetch of JSON).
    def write_reels
      @results.each_value do |r|
        js = "asobiReel(#{JSON.generate(r.key)}, #{Asobi::Reel.script_json(r.reel)});\n"
        File.write(File.join(@out, "reels", "#{r.key}.js"), js)
      end
    end

    def write_page(page, lang)
      view = PageView.new(self, page, lang)
      html = view.render
      path = lang == :en ? File.join(@out, "#{page}.html") : File.join(@out, "ja", "#{page}.html")
      File.write(path, html)
    end

    def template(name)
      @templates[name] ||= ERB.new(File.read(File.join(TEMPLATES, "#{name}.html.erb"), encoding: "UTF-8"), trim_mode: "-").tap do |erb|
        erb.filename = File.join(TEMPLATES, "#{name}.html.erb")
      end
    end

    def say(text) = @log&.puts(text)
  end

  # What a template sees: the data, the language, and helpers.
  class PageView
    include ERB::Util

    attr_reader :page, :lang, :content

    def initialize(builder, page, lang)
      @builder = builder
      @page = page
      @lang = lang
      @content = builder.content
      @words = content.words.to_h { [_1["word"], _1] }
    end

    def render
      body = partial(PAGES.fetch(@page).to_s)
      partial("layout", body:)
    end

    def partial(name, **locals)
      b = binding
      locals.each { |k, v| b.local_variable_set(k, v) }
      @builder.template(name).result(b)
    end

    def ui(key, *args)
      text = UI.fetch(@lang).fetch(key)
      args.empty? ? text : format(text, *args)
    end

    def t(map) = map && map.fetch(@lang)

    # Relative path from this page to the site root.
    def root = @lang == :en ? "" : "../"

    def href(page, fragment = nil) = "#{page}.html#{fragment ? "##{fragment}" : ""}"

    def other_language_href = @lang == :en ? "ja/#{@page}.html" : "../#{@page}.html"
    def other_lang = @lang == :en ? :ja : :en

    def title
      @page == "index" ? "asobi" : "#{ui(@page.to_sym)} — asobi"
    end

    def groups
      GROUPS.filter_map do |g|
        list = content.words.select { _1["group"] == g }
        [g, list] unless list.empty?
      end
    end

    def word_href(word, new_tab: false)
      a = AsobiSite.anchor(word)
      @page == "reference" && !new_tab ? "##{a}" : href("reference", a)
    end

    def play_href(code) = "#{href("playground")}#code=#{AsobiSite.encode_code(code)}"

    # Text with `code` spans; a backticked reference word becomes a link.
    # Blank lines separate paragraphs.
    def rich(text, tag: "p")
      return "" if text.nil? || text.strip.empty?

      text.strip.split(/\n\s*\n/).map do |para|
        "<#{tag}>#{inline(para.gsub(/\s*\n\s*/, " "))}</#{tag}>"
      end.join("\n")
    end

    def inline(text)
      text.split(/(`[^`]+`)/).map do |part|
        if part.start_with?("`") && part.end_with?("`") && part.size > 2
          inner = part[1..-2]
          word = linked_word(inner)
          code = "<code>#{h(inner)}</code>"
          word ? %(<a href="#{h(word_href(word))}">#{code}</a>) : code
        else
          h(part)
        end
      end.join
    end

    # `circle`, `circle(radius: 12)`, `.repeat` and `a.on(b)` style mentions.
    def linked_word(inner)
      return inner if @words.key?(inner)

      m = inner.match(/\A\.?([a-z_][a-z0-9_]*[?!]?)(?:\(|\z)/) || inner.match(/\A[a-z_][a-z0-9_]*\.([a-z_][a-z0-9_]*[?!]?)(?:\(|\z)/)
      m && @words.key?(m[1]) ? m[1] : nil
    end

    def result_for(code) = @builder.result_for(code)

    # The picture for a piece of code, with a small readout under it. A still
    # picture is plain inline SVG; a motion also shows its first frame as SVG,
    # and the page script loads its reel and plays it while it is on screen
    # (the stage on the home page plays its own: live: false).
    #
    # A light background reads as a sheet of paper pinned on the dark stage
    # ("paper"); a dark one as a screen ("screen").
    def picture(code, label, css: "", live: true, readout: true)
      r = result_for(code)
      reel = r.reel
      x, y, w, hgt = reel["view"]
      ratio = (w.to_f / [hgt.to_f, 1e-9].max).clamp(0.6, 2.4).round(3)
      bg = reel["background"].to_s
      svg = %(<svg class="pic-still" viewBox="#{[x, y, w, hgt].join(" ")}" preserveAspectRatio="xMidYMid meet" ) +
            %(stroke-linejoin="round" stroke-linecap="round" aria-hidden="true" focusable="false">) +
            %(<rect x="#{x}" y="#{y}" width="#{w}" height="#{hgt}" fill="#{h(bg)}"/>#{reel["frames"].first}</svg>)
      moving = r.moving? && live ? %( data-reel="#{r.key}" data-fps="#{reel["fps"]}" data-count="#{reel["frames"].size}") : ""
      kind = AsobiSite.light?(bg) ? "paper" : "screen"
      pic = %(<div class="pic" role="img" aria-label="#{h(ui(:picture_of, label))}" style="background:#{h(bg)};--r:#{ratio}"#{moving}>#{svg}</div>)
      %(<div class="shot #{kind} #{css}" style="--r:#{ratio}">#{pic}#{readout ? readout_for(r) : ""}</div>)
    end

    # "▶ 012/120 · every 4s" for a motion, "still" for a picture: the truth
    # about what is playing, in the margin, like a sketch's own HUD.
    def readout_for(result)
      reel = result.reel
      n = reel["frames"].size
      return %(<p class="readout" aria-hidden="true"><span class="ro-dot still"></span>#{ui(:still)} · #{reel["view"][2].round}×#{reel["view"][3].round}</p>) if n < 2

      digits = n.to_s.size
      %(<p class="readout" aria-hidden="true"><span class="ro-dot"></span><span data-fc>#{"0" * digits}</span>/#{n} · ) +
        %(#{ui(:every, seconds(n / reel["fps"].to_f))}</p>)
    end

    def seconds(value)
      value = value.round(1)
      value == value.round ? value.round.to_s : value.to_s
    end

    def word_list = @word_list ||= content.words.map { _1["word"] }.grep(/\A[a-z_][a-z0-9_]*[?!]?\z/)

    # A code block with Ruby tinting. The text inside is the code itself.
    def code_block(code, fresh: [], css: "code")
      %(<pre class="#{css}"><code>#{AsobiSite.highlight(code, word_list, fresh:)}</code></pre>)
    end

    # Code laid over a picture line by line, like the live view's `c` key.
    def subtitles(code, css: "subs")
      lines = code.chomp.split("\n", -1).map do |line|
        line.strip.empty? ? %(<span class="sub blank"> </span>) : %(<span class="sub">#{AsobiSite.highlight(line, word_list)}</span>)
      end
      %(<pre class="#{css}"><code>#{lines.join("\n")}</code></pre>)
    end

    def example_by_id(id) = content.examples.find { _1["id"] == id }

    # What the home stage plays: the hero first, then the stage: pieces.
    def stage_pieces
      hero = { "id" => "asobi", "title" => content.home["tagline"], "code" => default_play_code }
      [hero] + content.home["stage"].map { |id| ex = example_by_id(id); ex.merge("code" => AsobiSite.display_code(ex["code"])) }
    end

    def stage_data
      stage_pieces.map do |piece|
        r = result_for(piece["code"])
        reel = r.reel
        timing = r.moving? ? ui(:every, seconds(reel["frames"].size / reel["fps"].to_f)) : ui(:still)
        { "id" => piece["id"], "key" => r.key, "file" => "#{piece["id"]}.rb", "background" => reel["background"], "timing" => timing,
          "frames" => reel["frames"].size, "fps" => reel["fps"], "title" => t(piece["title"]),
          "play" => play_href(piece["code"]), "code" => piece["code"] }
      end
    end

    def gallery_glimpse
      ids = content.home["gallery"] || content.examples.first(3).map { _1["id"] }
      ids.map { example_by_id(_1) }
    end

    def group_title(group) = ui(:groups)[group]

    # Code + its picture + "open in playground".
    def example(code, label, caption: nil)
      partial("_example", code:, label:, caption:)
    end

    def default_play_code = AsobiSite.display_code(content.home["hero_code"])

    def play_config
      ui_keys = %i[loading_ruby ruby_ready running ruby_failed copied copy_failed every still]
      {
        "lang" => @lang.to_s,
        "ui" => ui_keys.to_h { [_1.to_s, ui(_1)] }.merge("too_slow" => ui(:too_slow, PLAY_TIMEOUT)),
        "timeout" => PLAY_TIMEOUT * 1000,
        "assets" => "#{root}assets/",
        "reels" => "#{root}reels/",
        "rubyWasm" => RUBY_WASM,
        "defaultCode" => default_play_code,
        "defaultKey" => result_for(default_play_code).key,
        "words" => word_list
      }
    end

    def script_json(data) = Asobi::Reel.script_json(data)
  end

  def self.main(argv)
    options = { out: File.join(ROOT, "_site"), data: File.join(SITE, "data") }
    OptionParser.new do |o|
      o.banner = "usage: ruby -Ilib site/build.rb [--out DIR] [--data DIR]"
      o.on("--out DIR", "where to write the site (default: _site)") { options[:out] = _1 }
      o.on("--data DIR", "where the YAML lives (default: site/data)") { options[:data] = _1 }
    end.parse!(argv)
    Builder.new(**options).build
    0
  rescue BuildError => e
    warn "site build failed:\n#{e.message}"
    1
  end
end

exit(AsobiSite.main(ARGV)) if $PROGRAM_NAME == __FILE__
