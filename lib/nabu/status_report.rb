# frozen_string_literal: true

require "time"

module Nabu
  # Renders `nabu status`. The DEFAULT is the COMPACT v2 (P40-s, owner-designed):
  # one dense row per registered row, GROUPED BY KIND (modules → shelves →
  # sources). Each row is
  #
  #     slug   col2   [MARK]   holdings   MM-DD HH:MM   +A ~U -W !E
  #
  # where col2 FUSES kind + enablement + cadence (`module` | `shelf` | bare
  # `a`/`m`/`f` for an ENABLED source | `off(a)`/`off(m)`/`off(f)` when
  # disabled — the word "source" never prints); the liveness cell is SILENT
  # when healthy/implied and prints a MARK only for exceptions (`OLD(Nd)`,
  # `DOWN`, `?REPROBE`, `UNPROBED`); holdings is one fused, humanized,
  # right-aligned column (`1.4K/395K` docs/passages, a single humanized number
  # for entry-/shelf-shaped rows, `—` never-synced, nothing for modules); the
  # stamp drops the clock past 24h and the year in the current year; and the
  # delta zero-suppresses (nothing when all four are zero).
  #
  # The DETAIL lives behind `nabu status <source>` (a full labeled block, incl.
  # healthy liveness, exact thousands-separated counts, license class, errors)
  # and `nabu status --long` (the same extended detail as a labeled table for
  # every row). Pure string building over the registry plus (optionally) the
  # catalog db and the history ledger, so it is unit-testable without the CLI.
  module StatusReport
    module_function

    # An upstream-probe cache older than this reads as `?REPROBE` (v2) /
    # `stale` (detail): whatever the cached "ok" said, it is too old to base a
    # sync decision on. Two weeks tracks the weekly maintenance cadence
    # (docs/ops.md §1). A cached BEHIND stays loud regardless (an alarm does
    # not go stale), and an already-indeterminate verdict keeps its age.
    STALE_AFTER_DAYS = 14

    # The kind groups, in the owner's render order (P39-0).
    GROUP_ORDER = %w[module shelf source].freeze

    # A source's cadence letter (P39-0/P40-s): a=auto, m=manual, f=frozen.
    CADENCE_LETTER = { "auto" => "a", "manual" => "m", "frozen" => "f" }.freeze

    # The cadence spelled out for the detail views.
    CADENCE_WORD = { "auto" => "auto", "manual" => "manual", "frozen" => "frozen" }.freeze

    # Pre-computed COMPACT column widths (global, so alignment is stable across
    # groups) plus the per-slug mark/holdings maps and the db/ledger handles.
    Layout = Data.define(:slug_w, :col2_w, :mark_w, :holdings_w, :marks, :holdings, :db, :ledger)
    private_constant :Layout

    # Pre-computed LONG-table column widths + per-slug label/count/license maps.
    LongLayout = Data.define(:slug_w, :enable_w, :kind_w, :up_w, :counts_w, :license_w,
                             :labels, :counts, :licenses, :db, :ledger)
    private_constant :LongLayout

    # `nabu status` (COMPACT v2 default) / `nabu status --long` (labeled detail
    # table). Rows are GROUPED BY KIND (modules → shelves → sources) with global
    # column widths so alignment holds across the groups.
    def render(registry:, db:, ledger:, long: false)
      return "No sources registered." if registry.empty?
      return render_long(registry: registry, db: db, ledger: ledger) if long

      layout = layout_for(registry, db, ledger)
      grouped_entries(registry).map { |entry| render_entry(entry, layout) }.join("\n")
    end

    # `status --axis` (P35-1): the SAME compact rows as #render, grouped under
    # the research axes (config/axes.yml) instead of by kind. +axes+ is the
    # pre-resolved, ordered Axis list; +tag_note+ the once-stated tag-semantics
    # line. Column widths are global across every source, so alignment holds.
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

    # `nabu status <source>`: the full labeled detail block for ONE row — kind,
    # enabled, cadence spelled out, liveness INCLUDING healthy states, exact
    # thousands-separated counts, license class, full timestamp, full delta,
    # last-run status. Returns nil for an unregistered slug (the CLI owns the
    # not-found error, mirroring `list SOURCE`).
    def render_source(registry:, db:, ledger:, slug:)
      entry = registry[slug]
      return nil if entry.nil?

      source = db && Store::Source.first(slug: slug)
      lines = ["#{slug}  (#{entry_name(entry)})"]
      lines << detail_line("kind", entry.kind)
      lines << detail_line("enabled", enabled_word(entry))
      lines << detail_line("cadence", cadence_word(entry))
      lines << detail_line("liveness", liveness_detail(entry, db, ledger))
      count_pairs(entry, source).each { |label, value| lines << detail_line(label, group_thousands(value)) }
      lines << detail_line("license", license_class(entry, source))
      lines << detail_line("last sync", last_run_detail(slug, ledger))
      lines << detail_line("status", run_status_word(slug, ledger))
      lines.join("\n")
    end

    # Entries reordered into the kind groups (modules, shelves, sources); each
    # group keeps registration order within it.
    def grouped_entries(registry)
      entries = registry.each_source.to_a
      GROUP_ORDER.flat_map { |kind| entries.select { |entry| entry.kind == kind } }
    end

    # -- COMPACT v2 --------------------------------------------------------------

    def layout_for(registry, db, ledger)
      entries = registry.each_source.to_a
      cache = probe_cache(ledger)
      marks = {}
      holdings = {}
      if db
        entries.each do |entry|
          code, age = upstream_verdict(entry, cache[entry.slug], ledger)
          marks[entry.slug] = liveness_mark(code, age) || ""
          holdings[entry.slug] = holdings_compact(entry, Store::Source.first(slug: entry.slug))
        end
      end
      Layout.new(
        slug_w: entries.map { |entry| entry.slug.length }.max,
        col2_w: entries.map { |entry| col2(entry).length }.max,
        mark_w: marks.values.map(&:length).max || 0,
        holdings_w: holdings.values.map(&:length).max || 0,
        marks: marks, holdings: holdings, db: db, ledger: ledger
      )
    end

    def render_entry(entry, layout)
      head = "#{entry.slug.ljust(layout.slug_w)}  #{col2(entry).ljust(layout.col2_w)}"
      return "#{head}  no database (run nabu sync)" if layout.db.nil?

      cells = [head]
      cells << layout.marks[entry.slug].ljust(layout.mark_w) if layout.mark_w.positive?
      cells << layout.holdings[entry.slug].rjust(layout.holdings_w) if layout.holdings_w.positive?
      cells << last_run_compact(entry.slug, layout.ledger)
      cells.join("  ")
    end

    # col2 (P40-s): kind fused with enablement + cadence. A shelf reads
    # `shelf`, a module `module` (enablement + cadence are moot). A SOURCE
    # reads a BARE cadence letter when enabled (the unmarked default) or
    # `off(letter)` when disabled — the word "source" never prints.
    def col2(entry)
      return entry.kind unless entry.source?

      letter = CADENCE_LETTER.fetch(entry.sync_policy, "?")
      entry.enabled ? letter : "off(#{letter})"
    end

    # The COMPACT liveness MARK, or nil when the row is SILENT (healthy or
    # structurally implied). The exception vocabulary, mapped from every real
    # verdict code (P40-s):
    #   :module :local :frozen :ok        → nil (silent)
    #   :behind                           → OLD(Nd)   (upstream moved past our pin)
    #   :stale :reprobe                   → ?REPROBE  (a verdict too old/answered to trust)
    #   :indeterminate                    → DOWN      (probed, no usable verdict)
    #   :unprobed :unprobed_synced        → UNPROBED  (a live upstream never probed)
    def liveness_mark(code, age)
      case code
      when :module, :local, :frozen, :ok then nil
      when :behind then "OLD(#{age}d)"
      when :stale, :reprobe then "?REPROBE"
      when :indeterminate then "DOWN"
      when :unprobed, :unprobed_synced then "UNPROBED"
      end
    end

    # The fused, humanized, right-aligned holdings cell (P40-s). A corpus reads
    # `docs/passages`; an entry-/shelf-shaped row a single humanized number;
    # a never-synced corpus/dictionary `—`; a module nothing.
    def holdings_compact(entry, source)
      return "" if entry.feature_module?

      case content_kind(entry)
      when :dictionary then source.nil? ? "—" : humanize(dictionary_entry_count(source))
      when :language then humanize(language_record_count)
      when :notes then humanize(urn_note_count)
      when :source then humanize(source_record_count)
      else
        return "—" if source.nil?

        counts = corpus_counts(source)
        "#{humanize(counts.fetch(:docs))}/#{humanize(counts.fetch(:passages))}"
      end
    end

    # Humanize a count (P40-s, the owner's approved rule): under 1000 verbatim;
    # otherwise K/M with ONE decimal ONLY when the leading digit is single
    # (1.4K, 16K, 3.0M). Rounding is half-up in integer tenths (no float drift);
    # a value that rounds up to ten units drops the decimal (9950 → 10K), and a
    # sub-1M value that rounds to 1000K stays K-tier (999949 → 1000K).
    def humanize(count)
      return count.to_s if count < 1000

      div, suffix = count >= 1_000_000 ? [1_000_000, "M"] : [1_000, "K"]
      tenths = ((count * 10) + (div / 2)) / div # nearest tenth-of-a-unit, integer math
      if tenths < 100 # under ten units → single leading digit → one decimal
        "#{tenths / 10}.#{tenths % 10}#{suffix}"
      else
        "#{(tenths + 5) / 10}#{suffix}" # ten+ units → whole number
      end
    end

    # The bare compact stamp + zero-suppressed delta (P40-s). A non-succeeded
    # run keeps its status word INLINE so errors show on the row.
    def last_run_compact(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never" if run.nil?

      parts = [timestamp(run.finished_at || run.started_at)]
      delta = delta_compact(run)
      parts << delta unless delta.empty?
      parts << run.status unless run.status == "succeeded"
      parts.join(" ")
    end

    # `MM-DD HH:MM`; the clock is dropped when the sync is older than 24h; the
    # year is prefixed only when it is not the current year (P40-s).
    def timestamp(at)
      time = at.is_a?(Time) ? at : Time.parse(at.to_s)
      now = Time.now
      stamp = time.strftime((now - time) < 86_400 ? "%m-%d %H:%M" : "%m-%d")
      time.year == now.year ? stamp : "#{time.year}-#{stamp}"
    end

    # Zero-suppressed delta: only the non-zero components (`+1418 !27`); the
    # empty string when all four are zero (the caller prints nothing).
    def delta_compact(run)
      parts = []
      parts << "+#{run.added}" if run.added.nonzero?
      parts << "~#{run.updated}" if run.updated.nonzero?
      parts << "-#{run.withdrawn_count}" if run.withdrawn_count.nonzero?
      parts << "!#{run.errored}" if run.errored.nonzero?
      parts.join(" ")
    end

    # -- LONG detail table -------------------------------------------------------

    # `nabu status --long`: the extended detail for EVERY row as a labeled
    # table (enablement spelled with cadence, kind, the verbose up= label incl.
    # healthy states, exact thousands-separated labeled counts, license class,
    # and the full stamp + full delta with zeros + status). Grouped by kind.
    def render_long(registry:, db:, ledger:)
      layout = long_layout_for(registry, db, ledger)
      grouped_entries(registry).map { |entry| render_entry_long(entry, layout) }.join("\n")
    end

    def long_layout_for(registry, db, ledger)
      entries = registry.each_source.to_a
      cache = probe_cache(ledger)
      labels = {}
      counts = {}
      licenses = {}
      if db
        entries.each do |entry|
          source = Store::Source.first(slug: entry.slug)
          code, age = upstream_verdict(entry, cache[entry.slug], ledger)
          labels[entry.slug] = "up=#{upstream_label(code, age)}"
          counts[entry.slug] = counts_long(entry, source)
          licenses[entry.slug] = license_class(entry, source)
        end
      end
      LongLayout.new(
        slug_w: entries.map { |entry| entry.slug.length }.max,
        enable_w: entries.map { |entry| enablement(entry).length }.max,
        kind_w: entries.map { |entry| entry.kind.length }.max,
        up_w: labels.values.map(&:length).max || 0,
        counts_w: counts.values.map(&:length).max || 0,
        license_w: licenses.values.map(&:length).max || 0,
        labels: labels, counts: counts, licenses: licenses, db: db, ledger: ledger
      )
    end

    def render_entry_long(entry, layout)
      head = "#{entry.slug.ljust(layout.slug_w)}  #{enablement(entry).ljust(layout.enable_w)}  " \
             "#{entry.kind.ljust(layout.kind_w)}"
      return "#{head}  no database (run nabu sync)" if layout.db.nil?

      cells = [head, layout.labels[entry.slug].ljust(layout.up_w)]
      cells << layout.counts[entry.slug].ljust(layout.counts_w) if layout.counts_w.positive?
      cells << layout.licenses[entry.slug].ljust(layout.license_w) if layout.license_w.positive?
      cells << last_run_long(entry.slug, layout.ledger)
      cells.join("  ")
    end

    # col2 for the LONG table (P39-0): enablement fused with cadence — a source
    # reads on(a)/off(m)/…; a shelf or module reads "-" (enablement is moot).
    def enablement(entry)
      return "-" unless entry.source?

      "#{entry.enabled ? 'on' : 'off'}(#{CADENCE_LETTER.fetch(entry.sync_policy, '?')})"
    end

    # The labeled, thousands-separated counts string for the long table (empty
    # for a module — it mints no catalog rows).
    def counts_long(entry, source)
      count_pairs(entry, source).map { |label, value| "#{label}=#{group_thousands(value)}" }.join(" ")
    end

    # The full stamp + full delta (all four components, zeros included) + a
    # non-succeeded status word, for the long table.
    def last_run_long(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never synced" if run.nil?

      at = (run.finished_at || run.started_at).strftime("%Y-%m-%d %H:%M")
      delta = "(+#{run.added} ~#{run.updated} -#{run.withdrawn_count} !#{run.errored})"
      run.status == "succeeded" ? "#{at} #{delta}" : "#{at} #{delta} #{run.status}"
    end

    # -- detail block (status <source>) ------------------------------------------

    def entry_name(entry)
      entry.manifest.name
    rescue Nabu::Error
      entry.slug
    end

    def detail_line(label, value)
      "  #{"#{label}:".ljust(11)}#{value}"
    end

    def enabled_word(entry)
      return "n/a (#{entry.kind})" unless entry.source?

      entry.enabled ? "yes" : "no"
    end

    def cadence_word(entry)
      return "local (no upstream)" if entry.shelf?
      return "n/a (module)" if entry.feature_module?

      CADENCE_WORD.fetch(entry.sync_policy, entry.sync_policy)
    end

    # The detail liveness cell: the verbose up= label INCLUDING healthy states.
    def liveness_detail(entry, db, ledger)
      return "no database (run nabu sync)" if db.nil?

      code, age = upstream_verdict(entry, probe_cache(ledger)[entry.slug], ledger)
      "up=#{upstream_label(code, age)}"
    end

    def last_run_detail(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      return "never synced" if run.nil?

      at = (run.finished_at || run.started_at).strftime("%Y-%m-%d %H:%M")
      "#{at}  (+#{run.added} ~#{run.updated} -#{run.withdrawn_count} !#{run.errored})"
    end

    def run_status_word(slug, ledger)
      return "no run history" if ledger.nil?

      run = Store::Run.where(source_slug: slug).order(Sequel.desc(:id)).first
      run ? run.status : "never synced"
    end

    # -- the upstream verdict (shared by compact marks + detail labels) ---------

    # The upstream freshness verdict as [code, age_or_nil]. Structural verdicts
    # come from KIND/policy (no probe); the live ones from the ledger's probe
    # cache — never a live probe. Codes:
    #   :module :local :frozen         structural (silent in compact)
    #   :ok :stale :behind             a CURRENT/BEHIND probe (age = probe age)
    #   :reprobe                       BEHIND but synced since (verdict answered)
    #   :indeterminate                 probed, drift not computable (age = probe age)
    #   :unprobed_synced               never probed but a last successful sync (age)
    #   :unprobed                      never probed AND never synced
    def upstream_verdict(entry, probe, ledger)
      return [:module, nil] if entry.feature_module?
      return [:local, nil] if entry.shelf?
      return [:frozen, nil] if entry.sync_policy == "frozen"
      return unprobed_verdict(entry, ledger) if probe.nil?

      age = age_days(probe.checked_at)
      case probe.drift
      when "behind"
        synced_since?(entry.slug, probe.checked_at, ledger) ? [:reprobe, nil] : [:behind, age]
      when "current"
        age > STALE_AFTER_DAYS ? [:stale, age] : [:ok, age]
      else
        [:indeterminate, age]
      end
    end

    def unprobed_verdict(entry, ledger)
      age = last_contact_age(entry.slug, ledger)
      age ? [:unprobed_synced, age] : [:unprobed, nil]
    end

    # The verbose up= label (detail + long views): the P39-0 vocabulary, so the
    # detail views keep the healthy verdicts the compact view falls silent on.
    def upstream_label(code, age)
      case code
      when :module then "module"
      when :local then "local"
      when :frozen then "frozen"
      when :ok then "ok(#{age}d)"
      when :stale then "stale(#{age}d)"
      when :behind then "BEHIND(#{age}d)"
      when :reprobe then "?(re-probe)"
      when :indeterminate, :unprobed_synced then "?(#{age}d)"
      when :unprobed then "?(unprobed)"
      end
    end

    # The age of the last successful sync (its last contact with upstream).
    # Runs live in the ledger (P7-1), so this must not touch Store::Run when
    # there is no ledger: no ledger means no known contact.
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
    # or the ledger predates the source_probes table.
    def probe_cache(ledger)
      return {} unless ledger&.table_exists?(:source_probes)

      Store::Probe.all.to_h { |probe| [probe.source_slug, probe] }
    end

    # -- counts (shared shape for compact/long/detail) --------------------------

    # The ordered [label, exact_count] pairs for this row, shaped by the
    # source's content_kind (P11-10). Empty for a module. A passage source
    # keeps the docs/passages pair, plus retired when non-zero (P5-2).
    def count_pairs(entry, source)
      return [] if entry.feature_module?

      case content_kind(entry)
      when :dictionary then [["entries", source.nil? ? 0 : dictionary_entry_count(source)]]
      when :language then [["records", language_record_count]]
      when :notes then [["notes", urn_note_count]]
      when :source then [["records", source_record_count]]
      else passage_pairs(source)
      end
    end

    def passage_pairs(source)
      return [["docs", 0], ["pass", 0]] if source.nil?

      counts = corpus_counts(source)
      pairs = [["docs", counts.fetch(:docs)], ["pass", counts.fetch(:passages)]]
      pairs << ["retired", counts.fetch(:retired)] if counts.fetch(:retired).positive?
      pairs
    end

    # P42-0: a passage source's holdings come from the source_stats derived
    # table (maintained at write time — the doctrine: read time is for
    # probes), never from a per-invocation aggregate over 60M+ passages. A
    # catalog predating migration 019 falls back to the live aggregates with
    # identical semantics.
    def corpus_counts(source)
      db = Store::Source.db
      if Store::SourceStats.available?(db)
        stats = Store::SourceStats.fetch(db, source.id)
        { docs: stats.fetch(:live_documents), passages: stats.fetch(:live_passages),
          retired: stats.fetch(:retired_documents) }
      else
        live = Store::Document.where(source_id: source.id, withdrawn: false)
        { docs: live.count, passages: passage_count(source.id),
          retired: live.where(retired_upstream: true).count }
      end
    end

    def content_kind(entry)
      entry.adapter_class.content_kind
    rescue Nabu::Error
      :passages
    end

    def license_class(entry, source)
      return source.license_class if source&.license_class

      entry.manifest.license_class
    rescue Nabu::Error
      "?"
    end

    # Thousands-separated integer for the labeled views (12000090 → 12,000,090).
    def group_thousands(count)
      count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    # Derived rows in language_records (the local-language shelf is their only
    # writer). A catalog predating migration 014 reads 0, honestly.
    def language_record_count
      db = Store::LanguageRecord.db
      return 0 unless db&.table_exists?(:language_records)

      Store::LanguageRecord.count
    end

    def urn_note_count
      db = Store::UrnNote.db
      return 0 unless db&.table_exists?(:urn_notes)

      Store::UrnNote.count
    end

    def source_record_count
      db = Store::SourceRecord.db
      return 0 unless db&.table_exists?(:source_records)

      Store::SourceRecord.count
    end

    # Deliberately LIVE, not source_stats (P42-0 measured decision): the
    # entry tables total ~1.3M rows against 62.8M passages, and this indexed
    # count is milliseconds — stats cover the corpus-mass grain only.
    def dictionary_entry_count(source)
      return 0 if source.nil?

      dictionaries = Store::Dictionary.where(source_id: source.id).select(:id)
      Store::DictionaryEntry.where(dictionary_id: dictionaries, withdrawn: false).count
    end

    # The pre-019 fallback for #corpus_counts (and nothing else).
    def passage_count(source_id)
      live_documents = Store::Document.where(source_id: source_id, withdrawn: false).select(:id)
      Store::Passage.where(withdrawn: false).where(document_id: live_documents).count
    end
  end
end
