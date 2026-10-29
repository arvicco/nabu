# frozen_string_literal: true

require "json"
require "securerandom"
require "uri"

require_relative "server"

module Nabu
  module MCP
    # The MCP streamable-HTTP transport's FRAMING (spec revision 2025-11-25,
    # …/basic/transports#streamable-http), as a pure function from a parsed
    # HTTP Request to a Response — no sockets here (HttpServer owns the wire),
    # so every rule below is unit-tested with plain values. The protocol
    # itself is Server's, byte-for-byte the stdio one: the same tool layer,
    # the same read-only openers, the same license etiquette — only the
    # carrier differs.
    #
    # == The subset implemented (the smallest honest one a standard client drives)
    #
    # - ONE endpoint (ENDPOINT, "/mcp"). POST carries exactly one JSON-RPC
    #   message (batches are refused by Server, as on stdio).
    # - A request → 200 application/json, one response object. The spec lets
    #   the server pick JSON or an SSE stream per request; this server always
    #   picks JSON (it never sends requests or notifications of its own, so a
    #   stream would carry nothing but the one response).
    # - A notification or response → 202 Accepted, empty body.
    # - Sessions: initialize mints an Mcp-Session-Id (a UUID) bound to its own
    #   Server instance (each session owns its handshake state); every later
    #   POST/DELETE must carry it — absent → 400, unknown/evicted → 404 (the
    #   client re-initializes, per spec). DELETE ends a session (200).
    # - MCP-Protocol-Version: when present it must name a supported revision
    #   (else 400); absent is accepted (the spec's backwards-compat default).
    # - Origin (DNS-rebinding guard, a spec MUST): absent passes (non-browser
    #   clients); a loopback origin (localhost / 127.0.0.1 / [::1], any port)
    #   passes; anything else must be listed in +allowed_origins+ — else 403.
    # - Content-Type must be application/json (415); an Accept header, when
    #   present, must admit application/json (406). Deliberately lenient: the
    #   spec has clients list BOTH json and event-stream, but refusing a
    #   json-only Accept would buy nothing (we only ever answer json) and
    #   would break plain curl.
    #
    # == Deliberate omissions
    #
    # - GET → 405 (Allow: POST, DELETE): no standalone server→client SSE
    #   stream, which the spec makes optional — nabu sends no server-initiated
    #   messages (tools listChanged is false, no sampling/elicitation).
    # - No SSE responses at all, hence no event ids and no resumability
    #   (Last-Event-ID) — both are features of streams we never open.
    # - No authorization: the served surface is read-only and carries only
    #   what the library's license classes already permit Server to serve.
    # - No idle expiry: the session table is bounded instead (max_sessions,
    #   least-recently-used evicted), so a long-lived hosted process cannot
    #   grow without limit.
    #
    # Thread safety: HttpServer answers each connection on its own thread;
    # #call serializes dispatch behind one mutex. The tool layer memoizes
    # read-only handles and was built for one caller at a time (stdio), and
    # SQLite reads are fast — one lane is the honest, simple choice.
    class HttpTransport
      ENDPOINT = "/mcp"
      SESSION_HEADER = "Mcp-Session-Id"
      # census: 256, 2026-10-29, concurrent sessions — a demo/hosting process
      # serves a handful of clients; the cap only bounds memory under churn.
      DEFAULT_MAX_SESSIONS = 256
      LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1] ::1].freeze

      # An HTTP request as HttpServer parsed it: +headers+ keys are lowercase.
      Request = Data.define(:verb, :path, :headers, :body)
      # An HTTP response: +headers+ keys in canonical case.
      Response = Data.define(:status, :headers, :body)

      def initialize(server_factory:, allowed_origins: [], log: nil,
                     session_id: -> { SecureRandom.uuid }, max_sessions: DEFAULT_MAX_SESSIONS)
        @server_factory = server_factory
        @allowed_origins = allowed_origins.map { |origin| origin.to_s.strip.chomp("/") }.reject(&:empty?)
        @log = log
        @session_id = session_id
        @max_sessions = max_sessions
        @sessions = {} # insertion order = recency (touched sessions re-insert)
        @lock = Mutex.new
      end

      def call(request)
        return status_only(404, "not found: the MCP endpoint is #{ENDPOINT}") unless request.path == ENDPOINT
        unless origin_ok?(request)
          return status_only(403,
                             "forbidden: Origin #{request.headers['origin']} is not allowed")
        end

        case request.verb
        when "POST" then @lock.synchronize { post(request) }
        when "DELETE" then @lock.synchronize { delete(request) }
        else
          Response.new(status: 405, headers: { "Allow" => "POST, DELETE", "Content-Type" => "text/plain" },
                       body: "method not allowed: POST JSON-RPC to #{ENDPOINT} (no server-initiated stream)\n")
        end
      end

      # The live session count (diagnostics).
      def session_count
        @lock.synchronize { @sessions.size }
      end

      private

      def post(request)
        unless json_content?(request)
          return rpc_error(415, Server::INVALID_REQUEST,
                           "Content-Type must be application/json")
        end
        unless accepts_json?(request)
          return rpc_error(406, Server::INVALID_REQUEST,
                           "Accept must admit application/json")
        end
        return rpc_error(400, Server::INVALID_REQUEST, "unsupported MCP-Protocol-Version") unless version_ok?(request)

        message = parse(request.body)
        # Unparseable or non-object: Server renders the canonical JSON-RPC
        # error body; the transport adds the HTTP status the spec requires.
        return json(400, server_error_body(request.body)) unless message.is_a?(Hash)

        message["method"] == "initialize" && !message["id"].nil? ? open_session(request.body) : in_session(request)
      end

      def open_session(body)
        server = @server_factory.call
        response = server.handle_line(body)
        id = @session_id.call
        @sessions[id] = server
        @sessions.delete(@sessions.keys.first) while @sessions.size > @max_sessions
        log("session opened (#{@sessions.size} live)")
        json(200, response, SESSION_HEADER => id)
      end

      def in_session(request)
        id = request.headers["mcp-session-id"].to_s
        if id.empty?
          return rpc_error(400, Server::INVALID_REQUEST,
                           "missing #{SESSION_HEADER} header — send initialize first")
        end

        server = @sessions.delete(id)
        return rpc_error(404, Server::INVALID_REQUEST, "unknown or expired session — re-initialize") unless server

        @sessions[id] = server # re-insert: most recently used
        response = server.handle_line(request.body)
        response ? json(200, response) : Response.new(status: 202, headers: {}, body: "")
      end

      def delete(request)
        id = request.headers["mcp-session-id"].to_s
        return status_only(400, "missing #{SESSION_HEADER} header") if id.empty?
        return status_only(404, "unknown session") unless @sessions.delete(id)

        log("session closed (#{@sessions.size} live)")
        status_only(200, "session terminated")
      end

      def parse(body)
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end

      def server_error_body(body)
        @server_factory.call.handle_line(body)
      end

      def origin_ok?(request)
        origin = request.headers["origin"].to_s.strip
        return true if origin.empty?
        return true if @allowed_origins.include?(origin.chomp("/"))

        LOOPBACK_HOSTS.include?(URI.parse(origin).host.to_s)
      rescue URI::InvalidURIError
        false
      end

      def json_content?(request)
        request.headers["content-type"].to_s.split(";").first.to_s.strip.casecmp?("application/json")
      end

      def accepts_json?(request)
        accept = request.headers["accept"].to_s
        return true if accept.strip.empty?

        accept.split(",").map { |part| part.split(";").first.to_s.strip.downcase }
                         .any? { |type| %w[application/json application/* */*].include?(type) }
      end

      def version_ok?(request)
        version = request.headers["mcp-protocol-version"].to_s.strip
        version.empty? || Server::SUPPORTED_VERSIONS.include?(version)
      end

      def json(status, body, extra = {})
        Response.new(status: status, headers: { "Content-Type" => "application/json" }.merge(extra), body: body)
      end

      def rpc_error(status, code, message)
        json(status, JSON.generate({ jsonrpc: "2.0", id: nil, error: { code: code, message: message } }))
      end

      def status_only(status, text)
        Response.new(status: status, headers: { "Content-Type" => "text/plain" }, body: "#{text}\n")
      end

      def log(text)
        @log&.puts("nabu-mcp: #{text}")
      end
    end
  end
end
