# frozen_string_literal: true

require "test_helper"

module MCP
  # Nabu::MCP::Server (P8-1) — the hand-rolled protocol core, driven entirely
  # through injected lines/IO (the real stdin loop is P8-2's entrypoint).
  # Framing under test is the MCP stdio transport as specified in the
  # 2025-11-25 revision: one UTF-8 JSON-RPC object per line, no batching, no
  # Content-Length headers; notifications never get a response; parse errors
  # answer id:null -32700 without crashing the loop.
  class ServerTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      source = Nabu::Store::Source.create(
        slug: "perseus", name: "Perseus", adapter_class: "TestAdapter", license_class: "open"
      )
      doc = Nabu::Store::Document.create(
        source_id: source.id, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2",
        title: "Iliad", language: "grc", content_sha256: "x", revision: 1
      )
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:1.1", sequence: 0, language: "grc",
        text: "μῆνιν ἄειδε θεά",
        text_normalized: Nabu::Normalize.search_form("μῆνιν ἄειδε θεά", language: "grc"),
        content_sha256: "x", revision: 1
      )
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
      @server = Nabu::MCP::Server.new(
        tools: Nabu::MCP::Tools.new(catalog: @catalog, fulltext: @fulltext)
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rig -------------------------------------------------------------------

    def request(method, params = nil, id: 1)
      msg = { jsonrpc: "2.0", id: id, method: method }
      msg[:params] = params if params
      JSON.generate(msg)
    end

    def notification(method, params = nil)
      msg = { jsonrpc: "2.0", method: method }
      msg[:params] = params if params
      JSON.generate(msg)
    end

    def roundtrip(line)
      response = @server.handle_line(line)
      response && JSON.parse(response)
    end

    def initialize!
      roundtrip(request("initialize", {
                          protocolVersion: Nabu::MCP::Server::PROTOCOL_VERSION,
                          capabilities: {}, clientInfo: { name: "test", version: "0" }
                        }))
      roundtrip(notification("notifications/initialized"))
    end

    # -- initialize handshake ----------------------------------------------------

    def test_initialize_round_trip
      response = roundtrip(request("initialize", {
                                     protocolVersion: "2025-11-25",
                                     capabilities: { roots: {} },
                                     clientInfo: { name: "claude-code", version: "2.1.193" }
                                   }, id: 7))
      assert_equal "2.0", response.fetch("jsonrpc")
      assert_equal 7, response.fetch("id")
      result = response.fetch("result")
      assert_equal "2025-11-25", result.fetch("protocolVersion")
      assert_equal false, result.dig("capabilities", "tools", "listChanged")
      assert_equal "nabu", result.dig("serverInfo", "name")
      assert_equal Nabu::VERSION, result.dig("serverInfo", "version")
    end

    def test_initialize_counter_offers_our_version_when_the_request_is_unsupported
      response = roundtrip(request("initialize", {
                                     protocolVersion: "1.0",
                                     capabilities: {}, clientInfo: { name: "x", version: "0" }
                                   }))
      assert_equal Nabu::MCP::Server::PROTOCOL_VERSION,
                   response.dig("result", "protocolVersion")
    end

    def test_initialized_notification_is_accepted_silently
      roundtrip(request("initialize", { protocolVersion: "2025-11-25", capabilities: {},
                                        clientInfo: { name: "x", version: "0" } }))
      assert_nil @server.handle_line(notification("notifications/initialized"))
    end

    def test_other_notifications_are_swallowed_silently
      initialize!
      assert_nil @server.handle_line(notification("notifications/cancelled", { requestId: 1 }))
    end

    def test_ping_answers_an_empty_result_even_before_initialize
      response = roundtrip(request("ping", nil, id: "p1"))
      assert_equal "p1", response.fetch("id")
      assert_equal({}, response.fetch("result"))
    end

    def test_non_ping_requests_before_initialize_are_rejected
      response = roundtrip(request("tools/list"))
      refute_nil response["error"]
      assert_match(/initialized?/i, response.dig("error", "message"))
    end

    # -- tools/list ---------------------------------------------------------------

    def test_tools_list_exposes_the_five_tools_with_schemas
      initialize!
      response = roundtrip(request("tools/list", {}, id: 2))
      tools = response.dig("result", "tools")
      assert_equal(%w[nabu_search nabu_show nabu_concord nabu_align nabu_status],
                   tools.map { |t| t.fetch("name") })
      tools.each do |tool|
        refute_empty tool.fetch("description")
        schema = tool.fetch("inputSchema")
        assert_equal "object", schema.fetch("type")
        assert_kind_of Hash, schema.fetch("properties")
      end
    end

    def test_tools_list_tolerates_absent_params
      initialize!
      response = roundtrip(request("tools/list", nil, id: 3))
      assert_equal 5, response.dig("result", "tools").size
    end

    # -- tools/call ----------------------------------------------------------------

    def test_tools_call_search_happy_path
      initialize!
      response = roundtrip(request("tools/call",
                                   { name: "nabu_search", arguments: { query: "μηνιν" } }, id: 4))
      result = response.fetch("result")
      assert_equal false, result.fetch("isError")
      content = result.fetch("content")
      assert_equal "text", content.fetch(0).fetch("type")
      body = JSON.parse(content.fetch(0).fetch("text"))
      urns = body.fetch("matches").map { |m| m.fetch("urn") }
      assert_equal ["urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1"], urns
    end

    def test_tools_call_status_happy_path
      initialize!
      response = roundtrip(request("tools/call", { name: "nabu_status" }, id: 5))
      body = JSON.parse(response.dig("result", "content", 0, "text"))
      assert_equal 1, body.fetch("totals").fetch("passages")
    end

    def test_tools_call_unknown_tool_is_a_protocol_error
      initialize!
      response = roundtrip(request("tools/call", { name: "nabu_teleport", arguments: {} }, id: 6))
      error = response.fetch("error")
      assert_equal(-32_602, error.fetch("code"))
      assert_match(/nabu_teleport/, error.fetch("message"))
    end

    # SEP-1303 (2025-11-25): semantic argument failures are TOOL errors
    # (isError:true) so the model can self-correct, not protocol errors.
    def test_tools_call_invalid_arguments_are_a_tool_error_result
      initialize!
      response = roundtrip(request("tools/call",
                                   { name: "nabu_search",
                                     arguments: { query: "a", lemma: "b" } }, id: 7))
      result = response.fetch("result")
      assert_equal true, result.fetch("isError")
      assert_match(/query|lemma/i, result.dig("content", 0, "text"))
    end

    def test_tools_call_without_a_tool_name_is_a_protocol_error
      initialize!
      response = roundtrip(request("tools/call", { arguments: {} }, id: 8))
      assert_equal(-32_602, response.dig("error", "code"))
    end

    # -- protocol robustness ----------------------------------------------------------

    def test_malformed_json_line_answers_parse_error_without_crashing
      response = roundtrip("{this is not json")
      assert_nil response.fetch("id")
      assert_equal(-32_700, response.dig("error", "code"))
      # The loop survives: a valid request still works afterwards.
      assert roundtrip(request("ping"))["result"]
    end

    def test_batch_arrays_are_rejected_as_invalid_request
      response = roundtrip('[{"jsonrpc":"2.0","id":1,"method":"ping"}]')
      assert_equal(-32_600, response.dig("error", "code"))
    end

    def test_unknown_method_is_method_not_found
      initialize!
      response = roundtrip(request("resources/list", {}, id: 9))
      assert_equal(-32_601, response.dig("error", "code"))
    end

    def test_responses_are_single_lines_without_embedded_newlines
      initialize!
      line = @server.handle_line(request("tools/list", {}, id: 10))
      refute_includes line, "\n", "stdio framing forbids embedded newlines"
    end

    # -- the injected-IO loop -----------------------------------------------------------

    def test_run_serves_a_scripted_session_and_returns_on_eof
      input = StringIO.new(<<~SESSION)
        #{request('initialize', { protocolVersion: '2025-11-25', capabilities: {},
                                  clientInfo: { name: 'x', version: '0' } }, id: 1)}
        #{notification('notifications/initialized')}
        #{request('tools/list', {}, id: 2)}
        #{request('tools/call', { name: 'nabu_status' }, id: 3)}
      SESSION
      output = StringIO.new

      @server.run(input, output)

      lines = output.string.split("\n")
      assert_equal 3, lines.size, "three requests, one notification: three responses"
      ids = lines.map { |line| JSON.parse(line).fetch("id") }
      assert_equal [1, 2, 3], ids
    end

    def test_run_skips_blank_lines
      input = StringIO.new("\n#{request('ping')}\n\n")
      output = StringIO.new
      @server.run(input, output)
      assert_equal 1, output.string.split("\n").size
    end
  end
end
