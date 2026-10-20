# frozen_string_literal: true

# Nabu::CLI — the `nabu creds` subcommand family (CredsCLI). Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # `nabu creds` — the ONE write gateway of local/config/credentials.yml
  # (Nabu::Credentials; the local/config write-through law). Gated
  # upstreams (the TITUS members area: HTTP Basic auth, a password that
  # rotates with emailed notice) read their stored credential through the
  # seam at sync time. Secrets never echo, never print, never enter shell
  # history; `list` shows names and ages only, and there is deliberately
  # no `show`.
  class CredsCLI < Thor
    namespace "creds"

    desc "set NAME", "Store (or rotate) the credential NAME — prompts with the secret hidden, or --stdin"
    long_desc <<~HELP, wrap: false
      Stores the user + password for NAME in local/config/credentials.yml
      (created mode 600, kept 600). Interactive by default: the user is
      asked, the password is read with echo OFF — nothing reaches the shell
      history. With --stdin, reads two lines (user, then password) for a
      scripted set, e.g. from a password manager's CLI:

        <emit the user line and the password line> | bin/nabu creds set titus --stdin

      Re-setting identical values is a no-op ("unchanged" — the recorded
      age stays the secret's age); a changed password is "updated". A
      source names its credential with `credentials: NAME` in
      config/sources.yml; its sync refuses until the credential exists.

      Examples:
        bin/nabu creds set titus
        bin/nabu creds list
    HELP
    option :stdin, type: :boolean, default: false,
                   desc: "Read `user\\npassword\\n` from stdin instead of prompting"
    def set(name)
      user, password = options[:stdin] ? read_stdin_pair : prompt_pair(name)
      store = Nabu::Credentials.new(path: Nabu::Config.load.credentials_path)
      status = store.set!(name, user: user, password: password)
      say "#{status}  #{name} (#{store.path}, mode 600)"
    rescue Nabu::Error => e
      raise Thor::Error, "creds set: #{e.message}"
    end

    desc "list", "Stored credential names and their ages (never a value)"
    def list
      config = Nabu::Config.load
      stored = Nabu::Credentials.new(path: config.credentials_path).list
      say "no credentials stored (bin/nabu creds set NAME)" if stored.empty?
      stored.each { |name, updated_at| say "#{name}  #{age_line(updated_at)}" }
      missing_declared(config, stored.map(&:first)).each do |name, slugs|
        say "#{name}  MISSING — needed by #{slugs.join(', ')} (bin/nabu creds set #{name})", :yellow
      end
    end

    private

    def read_stdin_pair
      [$stdin.gets.to_s.chomp, $stdin.gets.to_s.chomp]
    end

    def prompt_pair(name)
      unless $stdin.tty?
        raise Thor::Error, "creds set: no terminal for the hidden prompt — pipe the user and password " \
                           "lines with --stdin"
      end

      # Both reads go straight to $stdin: Thor's ask buffers differently
      # under a pseudo-TTY (observed on the CI runner — the user ask
      # consumed nothing and the hidden read took the user line), and a
      # credential prompt must be deterministic everywhere.
      $stdout.print "#{name} user: "
      $stdout.flush
      user = $stdin.gets.to_s.chomp
      $stdout.print "#{name} password (hidden): "
      $stdout.flush
      password = $stdin.noecho(&:gets).to_s.chomp
      $stdout.puts # the hidden read leaves the cursor on the prompt line
      [user, password]
    end

    def age_line(updated_at)
      return "updated (unknown)" if updated_at.nil?

      days = ((Time.now - updated_at) / 86_400).floor
      ago = days.zero? ? "today" : "#{days} day#{'s' unless days == 1} ago"
      "updated #{updated_at.localtime.strftime('%Y-%m-%d')} (#{ago})"
    end

    # { name => [slugs] } for credentials the registry declares but this
    # box has not stored — the honest "what still needs a set" line.
    def missing_declared(config, stored_names)
      return {} unless File.file?(config.sources_path)

      registry = Nabu::SourceRegistry.load(config.sources_path)
      registry.each_source.reject { |entry| entry.credentials.nil? || stored_names.include?(entry.credentials) }
                          .group_by(&:credentials).transform_values { |entries| entries.map(&:slug) }
    end
  end
end
