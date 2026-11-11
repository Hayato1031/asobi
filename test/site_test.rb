# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../site/build"

# The website builder (site/build.rb), built from the small fixture data in
# test/site/fixtures (the same schema as site/data).
class SiteTest < Minitest::Test
  FIXTURES = File.expand_path("site/fixtures", __dir__)
  PAGES = %w[index guide reference examples playground].freeze

  # One build of the fixtures, shared by the read-only tests.
  def self.built
    @built ||= begin
      out = Dir.mktmpdir("asobi-site-test")
      Minitest.after_run { FileUtils.remove_entry(out) if File.exist?(out) }
      AsobiSite::Builder.new(data: FIXTURES, out:, log: nil).build
      out
    end
  end

  def setup
    super
    ENV["ASOBI_LIVE"] = "0"
    @out = self.class.built
  end

  def read(rel) = File.read(File.join(@out, rel), encoding: "UTF-8")
  def html_files = Dir.glob(File.join(@out, "**", "*.html"))

  # A copy of the fixtures to break on purpose; answers the build's error.
  def build_error
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.cp_r(FIXTURES, data)
      yield data
      error = assert_raises(AsobiSite::BuildError) do
        AsobiSite::Builder.new(data:, out: File.join(dir, "out"), log: nil).build
      end
      error.message
    end
  end

  def edit(path)
    File.write(path, yield(File.read(path, encoding: "UTF-8")))
  end

  # ---- pages -----------------------------------------------------------------

  def test_every_page_in_both_languages
    PAGES.each do |page|
      en = read("#{page}.html")
      ja = read("ja/#{page}.html")
      assert_includes en, '<html lang="en"', page
      assert_includes ja, '<html lang="ja"', page
    end
    assert_includes read("guide.html"), "Make a shape"
    assert_includes read("ja/guide.html"), "形を作る"
    assert_includes read("ja/reference.html"), "塗りつぶした丸。"
  end

  def test_language_switch_shows_both_languages_and_opens_the_matching_page
    PAGES.each do |page|
      [%w[en ja], %w[ja en]].each do |current, other|
        file = current == "en" ? "#{page}.html" : "ja/#{page}.html"
        destination = current == "en" ? "ja/#{page}.html" : "../#{page}.html"
        switch = read(file)[%r{<nav\b[^>]*class="lang"[^>]*>.*?</nav>}m]
        assert switch, "#{file}: missing language switch"
        assert_match(/<nav\b[^>]*aria-label="[^"]+"/, switch)
        assert_equal %w[JA EN], switch.scan(/>(JA|EN)</).flatten, file

        active = switch[/<span\b[^>]*aria-current="true"[^>]*>/]
        assert active, "#{file}: missing current language"
        assert_includes active, %(lang="#{current}"), file
        names = { "ja" => "日本語", "en" => "English" }
        assert_includes switch, ">#{names.fetch(current)}</span>", file
        links = switch.scan(%r{<a\b([^>]*)>(JA|EN)</a>})
        assert_equal [other.upcase], links.map(&:last), file
        attrs = links.first.first
        assert_includes attrs, %( lang="#{other}"), file
        assert_includes attrs, %(aria-label="#{names.fetch(other)}"), file
        assert_includes attrs, %(hreflang="#{other}"), file
        assert_includes attrs, %(href="#{destination}"), file
        assert_includes attrs, "data-keep-hash", file
        refute_includes attrs, "aria-current", file
      end
    end
  end

  def test_sitemap_lists_the_canonical_pages_of_both_languages
    sitemap_urls = read("sitemap.xml").scan(%r{<loc>(.*?)</loc>}).flatten
    canonical_urls = []
    PAGES.each do |page|
      %w[en ja].each do |lang|
        directory = lang == "en" ? "" : "ja/"
        url = "https://asobi.myura.me/#{directory}#{page unless page == "index"}"
        html = read("#{directory}#{page}.html")
        assert_includes html, %(<link rel="canonical" href="#{url}">)
        assert_includes html, %(<link rel="alternate" hreflang="#{lang}" href="#{url}">)
        canonical_urls << url
      end
    end
    assert_equal canonical_urls.sort, sitemap_urls.sort
    assert_includes read("robots.txt").lines.map(&:chomp), "Sitemap: https://asobi.myura.me/sitemap.xml"
  end

  def test_footers_show_the_version_and_license_in_each_language
    PAGES.each do |page|
      { "#{page}.html" => [/MIT license/i, /browser.*Copy link/i],
        "ja/#{page}.html" => [/MIT\s*ライセンス/, /ブラウザ.*リンクをコピー/] }.each do |file, (license, sharing_note)|
        footer = read(file)[%r{<footer\b[^>]*>.*?</footer>}m]
        assert footer, "#{file}: missing footer"
        assert_includes footer, Asobi::VERSION, file
        assert_match license, footer, file
        refute_match(/ruby\.wasm|jsdelivr/i, footer, file)
        if page == "playground"
          assert_match sharing_note, footer, file
        else
          refute_match sharing_note, footer, file
        end
      end
    end
  end

  def test_every_internal_link_and_anchor_resolves
    checked = 0
    html_files.each do |file|
      text = File.read(file, encoding: "UTF-8")
      text.scan(/(?:href|src)="([^"]*)"/).flatten.each do |url|
        url = CGI.unescapeHTML(url)
        next if url.match?(%r{\A(?:https?:|mailto:|data:)})

        path, fragment = url.split("#", 2)
        target = path.empty? ? file : File.expand_path(path, File.dirname(file))
        assert File.file?(target), "#{file.delete_prefix(@out)} links to #{url}, which does not exist"
        if fragment && !fragment.start_with?("code=") && target.end_with?(".html")
          assert_includes File.read(target), %(id="#{fragment}"), "#{file.delete_prefix(@out)}: no anchor ##{fragment} in #{path}"
        end
        checked += 1
      end
      text.scan(/data-reel="([^"]+)"/).flatten.each do |key|
        assert File.file?(File.join(@out, "reels", "#{key}.js")), "missing reel #{key}"
      end
    end
    assert_operator checked, :>, 100
  end

  def test_only_external_resource_is_ruby_wasm_from_jsdelivr
    externals = (html_files + Dir.glob(File.join(@out, "assets", "*.{js,css}"))).flat_map do |f|
      source = File.read(f, encoding: "UTF-8")
      # Navigation and search metadata contain URLs but do not load resources.
      if f.end_with?(".html")
        source = source.gsub(%r{(<a\b[^>]*?\s)href="https?://[^"]*"}, '\1')
        source = source.gsub(/<link rel="(?:alternate|canonical)"[^>]*>/, "")
      end
      source.scan(%r{https?://[^\s"'<>)\\]+})
    end.uniq
    externals.reject! { _1.start_with?("http://www.w3.org/") } # the SVG namespace, not a download
    assert externals.all? { _1.start_with?("https://cdn.jsdelivr.net/npm/@ruby/") }, externals.inspect
    %w[playground.html ja/playground.html].each do |file|
      assert_includes read(file), "@ruby/3.4-wasm-wasi@#{AsobiSite::RUBY_WASM_VERSION}", file
    end
  end

  # ---- pictures --------------------------------------------------------------

  def test_a_still_example_is_inline_svg
    ref = read("reference.html")
    pic = ref[/<div class="pic"[^>]*aria-label="Picture: A still picture\."[^>]*>.*?<\/svg><\/div>/m]
    assert pic, "the circle example's picture"
    refute_includes pic, "data-reel"
    assert_includes pic, '<circle r="12"/>'
    assert_includes pic, 'role="img"'
  end

  def test_a_moving_example_ships_a_reel_with_many_frames
    ref = read("reference.html")
    key = ref[/aria-label="Picture: It moves\."[^>]*data-reel="(r\h{8})"/, 1]
    assert key, "the spin example is marked as moving"
    js = File.read(File.join(@out, "reels", "#{key}.js"))
    assert js.start_with?("asobiReel(\"#{key}\", ")
    reel = JSON.parse(js[/\A[^,]+, (.*)\);\n\z/m, 1])
    assert_operator reel["frames"].size, :>, 1
    assert_nil reel["error"]
    assert_equal AsobiSite.code_key(%(show star.colored(:crimson).spin(every: 2)\n)), key
  end

  def test_home_hero_plays_and_has_the_install_line
    home = read("index.html")
    # The stage lists the pieces it plays; each is a real reel shipped beside the page.
    stage = JSON.parse(home[%r{<script type="application/json" id="stage-data">(.*?)</script>}m, 1])
    refute_empty stage
    stage.each do |piece|
      assert_match(/\Ar\h{8}\z/, piece["key"])
      assert_operator piece["frames"], :>, 1
      assert File.exist?(File.join(@out, "reels", "#{piece["key"]}.js")), "reel for #{piece["id"]} is shipped"
    end
    assert_match(/<section class="stage"[^>]*>.*?<svg class="pic-still"/m, home, "the first frame is there before any script runs")
    assert_includes home, "gem install asobi"
    assert_includes home, 'href="playground.html"'
  end

  # ---- links between the parts --------------------------------------------------

  def test_backticked_words_link_to_the_reference
    assert_includes read("reference.html"), %(<a href="#ring"><code>ring</code></a>)
    assert_includes read("reference.html"), %(<a href="#star">) if read("reference.html").include?('id="star"')
    guide = read("guide.html")
    assert_includes guide, %(<a href="reference.html#circle"><code>circle</code></a>)
    assert_includes guide, "<code>nothing_linked</code>"
    refute_includes guide, "reference.html#nothing_linked"
    assert_includes read("reference.html"), 'id="op-plus"'
  end

  def test_playground_word_list_opens_reference_entries
    play = read("ja/playground.html")
    assert_includes play, %(href="reference.html#circle" target="_blank")
    assert_includes play, %(href="reference.html#op-plus")
  end

  def test_every_example_opens_in_the_playground_with_its_code
    ex = read("examples.html")
    links = ex.scan(/href="playground\.html#code=([A-Za-z0-9_-]+)"/).flatten
    assert_equal 2, links.size
    codes = links.map { AsobiSite.decode_code(_1) }
    assert_includes codes.last, %(show text("あそび & <b>", size: 20), on: :ivory)
    assert codes.all? { _1.start_with?(%(require "asobi"\n)) }
    # and the playground can find the picture made at build time
    codes.each { assert File.file?(File.join(@out, "reels", "#{AsobiSite.code_key(_1)}.js")) }
  end

  CODES = [
    "show circle\n",
    "# 日本語のコメント & \"quotes\" <tags> + * / ? = 🌸\nshow text(\"あそび\")\n",
    "x = [1, 2, 3].map { |n| n * 2 } # ~!@\#$%^&*()_+-={}[]|\\:;'<>,.?/\n",
    ""
  ].freeze

  def test_playground_code_round_trips_through_the_url
    CODES.each do |code|
      encoded = AsobiSite.encode_code(code)
      assert_match(/\A[A-Za-z0-9_-]*\z/, encoded)
      assert_equal code, AsobiSite.decode_code(encoded)
    end
  end

  def test_the_javascript_decoder_and_key_agree_with_ruby
    node = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, "node") }.find { File.executable?(_1) }
    skip "node is not installed" unless node

    script = <<~JS
      const api = require(process.argv[1]);
      const cases = JSON.parse(require("fs").readFileSync(0, "utf8"));
      console.log(JSON.stringify(cases.map(c => ({
        decoded: api.decode(c.encoded), encoded: api.encode(c.code), key: api.key(c.code),
        hash: api.fromHash("#code=" + c.encoded)
      }))));
    JS
    cases = CODES.map { { "code" => _1, "encoded" => AsobiSite.encode_code(_1) } }
    out, err, status = Open3.capture3(node, "-e", script, File.join(@out, "assets", "code-url.js"), stdin_data: JSON.generate(cases))
    assert status.success?, err
    JSON.parse(out.force_encoding(Encoding::UTF_8)).zip(CODES).each do |js, code|
      assert_equal code, js["decoded"]
      assert_equal code, js["hash"]
      assert_equal AsobiSite.encode_code(code), js["encoded"]
      assert_equal AsobiSite.code_key(code), js["key"]
    end
  end

  # ---- the browser bundle ------------------------------------------------------

  def test_browser_bundle_is_one_file_without_sockets_threads_or_requires
    ruby = read("assets/asobi.rb")
    refute_match(/require\s+["']socket["']/, ruby)
    refute_includes ruby, "TCPServer"
    refute_includes ruby, "Thread.new"
    refute_match(/^\s*require_relative\s/, ruby)
    refute_includes ruby, "__dir__"
    refute_includes ruby, "lib/asobi/live.rb"
    assert_includes ruby, "module Web"
    assert_includes ruby, 'ENV["ASOBI_LIVE"] = "0"'
    js = read("assets/asobi-ruby.js")
    assert_equal ruby, JSON.parse(js[/self\.ASOBI_RUBY = (.*);\n\z/m, 1].gsub("<\\/", "</"))
  end

  # The bundle stands on its own: plain Ruby (no -I lib) can load it, a
  # sketch's require "asobi" is a no-op, and Asobi::Web.run answers a Reel.
  def test_browser_bundle_runs_in_a_plain_ruby
    script = <<~RUBY
      eval(File.read(ARGV[0], encoding: "UTF-8"), TOPLEVEL_BINDING, "asobi.rb", 1)
      good = JSON.parse(Asobi::Web.run(%(require "asobi"\\nshow circle(radius: 3).spin\\n), "en"))
      bad = JSON.parse(Asobi::Web.run("show circel\\n", "ja"))
      puts JSON.generate([good["frames"].size, good["error"], bad["error"], defined?(Asobi::Live).inspect])
    RUBY
    out, err, status = Open3.capture3({ "ASOBI_LIVE" => nil }, RbConfig.ruby, "-e", script, File.join(@out, "assets", "asobi.rb"))
    assert status.success?, err
    frames, error, bad, live = JSON.parse(out.force_encoding(Encoding::UTF_8))
    assert_operator frames, :>, 1
    assert_nil error
    assert_match(/\Aplay\.rb:1 /, bad)
    assert_includes bad, "もしかして"
    assert_equal "nil", live
  end

  # ---- the build refuses to lie --------------------------------------------------

  def test_a_broken_example_fails_the_build_and_names_it
    message = build_error do |data|
      edit(File.join(data, "words.yml")) { _1.sub("show ring.colored(:teal)", "show ring.colored(:tael)") }
      edit(File.join(data, "examples.yml")) { _1.sub("show flower.spin(every: 8)", "show flowr.spin(every: 8)") }
    end
    assert_includes message, "2 example(s) do not run"
    assert_includes message, "words.yml, ring, example 1"
    assert_includes message, "show ring.colored(:tael)"
    assert_includes message, "tael"
    assert_includes message, "examples.yml, flower"
    assert_includes message, "flowr"
  end

  def test_an_unknown_group_fails_with_file_and_entry
    message = build_error do |data|
      edit(File.join(data, "words.yml")) { _1.sub("group: combine", "group: mixing") }
    end
    assert_includes message, "words.yml, entry 3 (+): unknown group \"mixing\""
    assert_includes message, "shapes, combine"
  end

  def test_a_missing_required_key_fails_with_file_and_entry
    message = build_error do |data|
      edit(File.join(data, "words.yml")) { _1.sub(%(  signature: "ring(radius: 20, thickness: 4)"\n), "") }
      edit(File.join(data, "guide.yml")) { _1.sub(%(  title: { en: "Make it move", ja: "動かす" }\n), "") }
      edit(File.join(data, "home.yml")) { _1.sub(/^install:.*\n/, "") }
      edit(File.join(data, "examples.yml")) { _1.sub(%(ja: "扇に並べた花びら。"), %(fr: "x")) }
    end
    assert_includes message, %(words.yml, entry 2 (ring): missing required key "signature")
    assert_includes message, %(guide.yml, entry 2 (motion): missing required key "title")
    assert_includes message, %(home.yml: missing required key "install")
    refute_includes message, "flower" # an optional text with one language is fine
  end

  def test_a_required_text_needs_both_languages_and_links_must_exist
    message = build_error do |data|
      edit(File.join(data, "words.yml")) do
        _1.sub(%(summary: { en: "A filled circle.", ja: "塗りつぶした丸。" }), %(summary: { en: "A filled circle." }))
          .sub("see: [ring, spin]", "see: [ring, spinn]")
      end
    end
    assert_includes message, %(words.yml, entry 1 (circle), summary: missing "ja")
    assert_includes message, %("circle" says see: spinn, but there is no word "spinn")
  end

  def test_will_not_wipe_a_directory_it_did_not_make
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "precious.txt"), "keep me")
      assert_raises(AsobiSite::BuildError) { AsobiSite::Builder.new(data: FIXTURES, out: dir, log: nil).build }
      assert File.file?(File.join(dir, "precious.txt"))
    end
  end

  def test_rebuilding_replaces_the_old_output
    Dir.mktmpdir do |dir|
      out = File.join(dir, "site")
      AsobiSite::Builder.new(data: FIXTURES, out:, log: nil).build
      File.write(File.join(out, "reels", "rstale000.js"), "")
      AsobiSite::Builder.new(data: FIXTURES, out:, log: nil).build
      refute File.exist?(File.join(out, "reels", "rstale000.js"))
      assert File.file?(File.join(out, ".nojekyll"))
    end
  end
end
