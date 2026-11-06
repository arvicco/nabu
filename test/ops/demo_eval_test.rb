# frozen_string_literal: true

require "test_helper"
require "json"
require "nabu/ops/demo_eval"

module Ops
  # Nabu::Ops::DemoEval — the demo eval pack's runner: tool-call steps
  # replayed against an MCP endpoint, each answer checked by machine
  # assertions. Everything here runs offline: the stdio and HTTP sessions
  # are driven through scripted stand-ins, never a real server.
  class DemoEvalTest < Minitest::Test
    E = Nabu::Ops::DemoEval

    def task_hash(id: "t1", steps: nil, difficulty: "lookup")
      steps ||= [{ "tool" => "nabu_search", "args" => { "query" => "Verbum" },
                   "expect" => [{ "path" => "matches.*.urn", "includes" => "urn:nabu:vulgate:jhn:1.1" }] }]
      { "id" => id, "question" => "Where is it?", "answer" => "urn:nabu:vulgate:jhn:1.1",
        "difficulty" => difficulty, "steps" => steps }
    end

    def pack_hash(tasks)
      { "schema" => E::SCHEMA, "tasks" => tasks }
    end

    def reply(payload, is_error: false)
      E::Reply.new(text: payload.is_a?(String) ? payload : JSON.generate(payload), is_error: is_error)
    end

    # A scripted session: answers tools/call from a table keyed by tool
    # name (a Proc answers from the arguments), recording every call.
    class FakeSession
      attr_reader :calls

      def initialize(table)
        @table = table
        @calls = []
      end

      def call_tool(name, arguments)
        @calls << [name, arguments]
        answer = @table.fetch(name)
        answer = answer.call(arguments) if answer.respond_to?(:call)
        raise answer if answer.is_a?(Exception)

        answer
      end
    end

    def opener_for(*sessions)
      opens = 0
      lambda do |&blk|
        opens += 1
        session = sessions.shift or raise Nabu::Error, "no more sessions"
        blk.call(session)
      end
    end

    def run_tasks(tasks, *sessions)
      E::Runner.new(tasks: E::Pack.parse(pack_hash(tasks)), opener: opener_for(*sessions)).run
    end

    # -- the pack schema --------------------------------------------------------

    def test_a_well_formed_pack_validates_clean
      assert_empty E::Pack.validate(pack_hash([task_hash]))
    end

    def test_validation_names_duplicate_ids_unknown_tools_and_bad_operators
      bad_step = { "tool" => "nabu_grep", "args" => {}, "expect" => [{ "path" => "x", "resembles" => 1 }] }
      errors = E::Pack.validate(pack_hash([task_hash, task_hash(steps: [bad_step])]))

      assert(errors.any? { |e| e.include?("duplicate id t1") }, errors.inspect)
      assert(errors.any? { |e| e.include?("unknown tool nabu_grep") }, errors.inspect)
      assert(errors.any? { |e| e.include?("exactly one operator") }, errors.inspect)
    end

    def test_validation_requires_question_answer_difficulty_and_checks
      task = task_hash(difficulty: "hard")
      task.delete("question")
      task["steps"][0]["expect"] = []
      errors = E::Pack.validate(pack_hash([task]))

      assert(errors.any? { |e| e.include?("question") }, errors.inspect)
      assert(errors.any? { |e| e.include?("difficulty hard") }, errors.inspect)
      assert(errors.any? { |e| e.include?("no checks") }, errors.inspect)
    end

    def test_validation_refuses_a_template_pointing_at_a_later_step
      steps = [{ "tool" => "nabu_show", "args" => { "urn" => "${2.matches.0.urn}" },
                 "expect" => [{ "text_includes" => "x" }] }]
      errors = E::Pack.validate(pack_hash([task_hash(steps: steps)]))

      assert(errors.any? { |e| e.include?("earlier step") }, errors.inspect)
    end

    def test_validation_refuses_a_foreign_schema
      assert(E::Pack.validate("schema" => "other/1", "tasks" => [task_hash]).any? { |e| e.include?("schema") })
    end

    def test_parse_raises_on_an_invalid_pack
      assert_raises(E::InvalidPack) { E::Pack.parse(pack_hash([task_hash(difficulty: "x")])) }
    end

    # -- paths and checks -------------------------------------------------------

    def test_dig_walks_keys_indexes_and_star_fanout
      payload = { "a" => [{ "b" => [{ "c" => 1 }, { "c" => 2 }] }, { "b" => [{ "c" => 3 }] }] }

      assert_equal [1, 2, 3], E::Probe.dig(payload, "a.*.b.*.c")
      assert_equal 3, E::Probe.dig(payload, "a.1.b.0.c")
      assert_equal E::Probe::MISSING, E::Probe.dig(payload, "a.5.b")
      assert_equal E::Probe::MISSING, E::Probe.dig(payload, "nope")
    end

    def test_every_operator_passes_and_fails_honestly
      r = reply({ "n" => 3, "list" => %w[x y], "note" => "36 matches, showing 36" })

      assert_nil E::Probe.check(r, { "path" => "n", "equals" => 3 })
      assert_match(/expected 4/, E::Probe.check(r, { "path" => "n", "equals" => 4 }))
      assert_nil E::Probe.check(r, { "path" => "list", "includes" => "y" })
      assert_nil E::Probe.check(r, { "path" => "note", "includes" => "36 matches" })
      refute_nil E::Probe.check(r, { "path" => "list", "includes" => "z" })
      assert_nil E::Probe.check(r, { "path" => "list", "excludes" => "z" })
      refute_nil E::Probe.check(r, { "path" => "list", "excludes" => "x" })
      assert_nil E::Probe.check(r, { "path" => "list", "size" => 2 })
      refute_nil E::Probe.check(r, { "path" => "list", "size" => 0 })
      assert_nil E::Probe.check(r, { "path" => "list", "min_size" => 1 })
      refute_nil E::Probe.check(r, { "path" => "list", "min_size" => 3 })
      assert_nil E::Probe.check(r, { "path" => "note", "matches" => "\\A\\d+ matches" })
      refute_nil E::Probe.check(r, { "path" => "missing", "equals" => nil })
    end

    def test_text_checks_read_the_raw_reply_and_is_error_is_explicit
      prose = reply("sign lookup needs the Oracc Sign List on disk")
      failed = reply("no place titled", is_error: true)

      assert_nil E::Probe.check(prose, { "text_includes" => "Oracc Sign List" })
      refute_nil E::Probe.check(prose, { "text_includes" => "Unikemet" })
      assert_match(/not JSON/, E::Probe.check(prose, { "path" => "x", "equals" => 1 }))
      assert_nil E::Probe.check(failed, { "is_error" => true })
      refute_nil E::Probe.check(prose, { "is_error" => true })
    end

    # -- the runner -------------------------------------------------------------

    def test_a_correct_answer_passes
      session = FakeSession.new("nabu_search" => reply({ "matches" => [{ "urn" => "urn:nabu:vulgate:jhn:1.1" }] }))
      result = run_tasks([task_hash], session).first

      assert_equal :pass, result.status
      assert_equal [["nabu_search", { "query" => "Verbum" }]], session.calls
    end

    def test_a_wrong_answer_fails_naming_the_check
      session = FakeSession.new("nabu_search" => reply({ "matches" => [{ "urn" => "urn:nabu:vulgate:gen:1.1" }] }))
      result = run_tasks([task_hash], session).first

      assert_equal :fail, result.status
      assert_match(/step 1 nabu_search: matches\.\*\.urn/, result.failures.first)
    end

    def test_an_unexpected_tool_error_fails_even_when_no_check_names_it
      steps = [{ "tool" => "nabu_place", "args" => { "query" => "Lilybaeum" },
                 "expect" => [{ "text_includes" => "Lilybaeum" }] }]
      session = FakeSession.new("nabu_place" => reply("no place titled \"Lilybaeum\"", is_error: true))
      result = run_tasks([task_hash(steps: steps)], session).first

      assert_equal :fail, result.status
      assert(result.failures.any? { |f| f.include?("isError") }, result.failures.inspect)
    end

    def test_a_chain_feeds_an_earlier_answer_into_the_next_call
      steps = [
        { "tool" => "nabu_clarify", "args" => { "query" => "Joannes 1.1" },
          "expect" => [{ "path" => "resolved_urn", "equals" => "urn:nabu:vulgate:jhn:1.1" }] },
        { "tool" => "nabu_show", "args" => { "urn" => "${1.resolved_urn}" },
          "expect" => [{ "path" => "text", "includes" => "In principio" }] }
      ]
      session = FakeSession.new(
        "nabu_clarify" => reply({ "resolved_urn" => "urn:nabu:vulgate:jhn:1.1" }),
        "nabu_show" => ->(args) { reply({ "urn" => args["urn"], "text" => "In principio erat Verbum" }) }
      )
      result = run_tasks([task_hash(steps: steps, difficulty: "chain")], session).first

      assert_equal :pass, result.status, result.failures.inspect
      assert_equal "urn:nabu:vulgate:jhn:1.1", session.calls.last[1]["urn"]
    end

    def test_a_chain_stops_when_its_template_cannot_resolve
      steps = [
        { "tool" => "nabu_search", "args" => { "query" => "x" }, "expect" => [{ "path" => "matches", "size" => 0 }] },
        { "tool" => "nabu_show", "args" => { "urn" => "${1.matches.0.urn}" }, "expect" => [{ "text_includes" => "x" }] }
      ]
      session = FakeSession.new("nabu_search" => reply({ "matches" => [] }), "nabu_show" => reply("unused"))
      result = run_tasks([task_hash(steps: steps, difficulty: "chain")], session).first

      assert_equal :fail, result.status
      assert_match(/cannot resolve/, result.failures.first)
      assert_equal 1, session.calls.size, "the dependent call is never sent with a hole in it"
    end

    def test_a_dead_server_errors_that_task_and_the_run_reopens_for_the_next
      dying = FakeSession.new("nabu_search" => Nabu::Error.new("worker ended before answering"))
      fresh = FakeSession.new("nabu_search" => reply({ "matches" => [{ "urn" => "urn:nabu:vulgate:jhn:1.1" }] }))
      results = run_tasks([task_hash(id: "a"), task_hash(id: "b")], dying, fresh)

      assert_equal %i[error pass], results.map(&:status)
      assert_match(/worker ended/, results.first.failures.first)
    end

    def test_a_server_that_never_starts_errors_every_task_once
      opener = ->(&_blk) { raise Nabu::Error, "command not found: docker" }
      tasks = E::Pack.parse(pack_hash([task_hash(id: "a"), task_hash(id: "b")]))
      results = E::Runner.new(tasks: tasks, opener: opener).run

      assert_equal %i[error error], results.map(&:status)
      assert(results.all? { |r| r.failures.first.include?("did not start") })
    end

    def test_render_reports_each_task_and_a_summary_with_tool_coverage
      session = FakeSession.new("nabu_search" => reply({ "matches" => [] }))
      results = run_tasks([task_hash(id: "a")], session)
      text = E.render(results)

      assert_match(/^FAIL +a /, text)
      assert_match(%r{0/1 passed \(1 failed, 0 errored\)}, text)
      assert_match(/tools exercised: 1/, text)
    end

    # -- the stdio session ------------------------------------------------------

    # The Shell::Duplex shape: write_line / read_line.
    class FakeDuplex
      attr_reader :written

      def initialize(replies)
        @replies = replies
        @written = []
      end

      def write_line(line) = @written << JSON.parse(line)

      def read_line = JSON.generate(@replies.shift)
    end

    def test_stdio_session_initializes_then_calls_tools
      io = FakeDuplex.new([
                            { "jsonrpc" => "2.0", "id" => 1, "result" => { "protocolVersion" => "2025-11-25" } },
                            { "jsonrpc" => "2.0", "id" => 2,
                              "result" => { "content" => [{ "type" => "text", "text" => "{\"a\":1}" }],
                                            "isError" => false } }
                          ])
      argv_seen = nil
      duplex = lambda do |*argv, &blk|
        argv_seen = argv
        blk.call(io)
      end
      got = E::StdioSession.open(%w[docker run -i --rm img], duplex: duplex) { |s| s.call_tool("nabu_status", {}) }

      assert_equal %w[docker run -i --rm img], argv_seen
      assert_equal(%w[initialize notifications/initialized tools/call], io.written.map { |m| m["method"] })
      assert_equal({ "name" => "nabu_status", "arguments" => {} }, io.written.last["params"])
      assert_equal "{\"a\":1}", got.text
      refute got.is_error
    end

    def test_stdio_session_turns_a_json_rpc_error_into_an_error_reply
      io = FakeDuplex.new([
                            { "jsonrpc" => "2.0", "id" => 1, "result" => {} },
                            { "jsonrpc" => "2.0", "id" => 2, "error" => { "code" => -32_602, "message" => "bad args" } }
                          ])
      duplex = ->(*_argv, &blk) { blk.call(io) }
      got = E::StdioSession.open(["x"], duplex: duplex) { |s| s.call_tool("nabu_show", {}) }

      assert got.is_error
      assert_match(/bad args/, got.text)
    end

    def test_stdio_session_refuses_a_mismatched_reply_id
      io = FakeDuplex.new([{ "jsonrpc" => "2.0", "id" => 9, "result" => {} }])
      duplex = ->(*_argv, &blk) { blk.call(io) }

      assert_raises(E::TransportError) { E::StdioSession.open(["x"], duplex: duplex) { |_s| nil } }
    end

    # -- the HTTP session -------------------------------------------------------

    def test_http_session_carries_the_session_id_minted_at_initialize
      seen = []
      post = lambda do |url, body, headers|
        message = JSON.parse(body)
        seen << [url, message["method"], headers]
        case message["method"]
        when "initialize"
          [200, { "mcp-session-id" => "abc" }, JSON.generate("jsonrpc" => "2.0", "id" => message["id"], "result" => {})]
        when "notifications/initialized" then [202, {}, ""]
        else
          [200, {}, JSON.generate("jsonrpc" => "2.0", "id" => message["id"],
                                  "result" => { "content" => [{ "type" => "text", "text" => "ok" }] })]
        end
      end
      got = E::HttpSession.open("http://localhost:8080/mcp", post: post) { |s| s.call_tool("nabu_status", {}) }

      assert_equal "ok", got.text
      assert_equal(%w[initialize notifications/initialized tools/call], seen.map { |row| row[1] })
      assert_nil seen.first[2]["Mcp-Session-Id"]
      assert_equal "abc", seen.last[2]["Mcp-Session-Id"]
      assert_equal "application/json", seen.last[2]["Content-Type"]
    end

    def test_http_session_raises_a_transport_error_on_a_non_ok_status
      post = ->(_url, _body, _headers) { [404, {}, "not found"] }

      assert_raises(E::TransportError) { E::HttpSession.open("http://localhost:8080/x", post: post) { |_s| nil } }
    end
  end
end
