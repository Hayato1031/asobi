# frozen_string_literal: true

require "socket"
require "json"
require "rbconfig"
require_relative "sketch"

module Asobi
  Say.add(:live_ready,
               en: "asobi: %{file} is playing at %{url}  -  save the file to change the picture, Ctrl-C to stop",
               ja: "asobi: %{file} を %{url} に表示しています。ファイルを保存すると絵が変わります。止めるには Ctrl-C")
  Say.add(:live_ready_irb,
               en: "asobi: playing at %{url}  -  every show changes the picture",
               ja: "asobi: %{url} に表示しています。show するたびに絵が変わります")
  Say.add(:live_bye, en: "asobi: bye!", ja: "asobi: またね")
  Messages.add(:live_no_port,
               en: "asobi couldn't find a free port from %{from} to %{to}. Close the other asobi, or pick one, like:  asobi --port 5000",
               ja: "%{from} から %{to} までの空いているポートが見つかりません。ほかの asobi を閉じるか、ポートを選んでください。例：asobi --port 5000")
  Messages.add(:live_invalid_reel,
               en: 'asobi could not send this sketch to the browser. Use UTF-8 for the file and its text, and finite numbers for drawing, like:  show text("hello", size: 24)',
               ja: 'このスケッチをブラウザに送れませんでした。ファイルと文字列には UTF-8 を使い、描画には有限の数を指定してください。例：show text("こんにちは", size: 24)')

  # The live view: a tiny HTTP server (standard library only) that serves the
  # player page and streams Reels to every open browser tab (Server-Sent
  # Events). It also serves the song a sketch plays (play "song.mp3") at
  # /song/ID, in pieces when the browser asks for them (Range), as media
  # players do. This is the only file that uses sockets and threads.
  module Live
    HOST = "127.0.0.1"
    DEFAULT_PORT = 4567
    PORT_TRIES = 20
    HEARTBEAT = 15 # seconds between keep-alive comments
    POLL = 0.2     # seconds between looks at the sketch file
    PAGE = File.join(__dir__, "web", "live.html")
    PLACEHOLDER = "/*ASOBI_PLAYER_JS*/"

    module_function

    # Blocking. Evaluate the sketch, serve it, and follow the file until
    # Ctrl-C (or until the server is stopped). Yields the server once it is
    # ready. +initial+ is a Reel already made from this run of the script
    # (when it is a pending preview, Sketch.finish has the rest).
    def run(path, port: DEFAULT_PORT, open: true, initial: nil, out: $stdout)
      path = File.expand_path(path.to_s)
      server = Server.new(port:)
      seen = stamp(path)
      first = server.push(initial || Sketch.evaluate(path, preview: true))
      builder = finish_later(server) if first["pending"]
      out.puts Say.text(:live_ready, file: File.basename(path), url: server.url)
      out.flush
      open_browser(server.url) if open
      yield server if block_given?
      watch(path, server, seen, builder)
    rescue Interrupt
      out.puts
      out.puts Say.text(:live_bye)
    ensure
      server&.stop
    end

    # Non-blocking, for irb: the server object (push, stop, url).
    def start(port: DEFAULT_PORT, open: true, announce: false, out: $stdout)
      server = Server.new(port:)
      if announce
        out.puts Say.text(:live_ready_irb, url: server.url)
        out.flush
      end
      open_browser(server.url) if open
      server
    end

    # Poll the file; when it changes (and has settled), evaluate and push.
    #
    # A motion arrives in two pushes: first a quick preview (one frame,
    # "pending"), then the whole Reel, made by a helper thread while this
    # loop keeps watching. If the file is saved again before the whole Reel
    # is ready, that Reel is already out of date: the helper is stopped and
    # never pushes, and the newest file is evaluated instead. So the screen
    # always ends on the newest file.
    def watch(path, server, seen = stamp(path), builder = nil)
      until server.stopped?
        sleep POLL
        now = stamp(path)
        next if now.nil? || now == seen

        loop do # wait until the editor has finished writing
          sleep 0.05
          later = stamp(path)
          break if later == now || later.nil?

          now = later
        end
        seen = now
        stop(builder) # a newer save: what it was making is out of date
        first = server.push(Sketch.evaluate(path, preview: true))
        builder = first["pending"] ? finish_later(server) : nil
      end
    ensure
      stop(builder)
    end

    # A thread that makes the whole Reel (Sketch.finish) and pushes it.
    def finish_later(server)
      thread = Thread.new do
        whole = Sketch.finish
        server.push(whole) if whole
      end
      thread.report_on_exception = false
      thread
    end

    # Stop a finish_later thread and wait until it has really stopped, so
    # it can never push after what comes next.
    def stop(builder)
      return unless builder

      builder.kill
      builder.join
    end

    def stamp(path)
      stat = File.stat(path)
      [stat.mtime, stat.size]
    rescue SystemCallError
      nil # briefly missing while an editor saves
    end

    def open_browser(url)
      return if ENV["ASOBI_BROWSER"] == "0"

      command =
        case RbConfig::CONFIG["host_os"]
        when /darwin/ then ["open", url]
        when /mswin|mingw|cygwin/ then ["cmd", "/c", "start", "", url]
        else ["xdg-open", url]
        end
      pid = Process.spawn(*command, out: File::NULL, err: File::NULL)
      Process.detach(pid)
    rescue SystemCallError
      nil # no browser to open; the URL was printed
    end

    def page
      @page ||= File.read(PAGE, encoding: "UTF-8").sub(PLACEHOLDER) { Reel.player_js }
    end

    # The piece of a file of +size+ bytes that a Range header asks for:
    #
    #   nil                     no header, or one this server does not follow
    #                           (several ranges, another unit): send it all
    #   [from, to]              those bytes, both ends in ("bytes=0-99",
    #                           "bytes=100-" to the end, "bytes=-100" the last 100)
    #   [:unsatisfiable, nil]   nothing of the file is in it (416)
    def byte_range(header, size)
      found = /\Abytes=(\d*)-(\d*)\z/.match(header.to_s.strip)
      return nil unless found

      first, last = found.captures
      return nil if first.empty? && last.empty?

      if first.empty? # the last +last+ bytes
        count = last.to_i
        return [:unsatisfiable, nil] if count.zero? || size.zero?

        return [[size - count, 0].max, size - 1]
      end

      from = first.to_i
      to = last.empty? ? size - 1 : [last.to_i, size - 1].min
      return nil if !last.empty? && last.to_i < from # not a range at all: ignored, as HTTP says
      return [:unsatisfiable, nil] if from >= size

      [from, to]
    end

    class Server
      attr_reader :port

      def initialize(port: DEFAULT_PORT)
        @mutex = Mutex.new
        @clients = []
        @reel = nil
        @good = nil
        @stopped = false
        @listener = listen(port)
        @port = @listener.addr[1]
        @thread = Thread.new { accept_loop }
        @thread.report_on_exception = false
      end

      def url = "http://#{HOST}:#{port}/"
      def stopped? = @stopped

      # Show this Reel (a Hash) in every open tab, now and for new tabs.
      def push(reel)
        begin
          json = JSON.generate(reel)
        rescue JSON::GeneratorError
          code = reel["code"]&.encode("UTF-8", invalid: :replace, undef: :replace)
          reel = Reel.error(Messages.text(:live_invalid_reel), code:)
          json = JSON.generate(reel)
        end
        @mutex.synchronize do
          @reel = json
          @good = json unless reel["error"]
          @clients.each { _1.queue << json }
        end
        reel
      end

      def stop
        return if @stopped

        @stopped = true
        @listener.close unless @listener.closed?
        @thread.kill
        @mutex.synchronize { @clients.each { _1.queue << :stop } }
      rescue IOError, SystemCallError
        nil
      end

      private

      Client = Struct.new(:socket, :queue)

      def listen(port)
        return TCPServer.new(HOST, port) if port.zero?

        port.upto(port + PORT_TRIES) do |candidate|
          next if taken?(candidate)

          begin
            return TCPServer.new(HOST, candidate)
          rescue Errno::EADDRINUSE, Errno::EACCES
            next
          end
        end
        raise Messages.error(IOError, :live_no_port, from: port, to: port + PORT_TRIES)
      end

      # Something already answers there (even when binding would not fail).
      def taken?(port)
        Socket.tcp(HOST, port, connect_timeout: 0.3) { true }
      rescue SystemCallError, IOError
        false
      end

      def accept_loop
        loop do
          socket = @listener.accept
          thread = Thread.new(socket) { |s| serve(s) }
          thread.report_on_exception = false
        end
      rescue IOError, SystemCallError
        nil
      end

      def serve(socket)
        request, headers = read_request(socket)
        return forbidden(socket) unless request.to_s.end_with?("\n") && local_host?(headers["host"])

        case request
        when %r{\AGET / }, %r{\AGET /\?\S* } then respond(socket, "200 OK", "text/html; charset=utf-8", Live.page)
        when %r{\AGET /events[ ?]} then stream(socket)
        when %r{\AGET /song/([0-9a-f]{12})[ ?]} then song(socket, Regexp.last_match(1), headers["range"])
        else not_found(socket)
        end
      rescue IOError, SystemCallError
        nil
      ensure
        socket.close unless socket.closed?
      end

      # A web page on another site can point its own name at this computer
      # (DNS rebinding) and then read the sketch. Browsers always send the
      # name they were asked for, so only answer to our own names. A request
      # whose Host line was never read (none sent, or pushed out of reach by a
      # very long address) must not get in either.
      def local_host?(host)
        return false if host.nil?

        name = host.start_with?("[") ? host[/\A\[[^\]]*\]/] : host.split(":", 2).first
        %w[127.0.0.1 localhost [::1]].include?(name.to_s.downcase)
      end

      # The request line, and the headers as { "range" => "bytes=0-" }
      # (names in small letters).
      def read_request(socket)
        return [nil, {}] unless IO.select([socket], nil, nil, 5)

        first = socket.gets("\n", 4096).to_s
        headers = {}
        32.times do
          break unless IO.select([socket], nil, nil, 2)

          line = socket.gets("\n", 8192)
          break if line.nil? || line.strip.empty?

          name, value = line.split(":", 2)
          next unless value

          name = name.strip.downcase
          # A second Host is a bad request; keep a value no one accepts.
          headers[name] = name == "host" && headers.key?(name) ? "twice" : value.strip
        end
        [first, headers]
      end

      def respond(socket, status, type, body)
        body = body.b
        socket.write "HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
                     "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        socket.write body
      end

      def forbidden(socket) = respond(socket, "403 Forbidden", "text/plain; charset=utf-8", "forbidden\n")

      def not_found(socket) = respond(socket, "404 Not Found", "text/plain; charset=utf-8", "not found\n")

      # The song with this id, if a sketch named it in play (Song.find);
      # never a path taken from the URL. All of it, or the piece a Range
      # header asks for (206), as browsers need for media.
      def song(socket, id, range)
        path = Song.find(id)
        return not_found(socket) unless path

        file = File.open(path, "rb")
      rescue SystemCallError
        not_found(socket) # the file went away
      else
        begin
          size = file.size
          type = Song::KINDS.fetch(File.extname(path).downcase, "application/octet-stream")
          from, to = Live.byte_range(range, size)
          if from == :unsatisfiable
            return socket.write("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */#{size}\r\n" \
                                "Content-Length: 0\r\nAccept-Ranges: bytes\r\nConnection: close\r\n\r\n")
          end

          status = from ? "206 Partial Content" : "200 OK"
          from ||= 0
          to ||= size - 1
          head = +"HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{to - from + 1}\r\nAccept-Ranges: bytes\r\n"
          head << "Content-Range: bytes #{from}-#{to}/#{size}\r\n" if status.start_with?("206")
          socket.write head << "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
          IO.copy_stream(file, socket, to - from + 1, from) if to >= from
        ensure
          file.close
        end
      end

      def stream(socket)
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        socket.write "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream; charset=utf-8\r\n" \
                     "Cache-Control: no-store\r\nConnection: keep-alive\r\n\r\nretry: 1000\n\n"
        client = Client.new(socket, Queue.new)
        @mutex.synchronize do
          return if @stopped

          client.queue << @good if @good && @good != @reel
          client.queue << @reel if @reel
          @clients << client
        end
        pump(client)
      ensure
        @mutex.synchronize { @clients.delete(client) } if client
      end

      def pump(client)
        loop do
          item = client.queue.pop(timeout: HEARTBEAT)
          return if item == :stop

          client.socket.write(item ? "data: #{item}\n\n" : ": keep-alive\n\n")
        end
      end
    end
  end
end
