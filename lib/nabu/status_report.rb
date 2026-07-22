# frozen_string_literal: true

require "time"

module Nabu
  # Renders `nabu status`: one aligned plain-text row per registered row,
  # GROUPED BY KIND (P39-0) in the order modules → shelves → sources. Each row
  # fuses enablement with cadence (on(a)/off(m)/…), names its kind, reports up=
  # freshness (structural for shelves/modules/frozen, probe-derived otherwise),
  # kind-appropriate holdings (docs=/pass=, entries=, records=, notes=), then
  # the last-sync stamp + (+A ~U -W !E) delta with any non-ok status inline.
  # Pure string building over the registry plus (optionally) the catalog db and
  # the history ledger (P7-1: runs live in the ledger, slug-keyed), so it is
  # unit-testable without the CLI. A nil db means "not built yet"; a nil ledger
  # means "no history yet" (fresh machine) and the run column degrades honestly.
  module StatusReport
    module_function

    # An upstream-probe cache older than this reads as `stale`: whatever the
    # cached "ok" said, it is too old to base a sync decision on. Two weeks
    # tracks the weekly maintenance cadence (docs/ops.md §1) — miss a cycle and
    # the verdict is no longer trustworthy. A cached BEHIND stays loud
    # regardless (an alarm does not go stale), and an already-unknown `?` just
    # keeps showing its age.
    STALE_AFTER_DAYS = 14

    # The kind groups, in the owner's render order (P39-0): modules, shelves,
    # then sources.
    GROUP_ORDER = %w[module shelf source].freeze

    # The pre-computed column widths (global, so alignment is stable across
    # groups) plus the probe-cell map and the db/ledger handles a row needs.
    Layout = Data.define(:slug_w, :enable_w, :kind_w, :up_w, :cells, :db, :ledger)
    private_constant :Layout

    # `nabu status`: one aligned row per registered row (P39-0), GROUPED BY
    # KIND in the order modules → shelves → sources. Each row fuses enablement
    # with cadence (on(a)/off(m)/…), names its kind, reports up= freshness,
    # then kind-appropriate holdings + the last-sync stamp/delta. Column widths
    # are global so alignment holds across the groups.
    def render(registry:, db:, ledger:)
      return "No sources registered." if registry.empty?

      layout = layout_for(registry, db, ledger)
      grouped_entries(registry).map { |entry| render_entry(entry, layout) }.join("\n")
    end

    # `status --axis` (P35-1): the SAME rows as #render, grouped under the
    # research axes (config/axes.yml) instead of by kind. Each axis leads with
    # its verbatim persona line and then its member rows, indented — a source
    # under each axis it serves (dual-tagging, D35). Column widths are global
    # across every registered source, so alignment stays stable across groups.
    # +axes+ is the pre-resolved, ordered Axis list (the CLI owns resolution +
    # the unknown-axis error); +tag_note+ is the once-stated tag-semantics line.
    def render_grouped(registry:, db:, ledger:, axes:, tag_note:)
      return "No sources registered." if registry.empty?

      layout = layout_for(registry, db, ledger)
      lines = [tag_note]
      axes.each do |axis|
        lines << ""
        lines << "#{axis.name} — #{axis.persona}"
        members = registry.each_source.select { |entry| entry.axes.include?(axis.name) }
        if members.empty?
          lines << "  (no sources on this axis)"
        else
          members.each { |entry| lines << "  #{render_entry(entry, layout)}" }
        end
      end
      lines.join("\n")
    end

    # Entries reordered into the kind groups (modules, shelves, sources); each
    # group keeps registration order within it.
    def grouped_entries(registry)
      entries = registry.each_source.to_a
      GROUP_ORDER.flat_map { |kind| entries.select { |entry| entry.kind == kind } }
    end

    def layout_for(registry, db, ledger)
      entries = registry.each_source.to_a
      cache = probe_cache(ledger)
      # The up= cell needs the catalog (last-contact age for unprobed rows), so
      # compute cells only when a db is present; without one every row degrades
      # to "no database" before the column is used.
      cells = db.nil? ? {} : entries.to_h { |e| [e.slug, upstream_cell(e, cache[e.slug], ledger: ledger)] }
      Layout.new(
        slug_w: entries.map { |entry| entry.slug.length }.max,
        enable_w: entries.map { |entry| enablement(entry).length }.max,
        kind_w: entries.map { |entry| entry.kind.length }.max,
        up_w: cells.values.map(&:length).max || 0,
        cells: cells, db: db, ledger: ledger
      )
    end

    def render_entry(entry, layout)
      head = "#{entry.slug.ljust(layout.slug_w)}  #{enablement(entry).ljust(layout.enable_w)}  " \
             "#{entry.kind.ljust(layout.kind_w)}"
      return "#{head}  no database (run nabu sync)" if layout.db.nil?

      # Enabled comes from the REGISTRY, always (P23-3b): the registry is
      # authoritative for enablement (sources.yml owner flips), and the db row
      # only mirrors it at that source's next sync — rendering the row value
      # showed stale off/on for flipped-but-unsynced sources (2026-07-14:
      # mw/iecor/liv/edl). Every line here IS a registry entry, so there is no
      # orphan case (an unregistered catalog source is `nabu list`'s loud story).
      source = Store::Source.first(slug: entry.slug)
      up = layout.cells[entry.slug].ljust(layout.up_w)
      # Compact (owner spec): drop empty holdings (modules) so the stamp closes
      # the row without a blank column.
      [head, up, holdings_fragment(entry, source), last_run(entry.slug, layout.ledger)]
        .reject { |cell| cell.nil? || cell.empty? }.join("  ")
    end

    # col2 (P39-0): enablement fused with cadence. A kind: source reads
    # on(a)/on(m)/on(f) or off(...) — a=auto, m=manual, f=frozen; a shelf or
    # module reads "-" (enablement is moot: a shelf always serves its local
    # data, a module mints nothing to serve).
    CADENCE_LETTER = { "auto" => "a", "manual" => "m", "frozen" => "f" }.freeze

    def enablement(entry)
      return "-" unless entry.source?

      "#{entry.enabled ? 'on' : 'off'}(#{CADENCE_LETTER.fetch(entry.sync_policy, '?')})"
    end

    # The compact up= freshness cell (P14-12/P39-0). The structural verdicts
    # come from KIND/policy (no probe, no cache); the live ones from the
    # ledger's probe cache — never a live probe.
    #   up=module      a kind: module row (machinery; no upstream to serve)
    #   up=local       a kind: shelf memory shelf (no upstream exists)
    #   up=frozen      a frozen-cadence source (immutable snapshot; cache ignored)
    #   up=BEHIND(Nd)  upstream moved past our pin (loud; staleness irrelevant)
    #   up=ok(Nd)      current as of a recent probe
    #   up=stale(Nd)   was "ok" but the probe is older than STALE_AFTER_DAYS
    #   up=?(Nd)       probed-indeterminate, OR unprobed with a known last
    #                  contact — N is the age of the last successful sync
    #   up=?(unprobed) never probed AND never synced — genuinely unknown
    def upstream_cell(entry, probe, ledger: nil)
      return "up=module" if entry.feature_module?
      return "up=local" if entry.shelf?
      return "up=frozen" if entry.sync_policy == "frozen"
      return unprobed_cell(entry, ledger) if probe.nil?

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

    # An unprobed live upstream still gets an informed cell: the age of the
    # last SUCCESSFUL sync (its last contact with upstream), up=?(Nd) — real
    # data, never an invented probe. A source that has never synced falls back
    # to up=?(unprobed) (owner spec, "up=?(Nd) for manual sources unprobed
    # since N").
    def unprobed_cell(entry, ledger)
      age = last_contact_age(entry.slug, ledger)
      age ? "up=?(#{age}d)" : "up=?(unprobed)"
    end

    # The age of the last successful sync (its last contact with upstream).
    # Runs live in the ledger (P7-1: Store::Run is bound to the ledger
    # connection), so — like #last_run — this must not touch Store::Run when
    # there is no ledger (a stale binding would raise): no ledger means no
    # known contact, so the cell stays up=?(unprobed).
    def last_contact_age(slug, ledger)
      return nil if ledger.nil?

      run = Store::Run.where(source_slug: slug, status: %w[succeeded ok]).order(Sequel.desc(:id)).first
      run && age_days(run.finished_at || run.started_at)
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

    # The kind-appropriate holdings label (P39-0). A machinery module mints no
    # catalog rows, so it has NO holdings — the empty cell is dropped from the
    # row entirely.
    def holdings_fragment(entry, source)
      return "" if entry.feature_module?

      counts_fragment(entry, source)
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
    # Compact (P39-0, owner spec): the bare stamp + delta, dropping the noise
    # "last "/"ok" tokens; a non-succeeded status stays loud and INLINE so
    # errors show on the row.
    def last_run(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never synced" if run.nil?

      at = (run.finished_at || run.started_at).strftime("%Y-%m-%d %H:%M")
      delta = "(+#{run.added} ~#{run.updated} -#{run.withdrawn_count} !#{run.errored})"
      run.status == "succeeded" ? "#{at} #{delta}" : "#{at} #{delta} #{run.status}"
    end
  end
end
