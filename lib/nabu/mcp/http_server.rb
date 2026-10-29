# frozen_string_literal: true

require "socket"

require_relative "../errors"
require_relative "http_transport"

module Nabu
  module MCP
    # The HTTP/1.1 wire under the streamable-HTTP transport (`nabu mcp
    # --http`): stdlib TCPServer, one thread per connection, ONE request per
    # connection (every response says Connection: close — valid HTTP/1.1, and
    # every client library reconnects transparently). Hand-rolled like the
    # stdio core (no gem: WEBrick left the stdlib in Ruby 3.0, and the subset
    # an MCP endpoint needs is a request line, headers, and a Content-Length
    # body). All MCP semantics live in HttpTransport; this class only parses
    # and serializes bytes.
    #
    # Deliberate omissions: no keep-alive, no chunked request bodies (501 —
    # MCP clients send a sized JSON body), no TLS (terminate it in front, as
    # every host does), no HTTP/2. Request bodies are capped at
    # MAX_BODY_BYTES (413), header blocks at MAX_HEADER_BYTES (431), and an
    # idle connection is dropped after READ_TIMEOUT seconds.
    #
    # #serve takes any IO-like connection (gets/read/write/close), which is
    # how the suite drives it without binding a port; #run takes any
    # listener answering #accept.
    class HttpServer
      # const: request-shape guards, not census claims — a JSON-RPC tool call
      # is a few hundred bytes; a megabyte bounds a hostile client.
      MAX_BODY_BYTES = 1_048_576
      MAX_HEADER_BYTES = 16_384
      READ_TIMEOUT = 30
      DEFAULT_PORT = 8080
      DEFAULT_HOST = "127.0.0.1"
      REASONS = {
        200 => "OK", 202 => "Accepted", 400 => "Bad Request", 403 => "Forbidden", 404 => "Not Found",
        405 => "Method Not Allowed", 406 => "Not Acceptable", 411 => "Length Required",
        413 => "Content Too Large", 415 => "Unsupported Media Type", 431 => "Request Header Fields Too Large",
        500 => "Internal Server Error", 501 => "Not Implemented"
      }.freeze

      # A framing failure: answered with +status+ before the transport sees it.
      class BadRequest < Nabu::Error
        attr_reader :status

        def initialize(status, message)
          super(message)
          @status = status
        end
      end

      def initialize(transport:, log: nil)
        @transport = transport
        @log = log
      end

      # Bind +host+:+port+ (port 0 = any free port). Returns the TCPServer;
      # its #local_address.ip_port is the bound port.
      def self.listen(host:, port:)
        TCPServer.new(host, port)
      end

      # The listening port: PORT from the environment (the hosting
      # convention — Smithery, Glama, most PaaS inject it), else DEFAULT_PORT.
      def self.port_from(env)
        value = env.fetch("PORT", "").to_s.strip
        return DEFAULT_PORT if value.empty?
        return value.to_i if value.match?(/\A\d+\z/) && value.to_i <= 65_535

        raise Nabu::Error, "PORT must be an integer 0-65535, got #{value.inspect}"
      end

      # The bind address: NABU_MCP_HOST, else loopback — the spec's SHOULD
      # for a locally run server. A container sets 0.0.0.0 explicitly.
      def self.host_from(env)
        value = env.fetch("NABU_MCP_HOST", "").to_s.strip
        value.empty? ? DEFAULT_HOST : value
      end

      # Extra browser origins to admit (NABU_MCP_ALLOWED_ORIGINS, comma-
      # separated); loopback origins always pass (HttpTransport).
      def self.allowed_origins_from(env)
        env.fetch("NABU_MCP_ALLOWED_ORIGINS", "").to_s.split(",").map(&:strip).reject(&:empty?)
      end

      # Accept connections until the listener closes, answering each on its
      # own thread; waits for in-flight connections before returning.
      def run(listener)
        threads = []
        loop do
          connection = accept(listener) or break
          threads.select!(&:alive?) if threads.size > 64
          threads << Thread.new(connection) { |io| serve(io) }
        end
        threads.each(&:join)
      end

      # Answer one request on +connection+, then close it.
      def serve(connection)
        connection.timeout = READ_TIMEOUT if connection.respond_to?(:timeout=)
        response = begin
          @transport.call(read_request(connection))
        rescue BadRequest => e
          plain(e.status, e.message)
        end
        write_response(connection, response)
      rescue IOError, SystemCallError => e
        log("connection dropped: #{e.class}: #{e.message}")
      ensure
        connection.close unless connection.closed?
      end

      private

      def accept(listener)
        listener.accept
      rescue IOError, Errno::EBADF, Errno::EINVAL
        nil
      end

      def read_request(io)
        method, target, = request_line(io)
        headers = read_headers(io)
        HttpTransport::Request.new(verb: method, path: target.split("?", 2).first,
                                   headers: headers, body: read_body(io, method, headers))
      end

      def request_line(io)
        line = io.gets("\r\n", MAX_HEADER_BYTES).to_s.chomp
        parts = line.split
        raise BadRequest.new(400, "bad request line") unless parts.size == 3 && parts[2].start_with?("HTTP/1.")

        parts
      end

      def read_headers(io)
        headers = {}
        total = 0
        loop do
          line = io.gets("\r\n", MAX_HEADER_BYTES)
          raise BadRequest.new(400, "truncated header block") if line.nil?

          total += line.bytesize
          raise BadRequest.new(431, "header block too large") if total > MAX_HEADER_BYTES

          line = line.chomp
          break if line.empty?

          name, value = line.split(":", 2)
          raise BadRequest.new(400, "malformed header line") if value.nil?

          headers[name.strip.downcase] = value.strip
        end
        headers
      end

      def read_body(io, method, headers)
        if headers.key?("transfer-encoding")
          raise BadRequest.new(501, "chunked request bodies are not supported — send Content-Length")
        end

        length = headers["content-length"]
        return "" if length.nil? && method != "POST"
        raise BadRequest.new(411, "Content-Length required") if length.nil?
        raise BadRequest.new(400, "bad Content-Length") unless length.match?(/\A\d+\z/)

        size = length.to_i
        raise BadRequest.new(413, "body exceeds #{MAX_BODY_BYTES} bytes") if size > MAX_BODY_BYTES

        body = size.zero? ? "" : io.read(size).to_s
        raise BadRequest.new(400, "truncated body") if body.bytesize < size

        body.force_encoding(Encoding::UTF_8)
      end

      def write_response(io, response)
        body = response.body.to_s.b
        head = ["HTTP/1.1 #{response.status} #{REASONS.fetch(response.status, 'Unknown')}"]
        response.headers.each { |name, value| head << "#{name}: #{value}" }
        head << "Content-Length: #{body.bytesize}" << "Connection: close"
        io.write("#{head.join("\r\n")}\r\n\r\n".b, body)
        io.flush
      end

      def plain(status, text)
        HttpTransport::Response.new(status: status, headers: { "Content-Type" => "text/plain" }, body: "#{text}\n")
      end

      def log(text)
        @log&.puts("nabu-mcp: #{text}")
      end
    end
  end
end
