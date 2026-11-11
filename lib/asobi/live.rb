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
  # Events). This is the only file that uses sockets and threads.
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
    # ready. +initial+ is a Reel already made from this run of the script.
    def run(path, port: DEFAULT_PORT, open: true, initial: nil, out: $stdout)
      path = File.expand_path(path.to_s)
      server = Server.new(port:)
      seen = stamp(path)
      server.push(initial || Sketch.evaluate(path))
      out.puts Say.text(:live_ready, file: File.basename(path), url: server.url)
      out.flush
      open_browser(server.url) if open
      yield server if block_given?
      watch(path, server, seen)
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
    def watch(path, server, seen = stamp(path))
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
        server.push(Sketch.evaluate(path))
      end
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
        request = read_request(socket)
        case request
        when %r{\AGET / }, %r{\AGET /\?\S* } then respond(socket, "200 OK", "text/html; charset=utf-8", Live.page)
        when %r{\AGET /events[ ?]} then stream(socket)
        else respond(socket, "404 Not Found", "text/plain; charset=utf-8", "not found\n")
        end
      rescue IOError, SystemCallError
        nil
      ensure
        socket.close unless socket.closed?
      end

      # The request line; the headers are read and dropped.
      def read_request(socket)
        return nil unless IO.select([socket], nil, nil, 5)

        first = socket.gets("\n", 4096).to_s
        32.times do
          break unless IO.select([socket], nil, nil, 2)

          line = socket.gets("\n", 8192)
          break if line.nil? || line.strip.empty?
        end
        first
      end

      def respond(socket, status, type, body)
        body = body.b
        socket.write "HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\n" \
                     "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        socket.write body
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
