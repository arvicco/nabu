# frozen_string_literal: true

require "fileutils"
require "time"
require "yaml"

require_relative "errors"

module Nabu
  # The credentials seam: stored upstream credentials for gated member
  # areas (the live case: the TITUS members area, HTTP Basic auth with a
  # password that ROTATES with emailed notice).
  #
  # == The one home
  #
  # local/config/credentials.yml (Config#credentials_path) — instance
  # config, never the public repo, never db/. Written ONLY through the
  # `nabu creds set` gateway (the local/config write-through law); the file
  # is created mode 600 and every write re-asserts 600. Shape:
  #
  #   credentials:
  #     titus:
  #       user: <member user>
  #       password: <secret>          # or token: <secret>
  #       updated_at: "2026-10-12T09:00:00Z"
  #
  # == Who reads it
  #
  # A source opts in with `credentials: <name>` on its sources.yml entry;
  # SyncRunner resolves the entry through Credentials.for BEFORE any
  # network and refuses (Missing) when nothing is stored, then hands the
  # Entry to the adapter, whose fetch arm injects it (TitusFetch: Basic
  # auth). An upstream 401 to sent credentials is Rejected — the rotation
  # signal.
  #
  # == Redaction
  #
  # An Entry's inspect / to_s / pretty_print never carry the password or
  # token; error messages name the credential, never its value. Nothing
  # here logs. `nabu creds list` shows names and ages only, and there is
  # deliberately no `creds show`.
  class Credentials
    FILENAME = "credentials.yml"

    # The credential name shape — a short registry-style key.
    NAME_SHAPE = /\A[a-z0-9][a-z0-9_-]*\z/

    REDACTED = "[REDACTED]"

    # A stored credential is absent: the sync-start refusal (before any
    # network). A FetchError so it aborts the one source's sync like any
    # other fetch failure.
    class Missing < FetchError
      def initialize(name)
        super(Credentials.required_message(name))
      end
    end

    # The upstream answered 401 to the credentials we sent — most likely the
    # rotated password.
    class Rejected < FetchError
      def initialize(name)
        super(Credentials.rejected_message(name))
      end
    end

    # One stored credential. +password+ or +token+ carries the secret (the
    # other is nil); +updated_at+ is when the secret last CHANGED.
    Entry = Data.define(:name, :user, :password, :token, :updated_at) do
      # The RFC 7617 Authorization header value (user:password, base64).
      def basic_auth_header
        "Basic #{["#{user}:#{password}"].pack('m0')}"
      end

      def inspect
        "#<Nabu::Credentials::Entry name=#{name.inspect} user=#{user.inspect} " \
          "#{token.nil? ? 'password' : 'token'}=#{REDACTED} updated_at=#{updated_at.inspect}>"
      end
      alias_method :to_s, :inspect

      def pretty_print(printer)
        printer.text(inspect)
      end
    end

    def self.required_message(name)
      "credentials required: run bin/nabu creds set #{name}"
    end

    def self.rejected_message(name)
      "#{name} credentials rejected (rotated?) — run bin/nabu creds set #{name}"
    end

    # The stored Entry for +name+, or nil. +path+ defaults to this
    # instance's home (Config#credentials_path).
    def self.for(name, path: Config.load.credentials_path)
      new(path: path)[name]
    end

    def initialize(path:)
      @path = path
    end

    attr_reader :path

    # Never the file's content — only where it lives.
    def inspect = "#<Nabu::Credentials path=#{@path.inspect}>"

    def [](name)
      record = records[name.to_s]
      record && entry(name.to_s, record)
    end

    # [[name, updated_at]] sorted by name — no secret ever leaves here.
    def list
      records.keys.sort.map { |name| [name, parse_time(records[name]["updated_at"])] }
    end

    # Store +name+'s credential. Returns :stored (new), :updated (a changed
    # value — updated_at moves) or :unchanged (identical — the file is not
    # rewritten, so the recorded age stays the age of the secret).
    def set!(name, user:, password: nil, token: nil, now: Time.now)
      validate!(name, password: password, token: token)
      record = { "user" => blank_to_nil(user), "password" => blank_to_nil(password),
                 "token" => blank_to_nil(token) }.compact
      all = records
      previous = all[name]
      return :unchanged if previous && previous.except("updated_at") == record

      all[name] = record.merge("updated_at" => now.utc.iso8601)
      write!(all)
      previous ? :updated : :stored
    end

    private

    def validate!(name, password:, token:)
      unless name.is_a?(String) && name.match?(NAME_SHAPE)
        raise ValidationError, "credential name must match #{NAME_SHAPE.inspect}, got #{name.inspect}"
      end
      return unless blank_to_nil(password).nil? && blank_to_nil(token).nil?

      raise ValidationError, "credential #{name}: a password or a token is required"
    end

    def blank_to_nil(value)
      value.nil? || value.to_s.strip.empty? ? nil : value.to_s
    end

    def records
      return {} unless File.file?(@path)

      data = YAML.safe_load_file(@path) || {}
      data.is_a?(Hash) ? (data["credentials"] || {}) : {}
    end

    def entry(name, record)
      Entry.new(name: name, user: record["user"], password: record["password"], token: record["token"],
                updated_at: parse_time(record["updated_at"]))
    end

    def parse_time(value)
      value.nil? ? nil : Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    # tmp (born 600) + chmod + rename: the secret is never on disk with a
    # wider mode, and a rewrite re-asserts 600 whatever the old file had.
    def write!(all)
      FileUtils.mkdir_p(File.dirname(@path))
      body = "# local/config/credentials.yml — stored upstream credentials (mode 600).\n" \
             "# Written only by `bin/nabu creds set`; never commit, never print.\n" +
             YAML.dump("credentials" => all.sort.to_h)
      tmp = "#{@path}.tmp"
      FileUtils.rm_f(tmp)
      File.write(tmp, body, perm: 0o600)
      File.chmod(0o600, tmp)
      File.rename(tmp, @path)
    end
  end
end
