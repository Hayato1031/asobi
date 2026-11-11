# frozen_string_literal: true

require_relative "test_helper"
require "asobi/live"
require "tmpdir"
require "json"
require "socket"
require "stringio"
require "timeout"

class LiveTest < Minitest::Test
  def setup
    super
    ENV["ASOBI_LIVE"] = "0"
    ENV["ASOBI_BROWSER"] = "0"
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "live_sketch.rb")
    @server = nil
    @runner = nil
  end

  def teardown
    @server&.stop
    @runner&.join(3)
    FileUtils.remove_entry(@dir)
  end

  def write(source)
    File.write(@path, source, encoding: "UTF-8")
    # make sure the change is visible even on file systems with coarse mtimes
    t = Time.now + (@bump = (@bump || 0) + 1)
    File.utime(t, t, @path)
  end

  # Live.run in a thread, on a free port; answers the server.
  def start_run
    ready = Queue.new
    @runner = Thread.new do
      Asobi::Live.run(@path, port: 0, open: false, out: StringIO.new) { |server| ready << server }
    end
    @runner.report_on_exception = false
    @server = Timeout.timeout(5) { ready.pop }
  end

  def get(path)
    socket = TCPSocket.new("127.0.0.1", @server.port)
    socket.write "GET #{path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
    Timeout.timeout(5) { socket.read }
  ensure
    socket&.close
  end

  # A raw socket on /events; answers an object with next_event.
  def events
    socket = TCPSocket.new("127.0.0.1", @server.port)
    socket.write "GET /events HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n"
    Timeout.timeout(5) { assert_match(%r{\AHTTP/1.1 200}, socket.gets) }
    Timeout.timeout(5) { loop { break if socket.gets.strip.empty? } } # headers
    stream = Object.new
    stream.define_singleton_method(:next_event) do |seconds = 3|
      Timeout.timeout(seconds) do
        loop do
          line = socket.gets
          raise EOFError, "stream closed" if line.nil?

          return JSON.parse(line.delete_prefix("data: ")) if line.start_with?("data: ")
        end
      end
    end
    stream.define_singleton_method(:close) { socket.close }
    @streams = (@streams || []) << stream
    stream
  end

  def test_page_has_the_player_and_no_placeholder
    write "show circle\n"
    start_run
    response = get("/")
    assert_match(%r{\AHTTP/1.1 200}, response)
    assert_includes response, "text/html"
    assert_includes response, "AsobiPlayer"
    assert_includes response, "EventSource"
    refute_includes response, "ASOBI_PLAYER_JS"
  end

  def test_other_paths_are_404
    write "show circle\n"
    start_run
    assert_match(%r{\AHTTP/1.1 404}, get("/nothing"))
    assert_match(%r{\AHTTP/1.1 404}, get("/events.json"))
  end

  def test_first_event_is_the_current_reel
    write "show circle(radius: 7)\n"
    start_run
    first = events.next_event
    assert_equal ['<circle r="7"/>'], first["frames"]
    assert_nil first["error"]
  end

  def test_save_during_the_first_render_is_seen_by_the_watcher
    write <<~'RUBY'
      File.write(__FILE__, "show circle(radius: 9)\n")
      show circle(radius: 7)
    RUBY
    start_run
    stream = events
    frames = stream.next_event["frames"]
    frames = stream.next_event["frames"] if frames == ['<circle r="7"/>']
    assert_equal ['<circle r="9"/>'], frames
  end

  def test_saving_the_file_pushes_a_new_reel_to_every_tab
    write "show circle(radius: 7)\n"
    start_run
    one = events
    two = events
    assert_equal 1, one.next_event["fps"]
    two.next_event
    write "show circle(radius: 9)\n"
    assert_equal ['<circle r="9"/>'], one.next_event["frames"]
    assert_equal ['<circle r="9"/>'], two.next_event["frames"]
  end

  def test_a_broken_sketch_is_an_error_event_and_fixing_it_recovers
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    write "show circl(radius: 7)\n"
    broken = stream.next_event
    assert_match(/live_sketch\.rb:1 /, broken["error"])
    write "show circle(radius: 8)\n"
    fixed = stream.next_event
    assert_nil fixed["error"]
    assert_equal ['<circle r="8"/>'], fixed["frames"]
  end

  def test_a_new_tab_during_an_error_still_gets_the_last_good_picture_first
    write "show circle(radius: 7)\n"
    start_run
    first = events
    first.next_event
    write "show circl\n"
    first.next_event
    late = events
    assert_equal ['<circle r="7"/>'], late.next_event["frames"]
    assert late.next_event["error"]
  end

  def test_a_non_utf8_save_shows_an_error_and_the_next_save_recovers
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event

    File.binwrite(@path, "# あそび\nshow circle(radius: 8)\n".encode("Windows-31J"))
    broken = stream.next_event
    assert_includes broken["error"], "UTF-8"
    assert_includes broken["code"], "show circle(radius: 8)"

    write "# あそび\nshow circle(radius: 8)\n"
    assert_equal ['<circle r="8"/>'], stream.next_event["frames"]
  end

  def test_a_file_missing_for_a_moment_is_tolerated
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    File.delete(@path)
    sleep 0.5
    write "show circle(radius: 5)\n"
    assert_equal ['<circle r="5"/>'], stream.next_event["frames"]
  end

  def test_run_returns_when_the_server_stops
    write "show circle\n"
    start_run
    @server.stop
    assert @runner.join(3), "run should end after stop"
  end

  def test_run_says_one_friendly_line
    write "show circle\n"
    out = StringIO.new
    ready = Queue.new
    @runner = Thread.new { Asobi::Live.run(@path, port: 0, open: false, out:) { |s| ready << s } }
    @server = Timeout.timeout(5) { ready.pop }
    assert_equal 1, out.string.lines.size
    assert_includes out.string, @server.url
    assert_includes out.string, "Ctrl-C"
  end

  def test_start_gives_a_server_you_can_push_to
    server = Asobi::Live.start(port: 0, open: false)
    @server = server
    server.push(Asobi::Reel.of(Asobi.circle(radius: 2)))
    assert_equal ['<circle r="2"/>'], events.next_event["frames"]
    server.push(Asobi::Reel.of(Asobi.circle(radius: 3)))
    assert_equal ['<circle r="3"/>'], @streams.last.next_event["frames"]
    assert_match(%r{\Ahttp://127\.0\.0\.1:\d+/\z}, server.url)
  end

  def test_busy_port_moves_on_to_the_next
    holder = TCPServer.new("127.0.0.1", 0)
    busy = holder.addr[1]
    @server = Asobi::Live::Server.new(port: busy)
    refute_equal busy, @server.port
    assert_operator @server.port, :>, busy
  ensure
    holder&.close
  end

  def test_stop_closes_event_streams
    write "show circle\n"
    start_run
    stream = events
    stream.next_event
    @server.stop
    assert_raises(EOFError, Errno::ECONNRESET) { stream.next_event(1) }
  end
end
