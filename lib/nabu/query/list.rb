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
                         :dossiers, :record_kinds, :description) do
        def initialize(dossiers: 0, record_kinds: {}, description: nil, **rest) = super
      end
      Dated = Data.define(:docs, :min, :max)
      FacetRow = Data.define(:facet, :values, :docs)
      DictionaryRow = Data.define(:slug, :title, :language, :entries)
      # The loans facet's two grains (P34-2): one census row per loan-origin
      # code, and one enumeration row per loan-bearing document.
      LoanRow = Data.define(:code, :docs, :passages, :tokens)
      LoanDocRow = Data.define(:urn, :title, :language, :tokens, :passages)

      # One enumeration page: the rows shown plus the HONEST total, so the
      # renderer can say "… N more — raise --limit".
      Page = Data.define(:rows, :total)
      DocRow = Data.define(:urn, :title, :language, :license_class, :withdrawn, :retired)
      # The dossier shelf's enumeration grain (language records, not documents).
      DossierRow = Data.define(:code, :name, :family)
      EntryRow = Data.define(:headword, :gloss, :dictionary_slug, :language)

      # One line of the grouped source map (`nabu list --sources`, P28-4).
      # +enabled+ is the CATALOG's flag — the CLI overrides it with the
      # registry's for registered slugs (P23-3b, registry authoritative).
      SourceLine = Data.define(:slug, :enabled, :description)

      REFERENCE_GROUP = "Reference & dictionaries"
      LOCAL_GROUP = "Your shelves"
      OTHER_GROUP = "Other"
      # The FIXED curated header order of the map (P28-4, journaled in the
      # backlog): unknown derived family labels append before Other; groups
      # with no sources are simply absent.
      GROUP_ORDER = ["Greek & Latin", "Biblical & Near Eastern", "Slavic", "Celtic",
                     "Indic & Iranian", "Egyptian & Coptic", "Germanic & Old English",
                     REFERENCE_GROUP, LOCAL_GROUP, OTHER_GROUP].freeze
      # Family-lane prose → curated header, FIRST match wins. The lanes are
      # free prose ("South Slavic", "Italic < Indo-European"), so this is a
      # keyword net, ordered so the specific fires before the general
      # (Egyptian before the Semitic net: "Egyptian < Afro-Asiatic" is not
      # Near Eastern by the Semitic keyword).
      FAMILY_GROUPS = [
        [/slavic/i, "Slavic"],
        [/hellenic|greek|italic|latin/i, "Greek & Latin"],
        [/celtic|goidelic|brittonic|brythonic|gaulish/i, "Celtic"],
        # indo-iran covers both spellings in the wild: the dossiers'
        # "Indo-Iranian" and IE-CoR's clade "Indo-Iranic".
        [/indo-iran|indo-aryan|\bindic\b|iranian/i, "Indic & Iranian"],
        [/egyptian|coptic/i, "Egyptian & Coptic"],
        [/germanic|anglic/i, "Germanic & Old English"],
        [/semitic|canaanite|aramaic|akkadian|sumerian|hebrew|ugaritic/i, "Biblical & Near Eastern"]
      ].freeze
      # The local shelves (architecture §16 content grains :language /
      # :source / :notes + the library) — always "Your shelves".
      LOCAL_SHELF_ADAPTERS = %w[Nabu::Adapters::LocalLanguage Nabu::Adapters::LocalSource
                                Nabu::Adapters::LocalNotes Nabu::Adapters::LocalLibrary].freeze

      DEFAULT_LIMIT = 50
      # The language-dossier shelf holds language_records, not documents —
      # detected from the catalog itself (adapter_class), never the registry
      # (the query-object contract). Live gap 2026-07-15: 199 dossiers
      # rendered as "empty".
      LANGUAGE_ADAPTER = "Nabu::Adapters::LocalLanguage"
      # Its P24-0 twin: the source-dossier shelf holds source_records.
      SOURCE_ADAPTER = "Nabu::Adapters::LocalSource"

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
            dossiers: shelf_dossier_count(source),
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
          dossiers: shelf_dossier_count(source),
          record_kinds: shelf_record_kinds(source),
          description: description_for(slug)
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
        if source_grain?(source)
          raise Error, "the source-dossier shelf's records render on each source's card — " \
                       "bare `nabu list` (census) and `nabu list SLUG` serve them"
        end
        # The P22-1 verdict stands for document grain: urns are never folded,
        # so a prefix here is a named inapplicability, not a silent no-match.
        raise Error, "--prefix filters headwords and dossier codes — this shelf enumerates documents" if prefix

        dataset = @catalog[:documents]
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:sources][:slug] => slug)
        dataset = dataset.where(Sequel[:documents][:language] => Nabu::Languages.code_variants(lang)) if lang
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
        dataset = dataset.where(Sequel[:dictionaries][:language] => Nabu::Languages.code_variants(lang)) if lang
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

      # The loans census (P34-2, the P17-1 promise): one row per loan-origin
      # code over the source's LIVE passages — distinct documents, passages,
      # and the summed token counts — read straight off the stored
      # annotations_json ("loans" is the {code => token count} object the
      # Coptic Scriptorium parser tallies per passage; verbatim upstream
      # names census as stored). Token-count order, code as the tiebreak;
      # empty for a shelf whose parses carry no language-of-origin layer
      # (the CLI words the honest miss). Query-time like the search facet:
      # no projection table, nothing extra for `nabu rebuild` to maintain.
      def loans_census(slug)
        source = source_row!(slug)
        loan_join(source.fetch(:id))
          .group(Sequel[:loan][:key])
          .select(
            Sequel[:loan][:key].as(:code),
            Sequel.function(:count, Sequel[:passages][:document_id]).distinct.as(:docs),
            Sequel.function(:count, Sequel[:passages][:id]).distinct.as(:passages),
            Sequel.function(:sum, Sequel[:loan][:value]).as(:tokens)
          )
          .order(Sequel.desc(:tokens), Sequel[:loan][:key])
          .all
          .map { |row| LoanRow.new(**row.slice(:code, :docs, :passages, :tokens)) }
      end

      # `--loans CODE`: the saturation enumeration — live documents carrying
      # ≥1 loan token of that origin, with their summed token and passage
      # counts, most-saturated first (urn as the tiebreak). Case-insensitive
      # on the code (the facet house rule); an unattested code is an honest
      # empty page, never an error.
      def loan_documents(slug, code:, limit: DEFAULT_LIMIT)
        source = source_row!(slug)
        dataset = loan_join(source.fetch(:id))
                  .where(Sequel.function(:lower, Sequel[:loan][:key]) => code.to_s.downcase)
                  .group(Sequel[:documents][:id])
                  .select(
                    Sequel[:documents][:urn], Sequel[:documents][:title],
                    Sequel[:documents][:language],
                    Sequel.function(:sum, Sequel[:loan][:value]).as(:tokens),
                    Sequel.function(:count, Sequel[:passages][:id]).distinct.as(:passages)
                  )
                  .order(Sequel.desc(:tokens), Sequel[:documents][:urn])
        page(dataset, limit) { |row| LoanDocRow.new(**row.slice(:urn, :title, :language, :tokens, :passages)) }
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

      # { slug => dossier description } from the derived source_records —
      # the P24-0 census/MCP lane. {} on a catalog predating migration 015.
      def descriptions
        return {} unless @catalog.table_exists?(:source_records)

        @catalog[:source_records].where(kind: "description").select_hash(:slug, :body)
      end

      # The grouped source map (`nabu list --sources`, P28-4):
      # [[group, [SourceLine, …]], …] in GROUP_ORDER (unknown derived labels
      # before Other), slug order within each group. Grouping is DERIVED —
      # a dossier's owner-curated `group:` lane (source_records kind=group)
      # wins; else local shelves read "Your shelves"; else the source's
      # census+dictionary languages join the language dossiers' family
      # lanes (hyphenated codes fall back to their prefix lane): one family
      # → that family's header; several + dictionaries → Reference; several
      # on a passage shelf → the dominant (most-attested) language's
      # family; nothing derivable → the honest Other.
      def source_groups
        descs = descriptions
        grouped = Hash.new { |hash, key| hash[key] = [] }
        @catalog[:sources].order(:slug).select(:id, :slug, :adapter_class, :enabled).all.each do |source|
          grouped[group_for(source)] << SourceLine.new(slug: source.fetch(:slug),
                                                       enabled: source.fetch(:enabled),
                                                       description: descs[source.fetch(:slug)])
        end
        group_order(grouped.keys).map { |group| [group, grouped.fetch(group)] }
      end

      private

      # Curated order first, unknown labels (sorted) before Other.
      def group_order(present)
        ordered = (GROUP_ORDER - [OTHER_GROUP]).select { |group| present.include?(group) }
        ordered += (present - GROUP_ORDER).sort
        ordered << OTHER_GROUP if present.include?(OTHER_GROUP)
        ordered
      end

      def group_for(source)
        override = group_overrides[source.fetch(:slug)]
        return override if override
        return LOCAL_GROUP if LOCAL_SHELF_ADAPTERS.include?(source.fetch(:adapter_class))

        id = source.fetch(:id)
        labels = family_labels(id)
        return OTHER_GROUP if labels.empty?
        return labels.first if labels.size == 1
        return REFERENCE_GROUP if dictionary_source_ids.include?(id)

        dominant_family_label(id) || labels.first
      end

      # The distinct family labels of every language the source holds
      # (live passages + dictionary languages), language order.
      def family_labels(source_id)
        langs = ((census_languages[source_id] || []) + dictionary_languages(source_id)).uniq.sort
        langs.filter_map { |code| family_label(code) }.uniq
      end

      # One code's label: the family lane (hyphenated codes fall back to
      # their prefix lane — the Languages#family_fallback rule) through the
      # keyword net; an unmatched lane derives its own label (first
      # `<`-segment, trailing parenthetical stripped); no lane → nil.
      def family_label(code)
        body = family_lanes[code] || family_lanes[code.split("-", 2).first]
        return nil unless body

        FAMILY_GROUPS.each { |pattern, group| return group if body.match?(pattern) }
        derived = body.split("<").first.to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip
        derived.empty? ? nil : derived
      end

      # Family evidence per code: the owner-curated family lane wins; codes
      # without one fall back to their iecor accretion's "clade X" phrase
      # (2026-07-18: only 45 of 199 dossiers carry family lanes, but the
      # IE-CoR clade names the family for most of the rest — derived
      # evidence, honestly weaker, used only in the lane's absence).
      def family_lanes
        @family_lanes ||= build_family_lanes
      end

      def build_family_lanes
        return {} unless @catalog.table_exists?(:language_records)

        lanes = record_lane("family")
        @catalog[:language_records].where(kind: "iecor").select_map(%i[lang_code body]).each do |code, body|
          next if lanes.key?(code)

          clade = body[/clade ([A-Za-z-]+)/, 1]
          lanes[code] = clade if clade
        end
        lanes
      end

      # {slug => group} from the dossiers' owner-curated group: lane.
      def group_overrides
        @group_overrides ||= if @catalog.table_exists?(:source_records)
                               @catalog[:source_records].where(kind: "group").select_hash(:slug, :body)
                             else
                               {}
                             end
      end

      def dictionary_source_ids
        @dictionary_source_ids ||= dictionary_shelf? ? @catalog[:dictionaries].distinct.select_map(:source_id) : []
      end

      # The most-attested live language that HAS a family label; ties break
      # by code. nil when none carries one. English is a translation layer
      # on every multilingual shelf (aligned -en siblings can outnumber the
      # source text — damaskini holds 6,036 eng vs 5,123 bul), so eng only
      # votes when no other labeled language exists.
      def dominant_family_label(source_id)
        counts = language_passage_counts.fetch(source_id, {})
        labeled = counts.keys.select { |c| family_label(c) }
        candidates = labeled.reject { |c| c.split("-", 2).first == "eng" }
        candidates = labeled if candidates.empty?
        code = candidates.min_by { |c| [-counts.fetch(c), c] }
        code && family_label(code)
      end

      def language_passage_counts
        @language_passage_counts ||= live_passages
                                     .exclude(Sequel[:passages][:language] => nil)
                                     .group(Sequel[:documents][:source_id], Sequel[:passages][:language])
                                     .select(Sequel[:documents][:source_id].as(:source_id),
                                             Sequel[:passages][:language].as(:language),
                                             Sequel.function(:count).*.as(:count))
                                     .all
                                     .group_by { |row| row.fetch(:source_id) }
                                     .transform_values do |rows|
                                       rows.to_h { |row| [row.fetch(:language), row.fetch(:count)] }
                                     end
      end

      def language_grain?(source)
        source.fetch(:adapter_class) == LANGUAGE_ADAPTER && @catalog.table_exists?(:language_records)
      end

      def source_grain?(source)
        source.fetch(:adapter_class) == SOURCE_ADAPTER && @catalog.table_exists?(:source_records)
      end

      # The dossier count for a shelf whose content grain is dossiers
      # (language or source shelf); 0 for ordinary sources.
      def shelf_dossier_count(source)
        return dossier_count if language_grain?(source)
        return source_dossier_count if source_grain?(source)

        0
      end

      def shelf_record_kinds(source)
        return record_kinds if language_grain?(source)
        return source_record_kinds if source_grain?(source)

        {}
      end

      def source_dossier_count
        @source_dossier_count ||= @catalog[:source_records].select(:slug).distinct.count
      end

      def source_record_kinds
        @source_record_kinds ||= @catalog[:source_records]
                                 .group_and_count(:kind).all
                                 .sort_by { |row| [-row.fetch(:count), row.fetch(:kind)] }
                                 .to_h { |row| [row.fetch(:kind), row.fetch(:count)] }
      end

      # One source's dossier description (P24-0), nil when the shelf has
      # nothing on it (or the catalog predates migration 015).
      def description_for(slug)
        return nil unless @catalog.table_exists?(:source_records)

        @catalog[:source_records].where(slug: slug, kind: "description").get(:body)
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

      # The loans base join (P34-2): the source's live passages cross-applied
      # to json_each over their stored "loans" object — one row per (passage,
      # code) with `loan.key`/`loan.value` alongside the passage columns. The
      # LIKE probe skips the JSON walk for the loan-free majority; json_each
      # on a missing path yields zero rows, so loan-less passages simply
      # contribute nothing.
      def loan_join(source_id)
        @catalog
          .from(:passages,
                Sequel.function(:json_each, Sequel[:passages][:annotations_json], "$.loans").as(:loan))
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false)
          .where(Sequel.like(Sequel[:passages][:annotations_json], '%"loans"%'))
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
