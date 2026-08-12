# frozen_string_literal: true

require_relative "../lects"
require_relative "../normalize"
require_relative "../store/reflex_roots_indexer"
require_relative "reflex_views"

module Nabu
  module Query
    # The comparativist's walk (P14-1, architecture §12; multi-hop P17-3):
    # `nabu etym богъ` takes an ATTESTED lemma, finds every reconstruction
    # entry naming it as a descendant reflex (folded match on the
    # crosswalk's word_folded OR roman_folded — the script bridge that lets
    # got guþ reach *gudą through 𐌲𐌿𐌸), and returns each proto entry with
    # its full cognate list (corpus attestation counts resolved at query
    # time via ReflexViews) plus the ASCENT CHAIN: entries of OTHER shelves
    # whose descendants name this entry, recursively — the same
    # shelf-visited walk as Store::ReflexRootsIndexer (each dictionary
    # language enterable once per walk, so the recursion provably
    # terminates and degenerates to the old one-hop report when no
    # intermediate shelf exists). With Proto-Balto-Slavic on the shelf the
    # chain runs богъ → *bogъ → *bogù → *bʰag- end to end; each ancestor
    # carries `edge_borrowed`, the loan flag of the reflex edge that names
    # it (renderers label "(loan)" per edge — P17-3's borrowed flag).
    #
    # A leading asterisk skips the attested side: `etym *bogъ` looks the
    # reconstruction headword up directly (same strip-the-asterisk
    # convention as `define *bogъ`; upstream stores headwords bare).
    #
    # Since P16-5 the attested wiktionary-cu entries carry reflexes too
    # (the descendants backfill), so the reflex walk can land on an OCS
    # entry: orv/sl lemmas reach their OCS ancestor, whose own ancestors
    # ride the same walk. Attested entries render WITHOUT the display
    # asterisk — only the -pro shelves earn it.
    #
    # Degradation is graceful everywhere: a catalog predating migration 007
    # (or with no shelves) returns []; without a fulltext handle the walk
    # works and every attestation count is an honest nil; reflex rows
    # predating migration 010 carry borrowed nil ("not yet reparsed").
    class Etym
      # How the walk entered this entry: the reflex that matched the query
      # (nil for direct asterisk lookups). +borrowed+ is that edge's loan
      # flag (true/false, nil when the row predates the flag reparse).
      # +lect_id+/+lect_name+ (P57-4, display-only): the resolved nabu-lects
      # id and its composed registry name for +language+, or nil/nil when
      # Lects is absent OR the resolved id has no registry entry (an honest
      # miss — e.g. a reflex language never minted as a lects.yml anchor).
      # The raw stored +language+ is never touched.
      # +uncertain+ (P76 U-6) mirrors +borrowed+: the kaikki doubt tag on
      # the matched edge, nil pre-migration-029 or pre-reparse.
      MatchedVia = Data.define(:language, :word, :roman, :borrowed, :uncertain, :lect_id, :lect_name) do
        def initialize(lect_id: nil, lect_name: nil, uncertain: nil, **rest)
          super(**rest, lect_id: lect_id, lect_name: lect_name, uncertain: uncertain)
        end
      end

      # One entry on the walk. +headword+ carries the display asterisk
      # (P57-4: earned via Nabu::Lects#reconstructed? when present, the old
      # "-pro shelf" string test as fallback — #reconstructed_language?);
      # +cognates+ are ReflexViews::View values in stored order; +ancestors+
      # are Results one shelf-visited hop up, recursively (empty when no
      # unvisited shelf names this entry). +edge_borrowed+ is the loan flag
      # of the reflex edge CONNECTING this entry to the descendant it was
      # reached from — nil on top-level results (no connecting edge; the
      # direct edge's flag lives on matched_reflex). +lect_id+/+lect_name+
      # (P57-4, display-only) mirror MatchedVia's, resolved for +language+
      # WITH its +source_slug+ (the dictionary's own source — the per-source
      # override seam).
      Result = Data.define(:urn, :dictionary_slug, :dictionary_title, :language,
                           :headword, :gloss, :license, :license_class, :source_slug,
                           :matched_reflex, :edge_borrowed, :cognates, :ancestors,
                           :lect_id, :lect_name) do
        def initialize(lect_id: nil, lect_name: nil, **rest) = super(**rest, lect_id: lect_id, lect_name: lect_name)
      end

      DEFAULT_LIMIT = 5

      # +lects+ (P57-4) is the recon-predicate/display-mapping seam: :auto
      # feature-detects Nabu::Lects.load_default LAZILY on first use (the
      # define.rb/search.rb :auto contract — absent canonical/nabu-lects,
      # byte-identical behavior), a loaded Nabu::Lects (tests, or a caller
      # that already resolved one), or nil (the bare fallback, forced).
      def initialize(catalog:, fulltext: nil, lects: :auto)
        @catalog = catalog
        @views = ReflexViews.new(catalog: catalog, fulltext: fulltext)
        @lects = lects
      end

      def run(lemma, lang: nil, limit: DEFAULT_LIMIT)
        return [] unless shelf?

        term = lemma.to_s.strip
        direct = term.delete_prefix("*")
        return [] if direct.strip.empty?

        return headword_results(direct, limit: limit) if term.start_with?("*")

        reflex = proto_rows_by_reflex(term, lang: lang, limit: limit)
                 .map { |row, matched| build_result(row, matched: matched) }
        return reflex unless reflex.empty?

        # Bare-form fallback (P14-10): the reflex path missed, so the user most
        # likely typed the RECONSTRUCTION form itself (bʰewgʰ, or ASCII bhewgh)
        # rather than an attested descendant. Try the -pro shelves' own
        # headwords — asterisk optional (zsh globs a bare *), trailing-hyphen
        # tolerant (root entries store *bʰewgʰ-), folded through §9. An
        # explicit --lang stays honored: the fallback is UNfiltered by design
        # (headwords have no reflex language), so a lang-scoped miss is an
        # honest empty — newly load-bearing since P27-2, when the cross-script
        # fold made Cyrillic spellings reach Latin proto headwords directly.
        lang ? [] : headword_results(direct, limit: limit)
      end

      # The shelves actually present in the crosswalk (P24-2): distinct
      # dictionary languages holding reflex rows, db-derived so a miss
      # message never rots into a hardcoded enumeration (the P11
      # DEFINE_LANGS lesson — a shelf added to the catalog appears with
      # zero code change). Sorted for determinism; [] on a catalog
      # predating migration 007.
      def crosswalk_shelves
        return [] unless shelf?

        @catalog[:dictionary_reflexes]
          .join(:dictionary_entries, id: Sequel[:dictionary_reflexes][:dictionary_entry_id])
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .distinct
          .select_map(Sequel[:dictionaries][:language])
          .sort
      end

      private

      def headword_results(headword, limit:)
        proto_rows_by_headword(headword, limit: limit)
          .map { |row| build_result(row, matched: nil) }
      end

      def shelf?
        @catalog.table_exists?(:dictionary_entries) && @views.available?
      end

      # -- entry finders -----------------------------------------------------------

      # Attested → proto: reflex rows whose word_folded/roman_folded hits the
      # query_forms union, deduplicated to entries (first matching reflex in
      # stored order wins as the MatchedVia).
      def proto_rows_by_reflex(term, lang:, limit:)
        variants = Nabu::Normalize.query_forms(term)
        dataset = entry_dataset
                  .join(:dictionary_reflexes, dictionary_entry_id: Sequel[:dictionary_entries][:id])
                  .where(
                    Sequel.|({ Sequel[:dictionary_reflexes][:word_folded] => variants },
                             { Sequel[:dictionary_reflexes][:roman_folded] => variants })
                  )
        dataset = dataset.where(Sequel[:dictionary_reflexes][:language] => lang) if lang
        rows = dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id],
                             Sequel[:dictionary_reflexes][:seq])
                      .select(*entry_columns,
                              Sequel[:dictionary_reflexes][:language].as(:reflex_language),
                              Sequel[:dictionary_reflexes][:word].as(:reflex_word),
                              Sequel[:dictionary_reflexes][:roman].as(:reflex_roman),
                              *borrowed_select, *uncertain_select)
                      .all
        rows.uniq { |row| row.fetch(:entry_row_id) }.first(limit).map do |row|
          # No source is known for a reflex row's OWN language (reflexes
          # carry no source column — the per-source override seam cannot
          # engage here; codemap/identity only, class doc).
          lect = lect_display(row.fetch(:reflex_language), source: nil)
          [row, MatchedVia.new(language: row.fetch(:reflex_language),
                               word: row.fetch(:reflex_word), roman: row.fetch(:reflex_roman),
                               borrowed: row[:reflex_borrowed],
                               uncertain: row[:reflex_uncertain], **lect)]
        end
      end

      # Migration-010 guard (the pre-006 precedent): a READ surface can
      # never migrate, so on an older catalog the loan flag is simply
      # unselected and every edge reads nil — honest unknown, no crash.
      def borrowed_select
        @borrowed_select ||=
          if @catalog[:dictionary_reflexes].columns.include?(:borrowed)
            [Sequel[:dictionary_reflexes][:borrowed].as(:reflex_borrowed)]
          else
            []
          end
      end

      # Migration-029 guard, the same pre-006 precedent as borrowed_select.
      def uncertain_select
        @uncertain_select ||=
          if @catalog[:dictionary_reflexes].columns.include?(:uncertain)
            [Sequel[:dictionary_reflexes][:uncertain].as(:reflex_uncertain)]
          else
            []
          end
      end

      # Direct `*headword` lookup — reconstruction shelves only. P57-4: with
      # Lects present the SQL "-pro" scope is dropped in favor of a Ruby-side
      # filter over #reconstructed_language? (the class-doc closure-ascent
      # correction — a headword_folded hit is already narrow, so loading the
      # small candidate set before filtering costs nothing measurable);
      # absent Lects, the old SQL scope is untouched (the fallback, forced).
      def proto_rows_by_headword(headword, limit:)
        dataset = entry_dataset
                  .where(Sequel[:dictionary_entries][:headword_folded] => headword_variants(headword))
        dataset = dataset.where(Sequel.like(Sequel[:dictionaries][:language], "%-pro")) unless lects_seam
        rows = dataset.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
                      .select(*entry_columns)
                      .all
        if lects_seam
          rows = rows.select { |row| reconstructed_language?(row.fetch(:language), source: row.fetch(:source_slug)) }
        end
        rows.first(limit)
      end

      # Folded lookup variants, trailing-hyphen tolerant (P14-10): a
      # reconstruction ROOT stores its headword with a trailing hyphen
      # (*bʰewgʰ-), so a query typed without it (bʰewgʰ, bhewgh) must still
      # reach the entry — and vice versa. Try each §9 fold variant as-is, with
      # a trailing hyphen appended, and with one stripped.
      def headword_variants(headword)
        Nabu::Normalize.query_forms(headword)
                       .flat_map { |form| [form, "#{form}-", form.chomp("-")] }
                       .uniq
      end

      # One shelf-visited round up: reflex rows of dictionaries in UNVISITED
      # languages naming this entry's language + folded headword. Every
      # ancestor of the round shares +visited+; all their shelves are marked
      # before recursing (the indexer's breadth-first-round rule, so the
      # rendered tree is walk-order independent). Duplicate naming edges
      # from one ancestor collapse, their loan flags merged true > false >
      # nil.
      def ancestors_of(row, visited)
        rows = entry_dataset
               .join(:dictionary_reflexes, dictionary_entry_id: Sequel[:dictionary_entries][:id])
               .where(Sequel[:dictionary_reflexes][:language] => row.fetch(:language),
                      Sequel[:dictionary_reflexes][:word_folded] => row.fetch(:headword_folded))
               .exclude(Sequel[:dictionaries][:language] => visited.to_a)
               .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
               .select(*entry_columns, *borrowed_select)
               .all
        grouped = rows.group_by { |ancestor| ancestor.fetch(:entry_row_id) }.values
        round = visited + grouped.map { |dups| dups.first.fetch(:language) }
        grouped.map do |dups|
          build_result(dups.first, matched: nil, visited: round,
                                   edge_borrowed: dups.map { |dup| dup[:reflex_borrowed] }
                                                      .reduce { |a, b| Store::ReflexRootsIndexer.max_flag(a, b) })
        end
      end

      def entry_dataset
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .join(:sources, id: Sequel[:dictionaries][:source_id])
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
      end

      def entry_columns
        [Sequel[:dictionary_entries][:id].as(:entry_row_id),
         Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:entry_id],
         Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:headword_folded],
         Sequel[:dictionary_entries][:gloss],
         Sequel[:dictionaries][:slug].as(:dictionary_slug),
         Sequel[:dictionaries][:title].as(:dictionary_title),
         Sequel[:dictionaries][:language],
         Sequel[:sources][:license], Sequel[:sources][:license_class],
         Sequel[:sources][:slug].as(:source_slug)]
      end

      # -- result assembly ----------------------------------------------------------

      # +visited+ seeds the shelf-visited walk with this entry's own
      # dictionary language (the same-language/derivational exclusion, and
      # the cycle bound: a shelf already on the path never re-enters).
      def build_result(row, matched:, visited: nil, edge_borrowed: nil)
        visited ||= Set[row.fetch(:language)]
        Result.new(
          urn: row.fetch(:urn), dictionary_slug: row.fetch(:dictionary_slug),
          dictionary_title: row.fetch(:dictionary_title), language: row.fetch(:language),
          headword: display_headword(row), gloss: row.fetch(:gloss),
          license: row.fetch(:license), license_class: row.fetch(:license_class),
          source_slug: row.fetch(:source_slug),
          matched_reflex: matched, edge_borrowed: edge_borrowed,
          cognates: @views.for_entry(row.fetch(:entry_row_id)),
          ancestors: row.fetch(:headword_folded) ? ancestors_of(row, visited) : [],
          **lect_display(row.fetch(:language), source: row.fetch(:source_slug))
        )
      end

      # The display asterisk is the reconstruction convention, earned by
      # #reconstructed_language? (P57-4: Lects#reconstructed? when present,
      # the old "-pro shelf" string test as fallback). An attested
      # (wiktionary-cu) entry on the walk is attested, not reconstructed,
      # and must not read as one.
      def display_headword(row)
        headword = row.fetch(:headword)
        reconstructed_language?(row.fetch(:language), source: row.fetch(:source_slug)) ? "*#{headword}" : headword
      end

      # -- P57-4: the Lects seam (recon predicate by mode + display mapping) -------

      # Feature-detect + memoize (the tibetan_words/:auto contract, Query::Search
      # precedent): loaded from canonical/nabu-lects on first use, nil while
      # absent (re-detected per call, so a mid-session `nabu sync nabu-lects`
      # is picked up without a restart).
      def lects_seam
        return @lects unless @lects == :auto

        loaded = Nabu::Lects.load_default
        @lects = loaded if loaded
        loaded
      end

      # THE reconstruction predicate (class doc): resolve +language+ (with
      # +source+ when known — the per-source override seam) and ask
      # #reconstructed? when Lects is present; the old "-pro suffix" string
      # test, UNCHANGED, when it is not (fallback, never removed).
      def reconstructed_language?(language, source: nil)
        seam = lects_seam
        return language.to_s.end_with?("-pro") unless seam

        seam.reconstructed?(seam.resolve(language, source: source))
      end

      # {lect_id:, lect_name:} for +code+ — both nil when Lects is absent OR
      # the resolved id has no registry entry (an honest miss, never an
      # error: e.g. a reflex language nabu-lects has not minted an anchor
      # for). Display-only; the raw stored code is never touched.
      def lect_display(code, source: nil)
        seam = lects_seam
        return { lect_id: nil, lect_name: nil } unless seam

        resolved = seam.resolve(code, source: source)
        lect = seam.lect(resolved)
        { lect_id: lect ? resolved : nil, lect_name: lect&.name }
      end
    end
  end
end
