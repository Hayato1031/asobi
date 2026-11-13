# frozen_string_literal: true

require_relative "test_helper"
require "asobi/live"
require "tmpdir"
require "json"
require "socket"
require "stringio"
require "timeout"
require "digest"

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

  # ---- a motion arrives in two pushes: a quick preview, then the whole reel ----

  def test_a_motion_is_pushed_as_a_preview_then_the_whole_reel
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    write "show circle(radius: 3).move(right: 10).spin(every: 2)\n"
    preview = stream.next_event
    assert_equal true, preview["pending"]
    assert_equal 1, preview["frames"].size
    whole = stream.next_event
    refute whole.key?("pending")
    assert_equal 60, whole["frames"].size
    assert_equal preview["frames"].first, whole["frames"].first
  end

  def test_the_first_reel_of_a_moving_sketch_is_a_preview_too
    write "show circle.pulse(every: 1)\n"
    start_run
    stream = events
    first = stream.next_event
    first = stream.next_event if first["pending"] # a fast whole reel may already be there
    assert_equal 30, first["frames"].size
    assert_nil first["pending"]
  end

  def test_the_sketch_is_evaluated_once_per_save
    marks = File.join(@dir, "marks.txt")
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    write %(File.write(#{marks.dump}, "x", mode: "a")\nshow circle.spin(every: 1)\n)
    assert stream.next_event["pending"]
    assert_equal 30, stream.next_event["frames"].size
    assert_equal "x", File.read(marks)
  end

  # Building the whole reel of the first save is slow. A second save during
  # that build stops it: the screen goes straight to the newest file and the
  # stale whole reel never arrives.
  def test_a_newer_save_wins_over_a_whole_reel_still_being_made
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    slow = <<~RUBY
      show circle(radius: 4).animate(4) { |c, t| sleep 0.01 if t > 0; c.move(right: t * 10) }
    RUBY
    write slow # 8 moments for the preview, 120 frames (over 1 s) for the whole reel
    preview = stream.next_event(5)
    assert_equal true, preview["pending"]
    write "show circle(radius: 9)\n"
    newest = stream.next_event(5)
    assert_equal ['<circle r="9"/>'], newest["frames"]
    assert_raises(Timeout::Error) { stream.next_event(2) } # nothing stale comes after
  end

  def test_an_error_while_a_whole_reel_is_being_made_is_shown_at_once
    write "show circle(radius: 7)\n"
    start_run
    stream = events
    stream.next_event
    write "show circle(radius: 4).animate(4) { |c, t| sleep 0.03 if t > 0; c }\n"
    assert stream.next_event(5)["pending"]
    write "show circl\n"
    broken = stream.next_event(5)
    assert_match(/live_sketch\.rb:1 /, broken["error"])
    late = events # a new tab: the last good picture (the preview), then the error
    assert late.next_event["pending"]
    assert late.next_event["error"]
  end

  def test_irb_show_pushes_a_preview_then_the_whole_reel
    server = Asobi::Live.start(port: 0, open: false)
    @server = server
    stream = events
    # What show does in irb, with this test's server in place of a new one.
    Asobi::Sketch.instance_variable_set(:@server, server)
    begin
      Asobi::Sketch.instance_variable_set(:@shown, Asobi::Sketch::Shown.new(Asobi.circle(radius: 2).spin))
      Asobi::Sketch.send(:push_to_server)
    ensure
      Asobi::Sketch.instance_variable_set(:@server, nil)
      Asobi::Sketch.forget
    end
    assert stream.next_event["pending"]
    assert_equal 120, stream.next_event["frames"].size
  end

  # --- the song (play "song.mp3") ----------------------------------------------

  SONG = ((0..255).map(&:chr).join * 40).b # 10240 bytes that stand for a song

  # A raw request with extra header lines; answers [status line, headers, body].
  def request(path, *headers)
    socket = TCPSocket.new("127.0.0.1", @server.port)
    socket.write "GET #{path} HTTP/1.1\r\nHost: x\r\n#{headers.map { "#{_1}\r\n" }.join}Connection: close\r\n\r\n"
    raw = Timeout.timeout(5) { socket.read }.b
    head, body = raw.split("\r\n\r\n", 2)
    status, *lines = head.split("\r\n")
    [status, lines.to_h { _1.split(": ", 2) }, body]
  ensure
    socket&.close
  end

  def start_with_song(name = "song.mp3", volume: nil)
    File.binwrite(File.join(@dir, name), SONG)
    write "play #{name.dump}#{", volume: #{volume}" if volume}\nshow circle\n"
    start_run
    events.next_event["song"]
  end

  def test_the_pushed_reel_names_the_song_by_url_not_by_bytes
    song = start_with_song(volume: 0.5)
    id = Digest::SHA256.hexdigest(SONG)[0, 12]
    assert_equal({ "id" => id, "src" => "/song/#{id}", "volume" => 0.5 }, song)
  end

  def test_the_song_is_served_whole_with_its_type
    song = start_with_song
    status, headers, body = request(song["src"])
    assert_equal "HTTP/1.1 200 OK", status
    assert_equal "audio/mpeg", headers["Content-Type"]
    assert_equal SONG.bytesize.to_s, headers["Content-Length"]
    assert_equal "bytes", headers["Accept-Ranges"]
    refute headers.key?("Content-Range")
    assert_equal SONG, body
  end

  def test_a_range_is_answered_with_206_and_just_those_bytes
    song = start_with_song("loop.wav")
    size = SONG.bytesize
    {
      "bytes=0-99" => [0, 99],
      "bytes=100-199" => [100, 199],
      "bytes=10000-" => [10_000, size - 1],
      "bytes=-300" => [size - 300, size - 1],
      "bytes=-99999" => [0, size - 1],
      "bytes=10000-99999" => [10_000, size - 1],
      "bytes=0-0" => [0, 0],
      "bytes=0-" => [0, size - 1]
    }.each do |range, (from, to)|
      status, headers, body = request(song["src"], "Range: #{range}")
      assert_equal "HTTP/1.1 206 Partial Content", status, range
      assert_equal "audio/wav", headers["Content-Type"]
      assert_equal "bytes #{from}-#{to}/#{size}", headers["Content-Range"], range
      assert_equal (to - from + 1).to_s, headers["Content-Length"], range
      assert_equal "bytes", headers["Accept-Ranges"]
      assert_equal SONG.byteslice(from..to), body, range
    end
  end

  def test_a_range_outside_the_song_is_416
    song = start_with_song
    ["bytes=#{SONG.bytesize}-", "bytes=99999-100000", "bytes=-0"].each do |range|
      status, headers, body = request(song["src"], "range: #{range}")
      assert_equal "HTTP/1.1 416 Range Not Satisfiable", status, range
      assert_equal "bytes */#{SONG.bytesize}", headers["Content-Range"]
      assert_equal "", body.to_s
    end
  end

  def test_a_range_this_server_does_not_follow_gets_the_whole_song
    song = start_with_song
    ["bytes=0-1,5-6", "items=0-1", "bytes=9-3", "bytes=-"].each do |range|
      status, _, body = request(song["src"], "Range: #{range}")
      assert_equal "HTTP/1.1 200 OK", status, range
      assert_equal SONG, body
    end
  end

  def test_only_songs_a_sketch_named_are_served
    start_with_song
    other = File.join(@dir, "secret.mp3")
    File.binwrite(other, "not for the browser")
    assert_match(%r{\AHTTP/1.1 404}, get("/song/#{Digest::SHA256.file(other).hexdigest[0, 12]}"))
    assert_match(%r{\AHTTP/1.1 404}, get("/song/000000000000"))
    assert_match(%r{\AHTTP/1.1 404}, get("/song/../live_sketch.rb"))
    assert_match(%r{\AHTTP/1.1 404}, get("/song/#{@path}"))
    assert_match(%r{\AHTTP/1.1 404}, get("/song/"))
  end

  def test_a_new_song_after_a_save_is_served_and_taking_out_play_stops_it
    song = start_with_song
    stream = events
    stream.next_event
    File.binwrite(File.join(@dir, "two.ogg"), "another song")
    write "play \"two.ogg\"\nshow circle(radius: 2)\n"
    two = stream.next_event["song"]
    refute_equal song["id"], two["id"]
    status, headers, body = request(two["src"])
    assert_equal ["HTTP/1.1 200 OK", "audio/ogg", "another song"], [status, headers["Content-Type"], body]
    write "show circle(radius: 3)\n"
    refute stream.next_event.key?("song")
  end

  def test_a_mistake_in_play_keeps_the_music_going
    start_with_song
    stream = events
    stream.next_event
    write "play \"missing.mp3\"\nshow circle\n"
    broken = stream.next_event
    assert_match(/live_sketch\.rb:1 /, broken["error"])
    refute broken.key?("song"), "an error says nothing about the song: the player keeps it"
  end

  def test_byte_range_reads_the_header
    assert_nil Asobi::Live.byte_range(nil, 10)
    assert_equal [2, 5], Asobi::Live.byte_range("bytes=2-5", 10)
    assert_equal [2, 9], Asobi::Live.byte_range(" bytes=2- ", 10)
    assert_equal [7, 9], Asobi::Live.byte_range("bytes=-3", 10)
    assert_equal [:unsatisfiable, nil], Asobi::Live.byte_range("bytes=0-", 0)
    assert_equal [:unsatisfiable, nil], Asobi::Live.byte_range("bytes=-5", 0)
    assert_equal [:unsatisfiable, nil], Asobi::Live.byte_range("bytes=10-12", 10)
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
