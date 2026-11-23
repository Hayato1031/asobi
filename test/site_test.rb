# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "digest"
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
        folder = current == "en" ? "ja/" : "../"
        destination = page == "index" ? folder : "#{folder}#{page}"
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
        # Clean links: "./", "ja/" and "../" are a folder's index.html, "playground" is playground.html.
        target = File.join(target, "index.html") if File.directory?(target)
        target += ".html" if !File.file?(target) && File.extname(target).empty? && File.file?("#{target}.html")
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

  # The site's own page links: relative, no scheme, not an asset or a script.
  def own_page_hrefs(dir)
    Dir.glob(File.join(dir, "**", "*.html")).flat_map do |file|
      File.read(file, encoding: "UTF-8").scan(/\shref="([^"]*)"/).flatten.reject { _1.match?(%r{\A(?:[a-z]+:|//)}) }
    end
  end

  def test_default_build_links_to_clean_urls
    hrefs = own_page_hrefs(@out)
    assert_operator hrefs.size, :>, 100
    assert_empty hrefs.grep(/\.html(?:#|\z)/).uniq.first(5)
    assert_empty hrefs.grep(/index(?:#|\z)/).uniq.first(5)
    assert_includes read("index.html"), 'href="playground"'
    assert_includes read("index.html"), 'href="ja/"'
    assert_includes read("ja/index.html"), 'href="../"'
    assert_includes read("ja/playground.html"), 'href="../playground"'
  end

  def test_file_links_build_keeps_html_for_opening_from_the_disk
    Dir.mktmpdir("asobi-site-files") do |out|
      AsobiSite::Builder.new(data: FIXTURES, out:, log: nil, file_links: true).build
      hrefs = own_page_hrefs(out)
      assert_includes hrefs, "playground.html"
      assert_includes hrefs, "index.html"
      assert_includes hrefs, "ja/index.html"
      assert_includes hrefs, "../playground.html"
      refute_includes hrefs, "./"
      assert_includes hrefs.grep(/\Areference\.html#/).first.to_s, "reference.html#"
    end
  end

  def test_only_external_resource_is_ruby_wasm_from_jsdelivr
    externals = (html_files + Dir.glob(File.join(@out, "assets", "*.{js,css}"))).flat_map do |f|
      source = File.read(f, encoding: "UTF-8")
      # Navigation, social previews, and search metadata contain URLs but do not load resources.
      if f.end_with?(".html")
        source.scan(/<meta\s+(?:property="og:image"|name="twitter:image")\s+content="([^"]+)"/).flatten.each do |img_url|
          assert img_url.start_with?(AsobiSite::SITE_URL), "#{f}: external preview image #{img_url}"
        end
        source = source.gsub(%r{(<a\b[^>]*?\s)href="https?://[^"]*"}, '\1')
        source = source.gsub(/<link rel="(?:alternate|canonical)"[^>]*>/, "")
        source = source.gsub(/<meta\s+(?:property="og:|name="twitter:)[^>]*>/, "")
        source = source.gsub(%r{<script\s+type="application/ld\+json">.*?</script>}m, "")
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
    assert_includes home, 'href="playground"'
    refute_includes home, 'class="press"' # no press list unless home.yml has one
    refute_includes home, 'id="film"' # no films unless home.yml has some
  end

  # ---- links between the parts --------------------------------------------------

  def test_backticked_words_link_to_the_reference
    assert_includes read("reference.html"), %(<a href="#ring"><code>ring</code></a>)
    assert_includes read("reference.html"), %(<a href="#star">) if read("reference.html").include?('id="star"')
    guide = read("guide.html")
    assert_includes guide, %(<a href="reference#circle"><code>circle</code></a>)
    assert_includes guide, "<code>nothing_linked</code>"
    refute_includes guide, "reference#nothing_linked"
    assert_includes read("reference.html"), 'id="op-plus"'
  end

  def test_playground_word_list_opens_reference_entries
    play = read("ja/playground.html")
    assert_includes play, %(href="reference#circle" target="_blank")
    assert_includes play, %(href="reference#op-plus")
  end

  def test_every_example_opens_in_the_playground_with_its_code
    ex = read("examples.html")
    links = ex.scan(/href="playground#code=([A-Za-z0-9_-]+)"/).flatten
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

  # The playground's two steps: start answers a motion's preview at once,
  # finish the whole Reel (what run answers in one step).
  def test_browser_bundle_answers_a_preview_first
    script = <<~RUBY
      eval(File.read(ARGV[0], encoding: "UTF-8"), TOPLEVEL_BINDING, "asobi.rb", 1)
      code = %(show circle(radius: 3).move(right: 9).spin\\n)
      first = JSON.parse(Asobi::Web.start(code, "en"))
      waiting = Asobi::Web.waiting?
      whole = JSON.parse(Asobi::Web.finish)
      still = JSON.parse(Asobi::Web.start("show circle\\n", "en"))
      puts JSON.generate([first["pending"], first["frames"].size, waiting, whole == JSON.parse(Asobi::Web.run(code, "en")),
                          still["pending"], Asobi::Web.waiting?, Asobi::Web.finish])
    RUBY
    out, err, status = Open3.capture3({ "ASOBI_LIVE" => nil }, RbConfig.ruby, "-e", script, File.join(@out, "assets", "asobi.rb"))
    assert status.success?, err
    assert_equal [true, 1, true, true, nil, false, nil], JSON.parse(out)
  end

  def test_playground_engine_speaks_in_two_steps
    worker = read("assets/ruby-worker.js")
    assert_includes worker, "preview: true"
    assert_includes worker, "skipped: true"
    assert_includes worker, "working: true"
    engine = read("assets/ruby-engine.js")
    assert_includes engine, "Asobi::Web.start"
    assert_includes engine, "Asobi::Web.finish"
    assert_includes engine, "Asobi::Web.finish_some"
    assert_includes engine, "Asobi::Web.drop"
    config = JSON.parse(read("playground.html")[%r{id="play-config">(.*?)</script>}m, 1])
    assert_operator config["finishTimeout"], :>, config["timeout"]
    assert_includes config["ui"]["too_slow_whole"], config["finishTimeout"].div(1000).to_s
  end

  def test_playground_says_when_ruby_crashed_in_both_languages
    en = JSON.parse(read("playground.html")[%r{id="play-config">(.*?)</script>}m, 1])
    ja = JSON.parse(read("ja/playground.html")[%r{id="play-config">(.*?)</script>}m, 1])
    assert_includes en["ui"]["crashed"], "started again"
    assert_includes ja["ui"]["crashed"], "起動し直しました"
  end

  # ---- what the playground lets through (a link can carry any Ruby) -----------

  # The site's CSP has no 'unsafe-eval', and the js gem runs JS.eval
  # (Function(code)) as it loads: the engine must never ask for it.
  def test_ruby_engine_does_without_the_js_bridge
    engine = read("assets/ruby-engine.js")
    refute_match(/require\s*\(?\s*["']js["']/, engine)
    refute_includes engine, ".wrap("
  end

  # Strings reach Ruby as Ruby source (test/web/ruby-string-check.js).
  def test_ruby_engine_writes_strings_as_hex_ruby_literals
    result = node_check("ruby-string-check.js", File.join(@out, "assets", "ruby-engine.js"))
    assert_equal 9, result["cases"].size
    result["cases"].each do |c|
      assert c["shape"], "only hex between the quotes: #{c["expr"]}"
      assert c["roundTrip"], "the hex is the UTF-8 bytes of #{c["text"].inspect}"
      ruby = eval(c["expr"]) # rubocop:disable Security/Eval -- checked above: hex digits only
      assert_equal c["text"], ruby
      assert_equal Encoding::UTF_8, ruby.encoding
      assert ruby.valid_encoding?
    end
    assert_equal ['"ja"', '"en"', '"en"', '"en"', '"en"'], result["lang"]
  end

  def test_playground_checks_what_the_engine_sends_in_both_languages
    { "playground.html" => "was not shown", "ja/playground.html" => "表示しませんでした" }.each do |file, words|
      html = read(file)
      config = JSON.parse(html[%r{id="play-config">(.*?)</script>}m, 1])
      assert_includes config["ui"]["blocked"], words, file
      safe = html.index(%r{<script src="[^"]*assets/safe-reel\.js" defer></script>})
      play = html.index(%r{<script src="[^"]*assets/playground\.js" defer></script>})
      assert safe && play && safe < play, "#{file}: safe-reel.js loads before playground.js"
    end
    assert File.exist?(File.join(@out, "assets", "safe-reel.js"))
  end

  def test_headers_set_a_content_security_policy_for_every_page
    headers = read("_headers")
    block = headers[%r{^/\*\n((?:  .*\n)+)}, 1]
    assert block, "a /* block"
    csp = block[/^  Content-Security-Policy: (.*)$/, 1]
    assert csp, "a Content-Security-Policy"
    directives = csp.split(";").map(&:strip).to_h { |d| d.split(" ", 2) }
    script = directives.fetch("script-src").split
    refute_includes script, "'unsafe-inline'"
    refute_includes script, "'unsafe-eval'"
    refute_includes script, "https://cdn.jsdelivr.net"
    assert_includes script, AsobiSite::RUBY_WASM.fetch("api")
    assert_includes script, "https://static.cloudflareinsights.com"
    assert_includes directives.fetch("connect-src").split, AsobiSite::RUBY_WASM.fetch("wasm")
    assert_includes directives.fetch("connect-src").split, "https://cloudflareinsights.com"
    assert_equal "'none'", directives.fetch("object-src")
    refute directives.key?("frame-ancestors"), "embedding the site stays allowed"
    assert_includes block, "Strict-Transport-Security: max-age=31536000"
    assert_includes block, "Permissions-Policy: camera=(), geolocation=()"
    refute_match(/microphone/, block, "the player listens to the microphone")
    refute_includes headers, "X-Frame-Options"
  end

  # The worker's address changes with the headers and the worker's scripts,
  # so a cache that kept old headers for the old address is not asked.
  def test_worker_address_carries_a_version_of_the_headers_and_scripts
    versions = %w[playground.html ja/playground.html].map do |page|
      JSON.parse(read(page)[%r{id="play-config">(.*?)</script>}m, 1]).fetch("workerVersion")
    end
    assert_equal 1, versions.uniq.size
    assert_match(/\A[0-9a-f]{12}\z/, versions.first)

    block = read("_headers")[%r{^/\*\n((?:  .*\n)+)}, 1]
    digest = Digest::SHA256.new
    block.lines.each { digest << _1.strip << "\n" }
    %w[ruby-worker.js ruby-engine.js asobi-ruby.js].each { digest << File.binread(File.join(@out, "assets", _1)) }
    assert_equal 3, block.lines.size
    assert_equal digest.hexdigest[0, 12], versions.first

    assert_includes read("assets/playground.js"), "ruby-worker.js\" + (v ? \"?v=\" + v"
    assert_includes read("assets/ruby-worker.js"), '"asobi-ruby.js" + q'
  end

  # The checker (site/assets/safe-reel.js) with every Reel the site built,
  # and with attacks (test/web/safe-reel-check.js).
  def test_safe_reel_lets_asobis_own_reels_through_and_nothing_else
    result = node_check("safe-reel-check.js", File.join(@out, "assets", "safe-reel.js"), File.join(@out, "reels"))

    reels = result["reels"]
    assert_operator reels["count"], :>, 0
    assert_equal [], reels["rejected"], "every Reel the site built passes"
    assert_equal [], reels["changed"], "with the same frames and parts"

    assert_operator result["attacks"], :>=, 27
    assert_equal [], result["attacksPassed"]
    assert_equal [], result["fineRejected"]
    result["reelRejects"].each { |name, ok| assert ok, "reel rejects: #{name}" }
    assert result["prototypeClean"]

    assert_equal({ "kept" => true, "song" => nil }, result["foreignSong"], "a song from elsewhere is dropped, the picture stays")
    assert_equal({ "id" => "3ff79180f05b", "src" => "assets/beat.wav", "volume" => 0.5 }, result["ownSong"])
    assert_equal({ "error" => "boom", "code" => "show x" }, result["errorReel"])
    assert_equal %w[background code controls error fps frames parts view], result["partsCopy"]["keys"]
    assert_equal({ "frames" => ["<g/>"], "turn" => "click", "fps" => 30, "sound" => "pop" }, result["partsCopy"]["p1"])
  end

  # The whole Reel in slices (what the worker does), in a plain Ruby.
  def test_browser_bundle_finishes_in_slices
    script = <<~RUBY
      eval(File.read(ARGV[0], encoding: "UTF-8"), TOPLEVEL_BINDING, "asobi.rb", 1)
      code = %(show circle(radius: 3).move(right: 9).spin.trail\\n)
      Asobi::Web.start(code, "en")
      slices = 0
      whole = nil
      while Asobi::Web.waiting?
        whole = Asobi::Web.finish_some("0")
        slices += 1
      end
      Asobi::Web.start(code, "en")
      half = Asobi::Web.finish_some("0")
      Asobi::Web.drop
      puts JSON.generate([slices > 1, whole == Asobi::Web.run(code, "en"), half, Asobi::Web.waiting?, Asobi::Web.finish_some("0")])
    RUBY
    out, err, status = Open3.capture3({ "ASOBI_LIVE" => nil }, RbConfig.ruby, "-e", script, File.join(@out, "assets", "asobi.rb"))
    assert status.success?, err
    assert_equal [true, true, nil, false, nil], JSON.parse(out)
  end

  def node
    found = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, "node") }.find { File.executable?(_1) }
    found || skip("node is not installed")
  end

  def node_check(script, *args)
    out, err, status = Open3.capture3(node, File.expand_path("web/#{script}", __dir__), *args)
    assert status.success?, err
    JSON.parse(out.force_encoding(Encoding::UTF_8))
  end

  # The worker with a pretend engine (test/web/worker-check.js).
  def test_worker_makes_the_whole_reel_in_slices_and_stops_for_a_newer_edit
    result = node_check("worker-check.js", File.join(@out, "assets", "ruby-worker.js"))

    whole = result["whole"]["out"].reject { _1["type"] }
    assert_equal({ "id" => 1, "json" => "preview:motion a", "pending" => true }, whole.first)
    assert_operator whole.count { _1["working"] }, :>, 5, "a small message between slices"
    assert_equal({ "id" => 1, "json" => "whole:motion a" }, whole[-2])
    assert_equal({ "id" => 2, "json" => "whole:still" }, whole[-1])
    assert(result["whole"]["log"].all? { _1 == "step 0.08" })

    newer = result["newer"]["out"].reject { _1["type"] || _1["working"] }
    assert_equal [[1, "pending"], [1, "skipped"], [2, "pending"], [2, "json"]],
                 newer.map { [_1["id"], _1["pending"] ? "pending" : (_1.keys - ["id"]).first] }
    assert_equal 1, result["newer"]["log"].count("drop")
    assert_operator result["newer"]["log"].index("drop"), :<, 5, "the old build stopped early"

    fatal = result["fatal"]["out"].last
    assert_equal 1, fatal["id"]
    assert_includes fatal["fatal"], "unreachable"

    assert_equal [["api.js", "asobi-ruby.js?v=0a1b", "ruby-engine.js?v=0a1b"]], result["versioned"]["imports"]
    assert_equal [[["api.js", "asobi-ruby.js", "ruby-engine.js"]]] * 3, result["notHex"].map { _1["imports"] }
  end

  # The page with a pretend worker (test/web/playground-check.js).
  def test_playground_recovers_after_ruby_crashes
    result = node_check("playground-check.js", File.join(@out, "assets", "playground.js"), File.join(@out, "playground.html"))
    crashed = result["crashed"]

    version = JSON.parse(read("playground.html")[%r{id="play-config">(.*?)</script>}m, 1]).fetch("workerVersion")
    assert_equal version, result["workerStart"]["v"], "the address and the hash carry the same version"
    assert_equal "assets/ruby-worker.js?v=#{version}", result["workerStart"]["path"]

    then_ = result["fatalThen"]
    assert_equal [true, false], then_["workers"].map { _1["terminated"] }, "the broken worker is replaced"
    assert_equal [], then_["workers"][1]["ran"], "the code that crashed is not run again by itself"
    assert_equal [crashed], then_["errors"]
    after = result["fatalAfter"]
    assert_equal ["fine b"], after["workers"][1]["ran"]
    assert_nil after["marker"]["error"]
    assert_equal 2, after["marker"]["frames"]

    error = result["error"]
    assert_equal [true, false], error["workers"].map { _1["terminated"] }
    assert_equal [crashed], error["errors"]
    assert_equal ["fine b"], error["workers"][1]["ran"]

    newest = result["newest"]
    assert_equal ["fine b"], newest["workers"][1]["ran"], "the newest waiting edit runs on the new worker"
    assert_equal "fine b", newest["last"]["code"]

    fails = result["bootFails"]
    assert_equal 2, fails["workers"].size, "no restart loop"
    assert_equal result["ruby_failed"], fails["status"]
    assert_equal 0, fails["scripts"], "no switch to the page engine"

    blocked = result["blocked"]
    attack = result["attack"]
    assert_equal [blocked, blocked], attack["errors"], "the preview and the whole Reel"
    assert(attack["shown"].none? { _1["frames"]&.any? { |f| f.include?("onerror") } }, "the frames never reach the player")
    assert_equal({ "error" => blocked, "code" => "attack a", "frames" => nil }, attack["shown"].last)
    refute attack["polluted"], "an id of __proto__ is ignored"
    assert_nil attack["after"]["error"], "the next sketch runs as usual"
    assert_equal 2, attack["after"]["frames"]

    assert_equal 0, result["noChecker"]["frames"], "without the checker nothing from the engine is shown"

    https = result["httpsNoWorker"]
    assert_equal result["ruby_failed"], https["status"]
    assert_equal 0, https["scripts"], "on https, never Ruby on the page"
    assert_equal 1, result["fileNoWorker"]["scripts"], "on file://, the page engine is the fallback"
  end

  # The player's reacting parts and sound analysis, without a browser (test/web/player-check.js).
  def test_player_numbers_copies_of_reacting_parts_and_hears_beats
    result = node_check("player-check.js", File.expand_path("../lib/asobi/web/player.js", __dir__))

    compose = result["compose"]
    assert_equal '<a/><g data-asobi-part="p1" data-asobi-n="0"><i0/></g><g data-asobi-part="p1" data-asobi-n="1"><i1/></g>' \
                 '<g data-asobi-part="p2" data-asobi-n="0"><o1><g data-asobi-part="p1" data-asobi-n="2"><i2/></g></o1></g>' \
                 "<!--asobi:p9--><b/>", compose["html"], "markers become numbered copies, nested ones too"
    assert_equal [["p1", 0, 0, -1], ["p1", 1, 1, -1], ["p2", 0, 1, -1], ["p1", 2, 2, 2]], compose["copies"]
    assert_equal "<i2/>", compose["inner"][3]
    refute_includes compose["outOfRange"], "<i1/>", "a frame out of range shows frame 0"
    assert compose["has"]["click"] && compose["has"]["mic"]
    assert_nil compose["noParts"], "a Reel without parts takes the plain path"
    assert compose["sameShape"]
    assert_equal 32, compose["cycle"], "a cycle stops at the depth limit"

    assert_equal [0, 0, 1, 1, 2, 4, 4, 4, 0], result["valueIndex"]
    assert_equal [0, 0, 1, 2, -1, -1], result["onceIndex"]

    beats = result["beats"]
    assert_equal 20, beats["kicks120"]
    assert_equal 20, beats["withHats"], "hats are not beats"
    assert_equal 0, beats["silence"]
    assert_equal 0, beats["noise"]
    assert_operator beats["fast"], :<=, 50, "never closer than 0.2 s"

    listener = result["listener"]
    %w[silence afterMusicLong room].each do |name|
      assert_equal({ "volume" => 0, "low" => 0, "mid" => 0, "high" => 0, "pitch" => 0 }, listener[name].except("beats"), name)
    end
    assert_equal 0, listener["room"]["beats"]
    assert_operator listener["afterMusic"]["pitch"], :>, 0.3, "pitch holds a moment after the sound stops"
    assert_operator listener["attack"], :<=, 2, "fast attack (frames)"
    assert_includes 8..40, listener["release"], "slower release (frames)"
    sweep = listener["sweep"]
    assert_operator sweep.first, :<, 0.1
    assert_operator sweep.last, :>, 0.85
    assert_equal sweep.sort, sweep, "pitch rises with the sweep"
    assert_equal 20, listener["kickBeats"]
    assert_equal 0, listener["quietKicks"]

    sound = result["sound"]
    assert_equal [{ "sound" => "pop" }, { "note" => 60 }, { "sound" => "bell" }, nil, nil, nil, nil], sound["partSound"],
                 "the six names and notes sound; value parts and unknown names are silent"
    assert_equal [true, false], sound["hasSound"]
    assert_equal [{ "id" => "3f9a0c2b7d1e", "src" => "/song/3f9a0c2b7d1e", "volume" => 0.5 },
                  { "id" => "3f9a0c2b7d1e", "src" => "data:audio/mpeg;base64,AAAA", "volume" => 1 },
                  { "id" => "a", "src" => "x.mp3", "volume" => 1 }, nil, nil], sound["songOf"]
  end

  # ---- the site's song (play "beat.wav") -----------------------------------------

  # A copy of the fixtures with one more word whose example is +code+, built
  # into a scratch folder; yields the output folder.
  def build_with(code)
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      FileUtils.cp_r(FIXTURES, data)
      entry = "\n- word: tune\n  group: react\n  signature: \"tune\"\n  summary: { en: \"A tune.\", ja: \"曲。\" }\n" \
              "  examples:\n    - code: |\n" + code.lines.map { "        #{_1}" }.join
      edit(File.join(data, "words.yml")) { _1 + entry }
      out = File.join(dir, "out")
      AsobiSite::Builder.new(data:, out:, log: nil).build
      yield out
    end
  end

  def reel_in(out, code)
    js = File.read(File.join(out, "reels", "#{AsobiSite.code_key(code)}.js"), encoding: "UTF-8")
    JSON.parse(js[/\AasobiReel\("r\h{8}", (.*)\);\n\z/m, 1])
  end

  # The site ships beat.wav, and an example that plays it plays the site's own
  # copy: a URL from the site's root, never "/song/ID" (only the live view has
  # that) and never a data URI (every page would carry the whole file).
  def test_an_example_plays_the_song_the_site_ships
    song = File.expand_path("../examples/reactions/beat.wav", __dir__)
    code = "play \"beat.wav\", volume: 0.5\nshow circle(9).colored(:teal).pulse.when_clicked.sounding(:pop)\n"
    build_with(code) do |out|
      assert_equal File.binread(song), File.binread(File.join(out, "assets", "beat.wav"))
      reel = reel_in(out, code)
      assert_equal({ "id" => Digest::SHA256.file(song).hexdigest[0, 12], "src" => "assets/beat.wav", "volume" => 0.5 }, reel["song"])
      assert_equal 1, reel["frames"].size, "it rests until clicked"

      # a picture that reacts gets a player on the page, though it has one frame
      %w[reference.html ja/reference.html].each do |page|
        html = File.read(File.join(out, page), encoding: "UTF-8")
        shot = html[/<div class="pic"[^>]*data-reel="#{AsobiSite.code_key(code)}"[^>]*>.*?<p class="readout"[^>]*>.*?<\/p>/m]
        assert shot, "#{page}: the reacting picture must be live"
        assert_includes shot, page.start_with?("ja") ? "反応する" : "reacts"
      end
      # the playground offers the same file, with the same id
      bundle = File.read(File.join(out, "assets", "asobi.rb"), encoding: "UTF-8")
      assert_includes bundle, %("beat.wav" => Song.new(path: "beat.wav", id: "#{Digest::SHA256.file(song).hexdigest[0, 12]}", src: "assets/beat.wav"))
      # and the pages put their own root in front of it (/ and /ja/)
      assert_match(%r{/\^assets\\//.*root \+ s\.src}m, File.read(File.join(out, "assets", "site.js"), encoding: "UTF-8"))
      assert_match(/cfg\.assets \+ s\.src\.slice\(7\)/, File.read(File.join(out, "assets", "playground.js"), encoding: "UTF-8"))
    end
  end

  def test_an_example_with_any_other_song_fails_the_build
    other = File.join(Dir.mktmpdir, "other.wav")
    File.binwrite(other, "RIFF not the site's song".b)
    message = build_error do |data|
      edit(File.join(data, "words.yml")) { _1.sub("show ring.colored(:teal)", "play #{other.dump}\n        show ring.colored(:teal)") }
    end
    assert_includes message, "words.yml, ring, example 1: the site has only one song"
  ensure
    FileUtils.rm_rf(File.dirname(other))
  end

  # A heavy motion is drawn again at a lower fps, with everything show and
  # play asked for (controls: false, the song), not only the picture.
  def test_lighter_keeps_what_show_and_play_asked_for
    builder = AsobiSite::Builder.new(data: FIXTURES, out: Dir.mktmpdir, log: nil)
    code = "play \"beat.wav\"\nshow star.spin(every: 1), on: :black, paper: [100, 80], grain: 0.2, controls: false\n"
    whole = Dir.mktmpdir do |dir|
      FileUtils.cp(File.expand_path("../examples/reactions/beat.wav", __dir__), dir)
      Dir.chdir(dir) { Asobi::Sketch.run(code, name: "heavy.rb") }
    end
    assert_nil whole["error"]
    heavy = whole.merge("frames" => ["x" * AsobiSite::REEL_BUDGET] + whole["frames"].drop(1))
    snippet = AsobiSite::Snippet.new(code:, file: "words.yml", entry: "heavy, example 1", label: "heavy")
    light = builder.send(:lighter, heavy, code, snippet)
    assert_operator light["frames"].size, :<, whole["frames"].size, "fewer frames"
    assert_equal whole.slice("view", "background", "controls", "song", "code"), light.slice("view", "background", "controls", "song", "code")
    assert_equal false, light["controls"]
    assert light["song"], "the song stays"
    assert_includes light["frames"].first, "feTurbulence", "the grain stays"
    assert_equal "assets/beat.wav", builder.send(:site_song, light, snippet)["song"]["src"]
  ensure
    Asobi::Sketch.forget
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

  # ---- SEO, AIO, and structured data ------------------------------------------

  def test_seo_metadata_hreflang_and_json_ld_on_every_page
    %w[en ja].each do |lang|
      directory = lang == "en" ? "" : "ja/"
      titles = PAGES.map do |page|
        html = read("#{directory}#{page}.html")
        title = html[%r{<title>([^<]+)</title>}, 1]
        desc = html[%r{<meta name="description" content="([^"]+)">}, 1]
        assert title && !title.empty?, "#{directory}#{page}.html: missing title"
        assert desc && !desc.empty?, "#{directory}#{page}.html: missing description"
        url = "https://asobi.myura.me/#{page unless page == "index"}"
        assert_includes html, %(<link rel="alternate" hreflang="x-default" href="#{url}">)
        assert_includes html, %(<meta property="og:title" content=")
        assert_includes html, %(<meta property="og:description" content=")
        assert_includes html, %(<meta name="twitter:card" content="summary_large_image">)
        assert_includes html, %(<link rel="alternate" type="text/markdown" title="llms.txt")

        ld = html[%r{<script type="application/ld\+json">(.*?)</script>}m, 1]
        assert ld, "#{directory}#{page}.html: missing JSON-LD"
        graph = JSON.parse(ld).fetch("@graph")
        types = graph.flat_map { Array(_1["@type"]) }
        assert_includes types, "WebSite"
        if page == "index"
          assert_includes types, "SoftwareApplication"
          assert_includes types, "SoftwareSourceCode"
          refute_includes types, "VideoObject" # the fixture has no films; with films: see the home page test
          software = graph.find { Array(_1["@type"]).include?("SoftwareApplication") }
          assert_equal %w[https://github.com/Hayato1031/asobi https://rubygems.org/gems/asobi], software["sameAs"]
          assert_equal %w[myura みゅーら], software.dig("author", "alternateName")
          assert_includes software["keywords"], "generative art"
          assert_includes software["keywords"], "zero dependencies"
          requirement = Gem::Specification.load(File.expand_path("../asobi.gemspec", __dir__)).required_ruby_version
          assert_equal "Ruby #{requirement}", software["softwareRequirements"]
          # the JSON-LD says "Ruby >= 3.2": the same words as the gemspec's requirement
        else
          assert_includes types, "BreadcrumbList"
          author = graph.filter_map { _1["author"] }.first
          next title unless author

          assert_equal "Hayato1031", author["name"], "#{directory}#{page}"
          assert_equal "https://github.com/Hayato1031", author["url"]
          assert_equal %w[myura みゅーら], author["alternateName"]
          assert_equal %w[https://github.com/Hayato1031 https://x.com/lit_myura https://rubygems.org/profiles/Myura], author["sameAs"]
        end
        title
      end
      assert_equal PAGES.size, titles.uniq.size, "#{lang}: duplicate page titles"
    end
  end

  def test_sitemap_alternates_llms_files_and_doc_navigation
    sitemap = read("sitemap.xml")
    assert_includes sitemap, 'xmlns:xhtml="http://www.w3.org/1999/xhtml"'
    assert_includes sitemap, '<xhtml:link rel="alternate" hreflang="x-default" href="https://asobi.myura.me/"/>'

    robots = read("robots.txt")
    assert_includes robots, "llms.txt"

    llms = read("llms.txt")
    assert_includes llms, "# asobi"
    assert_includes llms, "Object to Art. Art to Object."
    assert_includes llms, "## Vocabulary Index"
    assert_includes llms, "`circle`"
    assert_includes llms, "`ring`"

    llms_full = read("llms-full.txt")
    assert_includes llms_full, "## Getting Started Guide"
    assert_includes llms_full, "## Complete Reference"
    assert_includes llms_full, "## Examples Gallery"

    ref = read("reference.html")
    assert_includes ref, 'class="group-jump"'
    assert_includes ref, 'class="group-lead"'
    assert_includes read("guide.html"), 'class="doc-next"'
  end

  def test_agent_readiness_manifests_markdown_mirrors_and_webmcp
    robots = read("robots.txt")
    assert_includes robots, "Content-Signal: ai-train=yes, search=yes, ai-input=yes"

    PAGES.each do |page|
      %w[en ja].each do |lang|
        dir = lang == "en" ? "" : "ja/"
        html = read("#{dir}#{page}.html")
        assert_includes html, %(<link rel="alternate" type="text/markdown" href="#{page}.md">)
        assert_includes html, 'rel="api-catalog"'
        assert_includes html, 'rel="agent-skills"'
        assert_includes html, 'rel="service-doc"'

        md = read("#{dir}#{page}.md")
        assert md.lines.size > 3, "#{dir}#{page}.md should not be empty"
      end
    end

    skill_md = read(".well-known/agent-skills/asobi/SKILL.md")
    assert_includes skill_md, "name: asobi"
    assert_includes skill_md, "gem install asobi"

    skills_index = JSON.parse(read(".well-known/agent-skills/index.json"))
    assert_equal "https://schemas.agentskills.io/discovery/0.2.0/schema.json", skills_index["$schema"]
    skill_entry = skills_index.fetch("skills").first
    assert_equal "asobi", skill_entry["name"]
    assert_equal "skill-md", skill_entry["type"]
    assert_equal "sha256:#{Digest::SHA256.hexdigest(skill_md)}", skill_entry["digest"]

    ard = JSON.parse(read(".well-known/ai-catalog.json"))
    assert_equal "1.0", ard["specVersion"]
    assert(ard.fetch("entries").all? { _1["identifier"].start_with?("urn:air:asobi.myura.me:") && !_1["representativeQueries"].empty? })

    api_catalog = JSON.parse(read(".well-known/api-catalog"))
    assert_equal "https://asobi.myura.me/", api_catalog.fetch("linkset").first["anchor"]

    poppy = JSON.parse(read(".well-known/poppy.json"))
    assert_equal "0.1", poppy["protocol_version"]
    assert_equal "asobi.myura.me", poppy.dig("organization", "domain")

    headers = read("_headers")
    assert_includes headers, "Link:"
    assert_includes headers, "application/linkset+json"

    site_js = read("assets/site.js")
    assert_includes site_js, "registerTool"
    assert_includes site_js, "asobi_lookup_word"

    play_js = read("assets/playground.js")
    assert_includes play_js, "asobi_run_code"
  end

  def test_optional_home_cycle_comparison_and_faq_sections
    Dir.mktmpdir do |dir|
      data = File.join(dir, "data")
      out = File.join(dir, "out")
      FileUtils.cp_r(FIXTURES, data)
      extra = <<~YAML

        lead:
          en: "Objects become art."
          ja: "オブジェクトが絵になる。"
        cycle:
          sides:
            - label: "01 / Object -> Art"
              title: { en: "Object -> Art", ja: "Object -> Art" }
              text: { en: "Array to circles.", ja: "配列を円にする。" }
              code: "show [10, 16].to_art"
          conversions:
            - kind: { en: "Numbers", ja: "数値" }
              result: { en: "Turns into a circle.", ja: "円になる。" }
              code: "show 20.to_art"
        comparison:
          rows:
            - aspect: { en: "Model", ja: "モデル" }
              asobi: { en: "Immutable `Asobi::Art`", ja: "不変の `Asobi::Art`" }
              canvas: { en: "Mutable canvas", ja: "可変キャンバス" }
        faq:
          - q: { en: "What is Object to Art?", ja: "Object to Art とは？" }
            a: { en: "Turning values into art.", ja: "値を絵に変えること。" }
        films:
          - id: play
            title: Play
            version: "0.2"
            seconds: 60
            size: [1280, 720]
            date: "2026-11-23"
            description: { en: "A song moves the pictures.", ja: "曲が絵を動かす。" }
          - id: your-objects
            title: Your Objects
            version: "0.1"
            seconds: 32
            size: [1920, 1080]
            date: "2026-11-11"
            first: true
            description: { en: "Numbers become circles.", ja: "数字が円になる。" }
        press:
          - name: "Example Weekly #1"
            url: "https://example.com/weekly/1"
            date: { en: "Nov 19, 2026", ja: "2026年11月19日" }
            quote: "A bit like a sketchbook."
            translation: { ja: "スケッチブックみたい。" }
          - name: "Older Blog"
            url: "https://example.com/blog/older"
            date: { en: "Nov 12, 2026", ja: "2026年11月12日" }
      YAML
      edit(File.join(data, "home.yml")) { _1 + extra }
      AsobiSite::Builder.new(data:, out:, log: nil).build

      %w[index.html ja/index.html].each do |file|
        html = read(file)
        refute_includes html, 'id="object-to-art"' # fixture base omits optional sections
        rendered = File.read(File.join(out, file), encoding: "UTF-8")
        assert_includes rendered, 'id="object-to-art"'
        assert_includes rendered, 'id="compare"'
        assert_includes rendered, 'id="faq"'
        assert_includes rendered, 'class="compare-table"'
        # The films: the one marked first stands alone; under it, one tab per version, the newest in view.
        assert_match(%r{<section class="band film" id="film".*?<h2 id="film-title" lang="en">Your Objects</h2>.*?assets/your-objects\.mp4.*?</section>\s*<section class="band films" id="films"}m, rendered)
        assert_match(/role="tablist".*?id="film-tab-play"[^>]*aria-selected="true".*?id="film-tab-your-objects"[^>]*aria-selected="false"/m, rendered,
                     "#{file}: Play is in view, Your Objects is a tab away")
        refute_includes rendered, "film-new"
        assert_match(%r{id="film-play" role="tabpanel".*?assets/play\.mp4.*?id="film-your-objects" role="tabpanel".*?assets/your-objects\.mp4}m, rendered)
        assert_includes rendered, file.start_with?("ja") ? "紹介映像 · 60秒 · 音楽あり" : "Short film · 60 seconds · Music"
        assert_includes rendered, 'href="#film"'
        # Where asobi was featured: the quote in its own language, right under the film.
        assert_match(%r{id="films".*?</section>\s*<section class="band press-band" id="press".*?id="beliefs-title"}m, rendered, "#{file}: press sits between the films and the beliefs")
        assert_includes rendered, %(<blockquote cite="https://example.com/weekly/1" lang="en"><p>A bit like a sketchbook.</p></blockquote>)
        assert_includes rendered, %(<a href="https://example.com/weekly/1">Example Weekly #1)
        if file.start_with?("ja/")
          assert_includes rendered, %(<p class="press-translation">スケッチブックみたい。</p>)
          assert_includes rendered, "2026年11月19日"
        else
          refute_includes rendered, "press-translation", "no translation on the page in the quote's own language"
          assert_includes rendered, "Nov 19, 2026"
        end
        refute_match(%r{<div class="stage-copy">(?:(?!</div>).)*press}m, rendered, "#{file}: not on the stage")
        # Only the first one is a large quote; the rest is a list under it.
        assert_equal 1, rendered.scan("<blockquote").size
        older_date = file.start_with?("ja/") ? "2026年11月12日" : "Nov 12, 2026"
        assert_match(%r{<div class="press-more">.*?<li><span class="press-date">#{older_date}</span><a href="https://example\.com/blog/older">Older Blog}m, rendered)
        ld =rendered[%r{<script type="application/ld\+json">(.*?)</script>}m, 1]
        faq_schema = JSON.parse(ld).fetch("@graph").find { _1["@type"] == "FAQPage" }
        videos = JSON.parse(ld).fetch("@graph").select { _1["@type"] == "VideoObject" }
        assert_equal ["Play — asobi", "Your Objects — asobi"], videos.map { _1["name"] }, "#{file}: both films in the structured data"
        assert_equal "PT60S", videos.first["duration"]
        assert faq_schema, "#{file}: missing FAQPage JSON-LD"
        q_text = file.start_with?("ja/") ? "Object to Art とは？" : "What is Object to Art?"
        assert_equal [q_text], faq_schema.fetch("mainEntity").map { _1["name"] }
      end
      assert_includes File.read(File.join(out, "llms-full.txt"), encoding: "UTF-8"), "## Frequently Asked Questions"

      quote_line = %(    quote: "A bit like a sketchbook."\n)
      edit(File.join(data, "home.yml")) { _1.sub(quote_line, "") }
      error = assert_raises(AsobiSite::BuildError) { AsobiSite::Builder.new(data:, out:, log: nil).build }
      assert_includes error.message, "home.yml, press 1: the first entry is shown large as a quote"

      # A film needs its two files in site/assets.
      edit(File.join(data, "home.yml")) { _1.sub("  - id: play\n", "  - id: no-such-film\n") }
      error = assert_raises(AsobiSite::BuildError) { AsobiSite::Builder.new(data:, out:, log: nil).build }
      assert_includes error.message, "home.yml, films 1: site/assets/no-such-film.mp4 is missing"
      edit(File.join(data, "home.yml")) { _1.sub("  - id: no-such-film\n", "  - id: play\n") }

      edit(File.join(data, "home.yml")) do
        _1.sub(%(    date: { en: "Nov 19, 2026", ja: "2026年11月19日" }\n), "\\0#{quote_line}")
          .sub("show [10, 16].to_art", "show [10, 16].to_arttt")
      end
      error = assert_raises(AsobiSite::BuildError) { AsobiSite::Builder.new(data:, out:, log: nil).build }
      assert_includes error.message, "home.yml, cycle, side 1"
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

  # ---- _headers --------------------------------------------------------------

  # Cloudflare Pages applies every rule whose pattern matches a path and joins
  # equal header names with ", " (a "*" matches slashes too). Emulate that.
  def header_blocks
    blocks = []
    read("_headers").each_line do |line|
      if line =~ /\A\S/
        blocks << [line.strip, []]
      elsif line =~ /\A\s+([^:\s]+):\s*(.*?)\s*\z/
        blocks.last[1] << [$1, $2.strip]
      end
    end
    blocks
  end

  def header_pattern_regexp(pattern)
    /\A#{pattern.split("*", -1).map { Regexp.escape(_1) }.join(".*")}\z/m
  end

  def matching_header_blocks(path)
    header_blocks.select { |pattern, _| header_pattern_regexp(pattern).match?(path) }
  end

  def test_no_file_gets_the_same_header_from_two_rules
    root = File.join(@out, "")
    paths = Dir.glob(File.join(@out, "**", "*"), File::FNM_DOTMATCH).select { File.file?(_1) }.flat_map do |f|
      url = "/#{f.delete_prefix(root)}"
      [url, (url.delete_suffix(".html") if url.end_with?(".html"))].compact
    end
    paths = (paths + ["/", "/ja/"]).uniq
    refute_empty paths
    paths.each do |path|
      names = matching_header_blocks(path).flat_map { |_, hs| hs.map { |name, _| name.downcase } }
      dupes = names.tally.select { _2 > 1 }.keys
      assert_empty dupes, "#{path} gets #{dupes.join(", ")} from more than one _headers rule"
    end
  end

  def test_markdown_files_get_one_content_type_and_one_cors_header
    files = Dir.glob(File.join(@out, "**", "*.md"), File::FNM_DOTMATCH).map { "/#{_1.delete_prefix(File.join(@out, ""))}" }
    assert_includes files, "/ja/index.md"
    assert_includes files, "/.well-known/agent-skills/asobi/SKILL.md"
    assert_equal AsobiSite.markdown_paths.sort, files.sort
    files.each do |path|
      headers = matching_header_blocks(path).flat_map { |_, hs| hs }
      assert_equal ["text/markdown; charset=utf-8"], headers.select { |n, _| n.casecmp?("content-type") }.map { |_, v| v }, path
      assert_equal ["*"], headers.select { |n, _| n.casecmp?("access-control-allow-origin") }.map { |_, v| v }, path
    end
  end

  def test_missing_markdown_urls_are_not_labelled_as_markdown
    ["/auth.md", "/nope.md", "/ja/nope.md", "/.well-known/nope.md"].each do |path|
      names = matching_header_blocks(path).flat_map { |_, hs| hs.map { |n, _| n.downcase } }
      refute_includes names, "content-type", path
    end
  end

  # ---- _routes.json and the Markdown middleware ---------------------------------

  def test_routes_json_lists_exactly_the_page_urls
    routes = JSON.parse(read("_routes.json"))
    assert_equal 1, routes["version"]
    assert_equal [], routes["exclude"]
    expected = %w[/ /guide /reference /examples /playground /ja/ /ja/guide /ja/reference /ja/examples /ja/playground]
    assert_equal expected.sort, routes["include"].sort
    routes["include"].each do |path|
      html = path.end_with?("/") ? "#{path}index.html" : "#{path}.html"
      assert File.file?(File.join(@out, html)), html
      assert File.file?(File.join(@out, AsobiSite.markdown_path(*page_and_lang(path)))), path
    end
  end

  def page_and_lang(path)
    lang = path.start_with?("/ja/") ? :ja : :en
    name = File.basename(path)
    [path.end_with?("/") ? "index" : name, lang]
  end

  def test_the_middleware_answers_markdown_requests_with_the_markdown_twin
    node = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { File.join(_1, "node") }.find { File.executable?(_1) }
    skip "node is not installed" unless node

    middleware = "file://#{File.expand_path("../functions/_middleware.js", __dir__)}"
    script = <<~JS
      const m = await import(process.argv[1]);
      const fs = await import("node:fs");
      const out = process.argv[2];
      const files = (path) => {
        const rel = path === "/" ? "/index.html" : path;
        const file = out + rel;
        return fs.existsSync(file) && fs.statSync(file).isFile() ? fs.readFileSync(file) : null;
      };
      const context = (method, path, accept) => ({
        request: new Request("https://asobi.myura.me" + path, { method, headers: accept ? { Accept: accept } : {} }),
        env: { ASSETS: { fetch: async (req) => {
          const body = files(new URL(req.url).pathname);
          return body ? new Response(body, { status: 200, headers: { "Content-Type": "application/octet-stream" } }) : new Response("nope", { status: 404 });
        } } },
        next: async () => new Response("<html></html>", { status: 200, headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": "default-src 'self'" } })
      });
      const chrome = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8";
      const summary = async (res) => ({ status: res.status, type: res.headers.get("content-type"), vary: res.headers.get("vary"), csp: res.headers.get("content-security-policy"), location: res.headers.get("content-location"), body: await res.text() });
      console.log(JSON.stringify({
        paths: ["/", "/ja/", "/guide", "/ja/playground", "/assets/site.js", "/nope", "/guide.md"].map((p) => m.markdownPath(p)),
        routes: JSON.parse(fs.readFileSync(out + "/_routes.json", "utf8")).include.map((p) => m.markdownPath(p)),
        accepts: [chrome, "text/markdown", "text/markdown, text/html, */*", "text/html, text/markdown;q=0.5", "text/markdown;q=0", " Text/Markdown ; charset=utf-8 ", null].map((a) => m.prefersMarkdown(a)),
        markdown: await summary(await m.onRequest(context("GET", "/reference", "text/markdown"))),
        browser: await summary(await m.onRequest(context("GET", "/reference", chrome))),
        post: await summary(await m.onRequest(context("POST", "/reference", "text/markdown")))
      }));
    JS
    out, err, status = Open3.capture3(node, "--input-type=module", "-e", script, middleware, @out)
    assert status.success?, err
    result = JSON.parse(out.force_encoding(Encoding::UTF_8))

    assert_equal ["/index.md", "/ja/index.md", "/guide.md", "/ja/playground.md", nil, nil, nil], result["paths"]
    # The middleware keeps its own list of pages: it must know every page the
    # build routes to it, or a new page would quietly answer HTML only.
    routes = JSON.parse(read("_routes.json"))["include"]
    assert_equal routes.map { AsobiSite.markdown_path(*page_and_lang(_1)) }, result["routes"]
    assert_equal [false, true, true, false, false, true, false], result["accepts"]

    markdown = result["markdown"]
    assert_equal 200, markdown["status"]
    assert_equal "text/markdown; charset=utf-8", markdown["type"]
    assert_equal read("reference.md"), markdown["body"]
    assert_equal "/reference.md", markdown["location"]
    assert_match(/accept/i, markdown["vary"])

    browser = result["browser"]
    assert_equal "text/html; charset=utf-8", browser["type"]
    assert_equal "default-src 'self'", browser["csp"]
    assert_equal "<html></html>", browser["body"]
    assert_equal "Accept", browser["vary"]

    post = result["post"]
    assert_equal "<html></html>", post["body"]
    assert_nil post["vary"]
  end

  # ---- word counts and links -------------------------------------------------

  def test_ai_catalog_counts_the_real_vocabulary
    size = YAML.safe_load_file(File.join(FIXTURES, "words.yml")).size
    assert_equal size, read("llms.txt")[/Vocabulary Index \((\d+) words/, 1].to_i
    assert_operator size, :>, 0
    descriptions = JSON.parse(read(".well-known/ai-catalog.json")).fetch("entries").map { _1["description"] }
    counted = descriptions.grep(/-word /)
    refute_empty counted
    counted.each { assert_includes _1, "#{size}-word" }
  end

  def test_readmes_have_the_why_section_and_the_sites_faq
    readme_dir = File.expand_path("..", __dir__)
    faq = YAML.safe_load_file(File.join(AsobiSite::SITE, "data", "home.yml")).fetch("faq")
    lines = <<~RUBY.lines.map(&:chomp)
      require "asobi"
      tiles = square(18).repeat(36).change_each { |s, t| s.rotate(t * 90).grow(to: 1 - t * 0.5) }
      show tiles.in_grid(6, gap: 4).colored(:tomato, :navy)
    RUBY
    { "README.md" => ["## Why asobi", "## FAQ", "en", ""], "README.ja.md" => ["## asobi を選ぶ理由", "## よくある質問", "ja", "ja/"] }.each do |name, (why, faq_heading, lang, folder)|
      text = File.read(File.join(readme_dir, name), encoding: "UTF-8")
      assert_includes text, "#{why}\n", name
      assert_includes text, "#{faq_heading}\n", name
      assert_includes text, "```ruby\n#{lines.join("\n")}\n```", name
      assert_includes text, "https://asobi.myura.me/#{folder}playground#code=#{AsobiSite.encode_code(lines.join("\n") + "\n")}", name
      faq.each do |item|
        assert_includes text, "**Q: #{item["q"][lang]}**\n\n#{item["a"][lang]}\n", "#{name}: FAQ differs from the site's"
      end
    end
  end

  def test_readmes_link_to_the_site_without_html
    %w[README.md README.ja.md].each do |name|
      text = File.read(File.expand_path("../#{name}", __dir__), encoding: "UTF-8")
      assert_empty text.scan(%r{asobi\.myura\.me/[^\s)"'>]*\.html}), name
    end
  end
end
