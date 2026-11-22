# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_status tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      STATUS_DESCRIPTION =
        "Coverage of the local nabu corpus: per-source document/passage counts and last-sync " \
        "recency, passage counts by language and by license class, index state, and what is " \
        "excluded by default (research_private/restricted). Call this to interpret an empty " \
        "search — is the language, source, or period even ingested here? — before concluding " \
        "a text is unattested. Takes no arguments."

      STATUS_SCHEMA = { type: "object", properties: {}, additionalProperties: false }.freeze

      private

      def status(_args)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)

        census = corpus_census(catalog)
        json(
          sources: source_rows(catalog),
          languages: census.fetch(:languages),
          license_classes: census.fetch(:license_classes),
          excluded_by_default: census.fetch(:excluded_by_default),
          # Dictionary entries stay LIVE deliberately (P42-r2): the entry
          # tables are shelf-bounded (~1.3M rows against 62.8M passages,
          # measured 2.6s) — source_stats covers the corpus-mass grain only.
          totals: census.fetch(:totals)
                        .merge(dictionary_entries: dictionary_entry_counts(catalog).values.sum),
          index: index_state,
          note: "counts are live passages/documents (withdrawn excluded); " \
                "research_private/restricted material is excluded from these counts and " \
                "from every tool by default (see excluded_by_default). each source's " \
                "upstream.* fields are the CACHED verdict of the last `nabu health --remote` " \
                "/ `nabu status --remote` run (drift = has upstream moved past our pin; " \
                "checked_at = when) — MCP never probes upstreams live"
        )
      end

      # -- status internals -----------------------------------------------------------

      def source_rows(catalog)
        entries = dictionary_entry_counts(catalog)
        descriptions = source_descriptions(catalog)
        probes = probe_cache
        stats = Store::SourceStats.available?(catalog)
        catalog[:sources].order(:slug).to_a.select { |source| enabled_row?(source[:slug]) }.map do |source|
          holdings = source_holdings(catalog, source[:id], stats: stats)
          row = { slug: source[:slug], enabled: enabled_field(source),
                  license_class: source[:license_class],
                  documents: holdings[:documents],
                  passages: holdings[:passages],
                  # P11-10: a dictionary source's content is entries, not docs/passages;
                  # surfacing the entry count here stops the reference shelf (lexica,
                  # 168k entries) from reading as an empty docs=0 passages=0 source.
                  entries: entries[source[:id]] || 0,
                  last_sync_at: source[:last_sync_at]&.to_s,
                  upstream: upstream_field(probes[source[:slug]]) }
          # P24-0: the source's dossier description rides by default — the
          # owner's own library metadata is useful context for a model
          # deciding where to search. Absent dossier/table = absent key.
          description = descriptions[source[:slug]]
          row[:description] = description if description
          row
        end
      end

      # A source's live document/passage holdings (P42-7). When the
      # source_stats derived table is present (maintained at write time) the
      # counts are READ from it — retiring the O(corpus) live passage
      # aggregation this casually-callable surface otherwise ran per
      # invocation (measured minutes at 62.8M rows). A catalog predating
      # migration 019 falls back to the live per-source aggregate with
      # BYTE-IDENTICAL semantics (the reader-swap pattern of
      # StatusReport#corpus_counts): live_documents excludes withdrawn, and
      # live_passages is live-on-live (neither the passage nor its document
      # withdrawn) — exactly what the fallback join counts.
      def source_holdings(catalog, source_id, stats:)
        if stats
          row = Store::SourceStats.fetch(catalog, source_id)
          return { documents: row.fetch(:live_documents), passages: row.fetch(:live_passages) }
        end

        live_docs = catalog[:documents].where(source_id: source_id, withdrawn: false)
        { documents: live_docs.count,
          passages: catalog[:passages].where(withdrawn: false)
                                      .where(document_id: live_docs.select(:id)).count }
      end

      # { slug => description } from the derived source_records
      # (canonical/local-source dossiers, P24-0); {} on a catalog predating
      # migration 015 or before the owner seeded the shelf.
      def source_descriptions(catalog)
        return {} unless catalog.table_exists?(:source_records)

        catalog[:source_records].where(kind: "description").select_hash(:slug, :body)
      end

      # Is +slug+ shown in nabu_status's default sources array (P44-r3b)? The
      # ENABLED set, plus the owner's own shelves (always) and any catalog
      # orphan the registry does not know (never silently dropped). A nil
      # enabled set (unconfigured caller) shows everything, the pre-r3b default.
      def enabled_row?(slug)
        return true if @enabled_slugs.nil?
        return true if @enabled_slugs.include?(slug)

        entry = @registry && @registry[slug]
        entry.nil? || entry.shelf?
      end

      # Registry truth for registered slugs (class note at @registry), the db
      # value for orphans / an unconfigured registry.
      def enabled_field(source)
        entry = @registry && @registry[source[:slug]]
        return entry.wired unless entry.nil?

        [true, 1].include?(source[:enabled])
      end

      # { slug => source_probes row } from the read-only ledger (P14-12), or {}
      # when the ledger is unconfigured/absent or predates the source_probes
      # table (guarded). This is a cache read — never a live probe.
      def probe_cache
        ledger = resolve(@ledger)
        return {} unless ledger&.table_exists?(:source_probes)

        ledger[:source_probes].to_hash(:source_slug)
      end

      # The cached upstream-drift verdict for one source, or the honest
      # never_probed placeholder when this source has no cache row yet.
      def upstream_field(row)
        return { drift: "never_probed", checked_at: nil } unless row

        { drift: row[:drift], license: row[:license],
          checked_at: row[:checked_at]&.to_s, detail: row[:detail] }
      end

      # Live dictionary-entry counts keyed by owning source id — empty when this
      # catalog has no reference shelf yet (the dictionary tables land with the
      # first lexica sync, P11-4).
      def dictionary_entry_counts(catalog)
        return {} unless catalog.table_exists?(:dictionaries) && catalog.table_exists?(:dictionary_entries)

        catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .group_and_count(Sequel[:dictionaries][:source_id])
          .to_h { |row| [row[:source_id], row[:count]] }
      end

      # P42-r2: the corpus-wide census behind status (totals, languages,
      # license classes). When the source_stats derived table is present the
      # whole thing is COMPOSED from it plus ONE live query bounded by
      # license-overridden documents — the previous live path ran four
      # O(corpus) aggregates over the passages⋈documents⋈sources join per
      # invocation (measured 2026-07-23 at 62.8M passages: ~70s per GROUP BY,
      # 72.8s per license scan; the whole payload ~5 minutes). A catalog
      # predating migration 019 falls back to the live aggregates with
      # identical semantics (the P42-0 reader convention,
      # StatusReport#corpus_counts).
      def corpus_census(catalog)
        Store::SourceStats.available?(catalog) ? stats_census(catalog) : live_census(catalog)
      end

      # The pre-019 fallback: the original four live aggregates, unchanged.
      def live_census(catalog)
        { languages: language_counts(catalog),
          license_classes: license_counts(catalog, excluded: false),
          excluded_by_default: license_counts(catalog, excluded: true),
          totals: { documents: visible_documents(catalog).count,
                    passages: visible_passages(catalog).count } }
      end

      # The stats-composed census. Doc grain is EXACT from stats alone: per
      # source, live docs minus the stored override doc counts carry the
      # source's license_class; each override class carries its stored count.
      # Passage grain starts from the same base — all of a source's live
      # passages and their per-language split attributed to the source's
      # class — and then applies the override CORRECTION:
      # license_overrides_json stores doc counts only (no passage counts, no
      # language split), so one live query bounded by overridden live docs
      # (probe-scale: 9,725 docs / ~290K passages against 62.8M, measured
      # sub-second) moves each overridden document's live passages from the
      # source-class bucket to the override-class bucket, per language.
      def stats_census(catalog)
        classes = catalog[:sources].select_hash(:id, :license_class)
        documents = Hash.new(0) # {effective class => live doc count}
        passages = Hash.new { |by_class, klass| by_class[klass] = Hash.new(0) } # {class => {language|nil => n}}
        attribute_stats_base(catalog, classes, documents, passages)
        apply_override_correction(catalog, classes, passages)
        compose_census(documents, passages)
      end

      # Base attribution: every stats row lands whole on its source's class.
      # NULL-language passages carry no child row (the 019 rule: NULL rides
      # only in the parent total), so the nil bucket is the parent total
      # minus the named-language rows — matching the live GROUP BY, where a
      # NULL passages.language groups under a nil key.
      def attribute_stats_base(catalog, classes, documents, passages)
        by_language = catalog[Store::SourceStats::LANG_TABLE]
                      .select_hash_groups(:source_id, %i[language passages])
        catalog[Store::SourceStats::TABLE].each do |row|
          klass = classes.fetch(row[:source_id])
          overrides = JSON.parse(row[:license_overrides_json])
          documents[klass] += row[:live_documents] - overrides.values.sum
          overrides.each { |override, count| documents[override] += count }
          named = 0
          (by_language[row[:source_id]] || []).each do |language, count|
            passages[klass][language] += count
            named += count
          end
          passages[klass][nil] += row[:live_passages] - named
        end
      end

      # The O(overrides) correction: live passages of live overridden docs,
      # grouped by (source, override class, passage language). The withdrawn
      # filter is the SAME two-level rule the stats derivation applies (doc
      # withdrawn in the id-subquery, passage withdrawn in the outer scope),
      # so the moved counts match exactly what the base attribution included.
      # SHAPE (the P41-r2 lesson, measured live at 62.8M): grouping through
      # the passages⋈documents join made the planner drive from the passages
      # side — 64.5s. Scoping join-free (an id-subquery membership filter,
      # grouped by document only, class attribution folded in Ruby off the
      # tiny doc map) plans as per-document index probes: 7.8s, the honest
      # floor for touching ~290K scattered rows at read time. Retiring even
      # that cost means write-time override splits in source_stats
      # (migration 020) — a flagged P43 candidate, not a read-path trick.
      def apply_override_correction(catalog, classes, passages)
        overridden = catalog[:documents].exclude(license_override: nil).where(withdrawn: false)
        doc_map = overridden.select_hash(:id, %i[source_id license_override])
        catalog[:passages]
          .where(withdrawn: false, document_id: overridden.select(:id))
          .group(:document_id, :language)
          .select_group(:document_id, :language)
          .select_append { count.function.*.as(:n) }
          .each do |row|
            source_id, override = doc_map.fetch(row[:document_id])
            passages[classes.fetch(source_id)][row[:language]] -= row[:n]
            passages[override][row[:language]] += row[:n]
          end
      end

      # Fold the composed buckets into the frozen payload shape, mirroring
      # what the live GROUP BYs emit: only classes/languages actually holding
      # a live passage appear — a bucket emptied by the correction (every one
      # of a class's passages overridden away) must not surface as a zero,
      # because the live path never groups an empty class into existence.
      def compose_census(documents, passages)
        visible = passages.except(*EXCLUDED_LICENSE_CLASSES)
        languages = Hash.new(0)
        visible.each_value { |langs| langs.each { |language, count| languages[language] += count } }
        { languages: languages.select { |_language, count| count.positive? },
          license_classes: class_passage_totals(passages, excluded: false),
          excluded_by_default: class_passage_totals(passages, excluded: true),
          totals: { documents: documents.sum { |klass, count| EXCLUDED_LICENSE_CLASSES.include?(klass) ? 0 : count },
                    passages: visible.each_value.sum { |langs| langs.each_value.sum } } }
      end

      def class_passage_totals(passages, excluded:)
        passages.filter_map do |klass, langs|
          next unless EXCLUDED_LICENSE_CLASSES.include?(klass) == excluded

          total = langs.each_value.sum
          [klass, total] if total.positive?
        end.to_h
      end

      # Split note: also read by nabu_search's coverage hint; kept with its primary user.
      def language_counts(catalog)
        visible_passages(catalog)
          .group_and_count(Sequel[:passages][:language])
          .to_h { |row| [row[:language], row[:count]] }
      end

      # Live passage counts grouped by effective license class — the visible
      # classes, or (excluded: true) the default-hidden ones, counted honestly
      # (aggregate numbers only; no urns, titles, or text).
      def license_counts(catalog, excluded:)
        dataset = live_passages(catalog)
        dataset = if excluded
                    dataset.where(license_expr => EXCLUDED_LICENSE_CLASSES)
                  else
                    dataset.exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
                  end
        dataset.group_and_count(license_expr.as(:license_class))
               .to_h { |row| [row[:license_class], row[:count]] }
      end

      def index_state
        fulltext = resolve(@fulltext)
        fulltext&.table_exists?(Store::Indexer::TABLE) ? "present" : "unavailable (rebuilding or not built)"
      end

      # Live (two-level visibility) passages, all license classes.
      def live_passages(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
      end

      # Live AND default-visible (excluded classes filtered out).
      def visible_passages(catalog)
        live_passages(catalog).exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
      end

      def visible_documents(catalog)
        catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:withdrawn] => false)
          .exclude(license_expr => EXCLUDED_LICENSE_CLASSES)
      end

      # Split note: also read by the exclusion gate and nabu_search; kept with its primary user.
      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end
    end
  end
end
