# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  # The fetch-grant gate (P42-r1, owner-approved design 2026-07-23). Some
  # sources carry a right to fetch that a PUBLIC clone of nabu does NOT convey:
  # StarLing (a written e-mail grant to this project's author), the future TITUS
  # Avestan (granted personally, non-commercial + credit). A future user's
  # `nabu sync starling` must not scrape under someone else's grant — so a
  # `grant_required: true` source demands an explicit, recorded acknowledgment
  # before its first fetch.
  #
  # This is DISTINCT from ordinary public-license obligations: CC BY-NC-SA needs
  # no gate (the license-class machinery already carries attribution and the
  # no-redistribution posture). The gate criterion is solely "the right to FETCH
  # is not conveyed by a public license."
  #
  # The gate is an ON-RAMP, not just a wall: every refusal and every batch skip
  # points at the request scaffold (the registry's request_hint — whom to ask
  # and what to promise), so a new user learns how to obtain their own grant.
  #
  # This class owns the POLICY and the ledger record; the interactive IO (the
  # TTY prompt, reading the typed word) lives in the CLI, which drives this gate.
  class GrantGate
    # The word a user must type to acknowledge (not y/n — a deliberate,
    # unambiguous act). Compared case-insensitively after stripping.
    TYPED_WORD = "granted"

    # +ledger+ is the history ledger (Store::Ledger db handle) — nil is
    # tolerated as "no ledger yet". +grants_path+ (P70, the derivability
    # contract) is config/grants.yml — the SOURCE OF TRUTH: record! writes
    # it first (the ledger row is a historical mirror), acknowledged?
    # reads it first (ledger fallback covers pre-P70 boxes), and a restore
    # from canonical+config alone keeps every grant.
    def initialize(ledger:, grants_path: nil)
      @ledger = ledger
      @grants_path = grants_path
    end

    # Has this source's grant already been acknowledged? Config file first
    # (the P70 truth), then the ledger (pre-P70 fallback; guards on the
    # table's existence so a pre-P42 ledger reads as un-acknowledged).
    def acknowledged?(slug)
      return true if config_grants.any? { |g| g["source"] == slug }
      return false unless @ledger.respond_to?(:table_exists?) && @ledger.table_exists?(:grant_acknowledgments)

      @ledger[:grant_acknowledgments].where(source_slug: slug).any?
    end

    def config_grants
      return [] unless @grants_path && File.file?(@grants_path)

      (YAML.safe_load_file(@grants_path) || {}).fetch("grants", nil) || []
    end

    # A grant-required source with no recorded acknowledgment — the condition
    # both the interactive gate and the batch skip test for.
    def blocked?(entry)
      entry.grant_required? && !acknowledged?(entry.slug)
    end

    # Record the acknowledgment durably (idempotent — a second call is a no-op,
    # so re-syncing never appends). +how+ is "typed" (interactive prompt) or
    # "flag" (scripted --grant-acknowledged). +terms+ is the grant terms shown,
    # frozen verbatim as the audit of what was agreed to.
    def record!(slug:, terms:, how:)
      return if acknowledged?(slug)

      # P70: the config file is written FIRST — the durable record; the
      # ledger row is the historical mirror.
      if @grants_path
        grants = config_grants + [{ "source" => slug, "how" => how,
                                    "at" => Time.now.strftime("%Y-%m-%d"), "terms" => terms }]
        FileUtils.mkdir_p(File.dirname(@grants_path))
        File.write(@grants_path,
                   "# config/grants.yml — the owner's recorded grant agreements (P70:\n" \
                   "# the source of truth; the ledger row is a historical mirror).\n" +
                   YAML.dump("grants" => grants))
      end
      @ledger[:grant_acknowledgments].insert(
        source_slug: slug, terms: terms, how: how, created_at: Time.now
      )
    end

    # Does a typed answer acknowledge the grant? (case-insensitive, stripped —
    # the deliberate word, never y/n).
    def self.acknowledged_answer?(answer)
      answer.to_s.strip.casecmp?(TYPED_WORD)
    end

    # The review block the gate prints before the prompt AND embeds in every
    # refusal/skip — the terms verbatim, who granted them and when, the
    # criterion, and the request scaffold. Pure text so it is testable without
    # any IO. +entry+ carries the Grant block (grant_required guaranteed).
    def self.notice(entry)
      grant = entry.grant
      <<~TEXT.chomp
        #{entry.slug}: fetch requires a GRANT this public clone does not carry.
          terms: #{grant.terms}
          granted by #{grant.grantor}, #{grant.date} · #{grant.thread}
          This right was granted personally to the project author — you need your own.
          request your own: #{grant.request_hint}
      TEXT
    end

    # The one line the prompt shows to solicit the typed word.
    def self.prompt_line(entry)
      "  type `#{TYPED_WORD}` to acknowledge these terms and sync #{entry.slug} (anything else aborts):"
    end

    # The explanatory abort text for a refusal or a no-TTY environment: the full
    # notice plus the scaffold pointer — the on-ramp, never a bare wall.
    def self.abort_message(entry)
      "#{notice(entry)}\n  " \
        "Nothing was fetched. Re-run `nabu sync #{entry.slug}` on a terminal to review and type " \
        "`#{TYPED_WORD}`, or pass --grant-acknowledged once you hold your own grant."
    end

    # The one honest line a batch (`sync --all`, axis expansion) prints for a
    # grant-blocked source it skips — never a mid-batch prompt.
    def self.skip_line(slug)
      "skipped (grant required): #{slug} — run `nabu sync #{slug}` to review the terms"
    end
  end
end
