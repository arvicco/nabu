# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "builder"
require_relative "csv_writer"
require_relative "rollup_slice"

module Nabu
  module DataBuild
    # The mul/reflex-chains builder — the held etymological dictionaries'
    # descendant edges (the catalog's dictionary_reflexes crosswalk) as one
    # table: per row the dictionary, the entry (URN + headword verbatim —
    # the reconstruction/etymon on the proto shelves, the attested word on
    # the attested-language and loanword shelves), the reflex's upstream
    # language code verbatim plus the catalog code it joins on, the reflex
    # verbatim + romanization + both stored folded forms, and the
    # borrowed/uncertain edge flags carried through in their three honest
    # states (true / false / empty = the row predates the flag-aware parse).
    #
    # == The Attested join
    #
    # Attested is the number of GOLD passage attestations (the lemma_rollup
    # occurrences grain: one per distinct lemma per passage) whose folded
    # lemma key EQUALS the reflex's stored word_folded — or, failing that,
    # its roman_folded (the script bridge: Gothic 𐌷𐌻𐌰𐌹𐍆𐍃 joins the gold
    # lemma "hlaifs") — under the SAME catalog language code (the reflex's
    # language column; display-only nodes with no catalog code never join).
    # Attested_Via says which key matched (form | roman). Exactly the rule
    # Nabu's own etym/define desks resolve at query time
    # (Query::ReflexViews): stored-key equality, no fuzzy matching, no
    # cross-language matching, no re-folding. Only gold rows of
    # publishable sources count — a screened source's attestation never
    # hides in the integer (rows attested ONLY there are censused instead),
    # and the silver grade never counts. Empty = not attested in the held
    # gold corpus under this rule, never a zero claim.
    #
    # == License screening
    #
    # CC BY-SA 4.0 — the share-alike carve-out (wiktionary-recon dominates).
    # Open- and attribution-class dictionary sources only; nc (and any
    # other restricted class) rows are excluded row-by-row and censused per
    # class and per class/source in nabu.eval.
    #
    # == Provenance
    #
    # Own catalog projection (no cone sha is load-bearing); the recipe
    # embeds the published-slice sha256 — attested counts included — so an
    # unchanged slice is a fingerprint no-op and a screened row can never
    # move it. Rows stream to the CSV (well over a million).
    class ReflexChainsBuilder
      FILENAME = "reflex-chains.csv"
      COLUMNS = %w[ID Dictionary URN Headword Headword_Language Seq Lang_Code Language_ID Form Roman
                   Form_Folded Roman_Folded Borrowed Uncertain Attested Attested_Via Source].freeze
      INTEGER_COLUMNS = %w[Seq Attested].freeze
      BOOLEAN_COLUMNS = %w[Borrowed Uncertain].freeze

      GOLD_GRADE = "gold"
      KEY_SEPARATOR = "\x1f"

      OVERVIEW =
        "Etymological dictionaries tell you that Proto-Germanic *hlaibaz became Gothic hlaifs, Old " \
        "English hlāf and Old Norse hleifr — but not whether those descendant words actually occur " \
        "in the surviving texts. This dataset publishes every reconstruction→reflex edge of the " \
        "openly licensed etymological dictionaries Nabu holds (Wiktionary's reconstruction pages, " \
        "the Tower of Babel databases, IE-CoR, WOLD and smaller lanes) as one table, and joins each " \
        "reflex to Nabu's human-verified (gold) lemmatized corpus: when the reflex is a lemma of " \
        "the held corpus in that language, the row says how many passages attest it. That linkage " \
        "from reconstructed roots to attested text is what no etymological database publishes."

      NOTES = <<~NOTES.strip
        ## The Attested join rule

        `Attested` is mechanical and deliberately narrow: the sum of GOLD
        passage attestations (one per distinct lemma per passage) whose
        folded lemma key is EQUAL to the reflex's `Form_Folded` — or, when
        that finds nothing, its `Roman_Folded` (the script bridge: a
        Gothic-script reflex joins the romanized gold lemma) — under the SAME
        catalog language code (`Language_ID`). `Attested_Via` names the key
        that matched (`form` | `roman`). No fuzzy matching, no cross-language
        matching, no re-folding; only gold lemmatization from openly licensed
        corpora counts (automatic lemmatization and non-commercial corpora
        never enter the integer). An empty cell means "not attested in the
        held gold corpus under this rule" — never a zero claim. Rows with an
        empty `Language_ID` are display-only nodes (an upstream code with no
        catalog counterpart) and are never joined. nabu.eval carries the
        attested/missed census per language.

        ## Columns

        `Headword` is the dictionary entry's headword verbatim with its
        object language in `Headword_Language` — the reconstruction on the
        proto shelves, the attested word on the attested-language and
        loanword shelves. `Lang_Code` is the upstream language code verbatim;
        `Seq` the depth-first position of the node in the entry's descendant
        tree. `Borrowed` / `Uncertain` are the upstream edge markers: `true`,
        `false`, or empty (the row predates the flag-aware parse — unknown,
        never a claimed false).
      NOTES

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/reflex-chains needs the catalog open — dictionary_reflexes lives there" if catalog.nil?

        state = { excluded: Hash.new(0), excluded_by_source: Hash.new(0), slugs: Hash.new(0),
                  attestation: Hash.new(0), by_language: {}, minter: IdMinter.new, sha: Digest::SHA256.new }
        index = attestation_index(catalog)
        stream = RollupSlice::Stream.new { |&emit| each_published(catalog, index, state, &emit) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: stream)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(state[:sha].hexdigest),
          citations: RollupSlice.citations(registry, state[:slugs].keys.sort),
          evaluation: census(catalog, state, count),
          overview: OVERVIEW,
          notes: NOTES
        )
      end

      private

      def registry
        @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
      end

      # "language\x1flemma" -> [publishable gold occurrences, screened gold
      # occurrences], restricted to the languages the crosswalk carries.
      def attestation_index(catalog)
        languages = catalog[:dictionary_reflexes].exclude(language: nil).distinct.select_map(:language)
        rollup = :lemma_rollup
        catalog[rollup]
          .join(:sources, id: Sequel[rollup][:source_id])
          .where(Sequel[rollup][:grade] => GOLD_GRADE, Sequel[rollup][:language] => languages)
          .group(Sequel[rollup][:language], Sequel[rollup][:lemma], Sequel[:sources][:license_class])
          .select(Sequel[rollup][:language], Sequel[rollup][:lemma], Sequel[:sources][:license_class],
                  Sequel.function(:sum, Sequel[rollup][:occurrences]).as(:occurrences))
          .each_with_object({}) do |row, index|
            counts = (index[[row[:language], row[:lemma]].join(KEY_SEPARATOR)] ||= [0, 0])
            counts[RollupSlice.publishable?(row[:license_class]) ? 0 : 1] += row[:occurrences]
          end
      end

      # Live entries' reflexes ordered (dictionary slug, entry id, seq) —
      # slugs and upstream entry ids, not row ids, so the order survives a
      # catalog rebuild.
      def reflexes(catalog)
        r = :dictionary_reflexes
        e = :dictionary_entries
        d = :dictionaries
        catalog[r]
          .join(e, id: Sequel[r][:dictionary_entry_id])
          .join(d, id: Sequel[e][:dictionary_id])
          .join(:sources, id: Sequel[d][:source_id])
          .where(Sequel[e][:withdrawn] => false)
          .select(Sequel[d][:slug].as(:dictionary), Sequel[d][:language].as(:headword_language),
                  Sequel[e][:urn], Sequel[e][:entry_id], Sequel[e][:headword], Sequel[r][:seq],
                  Sequel[r][:lang_code], Sequel[r][:language], Sequel[r][:word], Sequel[r][:roman],
                  Sequel[r][:word_folded], Sequel[r][:roman_folded], Sequel[r][:borrowed],
                  Sequel[r][:uncertain], Sequel[:sources][:slug].as(:source),
                  Sequel[:sources][:license_class])
          .order(Sequel[d][:slug], Sequel[e][:entry_id], Sequel[r][:seq], Sequel[r][:id])
      end

      def each_published(catalog, index, state)
        reflexes(catalog).each do |row|
          unless RollupSlice.publishable?(row[:license_class])
            state[:excluded][row[:license_class]] += 1
            state[:excluded_by_source]["#{row[:license_class]}/#{row[:source]}"] += 1
            next
          end

          yield publish(state, row, attest(index, state, row))
        end
      end

      # [occurrences, via] or [nil, nil] — the stored-key equality rule.
      def attest(index, state, row)
        language = row[:language]
        if language.nil?
          state[:attestation]["display_only"] += 1
          return [nil, nil]
        end

        keys = { "form" => row[:word_folded], "roman" => row[:roman_folded] }
               .reject { |_, folded| folded.nil? || folded.empty? }
               .transform_values { |folded| index[[language, folded].join(KEY_SEPARATOR)] }
        hit = keys.find { |_, counts| counts && counts[0].positive? }
        tally_language(state, language, hit)
        unless hit
          state[:attestation]["attested_only_in_screened_sources"] += 1 if keys.values.any?
          return [nil, nil]
        end

        via, counts = hit
        state[:attestation]["attested"] += 1
        state[:attestation]["via_#{via}"] += 1
        [counts[0], via]
      end

      def tally_language(state, language, hit)
        tally = (state[:by_language][language] ||= { "attested" => 0, "missed" => 0 })
        tally[hit ? "attested" : "missed"] += 1
      end

      # The ID keys on an entry-id DIGEST (upstream entry ids are mostly
      # non-ASCII and would fold to nothing or collide under the CLDF
      # identifier class) plus the stored seq — unique per dictionary entry
      # by construction, stable across releases; the IdMinter catches any
      # residual digest collision.
      def publish(state, row, attestation)
        attested, via = attestation
        state[:slugs][row[:source]] += 1
        values = [row[:dictionary], row[:urn], row[:headword], row[:headword_language], row[:seq],
                  row[:lang_code], row[:language], row[:word], row[:roman], row[:word_folded],
                  row[:roman_folded], row[:borrowed], row[:uncertain], attested, via, row[:source]]
        state[:sha] << values.join(KEY_SEPARATOR) << "\n"
        id = state[:minter].mint(row[:dictionary], "E#{Digest::SHA256.hexdigest(row[:entry_id])[0, 12]}", row[:seq])
        COLUMNS.zip([id, *values]).to_h
      end

      def census(catalog, state, count)
        withdrawn = catalog[:dictionary_reflexes]
                    .join(:dictionary_entries, id: :dictionary_entry_id)
                    .where(Sequel[:dictionary_entries][:withdrawn] => true)
        { "reflex_rows" => catalog[:dictionary_reflexes].count,
          "withdrawn_entry_rows_skipped" => withdrawn.count,
          "published_rows" => count,
          "published_rows_by_source" => RollupSlice.sorted_census(state[:slugs]),
          "excluded_rows" => RollupSlice.sorted_census(state[:excluded]),
          "excluded_rows_by_source" => RollupSlice.sorted_census(state[:excluded_by_source]),
          "attestation" => attestation_census(state[:attestation]),
          "attestation_by_language" => RollupSlice.sorted_census(state[:by_language]) }
      end

      def attestation_census(counts)
        %w[attested via_form via_roman display_only attested_only_in_screened_sources]
          .to_h { |key| [key, counts[key]] }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: field_type(name) } }
        Resource.new(name: "reflex_chains", path: FILENAME, rows: count, fields: fields, primary_key: ["ID"])
      end

      def field_type(name)
        return "integer" if INTEGER_COLUMNS.include?(name)
        return "boolean" if BOOLEAN_COLUMNS.include?(name)

        "string"
      end

      def recipe(digest)
        "reflex-chains v1: project dictionary_reflexes of live entries at (dictionary, entry, seq) grain, " \
          "license classes #{RollupSlice::PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered (dictionary, " \
          "entry id, seq); Attested = sum of lemma_rollup grade gold occurrences from " \
          "#{RollupSlice::PUBLISHABLE_LICENSE_CLASSES.join('+')} sources whose folded lemma equals the " \
          "reflex word_folded, else roman_folded, under the same catalog language code (stored-key " \
          "equality only); published-slice sha256=#{digest}"
      end
    end
  end
end
