# frozen_string_literal: true

require "json"
require "yaml"
require "net/http"
require "uri"
require_relative "../errors"
require_relative "../shell"

module Nabu
  module Ops
    # The demo eval pack (eval/demo/pack.yml) and its runner: a fixed set of
    # natural-language questions over the FROZEN demo slice the public
    # image bakes in (Nabu::DemoBuild), each paired with the reference
    # tool-call steps an agent is expected to make and a machine-checkable
    # expected answer. Scoring is deterministic — expected URNs, substrings,
    # counts and structured fields read off the tool payloads — never a
    # model judgment.
    #
    # The runner replays every task's steps against a running MCP endpoint
    # and reports pass/fail per task plus a summary:
    #
    #   script/demo-eval                                  # docker run -i --rm <IMAGE>
    #   script/demo-eval --image ghcr.io/arvicco/nabu-demo:1.0.0
    #   script/demo-eval --url http://localhost:8080/mcp  # an HTTP-mode server
    #   script/demo-eval --command "bin/nabu mcp"         # a local stdio server
    #
    # It is the ONLY part of the pack that talks to a server; its tests drive
    # scripted sessions. Loads only the stdlib + Nabu::Shell (the
    # script/demo-smoke discipline), so it runs on a bare Ruby with no bundle.
    #
    # == The task shape
    #
    #   id          unique, kebab-case
    #   question    the natural-language question an agent is asked
    #   answer      the reference answer, in words (for grading an agent)
    #   difficulty  lookup | chain | negative
    #   steps       [{tool:, args:, expect: [check, ...]}, ...]
    #
    # A check is one of:
    #   {path: P, <op>: V}     op = equals | includes | excludes | size |
    #                          min_size | matches, over the JSON payload
    #   {text_includes: S}     substring of the raw reply text (prose replies)
    #   {is_error: true}       the reply must be a tool error
    # A step whose checks carry no is_error check must NOT be a tool error.
    #
    # A path is dot-separated: keys, array indexes, and * (fan out over an
    # array, flattening) — matches.*.urn, totals.passages, refs.0.witnesses.
    # An argument string "${N.path}" is replaced by the value at that path in
    # step N's payload (1-based, an earlier step) — the cross-tool chains.
    module DemoEval
      SCHEMA = "nabu.demo-eval/1"
      PACK = File.expand_path("../../../eval/demo/pack.yml", __dir__)
      DEFAULT_IMAGE = "ghcr.io/arvicco/nabu-demo:latest" # Nabu::Ops::DemoPublish::IMAGE (not loaded here)
      PROTOCOL_VERSION = "2025-11-25" # Nabu::MCP::Server::PROTOCOL_VERSION (not loaded here)

      # const: the MCP tool table's names (Nabu::MCP::Tools::TOOLS, not loaded
      # here — the pack test pins the two equal), code, not corpus.
      TOOLS = %w[nabu_search nabu_show nabu_concord nabu_align nabu_define nabu_etym nabu_parallels
                 nabu_cognates nabu_links nabu_char nabu_place nabu_signs nabu_clarify nabu_status].freeze
      DIFFICULTIES = %w[lookup chain negative].freeze
      OPERATORS = %w[equals includes excludes size min_size matches].freeze
      TEMPLATE = /\A\$\{(\d+)\.([^}]+)\}\z/

      # The pack file is malformed.
      class InvalidPack < Nabu::Error; end

      # The endpoint misbehaved below the tool layer (bad framing, wrong id,
      # HTTP status) — the task errors, it does not fail.
      class TransportError < Nabu::Error; end

      Task = Data.define(:id, :question, :answer, :difficulty, :steps) do
        def tools = steps.map(&:tool).uniq
      end
      Step = Data.define(:tool, :args, :expect)

      # One tools/call answer: the joined text content + the isError flag.
      Reply = Data.define(:text, :is_error) do
        # The parsed JSON payload, or nil for a prose reply.
        def payload
          JSON.parse(text)
        rescue JSON::ParserError
          nil
        end
      end

      # status: :pass | :fail (a wrong answer) | :error (the endpoint broke).
      Result = Data.define(:task, :status, :failures)

      # The pack file: schema validation + parsing into Task values.
      module Pack
        def self.load(path = PACK)
          parse(YAML.safe_load_file(path))
        end

        def self.parse(data)
          errors = validate(data)
          raise InvalidPack, "demo eval pack invalid: #{errors.join('; ')}" unless errors.empty?

          data.fetch("tasks").map do |task|
            steps = task.fetch("steps").map do |step|
              Step.new(tool: step.fetch("tool"), args: step.fetch("args", {}), expect: step.fetch("expect"))
            end
            Task.new(id: task.fetch("id"), question: task.fetch("question"), answer: task.fetch("answer"),
                     difficulty: task.fetch("difficulty"), steps: steps)
          end
        end

        # Every problem, as a list of strings (empty = well-formed).
        def self.validate(data)
          return ["pack is not a mapping"] unless data.is_a?(Hash)

          errors = []
          errors << "schema #{data['schema'].inspect} is not #{SCHEMA}" unless data["schema"] == SCHEMA
          tasks = data["tasks"]
          return errors << "tasks is not a non-empty list" unless tasks.is_a?(Array) && !tasks.empty?

          seen = {}
          tasks.each_with_index do |task, index|
            label = task.is_a?(Hash) && task["id"] ? task["id"] : "task ##{index + 1}"
            unless task.is_a?(Hash)
              errors << "#{label}: not a mapping"
              next
            end
            errors << "duplicate id #{label}" if seen[label]
            seen[label] = true
            errors.concat(task_errors(task, label))
          end
          errors
        end

        def self.task_errors(task, label)
          errors = []
          errors << "#{label}: id must be kebab-case" unless task["id"].to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
          %w[question answer].each do |key|
            errors << "#{label}: #{key} missing" unless task[key].is_a?(String) && !task[key].strip.empty?
          end
          errors << "#{label}: difficulty #{task['difficulty']} not in #{DIFFICULTIES.join('|')}" \
            unless DIFFICULTIES.include?(task["difficulty"])
          steps = task["steps"]
          return errors << "#{label}: steps is not a non-empty list" unless steps.is_a?(Array) && !steps.empty?

          steps.each_with_index do |step, index|
            errors.concat(step_errors(step, "#{label} step #{index + 1}", index + 1))
          end
          errors
        end
        private_class_method :task_errors

        def self.step_errors(step, label, number)
          return ["#{label}: not a mapping"] unless step.is_a?(Hash)

          errors = []
          errors << "#{label}: unknown tool #{step['tool']}" unless TOOLS.include?(step["tool"])
          args = step.fetch("args", {})
          errors << "#{label}: args is not a mapping" unless args.is_a?(Hash)
          if args.is_a?(Hash)
            args.each_value do |value|
              next unless value.is_a?(String) && (match = TEMPLATE.match(value))

              next if match[1].to_i.between?(1, number - 1)

              errors << "#{label}: template #{value} must name an earlier step"
            end
          end
          checks = step["expect"]
          return errors << "#{label}: no checks" unless checks.is_a?(Array) && !checks.empty?

          checks.each { |check| errors.concat(check_errors(check, label)) }
          errors
        end
        private_class_method :step_errors

        def self.check_errors(check, label)
          return ["#{label}: check is not a mapping"] unless check.is_a?(Hash)
          return [] if check.keys == ["text_includes"] && check["text_includes"].is_a?(String)
          return [] if check.keys == ["is_error"] && check["is_error"] == true

          ops = check.keys - ["path"]
          return ["#{label}: path check #{check.inspect} needs a path"] unless check["path"].is_a?(String)
          return ["#{label}: check #{check.inspect} needs exactly one operator (#{OPERATORS.join('|')})"] \
            unless ops.size == 1 && OPERATORS.include?(ops.first)

          op = ops.first
          if %w[size min_size].include?(op) && !check[op].is_a?(Integer)
            ["#{label}: #{op} takes an integer"]
          else
            []
          end
        end
        private_class_method :check_errors
      end

      # Path digging and the check operators.
      module Probe
        MISSING = Object.new.tap { |o| def o.inspect = "(absent)" }.freeze

        def self.dig(value, path)
          walk(value, path.to_s.split("."))
        end

        def self.walk(value, segments)
          return value if segments.empty?

          head, *rest = segments
          if head == "*"
            return MISSING unless value.is_a?(Array)

            value.flat_map do |item|
              got = walk(item, rest)
              got.equal?(MISSING) ? [] : got
            end
          elsif value.is_a?(Array) && head.match?(/\A\d+\z/)
            index = head.to_i
            index < value.size ? walk(value[index], rest) : MISSING
          elsif value.is_a?(Hash) && value.key?(head)
            walk(value[head], rest)
          else
            MISSING
          end
        end
        private_class_method :walk

        # nil when the check holds, else the reason.
        def self.check(reply, check)
          if check.key?("is_error")
            return reply.is_error ? nil : "expected a tool error, got a normal reply"
          end

          if check.key?("text_includes")
            needle = check["text_includes"]
            return reply.text.include?(needle) ? nil : "reply text lacks #{needle.inspect}"
          end

          payload = reply.payload
          return "reply is not JSON (#{reply.text[0, 120].inspect})" if payload.nil?

          path = check.fetch("path")
          op = (check.keys - ["path"]).first
          value = dig(payload, path)
          return "#{path}: absent" if value.equal?(MISSING)

          reason = operate(op, value, check[op])
          reason && "#{path}: #{reason}"
        end

        def self.operate(operator, value, expected)
          case operator
          when "equals" then value == expected ? nil : "expected #{expected.inspect}, got #{brief(value)}"
          when "includes" then contains?(value, expected) ? nil : "#{brief(value)} lacks #{expected.inspect}"
          when "excludes" then contains?(value, expected) ? "#{brief(value)} carries #{expected.inspect}" : nil
          when "size", "min_size" then size_check(operator, value, expected)
          when "matches" then match_any?(value, Regexp.new(expected)) ? nil : "#{brief(value)} !~ /#{expected}/"
          end
        end
        private_class_method :operate

        def self.match_any?(value, pattern)
          Array(value).any? { |item| item.is_a?(String) && pattern.match?(item) }
        end
        private_class_method :match_any?

        def self.contains?(value, expected)
          case value
          when Array then value.include?(expected)
          when String then value.include?(expected.to_s)
          when Hash then value.key?(expected.to_s)
          else false
          end
        end
        private_class_method :contains?

        def self.size_check(operator, value, expected)
          return "#{brief(value)} has no size" unless value.respond_to?(:size) && !value.is_a?(Numeric)

          exact = operator == "size"
          return nil if exact ? value.size == expected : value.size >= expected

          "size #{value.size}, expected #{'>= ' unless exact}#{expected}"
        end
        private_class_method :size_check

        def self.brief(value)
          text = value.inspect
          text.size > 160 ? "#{text[0, 157]}..." : text
        end
        private_class_method :brief
      end

      # The JSON-RPC exchange both sessions share: initialize, the
      # initialized notification, then tools/call per request.
      module Rpc
        CLIENT_INFO = { "name" => "nabu-demo-eval", "version" => "1" }.freeze

        def initialize_params
          { "protocolVersion" => PROTOCOL_VERSION, "capabilities" => {}, "clientInfo" => CLIENT_INFO }
        end

        def next_id
          @next_id = (@next_id || 0) + 1
        end

        # A tools/call reply message → Reply (a JSON-RPC error is an error reply).
        def to_reply(message, id)
          raise TransportError, "reply id #{message['id'].inspect}, expected #{id}" unless message["id"] == id

          if message.key?("error")
            text = message.dig("error", "message") || JSON.generate(message["error"])
            return Reply.new(text: text.to_s, is_error: true)
          end

          result = message.fetch("result") { raise TransportError, "reply carries no result" }
          text = Array(result["content"]).filter_map { |part| part["text"] }.join("\n")
          Reply.new(text: text, is_error: result["isError"] == true)
        end

        def check_handshake!(message, id)
          unless message["id"] == id
            raise TransportError,
                  "initialize: reply id #{message['id'].inspect}, expected #{id}"
          end
          raise TransportError, "initialize: #{message.dig('error', 'message')}" if message.key?("error")
        end
      end

      # A stdio MCP server: `docker run -i --rm IMAGE` or a local `bin/nabu mcp`.
      class StdioSession
        include Rpc

        # +duplex+ opens the stdio session (default Nabu::Shell.duplex).
        def self.open(argv, duplex: nil, &)
          duplex ||= ->(*cmd, &blk) { Nabu::Shell.duplex(*cmd, &blk) }
          duplex.call(*argv) do |io|
            session = new(io)
            session.handshake!
            yield session
          end
        end

        def initialize(io)
          @io = io
        end

        def handshake!
          id = next_id
          check_handshake!(request(id, "initialize", initialize_params), id)
          @io.write_line(JSON.generate("jsonrpc" => "2.0", "method" => "notifications/initialized"))
        end

        def call_tool(name, arguments)
          id = next_id
          to_reply(request(id, "tools/call", { "name" => name, "arguments" => arguments }), id)
        end

        private

        def request(id, method, params)
          @io.write_line(JSON.generate("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params))
          JSON.parse(@io.read_line)
        rescue JSON::ParserError => e
          raise TransportError, "#{method}: non-JSON on stdout (#{e.message[0, 120]})"
        end
      end

      # A streamable-HTTP MCP server (`bin/nabu mcp --http`, POST /mcp).
      class HttpSession
        include Rpc

        # +post+ is (url, body, headers) → [status, headers (lowercase keys), body];
        # the default is Net::HTTP.
        def self.open(url, post: nil)
          session = new(url, post || method(:net_post))
          session.handshake!
          yield session
        end

        def self.net_post(url, body, headers)
          uri = URI(url)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                         open_timeout: 10, read_timeout: 120) do |http|
            http.post(uri.request_uri, body, headers)
          end
          [response.code.to_i, response.each_header.to_h, response.body.to_s]
        rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout => e
          raise TransportError, "POST #{url}: #{e.message}"
        end

        def initialize(url, post)
          @url = url
          @post = post
          @session_id = nil
        end

        def handshake!
          id = next_id
          status, headers, body = send_message({ "jsonrpc" => "2.0", "id" => id, "method" => "initialize",
                                                 "params" => initialize_params })
          expect_ok!(status, body, "initialize")
          check_handshake!(parse(body, "initialize"), id)
          @session_id = headers["mcp-session-id"]
          send_message({ "jsonrpc" => "2.0", "method" => "notifications/initialized" })
        end

        def call_tool(name, arguments)
          id = next_id
          status, _headers, body = send_message({ "jsonrpc" => "2.0", "id" => id, "method" => "tools/call",
                                                  "params" => { "name" => name, "arguments" => arguments } })
          expect_ok!(status, body, "tools/call")
          to_reply(parse(body, "tools/call"), id)
        end

        private

        def send_message(message)
          headers = { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream" }
          if @session_id
            headers["Mcp-Session-Id"] = @session_id
            headers["MCP-Protocol-Version"] = PROTOCOL_VERSION
          end
          @post.call(@url, JSON.generate(message), headers)
        end

        def expect_ok!(status, body, method)
          raise TransportError, "#{method}: HTTP #{status} (#{body.to_s[0, 120].strip})" unless status == 200
        end

        def parse(body, method)
          JSON.parse(body)
        rescue JSON::ParserError => e
          raise TransportError, "#{method}: non-JSON body (#{e.message[0, 120]})"
        end
      end

      # Runs tasks over sessions from +opener+ (a callable that yields one
      # open session to its block). A session that dies mid-task errors
      # that task; the next task gets a fresh session. A server that never
      # starts errors every remaining task once, rather than retrying.
      class Runner
        def initialize(tasks:, opener:)
          @tasks = tasks
          @opener = opener
        end

        def run
          results = []
          queue = @tasks.dup
          until queue.empty?
            opened = false
            begin
              @opener.call do |session|
                opened = true
                until queue.empty?
                  results << run_task(queue.first, session)
                  queue.shift
                end
              end
            rescue Nabu::Error => e
              if opened
                results << Result.new(task: queue.shift, status: :error, failures: [e.message]) unless queue.empty?
              else
                queue.each do |task|
                  results << Result.new(task: task, status: :error, failures: ["server did not start: #{e.message}"])
                end
                queue.clear
              end
            end
          end
          results
        end

        private

        # A task's own session failure is re-raised as a Nabu::Error with the
        # task still at the queue head, so #run errors exactly that task.
        def run_task(task, session)
          replies = []
          failures = []
          task.steps.each_with_index do |step, index|
            label = "step #{index + 1} #{step.tool}"
            args, hole = resolve_args(step.args, replies)
            if hole
              failures << "#{label}: cannot resolve #{hole}"
              break
            end
            reply = session.call_tool(step.tool, args)
            replies << reply
            failures.concat(step_failures(step, reply).map { |reason| "#{label}: #{reason}" })
          end
          Result.new(task: task, status: failures.empty? ? :pass : :fail, failures: failures)
        end

        def step_failures(step, reply)
          reasons = step.expect.filter_map { |check| Probe.check(reply, check) }
          expects_error = step.expect.any? { |check| check["is_error"] == true }
          reasons.unshift("unexpected isError reply: #{reply.text[0, 160].inspect}") if reply.is_error && !expects_error
          reasons
        end

        def resolve_args(args, replies)
          hole = nil
          resolved = args.transform_values do |value|
            match = value.is_a?(String) && TEMPLATE.match(value)
            next value unless match

            payload = replies[match[1].to_i - 1]&.payload
            got = payload.nil? ? Probe::MISSING : Probe.dig(payload, match[2])
            if got.equal?(Probe::MISSING) || got.nil?
              hole ||= value
              next nil
            end
            got
          end
          [resolved, hole]
        end
      end

      # The per-task lines + the summary.
      def self.render(results)
        lines = results.map do |result|
          head = "#{result.status.to_s.upcase.ljust(6)}#{result.task.id} [#{result.task.tools.join(', ')}]"
          ([head] + result.failures.map { |reason| "       #{reason}" }).join("\n")
        end
        counts = results.group_by(&:status).transform_values(&:size)
        tools = results.flat_map { |result| result.task.tools }.uniq
        lines << ""
        lines << "#{counts.fetch(:pass, 0)}/#{results.size} passed (#{counts.fetch(:fail, 0)} failed, " \
                 "#{counts.fetch(:error, 0)} errored); tools exercised: #{tools.size}/#{TOOLS.size}"
        lines.join("\n")
      end

      # The agent-facing view: questions without the reference steps/answers.
      def self.questions(tasks)
        tasks.map { |task| { "id" => task.id, "question" => task.question } }
      end
    end
  end
end
