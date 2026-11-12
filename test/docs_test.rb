# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "json"
require "tmpdir"
require "fileutils"

# The documentation must not rot: every code example in the data files, in
# the examples/ folder and in the two READMEs is run for real.
module DocsHelper
  ROOT = File.expand_path("..", __dir__)
  DATA = File.join(ROOT, "site", "data")
  GROUPS = %w[shapes combine change color effect arrange to_art motion show].freeze

  module_function

  def data(name) = YAML.safe_load_file(File.join(DATA, "#{name}.yml"), permitted_classes: [], aliases: false)

  def read(path) = File.read(path, encoding: "UTF-8")

  # Runs a sketch the way the live view does and answers its Reel (a Hash).
  # The sketch runs in a scratch folder, so a save inside it leaves no mess.
  def run(code)
    Dir.mktmpdir("asobi-docs") do |dir|
      path = File.join(dir, "sketch.rb")
      File.write(path, %(require "asobi"\n#{code}), encoding: "UTF-8")
      Dir.chdir(dir) { Asobi::Sketch.evaluate(path) }
    end
  end

  def ruby_blocks(markdown) = markdown.scan(/^```ruby\n(.*?)^```/m).flatten
end

module DocsAssertions
  def assert_texts(value, where)
    assert_kind_of Hash, value, "#{where} must be a map with en and ja"
    assert_equal %w[en ja], value.keys.sort, "#{where} must have exactly en and ja"
    %w[en ja].each do |lang|
      assert_kind_of String, value[lang], "#{where}.#{lang} must be a string"
      refute_empty value[lang].strip, "#{where}.#{lang} must not be empty"
    end
  end

  def assert_code(code, where)
    assert_kind_of String, code, "#{where} must be code"
    refute_empty code.strip, "#{where} must not be empty"
    refute_match(/^\s*require ["']asobi["']/, code, "#{where}: leave out the require line")
    assert_match(/\bshow\b/, code.lines.reject { _1.strip.start_with?("#") }.join, "#{where} must call show")
  end

  # The site slims any reel bigger than this (and says so while building), so
  # a documented example must fit without that.
  MAX_REEL_BYTES = 1_500_000

  def assert_runs(code, where)
    reel = DocsHelper.run(code)
    assert_nil reel["error"], "#{where} failed:\n#{reel["error"]}\n--- code ---\n#{code}"
    assert_operator reel["frames"].size, :>=, 1, "#{where} made no frames"
    bytes = JSON.generate(reel).bytesize
    assert_operator bytes, :<=, MAX_REEL_BYTES,
                    "#{where} makes a #{bytes} byte reel (#{reel["frames"].size} frames); shorten `every` or use fewer shapes\n#{code}"
  end
end

class DocsTest < Minitest::Test
  include DocsAssertions

  WORDS = DocsHelper.data("words")
  GUIDE = DocsHelper.data("guide")
  EXAMPLES = DocsHelper.data("examples")
  HOME = DocsHelper.data("home")

  # ---------------------------------------------------------------- schema

  def test_words_schema
    assert_kind_of Array, WORDS
    refute_empty WORDS
    names = WORDS.map { _1["word"] }
    assert_equal names.uniq, names, "words must be unique: #{names.tally.select { |_, n| n > 1 }.keys}"

    WORDS.each do |entry|
      where = "words.yml #{entry["word"].inspect}"
      assert_kind_of String, entry["word"], "#{where}: word must be a string (quote on, y, n ...)"
      assert_includes DocsHelper::GROUPS, entry["group"], "#{where}: bad group"
      assert_kind_of String, entry["signature"], "#{where}: signature"
      refute_empty entry["signature"].strip, "#{where}: signature"
      assert_texts entry["summary"], "#{where} summary"
      assert_texts entry["details"], "#{where} details" if entry.key?("details")
      refute_empty Array(entry["examples"]), "#{where} needs at least one example"
      entry["examples"].each_with_index do |ex, i|
        assert_code ex["code"], "#{where} example #{i + 1}"
        assert_texts ex["caption"], "#{where} example #{i + 1} caption" if ex.key?("caption")
      end
      Array(entry["see"]).each do |other|
        assert_includes names, other, "#{where}: see #{other.inspect} is not a word in words.yml"
        refute_equal entry["word"], other, "#{where}: see points to itself"
      end
      assert_equal %w[word group signature summary details examples see].select { entry.key?(_1) }.sort,
                   entry.keys.sort, "#{where}: unknown keys"
    end
  end

  def test_every_group_has_words
    assert_equal DocsHelper::GROUPS.sort, WORDS.map { _1["group"] }.uniq.sort
  end

  def test_the_words_of_the_library_are_all_documented
    documented = WORDS.map { _1["word"] }
    # Words a sketch author uses, as named in DESIGN.md sections 4 to 9.
    expected = %w[circle ellipse rect square triangle polygon star line text path arc wave ring heart petal
                  moon drop cloud space nothing hsl gray
                  on under + repeat * beside above
                  move rotate scale grow shrink mirror flip
                  colored outlined stroke opacity
                  in_row in_column in_grid in_ring in_fan in_spiral scattered change_each
                  to_art
                  spin pulse sway orbit fade bounce drift shift_color one_by_one animate at
                  show save turn]
    assert_empty expected - documented, "words with no entry in words.yml"
  end

  def test_guide_schema
    assert_kind_of Array, GUIDE
    assert_operator GUIDE.size, :>=, 8
    assert_operator GUIDE.size, :<=, 12
    ids = GUIDE.map { _1["id"] }
    assert_equal ids.uniq, ids, "guide ids must be unique"
    names = WORDS.map { _1["word"] }

    GUIDE.each do |chapter|
      where = "guide.yml #{chapter["id"].inspect}"
      assert_match(/\A[a-z][a-z_]*\z/, chapter["id"], "#{where}: id")
      assert_texts chapter["title"], "#{where} title"
      refute_empty Array(chapter["steps"]), "#{where} needs steps"
      chapter["steps"].each_with_index do |step, i|
        assert_texts step["text"], "#{where} step #{i + 1} text"
        assert_code step["code"], "#{where} step #{i + 1} code" if step.key?("code")
        Array(step["words"]).each do |word|
          assert_includes names, word, "#{where} step #{i + 1}: words has #{word.inspect}, which is not in words.yml"
        end
      end
    end
  end

  def test_examples_schema
    assert_kind_of Array, EXAMPLES
    assert_operator EXAMPLES.size, :>=, 8
    assert_operator EXAMPLES.size, :<=, 16
    ids = EXAMPLES.map { _1["id"] }
    assert_equal ids.uniq, ids, "example ids must be unique"

    EXAMPLES.each do |ex|
      where = "examples.yml #{ex["id"].inspect}"
      assert_match(/\A[a-z][a-z_]*\z/, ex["id"], "#{where}: id")
      assert_texts ex["title"], "#{where} title"
      assert_texts ex["text"], "#{where} text" if ex.key?("text")
      assert_code ex["code"], where
    end
  end

  def test_home_schema
    assert_texts HOME["tagline"], "home.yml tagline"
    assert_operator HOME["philosophy"].size, :>=, 2
    assert_operator HOME["philosophy"].size, :<=, 4
    HOME["philosophy"].each_with_index { |line, i| assert_texts line, "home.yml philosophy #{i + 1}" }
    assert_code HOME["hero_code"], "home.yml hero_code"
    assert_operator HOME["hero_code"].lines.count { !_1.strip.empty? }, :<=, 6, "hero_code is at most 6 lines"
    assert_texts HOME["install"], "home.yml install"
  end

  # ------------------------------------------------------------- the code

  WORDS.each do |entry|
    entry["examples"].each_with_index do |ex, i|
      define_method("test_runs_word_#{entry["word"]}_#{i + 1}") do
        assert_runs ex["code"], "words.yml #{entry["word"].inspect} example #{i + 1}"
      end
    end
  end

  GUIDE.each do |chapter|
    chapter["steps"].each_with_index do |step, i|
      next unless step["code"]

      define_method("test_runs_guide_#{chapter["id"]}_#{i + 1}") do
        assert_runs step["code"], "guide.yml #{chapter["id"].inspect} step #{i + 1}"
      end
    end
  end

  EXAMPLES.each do |ex|
    define_method("test_runs_gallery_#{ex["id"]}") { assert_runs ex["code"], "examples.yml #{ex["id"].inspect}" }
  end

  def test_gallery_stays_short
    EXAMPLES.each do |ex|
      lines = ex["code"].lines.count { !_1.strip.empty? }
      assert_operator lines, :<=, 14, "examples.yml #{ex["id"].inspect} is #{lines} lines"
    end
  end

  def test_runs_home_hero_code
    assert_runs HOME["hero_code"], "home.yml hero_code"
  end

  # ------------------------------------------------------------ examples/

  def test_example_files_match_the_gallery
    files = Dir[File.join(DocsHelper::ROOT, "examples", "*.rb")].map { File.basename(_1, ".rb") }.sort
    assert_equal EXAMPLES.map { _1["id"] }.sort, files, "examples/*.rb and examples.yml must list the same pieces"
  end

  Dir[File.join(DocsHelper::ROOT, "examples", "*.rb")].sort.each do |path|
    id = File.basename(path, ".rb")
    define_method("test_runs_example_file_#{id}") do
      source = DocsHelper.read(path)
      assert_match(/^require "asobi"$/, source, "#{id}.rb must start with require \"asobi\"")
      assert_match(/^#/, source, "#{id}.rb needs a comment line")
      gallery = EXAMPLES.find { _1["id"] == id }
      refute_nil gallery, "examples/#{id}.rb is not in examples.yml"
      assert_includes source, gallery["code"], "examples/#{id}.rb differs from its code in examples.yml"
      assert_runs source.sub(/^require "asobi"\n/, ""), "examples/#{id}.rb"
    end
  end

  # -------------------------------------------------------------- READMEs

  README = File.join(DocsHelper::ROOT, "README.md")
  README_JA = File.join(DocsHelper::ROOT, "README.ja.md")

  def test_readmes_link_to_each_other
    assert_includes DocsHelper.read(README).lines.first(6).join, "README.ja.md"
    assert_includes DocsHelper.read(README_JA).lines.first(6).join, "README.md"
  end

  def test_readmes_have_the_same_number_of_ruby_blocks
    en = DocsHelper.ruby_blocks(DocsHelper.read(README))
    ja = DocsHelper.ruby_blocks(DocsHelper.read(README_JA))
    assert_operator en.size, :>=, 6
    assert_equal en.size, ja.size, "README.md and README.ja.md must have the same number of ruby blocks"
    assert_equal en.map { _1.include?("show") }, ja.map { _1.include?("show") },
                 "the same blocks must call show in both READMEs"
  end

  [["README.md", README], ["README.ja.md", README_JA]].each do |name, path|
    define_method("test_runs_ruby_blocks_in_#{name.tr(".", "_")}") do
      blocks = DocsHelper.ruby_blocks(DocsHelper.read(path))
      refute_empty blocks
      blocks.each_with_index do |code, i|
        next unless code.include?("show")

        assert_runs code, "#{name} ruby block #{i + 1}"
      end
    end
  end

  # ------------------------------------------------------- examples/showcase
  # The bigger pieces shown in the READMEs. They are not on the site, so the
  # reel size limit does not apply; they only have to run.

  SHOWCASE = Dir[File.join(DocsHelper::ROOT, "examples", "showcase", "*.rb")].sort

  SHOWCASE.each do |path|
    id = File.basename(path, ".rb")
    define_method("test_runs_showcase_file_#{id}") do
      source = DocsHelper.read(path)
      assert_match(/^require "asobi"$/, source, "showcase/#{id}.rb must start with require \"asobi\"")
      assert_match(/^#/, source, "showcase/#{id}.rb needs a comment line")
      reel = DocsHelper.run(source.sub(/^require "asobi"\n/, ""))
      assert_nil reel["error"], "showcase/#{id}.rb failed:\n#{reel["error"]}"
      assert_operator reel["frames"].size, :>, 1, "showcase/#{id}.rb must move"
    end
  end

  [["README.md", README], ["README.ja.md", README_JA]].each do |name, path|
    define_method("test_#{name.tr(".", "_")}_shows_every_showcase_piece") do
      text = DocsHelper.read(path)
      SHOWCASE.each do |file|
        id = File.basename(file, ".rb")
        assert_includes text, "examples/showcase/#{id}.rb", "#{name} must link to showcase/#{id}.rb"
        assert_path_exists File.join(DocsHelper::ROOT, "docs", "readme", "media", "#{id}.gif")
      end
      text.scan(/(?:src="|\]\()(docs\/[^")]+)/).flatten.each do |image|
        assert_path_exists File.join(DocsHelper::ROOT, image), "#{name} shows #{image}, which is missing"
      end
    end

    # The fireworks at the top are too big for the reel limit, so their code
    # sits in an "rb" block; it must stay the same as the showcase file.
    define_method("test_#{name.tr(".", "_")}_fireworks_match_the_showcase_file") do
      block = DocsHelper.read(path)[/^```rb\n(.*?)^```/m, 1]
      refute_nil block, "#{name} must show the fireworks code in an rb block"
      source = DocsHelper.read(File.join(DocsHelper::ROOT, "examples", "showcase", "hanabi.rb"))
      assert_equal source.lines.reject { _1.start_with?("#") }.join, block
    end
  end
end
