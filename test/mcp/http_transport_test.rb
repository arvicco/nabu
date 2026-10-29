# frozen_string_literal: true

require "test_helper"

module MCP
  # Nabu::MCP::HttpTransport — the streamable-HTTP framing layer, driven
  # with plain Request values (no sockets): POST JSON-RPC in, application/json
  # out; notifications 202; sessions minted at initialize and demanded after;
  # Origin validation; GET answers 405 (no server-initiated SSE stream). The
  # protocol semantics themselves are Server's (server_test.rb) — this file
  # proves only that HTTP carries them faithfully.
  class HttpTransportTest < Minitest::Test
    # A stand-in tool layer: the transport never looks inside it.
    class EchoTools
      def definitions = [{ name: "echo", description: "echo", inputSchema: { type: "object" } }]

      def call(_name, arguments)
        { content: [{ type: "text", text: JSON.generate(arguments) }] }
      end
    end

    Request = Nabu::MCP::HttpTransport::Request

    def setup
      tools = EchoTools.new
      counter = 0
      @transport = Nabu::MCP::HttpTransport.new(
        server_factory: -> { Nabu::MCP::Server.new(tools: tools) },
        session_id: -> { "session-#{counter += 1}" }
      )
    end

    def post(message, session: nil, headers: {})
      base = { "content-type" => "application/json", "accept" => "application/json, text/event-stream" }
      base["mcp-session-id"] = session if session
      body = message.is_a?(String) ? message : JSON.generate(message)
      @transport.call(Request.new(verb: "POST", path: "/mcp", headers: base.merge(headers), body: body))
    end

    def rpc(id, method, params = nil)
      msg = { jsonrpc: "2.0", id: id, method: method }
      msg[:params] = params if params
      msg
    end

    def initialize_session
      response = post(rpc(1, "initialize", protocolVersion: "2025-11-25", capabilities: {},
                                           clientInfo: { name: "t", version: "0" }))
      response.headers.fetch("Mcp-Session-Id")
    end

    def test_initialize_answers_json_and_mints_a_session
      response = post(rpc(1, "initialize", protocolVersion: "2025-11-25", capabilities: {},
                                           clientInfo: { name: "t", version: "0" }))
      assert_equal 200, response.status
      assert_equal "application/json", response.headers["Content-Type"]
      assert_equal "session-1", response.headers["Mcp-Session-Id"]
      body = JSON.parse(response.body)
      assert_equal 1, body["id"]
      assert_equal "2025-11-25", body.dig("result", "protocolVersion")
    end

    def test_notification_is_accepted_with_no_body
      session = initialize_session
      response = post({ jsonrpc: "2.0", method: "notifications/initialized" }, session: session)
      assert_equal 202, response.status
      assert_equal "", response.body
    end

    def test_tools_list_and_call_ride_the_session
      session = initialize_session
      list = JSON.parse(post(rpc(2, "tools/list"), session: session).body)
      assert_equal(["echo"], list.dig("result", "tools").map { |tool| tool["name"] })

      call = JSON.parse(post(rpc(3, "tools/call", name: "echo", arguments: { a: 1 }), session: session).body)
      assert_equal '{"a":1}', call.dig("result", "content", 0, "text")
    end

    def test_sessions_are_isolated
      first = initialize_session
      second = initialize_session
      refute_equal first, second
      # Each session carries its own handshake: both answer.
      [first, second].each do |session|
        assert_equal 200, post(rpc(2, "tools/list"), session: session).status
      end
    end

    def test_missing_session_header_is_bad_request
      initialize_session
      response = post(rpc(2, "tools/list"))
      assert_equal 400, response.status
      assert_match(/Mcp-Session-Id/, JSON.parse(response.body).dig("error", "message"))
    end

    def test_unknown_session_is_not_found
      response = post(rpc(2, "tools/list"), session: "nope")
      assert_equal 404, response.status
    end

    def test_delete_terminates_the_session
      session = initialize_session
      response = @transport.call(Request.new(verb: "DELETE", path: "/mcp",
                                             headers: { "mcp-session-id" => session }, body: ""))
      assert_equal 200, response.status
      assert_equal 404, post(rpc(2, "tools/list"), session: session).status
    end

    def test_get_is_method_not_allowed_no_server_initiated_stream
      response = @transport.call(Request.new(verb: "GET", path: "/mcp", headers: {}, body: ""))
      assert_equal 405, response.status
      assert_equal "POST, DELETE", response.headers["Allow"]
    end

    def test_other_paths_are_not_found
      response = @transport.call(Request.new(verb: "POST", path: "/elsewhere", headers: {}, body: "{}"))
      assert_equal 404, response.status
    end

    def test_malformed_json_is_bad_request_with_a_parse_error_body
      response = post("{not json")
      assert_equal 400, response.status
      assert_equal(-32_700, JSON.parse(response.body).dig("error", "code"))
    end

    def test_batch_array_is_bad_request
      response = post([rpc(1, "ping")])
      assert_equal 400, response.status
      assert_equal(-32_600, JSON.parse(response.body).dig("error", "code"))
    end

    def test_wrong_content_type_is_unsupported_media
      response = post(rpc(1, "ping"), headers: { "content-type" => "text/plain" })
      assert_equal 415, response.status
    end

    def test_accept_that_excludes_json_is_not_acceptable
      response = post(rpc(1, "ping"), headers: { "accept" => "text/event-stream" })
      assert_equal 406, response.status
    end

    def test_foreign_origin_is_forbidden_local_origin_passes
      foreign = post(rpc(1, "initialize", protocolVersion: "2025-11-25"),
                     headers: { "origin" => "https://evil.example" })
      assert_equal 403, foreign.status
      local = post(rpc(1, "initialize", protocolVersion: "2025-11-25"),
                   headers: { "origin" => "http://localhost:6274" })
      assert_equal 200, local.status
    end

    def test_configured_origin_passes
      transport = Nabu::MCP::HttpTransport.new(
        server_factory: -> { Nabu::MCP::Server.new(tools: EchoTools.new) },
        allowed_origins: ["https://inspector.example"]
      )
      response = transport.call(Request.new(
                                  verb: "POST", path: "/mcp",
                                  headers: { "content-type" => "application/json",
                                             "origin" => "https://inspector.example" },
                                  body: JSON.generate(rpc(1, "initialize", protocolVersion: "2025-11-25"))
                                ))
      assert_equal 200, response.status
    end

    def test_unsupported_protocol_version_header_is_bad_request
      session = initialize_session
      response = post(rpc(2, "tools/list"), session: session, headers: { "mcp-protocol-version" => "1999-01-01" })
      assert_equal 400, response.status
    end

    def test_session_table_is_bounded
      transport = Nabu::MCP::HttpTransport.new(
        server_factory: -> { Nabu::MCP::Server.new(tools: EchoTools.new) }, max_sessions: 2
      )
      init = JSON.generate(rpc(1, "initialize", protocolVersion: "2025-11-25"))
      headers = { "content-type" => "application/json" }
      sessions = Array.new(3) do
        transport.call(Request.new(verb: "POST", path: "/mcp", headers: headers, body: init))
                 .headers["Mcp-Session-Id"]
      end
      list = JSON.generate(rpc(2, "tools/list"))
      statuses = sessions.map do |id|
        transport.call(Request.new(verb: "POST", path: "/mcp", headers: headers.merge("mcp-session-id" => id),
                                   body: list)).status
      end
      assert_equal [404, 200, 200], statuses, "the oldest session is evicted past the cap"
    end
  end
end
