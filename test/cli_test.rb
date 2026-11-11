# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "tmpdir"
require "rbconfig"

class CliTest < Minitest::Test
  EXE = File.expand_path("../exe/asobi", __dir__)

  # Run exe/asobi in +dir+ with English messages; the live view never starts
  # (ASOBI_CREATE_ONLY=1 stops it right after play.rb is made or found).
  def asobi(*args, dir:, lang: "C.UTF-8")
    env = { "ASOBI_CREATE_ONLY" => "1", "ASOBI_BROWSER" => "0", "LC_ALL" => lang, "LANG" => lang }
    Open3.capture3(env, RbConfig.ruby, EXE, *args, chdir: dir).map { _1.is_a?(String) ? _1.force_encoding("UTF-8") : _1 }
  end

  def test_executable_bit
    assert File.executable?(EXE)
  end

  def test_version
    Dir.mktmpdir do |dir|
      out, _err, status = asobi("version", dir:)
      assert status.success?
      assert_equal Asobi::VERSION, out.strip
    end
  end

  def test_help_in_both_languages
    Dir.mktmpdir do |dir|
      out, _err, status = asobi("help", dir:)
      assert status.success?
      assert_includes out, "--no-open"
      assert_includes out, "--port"
      out, = asobi("--help", dir:)
      assert_includes out, "asobi FILE.rb"
      out, = asobi("help", dir:, lang: "ja_JP.UTF-8")
      assert_includes out, "ライブ表示"
    end
  end

  def test_missing_file_is_one_friendly_line_and_status_1
    Dir.mktmpdir do |dir|
      out, err, status = asobi("nope.rb", dir:)
      assert_equal 1, status.exitstatus
      assert_equal "", out
      assert_equal 1, err.lines.size
      assert_includes err, "nope.rb"
    end
  end

  def test_unknown_option_is_friendly
    Dir.mktmpdir do |dir|
      _out, err, status = asobi("--bogus", dir:)
      assert_equal 1, status.exitstatus
      assert_includes err, "--help"
    end
  end

  def test_no_arguments_makes_the_starter_play_rb
    Dir.mktmpdir do |dir|
      out, _err, status = asobi(dir:)
      assert status.success?
      assert_includes out, "play.rb"
      code = File.read(File.join(dir, "play.rb"), encoding: "UTF-8")
      assert_includes code, 'require "asobi"'
      assert_includes code, "# Change anything and save. The picture follows."
      expected = <<~RUBY
        require "asobi"

        # Change anything and save. The picture follows.
        flower = petal.repeat(8).in_fan.colored(:crimson, :navy)

        show flower.spin(every: 8)
      RUBY
      assert_equal expected, code
    end
  end

  def test_the_starter_plays
    Dir.mktmpdir do |dir|
      asobi(dir:)
      reel = Asobi::Sketch.evaluate(File.join(dir, "play.rb"))
      assert_nil reel["error"]
      assert_equal 240, reel["frames"].size # 8 s at 30 fps
      assert_equal 30, reel["fps"]
      refute_equal reel["frames"][0], reel["frames"][60]
    end
  end

  def test_starter_comment_follows_the_language
    Dir.mktmpdir do |dir|
      asobi(dir:, lang: "ja_JP.UTF-8")
      code = File.read(File.join(dir, "play.rb"), encoding: "UTF-8")
      assert_includes code, "# どこでも書き換えて保存してください"
      assert_includes code, "show flower.spin(every: 8)"
    end
  end

  def test_existing_play_rb_is_never_overwritten
    Dir.mktmpdir do |dir|
      path = File.join(dir, "play.rb")
      File.write(path, "show circle # mine\n")
      _out, _err, status = asobi(dir:)
      assert status.success?
      assert_equal "show circle # mine\n", File.read(path)
    end
  end

  def test_a_given_file_that_exists_is_accepted
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "f.rb"), "show circle\n")
      _out, err, status = asobi("f.rb", dir:)
      assert status.success?, err
      refute File.exist?(File.join(dir, "play.rb"))
    end
  end
end
