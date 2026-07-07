# frozen_string_literal: true

require "json"

require_relative "../version"
require_relative "../errors"
require_relative "tools"

module Nabu
  module MCP
    # Hand-rolled MCP server core (P8-1): JSON-RPC 2.0 dispatch, the
    # initialize lifecycle, tools/list and tools/call — nothing else. Owner
    # decision (backlog P8-1): no gem — the field moves fast, we keep control,
    # and the conformant core is this small.
    #
    # == Protocol version + framing (researched 2026-07, pinned here)
    #
    # Implements MCP spec revision 2025-11-25 — the current release
    # (modelcontextprotocol.io/specification/versioning); Claude Code 2.1.x
    # requests exactly this version. stdio framing per
    # …/2025-11-25/basic/transports: one UTF-8 JSON-RPC object per line,
    # newline-delimited, NO Content-Length headers (that is LSP), no embedded
    # newlines in a message, and nothing on stdout that is not a protocol
    # message. JSON-RPC batching was REMOVED in spec 2025-06-18; an array on
    # the wire is rejected as an invalid request.
    #
    # == Error semantics (spec …/2025-11-25/server/tools, SEP-1303)
    #
    # - Unknown tool name → JSON-RPC -32602 (the spec's own example).
    # - Semantically invalid tool ARGUMENTS → a tool RESULT with isError:true,
    #   so the model can read the message and self-correct.
    # - Unknown method → -32601; malformed JSON line → -32700 with id:null;
    #   non-object message → -32600. The loop never crashes on bad input.
    #
    # == Who owns the real stdin
    #
    # Nobody here: the core is driven line-by-line (#handle_line) or by any
    # injected IO pair (#run) — which is also how the tests drive it. The
    # P8-2 entrypoint (`bin/nabu mcp`) wires $stdin/$stdout and owns process
    # concerns (logging to stderr, signal handling). stdout is sacred: this
    # class writes protocol messages to the injected output and NOTHING else;
    # diagnostics go to the injected log IO (stderr in production).
    class Server
      # MCP spec revision 2025-11-25 (current as of 2026-07; the 2026-07-28
      # revision is still a release candidate). Claude Code 2.1.x sends this.
      PROTOCOL_VERSION = "2025-11-25"
      SUPPORTED_VERSIONS = [PROTOCOL_VERSION].freeze

      SERVER_INFO = {
        name: "nabu",
        title: "Nabu — local ancient-text corpus (read-only)",
        version: Nabu::VERSION
      }.freeze

      # JSON-RPC 2.0 error codes.
      PARSE_ERROR = -32_700
      INVALID_REQUEST = -32_600
      METHOD_NOT_FOUND = -32_601
      INVALID_PARAMS = -32_602

      def initialize(tools:, log: nil)
        @tools = tools
        @log = log
        @handshaken = false
      end

      # Serve +input+ line by line, writing one response line per request to
      # +output+ (notifications get none), until EOF. Blank lines are skipped.
      # Flushed per message: the client is waiting on a pipe.
      def run(input, output)
        input.each_line do |line|
          next if line.strip.empty?

          response = handle_line(line)
          next unless response

          output.write(response, "\n")
          output.flush
        end
      end

      # One wire line in, one wire line out (a JSON string without embedded
      # newlines), or nil when the line was a notification.
      def handle_line(line)
        message = JSON.parse(line)
        return invalid_request(message) unless message.is_a?(Hash)

        dispatch(message)
      rescue JSON::ParserError => e
        log("parse error: #{e.message}")
        error(nil, PARSE_ERROR, "parse error: line is not valid JSON")
      end

      private

      def invalid_request(message)
        detail = if message.is_a?(Array)
                   "JSON-RPC batching is not supported (removed in MCP 2025-06-18)"
                 else
                   "message must be a JSON object"
                 end
        error(nil, INVALID_REQUEST, "invalid request: #{detail}")
      end

      def dispatch(message)
        id = message["id"]
        method = message["method"]
        # No method: either a stray response (we never send requests — ignore)
        # or a malformed request that still expects an answer.
        return id.nil? ? nil : error(id, INVALID_REQUEST, "invalid request: missing method") if method.nil?
        # Notifications (no id) never get a response, whatever the method —
        # notifications/initialized, notifications/cancelled, anything.
        return nil if id.nil?

        request(id, method, message["params"])
      end

      def request(id, method, params)
        case method
        when "ping" then result(id, {}) # answerable any time, even pre-handshake
        when "initialize" then handle_initialize(id, params || {})
        else
          return error(id, INVALID_REQUEST, "server not initialized — send initialize first") unless @handshaken

          post_handshake(id, method, params)
        end
      end

      def post_handshake(id, method, params)
        case method
        when "tools/list" then result(id, { tools: @tools.definitions })
        when "tools/call" then handle_call(id, params)
        else error(id, METHOD_NOT_FOUND, "method not found: #{method}")
        end
      end

      # Version negotiation (spec lifecycle): echo a supported requested
      # version; otherwise counter-offer our latest — the CLIENT then decides
      # whether to proceed or disconnect. Never an error.
      def handle_initialize(id, params)
        requested = params["protocolVersion"]
        @handshaken = true
        result(id, {
                 protocolVersion: SUPPORTED_VERSIONS.include?(requested) ? requested : PROTOCOL_VERSION,
                 capabilities: { tools: { listChanged: false } },
                 serverInfo: SERVER_INFO
               })
      end

      def handle_call(id, params)
        name = params.is_a?(Hash) ? params["name"] : nil
        return error(id, INVALID_PARAMS, "tools/call needs params.name (a tool name string)") unless name.is_a?(String)

        arguments = params["arguments"] || {}
        return error(id, INVALID_PARAMS, "tools/call arguments must be an object") unless arguments.is_a?(Hash)

        result(id, @tools.call(name, arguments))
      rescue Tools::UnknownTool => e
        error(id, INVALID_PARAMS, e.message)
      rescue Tools::InvalidArguments => e
        tool_failure(id, e.message)
      rescue Nabu::Error, Sequel::Error => e
        # A tool blowing up is a tool-execution error, not a dead server.
        log("#{name}: #{e.class}: #{e.message}")
        tool_failure(id, "#{name} failed: #{e.message}")
      end

      def tool_failure(id, text)
        result(id, { content: [{ type: "text", text: text }], isError: true })
      end

      def result(id, payload)
        JSON.generate({ jsonrpc: "2.0", id: id, result: payload })
      end

      def error(id, code, message)
        JSON.generate({ jsonrpc: "2.0", id: id, error: { code: code, message: message } })
      end

      def log(text)
        @log&.puts("nabu-mcp: #{text}")
      end
    end
  end
end
