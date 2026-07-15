# frozen_string_literal: true

require_relative "../normalize"
require_relative "catalog_join"

module Nabu
  module Query
    # `nabu list` (P22-1): the WHAT-IS-HELD read surface — the shelf census
    # (one row per source), one source's info/stats card, and the bounded
    # document/entry/collection enumerations. The sync-state sibling is
    # `nabu status` (StatusReport); this class never touches the registry or
    # the ledger — it reads only the catalog it is given (the query-object
    # contract: datasets injected, READ-only, no connections of its own).
    #
    # == Counting semantics (the status precedent)
    #
    # "Live" counts exclude withdrawn rows (a withdrawn document's passages
    # are not held content), exactly as StatusReport counts them; withdrawn
    # and retired-upstream counts are carried SEPARATELY so the stewardship
    # story stays visible (`--withdrawn` is the lens onto them). License mix
    # is the effective class per live document (override coalesced over the
    # source class — CatalogJoin's rule); a source with no live documents
    # reads as its declared class.
    #
    # == Collections (the urn-segment census)
    #
    # A manifest-collection shelf mints urns of the shape
    # urn:nabu:<slug>:<collection>:<rest> (local-library, architecture §16).
    # #collections censuses exactly that shape mechanically — a live document
    # urn under urn:nabu:<slug>: whose remainder still carries ≥ 2 segments
    # contributes its first segment — so any nabu-urn source with nested
    # segments reads honestly (ddbdp's series would census as collections),
    # and CTS shelves miss honestly (nil).
    class List
      # A caller-fixable problem (unknown source slug): the CLI turns the
      # message into a clean stderr line + exit 1 (the Random::Error pattern).
      class Error < Nabu::Error; end

      include CatalogJoin # license_expr + axis_exists (the shared join rules)

      # One census row (`nabu list`). +languages+ is the sorted union of live
      # passage languages and dictionary languages; +license_classes+ the
      # sorted effective-class mix.
      CensusRow = Data.define(:slug, :docs, :passages, :entries, :languages,
                              :license_classes, :withdrawn, :retired, :dossiers) do
        def initialize(dossiers: 0, **rest) = super
      end

      # One source's card (`nabu list SOURCE`). +languages+ maps language →
      # live passage count; +dictionaries+ lists DictionaryRow values;
      # +dated+ is a Dated (or nil when no axis rows); +facets+ FacetRow
      # values ([] when none); +collections+ {collection => doc count} or nil.
      Card = Data.define(:slug, :name, :adapter_class, :enabled, :license_text, :license_classes,
                         :docs, :passages, :entries, :withdrawn, :retired,
                         :languages, :dictionaries, :dated, :facets, :collections,
                         :dossiers, :record_kinds) do
        def initialize(dossiers: 0, record_kinds: {}, **rest) = super
      end
      Dated = Data.define(:docs, :min, :max)
      FacetRow = Data.define(:facet, :values, :docs)
      DictionaryRow = Data.define(:slug, :title, :language, :entries)

      # One enumeration page: the rows shown plus the HONEST total, so the
      # renderer can say "… N more — raise --limit".
      Page = Data.define(:rows, :total)
      DocRow = Data.define(:urn, :title, :language, :license_class, :withdrawn, :retired)
      # The dossier shelf's enumeration grain (language records, not documents).
      DossierRow = Data.define(:code, :name, :family)
      EntryRow = Data.define(:headword, :gloss, :dictionary_slug, :language)

      DEFAULT_LIMIT = 50
      # The language-dossier shelf holds language_records, not documents —
      # detected from the catalog itself (adapter_class), never the registry
      # (the query-object contract). Live gap 2026-07-15: 199 dossiers
      # rendered as "empty".
      LANGUAGE_ADAPTER = "Nabu::Adapters::LocalLanguage"

      def initialize(catalog:)
        @catalog = catalog
      end

      # The content census: one CensusRow per catalog source, slug order.
      def census
        docs = doc_counts
        passages = passage_counts
        entries = entry_counts
        langs = census_languages
        licenses = license_mix
        @catalog[:sources].order(:slug).select(:id, :slug, :license_class, :adapter_class).all.map do |source|
          id = source.fetch(:id)
          doc = docs.fetch(id, { docs: 0, withdrawn: 0, retired: 0 })
          CensusRow.new(
            slug: source.fetch(:slug), docs: doc.fetch(:docs), passages: passages.fetch(id, 0),
            entries: entries.fetch(id, 0),
            dossiers: language_grain?(source) ? dossier_count : 0,
            languages: ((langs[id] || []) + dictionary_languages(id)).uniq.sort,
            license_classes: licenses.fetch(id, [source.fetch(:license_class)]).sort,
            withdrawn: doc.fetch(:withdrawn), retired: doc.fetch(:retired)
          )
        end
      end

      # One source's card; unknown +slug+ raises Error naming the valid slugs.
      def card(slug)
        source = source_row!(slug)
        id = source.fetch(:id)
        doc = doc_counts.fetch(id, { docs: 0, withdrawn: 0, retired: 0 })
        Card.new(
          slug: slug, name: source.fetch(:name), adapter_class: source.fetch(:adapter_class),
          enabled: source.fetch(:enabled), license_text: source.fetch(:license),
          license_classes: license_mix.fetch(id, [source.fetch(:license_class)]).sort,
          docs: doc.fetch(:docs), passages: passage_counts.fetch(id, 0),
          entries: entry_counts.fetch(id, 0),
          withdrawn: doc.fetch(:withdrawn), retired: doc.fetch(:retired),
          languages: card_languages(id), dictionaries: dictionary_rows(id),
          dated: dated_coverage(id), facets: facet_summary(id), collections: collections(slug),
          dossiers: language_grain?(source) ? dossier_count : 0,
          record_kinds: language_grain?(source) ? record_kinds : {}
        )
      end

      # Enumerate the source's documents in urn order — withdrawn/retired rows
      # INCLUDED and flagged (this is the inspection lens; +withdrawn_only+
      # narrows to exactly them). +limit+ 0 = unlimited; Page#total is always
      # the filtered whole.
      def documents(slug, lang: nil, license: nil, withdrawn_only: false,
                    from: nil, to: nil, limit: DEFAULT_LIMIT, prefix: nil)
        source = source_row!(slug)
        if language_grain?(source)
          return dossiers(lang: lang, license: license, withdrawn_only: withdrawn_only,
                          from: from, to: to, limit: limit, prefix: prefix)
        end
        # The P22-1 verdict stands for document grain: urns are never folded,
        # so a prefix here is a named inapplicability, not a silent no-match.
        raise Error, "--prefix filters headwords and dossier codes — this shelf enumerates documents" if prefix

        dataset = @catalog[:documents]
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:sources][:slug] => slug)
        dataset = dataset.where(Sequel[:documents][:language] => lang) if lang
        dataset = dataset.where(license_expr => license) if license
        if withdrawn_only
          dataset = dataset.where(
            Sequel.expr(Sequel[:documents][:withdrawn] => true) |
            Sequel.expr(Sequel[:documents][:retired_upstream] => true)
          )
        end
        dataset = dataset.where(axis_exists(from: from, to: to, place: nil)) if from || to
        page(dataset.order(Sequel[:documents][:urn]), limit) { |row| build_doc_row(row) }
      end

      # Enumerate a dictionary source's live entries (headword + gloss) in
      # (dictionary, entry_id) order. nil when the source owns no dictionaries
      # (the CLI words the honest miss). +prefix+ filters headwords by FOLDED
      # prefix — the define contract: every Normalize.query_forms variant is
      # tried, so ASCII `bh` (and a quoted `*bʰ`) reach *bʰer-.
      def entries(slug, prefix: nil, lang: nil, limit: DEFAULT_LIMIT)
        source = source_row!(slug)
        return nil unless dictionary_source?(source.fetch(:id))

        dataset = @catalog[:dictionary_entries]
                  .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                  .where(Sequel[:dictionaries][:source_id] => source.fetch(:id),
                         Sequel[:dictionary_entries][:withdrawn] => false)
        dataset = dataset.where(Sequel[:dictionaries][:language] => lang) if lang
        dataset = dataset.where(prefix_expr(prefix)) if prefix
        dataset = dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
        page(dataset, limit) { |row| build_entry_row(row) }
      end

      # {collection => live document count} for urn:nabu:<slug>:<collection>:…
      # urns; nil when no urn carries a collection segment (CTS shelves, flat
      # local shelves) — the honest miss.
      def collections(slug)
        source_row!(slug)
        prefix = "urn:nabu:#{slug}:"
        urns = @catalog[:documents]
               .join(:sources, id: Sequel[:documents][:source_id])
               .where(Sequel[:sources][:slug] => slug, Sequel[:documents][:withdrawn] => false)
               .where(byte_prefix(Sequel[:documents][:urn], prefix))
               .select_map(Sequel[:documents][:urn])
        counts = urns.each_with_object(Hash.new(0)) do |urn, out|
          segments = urn.delete_prefix(prefix).split(":")
          out[segments.first] += 1 if segments.size >= 2
        end
        counts.empty? ? nil : counts
      end

      # The dossier shelf's --documents: one row per language code (name and
      # family lanes joined in), code order. Document-shaped filters are
      # honestly inapplicable here — a named error, never a silent empty.
      def dossiers(lang:, license:, withdrawn_only:, from:, to:, limit:, prefix:)
        if lang || license || withdrawn_only || from || to
          raise Error, "the dossier shelf holds language records — only --prefix and --limit apply"
        end

        codes = @catalog[:language_records].distinct.order(:lang_code).select_map(:lang_code)
        codes = codes.select { |code| code.start_with?(prefix) } if prefix
        names = record_lane("name")
        families = record_lane("family")
        rows = (limit.positive? ? codes.first(limit) : codes).map do |code|
          DossierRow.new(code: code, name: names[code], family: families[code])
        end
        Page.new(rows: rows, total: codes.size)
      end

      private

      def language_grain?(source)
        source.fetch(:adapter_class) == LANGUAGE_ADAPTER && @catalog.table_exists?(:language_records)
      end

      def dossier_count
        @dossier_count ||= @catalog[:language_records].select(:lang_code).distinct.count
      end

      # {kind => record count}, largest lanes first (the card's records line).
      def record_kinds
        @record_kinds ||= @catalog[:language_records]
                          .group_and_count(:kind).all
                          .sort_by { |row| [-row.fetch(:count), row.fetch(:kind)] }
                          .to_h { |row| [row.fetch(:kind), row.fetch(:count)] }
      end

      def record_lane(kind)
        @catalog[:language_records].where(kind: kind).select_hash(:lang_code, :body)
      end

      def source_row!(slug)
        row = @catalog[:sources]
              .where(slug: slug)
              .select(:id, :slug, :name, :adapter_class, :enabled, :license, :license_class)
              .first
        return row if row

        known = @catalog[:sources].order(:slug).select_map(:slug)
        raise Error, "unknown source #{slug.inspect} — the catalog holds: #{known.join(', ')}"
      end

      # -- grouped counters (one query per table, assembled per source) -----

      def doc_counts
        @doc_counts ||= @catalog[:documents]
                        .group(:source_id)
                        .select(
                          :source_id,
                          Sequel.function(:sum, Sequel.case({ { withdrawn: false } => 1 }, 0)).as(:docs),
                          Sequel.function(:sum, Sequel.case({ { withdrawn: true } => 1 }, 0)).as(:withdrawn),
                          Sequel.function(:sum, Sequel.case({ { retired_upstream: true, withdrawn: false } => 1 }, 0))
                                .as(:retired)
                        ).all
                        .to_h { |row| [row.fetch(:source_id), row.slice(:docs, :withdrawn, :retired)] }
      end

      def passage_counts
        @passage_counts ||= live_passages
                            .group(Sequel[:documents][:source_id])
                            .select(Sequel[:documents][:source_id].as(:source_id),
                                    Sequel.function(:count).*.as(:count))
                            .all.to_h { |row| [row.fetch(:source_id), row.fetch(:count)] }
      end

      def census_languages
        @census_languages ||= live_passages
                              .exclude(Sequel[:passages][:language] => nil)
                              .distinct
                              .select_map([Sequel[:documents][:source_id], Sequel[:passages][:language]])
                              .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      end

      def live_passages
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
      end

      def license_mix
        @license_mix ||= @catalog[:documents]
                         .join(:sources, id: Sequel[:documents][:source_id])
                         .where(Sequel[:documents][:withdrawn] => false)
                         .distinct
                         .select_map([Sequel[:documents][:source_id], license_expr.as(:effective)])
                         .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      end

      def entry_counts
        return @entry_counts ||= {} unless dictionary_shelf?

        @entry_counts ||= @catalog[:dictionary_entries]
                          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                          .where(Sequel[:dictionary_entries][:withdrawn] => false)
                          .group(Sequel[:dictionaries][:source_id])
                          .select(Sequel[:dictionaries][:source_id].as(:source_id),
                                  Sequel.function(:count).*.as(:count))
                          .all.to_h { |row| [row.fetch(:source_id), row.fetch(:count)] }
      end

      def dictionary_languages(source_id)
        return [] unless dictionary_shelf?

        (@dictionary_languages ||= @catalog[:dictionaries]
                                   .distinct
                                   .select_map(%i[source_id language])
                                   .group_by(&:first).transform_values { |pairs| pairs.map(&:last) })
          .fetch(source_id, [])
      end

      def dictionary_shelf?
        @catalog.table_exists?(:dictionary_entries)
      end

      def dictionary_source?(source_id)
        dictionary_shelf? && @catalog[:dictionaries].where(source_id: source_id).any?
      end

      # -- card details ------------------------------------------------------

      def card_languages(source_id)
        live_passages
          .where(Sequel[:documents][:source_id] => source_id)
          .exclude(Sequel[:passages][:language] => nil)
          .group_and_count(Sequel[:passages][:language])
          .all.to_h { |row| [row.fetch(:language), row.fetch(:count)] }
      end

      def dictionary_rows(source_id)
        return [] unless dictionary_shelf?

        @catalog[:dictionaries].where(source_id: source_id).order(:slug).all.map do |dict|
          DictionaryRow.new(
            slug: dict.fetch(:slug), title: dict.fetch(:title), language: dict.fetch(:language),
            entries: @catalog[:dictionary_entries]
                     .where(dictionary_id: dict.fetch(:id), withdrawn: false).count
          )
        end
      end

      def dated_coverage(source_id)
        return nil unless @catalog.table_exists?(:document_axes)

        row = @catalog[:document_axes]
              .join(:documents, id: Sequel[:document_axes][:document_id])
              .where(Sequel[:documents][:source_id] => source_id, Sequel[:documents][:withdrawn] => false)
              .select(
                Sequel.function(:count, Sequel[:document_axes][:document_id]).distinct.as(:docs),
                Sequel.function(:min, Sequel[:document_axes][:not_before]).as(:min),
                Sequel.function(:max, Sequel[:document_axes][:not_after]).as(:max)
              ).first
        row[:docs].to_i.positive? ? Dated.new(docs: row[:docs], min: row[:min], max: row[:max]) : nil
      end

      def facet_summary(source_id)
        return [] unless @catalog.table_exists?(:document_facets)

        @catalog[:document_facets]
          .join(:documents, id: Sequel[:document_facets][:document_id])
          .where(Sequel[:documents][:source_id] => source_id, Sequel[:documents][:withdrawn] => false)
          .group(Sequel[:document_facets][:facet])
          .select(
            Sequel[:document_facets][:facet],
            Sequel.function(:count, Sequel[:document_facets][:value]).distinct.as(:values),
            Sequel.function(:count, Sequel[:document_facets][:document_id]).distinct.as(:docs)
          )
          .order(Sequel[:document_facets][:facet])
          .all.map { |row| FacetRow.new(facet: row.fetch(:facet), values: row.fetch(:values), docs: row.fetch(:docs)) }
      end

      # -- enumeration plumbing ----------------------------------------------

      def page(dataset, limit, &)
        total = dataset.count
        rows = (limit.to_i.positive? ? dataset.limit(limit.to_i) : dataset).all
        Page.new(rows: rows.map(&), total: total)
      end

      def build_doc_row(row)
        DocRow.new(
          urn: row.fetch(:urn), title: row.fetch(:title), language: row.fetch(:language),
          license_class: effective_license(row),
          withdrawn: row.fetch(:withdrawn), retired: row.fetch(:retired_upstream)
        )
      end

      def effective_license(row)
        row.fetch(:license_override, nil) || row.fetch(:license_class)
      end

      def build_entry_row(row)
        EntryRow.new(
          headword: row.fetch(:headword), gloss: row.fetch(:gloss),
          dictionary_slug: row.fetch(:slug), language: row.fetch(:language)
        )
      end

      # Folded-prefix match, the define contract: strip the comparativist's
      # leading asterisk, take every query_forms variant, and OR a byte-range
      # prefix per variant (rides the headword_folded index, nothing to
      # escape — the Scope#prefix_match precedent).
      def prefix_expr(prefix)
        variants = Nabu::Normalize.query_forms(prefix.to_s.strip.delete_prefix("*"))
        variants.reject { |variant| variant.strip.empty? }
                .map { |variant| byte_prefix(Sequel[:dictionary_entries][:headword_folded], variant) }
                .reduce { |a, b| Sequel.|(a, b) } || Sequel.lit("1 = 0")
      end

      def byte_prefix(column, prefix)
        Sequel.expr(column >= prefix) & (column < "#{prefix}\u{10FFFF}")
      end
    end
  end
end
