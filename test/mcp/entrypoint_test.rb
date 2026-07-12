# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"
require "tmpdir"
require "fileutils"

module MCP
  # `bin/nabu mcp` (P8-2) — the stdio entrypoint, tested for real: a child
  # process is spawned with `bundle exec bin/nabu mcp` and driven over its
  # pipes with newline-delimited JSON-RPC, exactly as an MCP client (Claude
  # Code / Desktop) drives it. This is the ONE process-level test — the
  # protocol semantics are covered exhaustively by server_test/tools_test
  # against the injected IO; here we prove the wiring: real stdin/stdout, a
  # read-only corpus opened from a config, a full handshake, one real
  # tools/call, and a clean EOF shutdown. STDOUT must carry protocol AND
  # NOTHING ELSE — that assertion is the whole point of the entrypoint.
  class EntrypointTest < Minitest::Test
    include StoreTestDB

    PROJECT_ROOT = File.expand_path("../..", __dir__)

    # Build a real on-disk fixture corpus (catalog + FTS index) under +dir+ and
    # a nabu.yml pointing at it, then hand back the config path the child reads
    # via NABU_CONFIG. Mirrors the query-test rig, but to files, not :memory:.
    def build_corpus(dir)
      db_dir = File.join(dir, "db")
      FileUtils.mkdir_p(db_dir)
      catalog = Nabu::Store.connect(File.join(db_dir, "catalog.sqlite3"))
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      source = Nabu::Store::Source.create(
        slug: "perseus", name: "Perseus", adapter_class: "TestAdapter",
        license_class: "open", enabled: true, last_sync_at: Time.utc(2026, 7, 1)
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
      fulltext = Nabu::Store.connect_fulltext(File.join(db_dir, "fulltext.sqlite3"))
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      catalog.disconnect
      fulltext.disconnect

      config_path = File.join(dir, "nabu.yml")
      File.write(config_path, "paths:\n  db: #{db_dir}\n")
      config_path
    end

    def test_spawn_handshake_tools_call_and_clean_eof_shutdown
      Dir.mktmpdir("nabu-mcp-smoke") do |dir|
        config_path = build_corpus(dir)

        stdout_lines = []
        status = nil
        Timeout.timeout(30) do
          Open3.popen3({ "NABU_CONFIG" => config_path }, "bundle", "exec", "bin/nabu", "mcp",
                       chdir: PROJECT_ROOT) do |stdin, stdout, _stderr, wait_thread|
            # initialize → one response line
            stdin.puts(rpc(1, "initialize", protocolVersion: "2025-11-25",
                                            capabilities: {}, clientInfo: { name: "smoke", version: "0" }))
            init = JSON.parse(stdout.gets)

            # the initialized notification gets no reply — do not read
            stdin.puts(JSON.generate(jsonrpc: "2.0", method: "notifications/initialized"))

            # tools/list → one response line
            stdin.puts(rpc(2, "tools/list"))
            list = JSON.parse(stdout.gets)

            # one real tools/call against the fixture corpus
            stdin.puts(rpc(3, "tools/call", name: "nabu_status", arguments: {}))
            call = JSON.parse(stdout.gets)

            stdin.close # EOF → the run loop ends, the process exits 0
            status = wait_thread.value

            stdout_lines = [init, list, call]
            assert_handshake(init)
            assert_tools_list(list)
            assert_status_call(call)
          end
        end

        assert status, "child never reported an exit status"
        assert_predicate status, :success?, "child exited non-zero (#{status.exitstatus})"
        # Every stdout line was a well-formed JSON-RPC 2.0 message: the channel
        # carried protocol and nothing else (a stray `say`/warn would have made
        # JSON.parse blow up above or slipped a non-2.0 line through here).
        stdout_lines.each { |line| assert_equal "2.0", line["jsonrpc"] }
      end
    end

    private

    def rpc(id, method, **params)
      msg = { jsonrpc: "2.0", id: id, method: method }
      msg[:params] = params unless params.empty?
      JSON.generate(msg)
    end

    def assert_handshake(init)
      assert_equal 1, init["id"]
      result = init.fetch("result")
      assert_equal "2025-11-25", result["protocolVersion"]
      assert_equal "nabu", result.dig("serverInfo", "name")
      assert result.dig("capabilities", "tools"), "server did not advertise the tools capability"
    end

    def assert_tools_list(list)
      names = list.fetch("result").fetch("tools").map { |tool| tool["name"] }
      assert_equal %w[nabu_search nabu_show nabu_concord nabu_align nabu_define nabu_etym
                      nabu_parallels nabu_status].sort, names.sort
    end

    def assert_status_call(call)
      result = call.fetch("result")
      refute result["isError"], "nabu_status reported an error result"
      text = result.fetch("content").first.fetch("text")
      payload = JSON.parse(text)
      assert_equal 1, payload.dig("totals", "documents")
      assert_equal 1, payload.dig("totals", "passages")
      assert_equal({ "grc" => 1 }, payload["languages"])
    end
  end
end
