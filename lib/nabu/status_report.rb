# frozen_string_literal: true

require "time"

module Nabu
  # Renders `nabu status`: one aligned plain-text line per registered source —
  # enabled/disabled, sync policy, live document/passage counts (withdrawn
  # excluded), and the last run's outcome. Pure string building over the
  # registry plus (optionally) the catalog db and the history ledger (P7-1:
  # runs live in the ledger, slug-keyed), so it is unit-testable without the
  # CLI. A nil db means "not built yet"; a nil ledger means "no history yet"
  # (fresh machine) and the run column degrades honestly.
  module StatusReport
    module_function

    # An upstream-probe cache older than this reads as `stale`: whatever the
    # cached "ok" said, it is too old to base a sync decision on. Two weeks
    # tracks the weekly maintenance cadence (docs/ops.md §1) — miss a cycle and
    # the verdict is no longer trustworthy. A cached BEHIND stays loud
    # regardless (an alarm does not go stale), and an already-unknown `?` just
    # keeps showing its age.
    STALE_AFTER_DAYS = 14

    def render(registry:, db:, ledger:)
      return "No sources registered." if registry.empty?

      width = registry.each_source.map { |entry| entry.slug.length }.max
      cache = probe_cache(ledger)
      cells = registry.each_source.to_h do |entry|
        [entry.slug, upstream_cell(entry, cache[entry.slug], ledger: ledger)]
      end
      up_w = cells.values.map(&:length).max
      registry.each_source.map { |entry| render_entry(entry, db, ledger, width, cells[entry.slug], up_w) }.join("\n")
    end

    def render_entry(entry, db, ledger, width, up_cell, up_w)
      head = "#{entry.slug.ljust(width)}  #{state(entry.enabled).ljust(3)}  #{entry.sync_policy.ljust(6)}"
      return "#{head}  no database (run nabu sync)" if db.nil?

      # Enabled comes from the REGISTRY, always (P23-3b): the registry is
      # authoritative for enablement (sources.yml owner flips), and the db
      # row only mirrors it at that source's next sync — rendering the row
      # value showed stale off/on for flipped-but-unsynced sources
      # (2026-07-14: mw/iecor/liv/edl). Every line here IS a registry entry,
      # so there is no orphan case to fall back for (an unregistered catalog
      # source is `nabu list`'s loud NOT IN REGISTRY story).
      source = Store::Source.first(slug: entry.slug)
      # up= (the upstream-drift column, P14-12) sits right after policy: policy
      # is HOW we pull, up= is WHETHER upstream moved since we last did — read
      # together they answer "should I sync this now?". counts/last_run stay the
      # trailing free-form descriptors.
      "#{entry.slug.ljust(width)}  #{state(entry.enabled).ljust(3)}  #{entry.sync_policy.ljust(6)}  " \
        "#{up_cell.ljust(up_w)}  #{counts_fragment(entry, source)}  #{last_run(entry.slug, ledger)}"
    end

    # The compact upstream-drift cell rendered from the ledger's probe cache
    # (P14-12) — never a live probe. Vocabulary honours terseness: BEHIND is
    # loud, ok is quiet, the age is always shown so a decision is informed.
    #   up=frozen      frozen-policy source (no probe expected; cache ignored)
    #   up=local       local-policy shelf (no upstream exists; cache ignored)
    #   up=?(unprobed) no cached probe yet — run `nabu status --remote`
    #                  ("never" read as never-SYNCED — owner defect 2026-07-13)
    #   up=BEHIND(Nd)  upstream moved past our pin (loud; staleness irrelevant)
    #   up=ok(Nd)      current as of a recent probe
    #   up=stale(Nd)   was "ok" but the probe is older than STALE_AFTER_DAYS
    #   up=?(Nd)       drift indeterminate (never synced / unreachable / multi)
    def upstream_cell(entry, probe, ledger: nil)
      return "up=frozen" if entry.sync_policy == "frozen"
      return "up=local" if entry.sync_policy == "local"
      return "up=?(unprobed)" if probe.nil?

      age = age_days(probe.checked_at)
      case probe.drift
      when "behind"
        # A BEHIND verdict older than the source's last ok sync is answered
        # noise (owner defect 2026-07-14: re-synced perseus-greek still read
        # BEHIND from a 15-hour-old cache). The verdict cannot be trusted
        # either way after a sync — say so and point at the re-probe.
        return "up=?(re-probe)" if synced_since?(entry.slug, probe.checked_at, ledger)

        "up=BEHIND(#{age}d)"
      when "current" then age > STALE_AFTER_DAYS ? "up=stale(#{age}d)" : "up=ok(#{age}d)"
      else "up=?(#{age}d)"
      end
    end

    # True when the source has a SUCCEEDED run newer than the probe.
    def synced_since?(slug, checked_at, ledger)
      return false unless ledger&.table_exists?(:runs)

      probe_time = checked_at.is_a?(Time) ? checked_at : Time.parse(checked_at.to_s)
      last_ok = ledger[:runs].where(source_slug: slug, status: %w[ok succeeded])
                             .order(Sequel.desc(:id)).get(:finished_at)
      return false unless last_ok

      (last_ok.is_a?(Time) ? last_ok : Time.parse(last_ok.to_s)) > probe_time
    end

    def age_days(checked_at)
      time = checked_at.is_a?(Time) ? checked_at : Time.parse(checked_at.to_s)
      [((Time.now - time) / 86_400).floor, 0].max
    end

    # { slug => Store::Probe } from the ledger. Empty when there is no ledger
    # (fresh machine) or the ledger predates the source_probes table (a
    # read-only status before any health --remote migrated it) — every source
    # then renders up=?(unprobed), honestly.
    def probe_cache(ledger)
      return {} unless ledger&.table_exists?(:source_probes)

      Store::Probe.all.to_h { |probe| [probe.source_slug, probe] }
    end

    # The count fragment of the row, shaped by the source's content_kind
    # (P11-10). A dictionary source's content is entries, not docs/passages —
    # rendering docs=0 passages=0 for a 168k-entry lexicon was a misleading
    # zero (the P11-7 missed-surface class). Passage sources keep the
    # docs/passages/retired triple.
    def counts_fragment(entry, source)
      return "entries=#{dictionary_entry_count(source)}" if dictionary?(entry)
      return "records=#{language_record_count}" if language?(entry)
      return "notes=#{urn_note_count}" if notes?(entry)
      return "records=#{source_record_count}" if source_shelf?(entry)
      return "docs=0 pass=0" if source.nil?

      live = Store::Document.where(source_id: source.id, withdrawn: false)
      # retired (upstream-scrapped, attic-kept — P5-2) documents are live and
      # inside docs=; the count appears only when non-zero (owner UX ruling
      # 2026-07-11: compact rows, zero-noise suppressed).
      fragment = "docs=#{live.count} pass=#{passage_count(source.id)}"
      retired = live.where(retired_upstream: true).count
      retired.positive? ? "#{fragment} retired=#{retired}" : fragment
    end

    def dictionary?(entry)
      content_kind(entry) == :dictionary
    end

    # A language dossier shelf's content is per-language records (P19-1) —
    # docs=0 pass=0 would be the misleading-zero class P11-10 closed.
    def language?(entry)
      content_kind(entry) == :language
    end

    # The owner-notes shelf's content is per-urn notes (P24-1) — the same
    # misleading-zero rule.
    def notes?(entry)
      content_kind(entry) == :notes
    end

    # The source-dossier shelf's twin (P24-0): per-source records.
    def source_shelf?(entry)
      content_kind(entry) == :source
    end

    def content_kind(entry)
      entry.adapter_class.content_kind
    rescue Nabu::Error
      # A broken/unknown adapter class is not this renderer's problem to
      # raise on; treat it as a plain passage source so status still prints.
      :passages
    end

    # Derived rows in language_records (the local-language shelf is their
    # only writer). A catalog predating migration 014 reads 0, honestly.
    def language_record_count
      db = Store::LanguageRecord.db
      return 0 unless db&.table_exists?(:language_records)

      Store::LanguageRecord.count
    end

    # Derived rows in urn_notes (the local-notes shelf is their only
    # writer). A catalog predating migration 015 reads 0, honestly.
    def urn_note_count
      db = Store::UrnNote.db
      return 0 unless db&.table_exists?(:urn_notes)

      Store::UrnNote.count
    end

    # Derived rows in source_records (the local-source shelf is their only
    # writer). A catalog predating migration 016 reads 0, honestly.
    def source_record_count
      db = Store::SourceRecord.db
      return 0 unless db&.table_exists?(:source_records)

      Store::SourceRecord.count
    end

    # Live dictionary entries owned by this source (across all its
    # dictionaries). Zero for an unsynced source (no rows yet) — honest, not
    # misleading, because the row shape already says "entries".
    def dictionary_entry_count(source)
      return 0 if source.nil?

      dictionaries = Store::Dictionary.where(source_id: source.id).select(:id)
      Store::DictionaryEntry.where(dictionary_id: dictionaries, withdrawn: false).count
    end

    def passage_count(source_id)
      live_documents = Store::Document.where(source_id: source_id, withdrawn: false).select(:id)
      Store::Passage.where(withdrawn: false).where(document_id: live_documents).count
    end

    # The latest run of ANY kind — a rebuild replay is honest "last activity"
    # here (trend queries elsewhere filter kind=sync; status just reports).
    def last_run(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never synced" if run.nil?

      at = (run.finished_at || run.started_at).strftime("%Y-%m-%d %H:%M")
      "last #{at} #{status_word(run.status)} " \
        "(+#{run.added} ~#{run.updated} -#{run.withdrawn_count} !#{run.errored})"
    end

    # Compact status vocabulary (owner UX ruling 2026-07-11): the common case
    # reads "ok"; anything else keeps its loud full word.
    def status_word(status)
      status == "succeeded" ? "ok" : status
    end

    def state(enabled)
      enabled ? "on" : "off"
    end
  end
end
