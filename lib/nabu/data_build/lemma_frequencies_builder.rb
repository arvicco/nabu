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
    # The mul/lemma-frequencies builder — the catalog's lemma_rollup
    # (Store::LemmaRollup) published as per-language frequency tables at
    # century grain. One row per (lemma, language, century, basis, source):
    # passage attestations (Occurrences — the passage_lemmas grain, one per
    # distinct lemma per passage, NOT a token count) and attesting documents.
    #
    # == Scope: gold only
    #
    # Only grade "gold" rollup rows publish — treebank / verified-annotation
    # lemmatization. The silver grade (automatic lemmatization) is skipped
    # and censused. Lemma is the rollup's FOLDED key (passage_lemmas
    # lemma_folded — Normalize.search_form under the passage language), the
    # same key Nabu's lemma desk looks up; Language_ID is the passage code
    # the lemma was folded under. Century is the signed century index of
    # the document's date-envelope midpoint (-2 = 2nd c. BCE, 1 = 1st c.
    # CE); Basis is the envelope's date class (composition | artifact); both
    # empty = undated. Silver-estimate datings fold into undated
    # (RollupSlice).
    #
    # == License screening
    #
    # CC BY-SA 4.0 — the share-alike carve-out (aes, tla-hf, menota, glaux
    # ride inside it). Open- and attribution-class sources only; nc, odbl
    # and research_private source rows are excluded row-by-row and censused
    # (rows and occurrences per class) in nabu.eval — no screened
    # contribution can hide in an integer.
    #
    # == Provenance
    #
    # Own catalog projection (no cone sha is load-bearing); the recipe
    # embeds the published-slice sha256, so an unchanged slice is a
    # fingerprint no-op and a screened row can never move it.
    class LemmaFrequenciesBuilder
      FILENAME = "lemma-frequencies.csv"
      COLUMNS = %w[ID Lemma Language_ID Century Basis Occurrences Documents Source].freeze
      INTEGER_COLUMNS = %w[Century Occurrences Documents].freeze

      GOLD_GRADE = "gold"

      OVERVIEW =
        "How often does a word occur in a premodern language, and how did that change over the " \
        "centuries? Frequency dictionaries exist for almost none of the ancient and premodern " \
        "languages, and diachronic ones for none. This dataset publishes Nabu's lemma census " \
        "built from human-verified (gold) lemmatization only: for each lemma, language, century " \
        "and corpus, how many passages and documents attest it — Sanskrit, Sumerian, Middle High " \
        "German, Middle Dutch, Hebrew, Egyptian, Latin, Akkadian, Greek, Old East Slavic, " \
        "Classical Chinese, Old Norse, Coptic and dozens more. Teaching tools get real core " \
        "vocabularies; historical linguists get the rise and fall of words at century grain."

      def initialize(registry: nil)
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/lemma-frequencies needs the catalog open — lemma_rollup lives there" if catalog.nil?

        state = { excluded: Hash.new(0), excluded_occurrences: Hash.new(0), slugs: {},
                  by_language: Hash.new(0), minter: IdMinter.new, sha: Digest::SHA256.new }
        stream = RollupSlice::Stream.new { |&emit| each_published(catalog, state, &emit) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: stream)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(state[:sha].hexdigest),
          citations: RollupSlice.citations(registry, state[:slugs].keys.sort),
          evaluation: census(catalog, state, count),
          overview: OVERVIEW
        )
      end

      private

      def registry
        @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
      end

      def each_published(catalog, state)
        grouped(catalog).each do |row|
          unless RollupSlice.publishable?(row[:license_class])
            state[:excluded][row[:license_class]] += 1
            state[:excluded_occurrences][row[:license_class]] += row[:occurrences]
            next
          end

          yield publish(state, row)
        end
      end

      # Gold rows, silver-estimate datings folded undated, regrouped on the
      # folded key; ordered (language, lemma, century, basis, source slug) —
      # slug, not source id, so the order survives a catalog rebuild.
      def grouped(catalog)
        rollup = :lemma_rollup
        century = RollupSlice.century_expression(rollup)
        basis = RollupSlice.basis_expression(rollup)
        catalog[rollup]
          .join(:sources, id: Sequel[rollup][:source_id])
          .where(Sequel[rollup][:grade] => GOLD_GRADE)
          .group(Sequel[rollup][:language], Sequel[rollup][:lemma], century, basis,
                 Sequel[:sources][:slug], Sequel[:sources][:license_class])
          .select(Sequel[rollup][:lemma], Sequel[rollup][:language], century.as(:century),
                  basis.as(:basis), Sequel[:sources][:slug], Sequel[:sources][:license_class],
                  Sequel.function(:sum, Sequel[rollup][:occurrences]).as(:occurrences),
                  Sequel.function(:sum, Sequel[rollup][:documents]).as(:documents))
          .order(Sequel[rollup][:language], Sequel[rollup][:lemma], century, basis, Sequel[:sources][:slug])
      end

      # The ID keys on a lemma DIGEST: a folded lemma is mostly non-ASCII
      # (Devanagari, Greek, cuneiform transliteration diacritics) and would
      # fold to nothing — or collide — under the CLDF identifier class. The
      # digest keeps the ID stable across releases; the IdMinter catches
      # any residual collision.
      def publish(state, row)
        slug = row[:slug]
        state[:slugs][slug] = true
        state[:by_language][row[:language]] += row[:occurrences]
        state[:sha] << [row[:lemma], row[:language], row[:century], row[:basis], slug,
                        row[:occurrences], row[:documents]].join("\x1f") << "\n"
        id = state[:minter].mint(slug, row[:language], RollupSlice.century_token(row[:century]),
                                 row[:basis], "L#{Digest::SHA256.hexdigest(row[:lemma])[0, 12]}")
        { "ID" => id, "Lemma" => row[:lemma], "Language_ID" => row[:language],
          "Century" => row[:century], "Basis" => row[:basis], "Occurrences" => row[:occurrences],
          "Documents" => row[:documents], "Source" => slug }
      end

      def census(catalog, state, count)
        rollup = catalog[:lemma_rollup]
        gold = rollup.where(grade: GOLD_GRADE)
        { "gold_rollup_rows" => gold.count,
          "silver_grade_rows_skipped" => rollup.exclude(grade: GOLD_GRADE).count,
          "silver_dated_rows_folded" => gold.where(basis: RollupSlice::SILVER_BASIS).count,
          "published_rows" => count,
          "excluded_rows" => RollupSlice.sorted_census(state[:excluded]),
          "excluded_occurrences" => RollupSlice.sorted_census(state[:excluded_occurrences]),
          "published_occurrences_by_language" => RollupSlice.sorted_census(state[:by_language]) }
      end

      def resource(count)
        fields = COLUMNS.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
        Resource.new(name: "lemma_frequencies", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(digest)
        "lemma-frequencies v1: project lemma_rollup grade gold at (lemma, language, century, basis, " \
          "source) grain, silver-estimate datings folded undated, license classes " \
          "#{RollupSlice::PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered (language, lemma, " \
          "century, basis, source); published-slice sha256=#{digest}"
      end
    end
  end
end
