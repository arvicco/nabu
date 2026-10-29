# frozen_string_literal: true

require "test_helper"
require "stringio"

module MCP
  # Nabu::MCP::HttpServer — the HTTP/1.1 wire under the streamable-HTTP
  # transport. Driven the way server_test drives the stdio core: through an
  # injected IO (one connection = one duplex IO), no sockets — the request
  # bytes in, the response bytes out. The listener loop is proven with an
  # injected listener double, so the suite never binds a port.
  class HttpServerTest < Minitest::Test
    include StoreTestDB

    # A connection double: reads from +input+, captures writes.
    class Connection
      attr_reader :written

      def initialize(input)
        @input = StringIO.new(input.b)
        @written = +""
        @closed = false
      end

      def gets(*) = @input.gets(*)
      def read(*) = @input.read(*)
      def write(*chunks) = chunks.each { |chunk| @written << chunk.to_s.b }.sum(&:bytesize)
      def close = (@closed = true)
      def closed? = @closed
      def flush = self
    end

    # Accepts each queued connection once, then reports itself closed.
    class Listener
      def initialize(connections) = (@connections = connections.dup)
      def accept = @connections.shift || raise(IOError, "closed")
      def close = nil
    end

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      source = Nabu::Store::Source.create(slug: "perseus", name: "Perseus", adapter_class: "TestAdapter",
                                          license_class: "open")
      doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2",
                                         title: "Iliad", language: "grc", content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:1.1", sequence: 0, language: "grc", text: "μῆνιν ἄειδε θεά",
        text_normalized: Nabu::Normalize.search_form("μῆνιν ἄειδε θεά", language: "grc"),
        content_sha256: "x", revision: 1
      )
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      Nabu::Store::SourceStats.derive!(@catalog, note: "test")
      tools = Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext)
      transport = Nabu::MCP::HttpTransport.new(server_factory: -> { Nabu::MCP::Server.new(tools: tools) })
      @server = Nabu::MCP::HttpServer.new(transport: transport)
    end

    def teardown
      @fulltext.disconnect
    end

    def http_post(body, session: nil)
      head = ["POST /mcp HTTP/1.1", "Host: localhost", "Content-Type: application/json",
              "Accept: application/json, text/event-stream", "Content-Length: #{body.bytesize}"]
      head << "Mcp-Session-Id: #{session}" if session
      "#{head.join("\r\n")}\r\n\r\n#{body}"
    end

    # Serve one raw request; return [status, headers(lowercased), body].
    def exchange(raw)
      connection = Connection.new(raw)
      @server.serve(connection)
      assert_predicate connection, :closed?, "the server closes every connection (Connection: close)"
      parse_response(connection.written)
    end

    def parse_response(bytes)
      head, body = bytes.split("\r\n\r\n", 2)
      lines = head.split("\r\n")
      status = lines.shift[%r{\AHTTP/1\.1 (\d{3}) }, 1].to_i
      headers = lines.to_h { |line| line.split(": ", 2).then { |key, value| [key.downcase, value] } }
      assert_equal body.bytesize, headers["content-length"].to_i, "Content-Length matches the body bytes"
      [status, headers, body.force_encoding(Encoding::UTF_8)]
    end

    def rpc(id, method, **params)
      msg = { jsonrpc: "2.0", id: id, method: method }
      msg[:params] = params unless params.empty?
      JSON.generate(msg)
    end

    def test_full_conversation_over_the_wire
      status, headers, body = exchange(http_post(rpc(1, "initialize", protocolVersion: "2025-11-25",
                                                                      capabilities: {},
                                                                      clientInfo: { name: "t", version: "0" })))
      assert_equal 200, status
      assert_equal "close", headers["connection"]
      session = headers.fetch("mcp-session-id")
      assert_equal "nabu", JSON.parse(body).dig("result", "serverInfo", "name")

      status, = exchange(http_post(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"),
                                   session: session))
      assert_equal 202, status

      _, _, body = exchange(http_post(rpc(2, "tools/list"), session: session))
      assert_includes JSON.parse(body).dig("result", "tools").map { |tool| tool["name"] }, "nabu_status"

      _, _, body = exchange(http_post(rpc(3, "tools/call", name: "nabu_status", arguments: {}), session: session))
      result = JSON.parse(body).fetch("result")
      refute result["isError"]
      payload = JSON.parse(result.dig("content", 0, "text"))
      assert_equal 1, payload.dig("totals", "passages")
    end

    def test_utf8_body_length_is_bytes_not_chars
      _, _, body = exchange(http_post(rpc(1, "initialize", protocolVersion: "2025-11-25")))
      assert_includes body, "Nabu — local" # the em dash is three bytes; parse_response checked the length
    end

    def test_header_names_are_case_insensitive
      raw = "POST /mcp HTTP/1.1\r\ncontent-type: application/json\r\nCONTENT-LENGTH: 2\r\n\r\n{}"
      status, _, body = exchange(raw)
      # The body reached the transport (which then asks for a session), so
      # the lowercase/uppercase header names framed correctly.
      assert_equal 400, status
      assert_includes body, "Mcp-Session-Id"
    end

    def test_query_string_is_ignored_for_routing
      raw = http_post(rpc(1, "ping")).sub("POST /mcp ", "POST /mcp?x=1 ")
      status, = exchange(raw)
      assert_equal 400, status # reached the transport: ping without a session
    end

    def test_missing_content_length_is_length_required
      status, = exchange("POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{}")
      assert_equal 411, status
    end

    def test_chunked_body_is_not_implemented
      raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\n" \
            "Transfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n"
      status, = exchange(raw)
      assert_equal 501, status
    end

    def test_oversized_body_is_too_large
      raw = "POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\n" \
            "Content-Length: #{Nabu::MCP::HttpServer::MAX_BODY_BYTES + 1}\r\n\r\n"
      status, = exchange(raw)
      assert_equal 413, status
    end

    def test_garbage_request_line_is_bad_request
      status, = exchange("HELLO\r\n\r\n")
      assert_equal 400, status
    end

    def test_truncated_body_is_bad_request
      status, = exchange("POST /mcp HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 50\r\n\r\n{}")
      assert_equal 400, status
    end

    def test_get_is_method_not_allowed
      status, headers, = exchange("GET /mcp HTTP/1.1\r\nHost: localhost\r\n\r\n")
      assert_equal 405, status
      assert_equal "POST, DELETE", headers["allow"]
    end

    def test_port_host_and_origins_from_the_environment
      klass = Nabu::MCP::HttpServer
      assert_equal 8080, klass.port_from({})
      assert_equal 8081, klass.port_from("PORT" => "8081")
      assert_raises(Nabu::Error) { klass.port_from("PORT" => "http") }
      assert_raises(Nabu::Error) { klass.port_from("PORT" => "70000") }
      assert_equal "127.0.0.1", klass.host_from({})
      assert_equal "0.0.0.0", klass.host_from("NABU_MCP_HOST" => "0.0.0.0")
      assert_equal %w[https://a.example https://b.example],
                   klass.allowed_origins_from("NABU_MCP_ALLOWED_ORIGINS" => "https://a.example, https://b.example")
    end

    def test_run_serves_each_accepted_connection_until_the_listener_closes
      first = Connection.new(http_post(rpc(1, "initialize", protocolVersion: "2025-11-25")))
      second = Connection.new("GET /mcp HTTP/1.1\r\n\r\n")
      @server.run(Listener.new([first, second]))
      assert_match %r{\AHTTP/1\.1 200 }, first.written
      assert_match %r{\AHTTP/1\.1 405 }, second.written
    end
  end
end
