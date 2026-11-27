# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "uri"

require_relative "../errors"
require_relative "../config"

module Nabu
  module Ops
    # `rake "mail:fetch[EMAIL_ID,FILTER]"` — saves one message's
    # attachments into the local intake folder (.docs/inbox/) over JMAP
    # (RFC 8620 core, RFC 8621 mail), byte-exact, so a binary delivery (a
    # corpus archive) reaches the box without hand-saving.
    #
    # READ-ONLY against the mailbox by construction: exactly three kinds
    # of call — the Session GET, one Email/get, one blob download per
    # attachment. No /set, /copy, /import or upload method exists here.
    #
    # The token (settings overlay key email.download_token) travels only
    # in the Authorization header; no message, line or error carries it.
    #
    # Per attachment: the name is reduced to a safe basename (no path
    # separators, no leading dots); the downloaded byte count must equal
    # the size JMAP reported; an existing file of the same name is
    # "already present" when its sha256 matches and REFUSED (both shas
    # printed, nothing written) when it differs. Any failure → report not
    # ok (the task exits 1); the other attachments still run.
    class MailFetch
      SESSION_URL = "https://api.fastmail.com/jmap/session"
      CORE = "urn:ietf:params:jmap:core"
      MAIL = "urn:ietf:params:jmap:mail"
      TOKEN_KEY = %w[email download_token].freeze
      BODY_PROPERTIES = %w[blobId name type size].freeze
      DEFAULT_TYPE = "application/octet-stream"
      REDIRECTS = 3

      class Error < Nabu::Error; end

      # One attachment's outcome; +ok+ false counts as a failure.
      Outcome = Data.define(:name, :ok, :line)

      Report = Data.define(:outcomes) do
        def failures = outcomes.count { |o| !o.ok }
        def ok? = failures.zero?
      end

      # The download token from the settings overlay under +local_dir+;
      # absent = one line naming the key and the file (never a value).
      def self.token!(local_dir:)
        token = Nabu::Config.local_settings(local_dir).dig(*TOKEN_KEY)
        return token.to_s.strip unless token.to_s.strip.empty?

        raise Error, "no #{TOKEN_KEY.join('.')} in #{Nabu::Config.local_settings_path(local_dir)} " \
                     "(a Fastmail API token of type JMAP, read-only scope)"
      end

      # +http+ is a callable (method, url, headers, body) → [status
      # Integer, body String]; the default is Net::HTTP (WebMock
      # intercepts it in tests). +log+ receives the per-file lines.
      def initialize(token:, inbox_dir:, http: self.class.method(:http_call), log: $stdout)
        @token = token
        @inbox = inbox_dir
        @http = http
        @log = log
      end

      def run(email_id, filter: nil)
        session = session!
        account = session.dig("primaryAccounts", MAIL) or raise Error, "the session names no primary mail account"
        attachments = attachments!(session.fetch("apiUrl"), account, email_id)
        chosen = select(attachments, filter)
        if chosen.empty?
          line = attachments.empty? ? "the message has no attachments" : "no attachment matches #{filter.inspect}"
          @log.puts("  FAIL  #{line}")
          return Report.new(outcomes: [Outcome.new(name: nil, ok: false, line: line)])
        end

        FileUtils.mkdir_p(@inbox)
        Report.new(outcomes: chosen.map { |part| save(session.fetch("downloadUrl"), account, part) })
      end

      # A basename safe to create under the inbox: the last segment after
      # either separator, control characters and leading dots stripped.
      def self.safe_name(name, fallback:)
        base = name.to_s.split(%r{[/\\]}).last.to_s.gsub(/[[:cntrl:]]/, "").sub(/\A[.\s]+/, "").strip
        base.empty? ? fallback : base
      end

      # RFC 6570 simple expansion: everything outside the unreserved set
      # percent-encoded (so a name's "/" or space cannot reshape the URL).
      def self.expand(template, values)
        template.gsub(/\{(\w+)\}/) do
          values.fetch(Regexp.last_match(1), "").to_s.b.gsub(/[^A-Za-z0-9\-._~]/) { |c| format("%%%02X", c.ord) }
        end
      end

      def self.http_call(method, url, headers, body = nil, limit: REDIRECTS)
        uri = URI(url)
        request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri, headers)
        request.body = body if body
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                                           open_timeout: 15, read_timeout: 120) do |http|
          http.request(request)
        end
        if response.is_a?(Net::HTTPRedirection) && method == :get && limit.positive? && response["location"]
          target = URI.join(url, response["location"])
          # The bearer token never follows a redirect off the original host.
          headers = headers.except("Authorization") unless target.host == uri.host
          return http_call(:get, target.to_s, headers, limit: limit - 1)
        end
        [Integer(response.code, 10), response.body.to_s.b]
      end

      private

      def auth = { "Authorization" => "Bearer #{@token}" }

      def call(method, url, body = nil, headers: {})
        @http.call(method, url, auth.merge(headers), body)
      rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError,
             Net::HTTPBadResponse => e
        raise Error, "#{URI(url).host} unreachable (#{e.class.name.split('::').last})"
      end

      def session!
        status, body = call(:get, SESSION_URL)
        raise Error, "the JMAP session was refused (HTTP #{status}) — check the token's type and scope" if
          [401, 403].include?(status)
        raise Error, "the JMAP session answered HTTP #{status}" unless (200..299).cover?(status)

        parse(body, "the session")
      end

      def attachments!(api_url, account, email_id)
        request = { "using" => [CORE, MAIL],
                    "methodCalls" => [["Email/get", { "accountId" => account, "ids" => [email_id],
                                                      "properties" => ["attachments"],
                                                      "bodyProperties" => BODY_PROPERTIES }, "0"]] }
        status, body = call(:post, api_url, JSON.generate(request), headers: { "Content-Type" => "application/json" })
        raise Error, "Email/get answered HTTP #{status}" unless (200..299).cover?(status)

        name, args, = parse(body, "the Email/get response").fetch("methodResponses", []).first
        raise Error, "Email/get failed: #{args&.fetch('type', 'unknown error')}" unless name == "Email/get"

        message = Array(args["list"]).find { |email| email["id"] == email_id }
        raise Error, "email #{email_id} not found in the account" if message.nil?

        Array(message["attachments"])
      end

      def select(attachments, filter)
        named = attachments.each_with_index.map do |part, i|
          part.merge("safe_name" => self.class.safe_name(part["name"], fallback: "attachment-#{i + 1}"))
        end
        return named if filter.to_s.strip.empty?

        named.select { |part| part["safe_name"].downcase.include?(filter.strip.downcase) }
      end

      def save(template, account, part)
        name = part["safe_name"]
        url = self.class.expand(template, "accountId" => account, "blobId" => part["blobId"], "name" => name,
                                          "type" => part["type"] || DEFAULT_TYPE)
        status, bytes = call(:get, url)
        return outcome(name, false, "download answered HTTP #{status}") unless (200..299).cover?(status)

        sha = Digest::SHA256.hexdigest(bytes)
        unless part["size"].nil? || bytes.bytesize == part["size"]
          return outcome(name, false, "size mismatch: got #{bytes.bytesize} bytes, JMAP reported #{part['size']}")
        end

        write(name, bytes, sha)
      rescue Error => e
        outcome(name, false, e.message)
      end

      def write(name, bytes, sha)
        path = File.join(@inbox, name)
        summary = "#{bytes.bytesize} bytes · sha256 #{sha}"
        if File.exist?(path)
          existing = Digest::SHA256.file(path).hexdigest
          return outcome(name, true, "#{summary} · already present") if existing == sha

          return outcome(name, false, "REFUSED — a different file exists (existing sha256 #{existing}, " \
                                      "incoming sha256 #{sha}); skipped")
        end

        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::BINARY) { |f| f.write(bytes) }
        outcome(name, true, "#{summary} · saved")
      end

      def outcome(name, passed, detail)
        line = "#{name} · #{detail}"
        @log.puts("  #{passed ? 'OK  ' : 'FAIL'}  #{line}")
        Outcome.new(name: name, ok: passed, line: line)
      end

      def parse(body, what)
        data = JSON.parse(body)
        raise Error, "#{what} is not a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError
        raise Error, "#{what} is not JSON"
      end
    end
  end
end
