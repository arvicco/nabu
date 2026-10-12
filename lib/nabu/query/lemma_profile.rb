# frozen_string_literal: true

require_relative "../normalize"
require_relative "../languages"
require_relative "../timeline"

module Nabu
  module Query
    # `nabu lemma FORM [--language X]` (P121-2): a lemma's attestation
    # profile read ONLY from the precompiled lemma_rollup (Store::LemmaRollup)
    # — first/last attested century with the date basis, a per-century curve
    # with gold and silver kept apart, the top sources, and the dictionary
    # shelves that carry the form. Every read is an indexed point lookup on
    # the rollup's (lemma, language, …) key or the dictionary's folded
    # headword; nothing scans passages or passage_lemmas (the desk-commands
    # law). An absent or never-built rollup is a +status+, never a scan.
    #
    # Folding follows the lemma-search contract: the form folds through the
    # Normalize.query_forms union (plus the explicit language's own fold),
    # and --language widens through Languages.code_variants so every stored
    # spelling of the code lands.
    class LemmaProfile
      # One century of the curve: signed index (nil = undated), label, and
      # per-grade { occurrences:, documents: } plus the bases seen there.
      Point = Data.define(:century, :label, :gold, :silver, :bases)

      # One source's share: slug, gold and silver attestation totals.
      SourceShare = Data.define(:slug, :gold, :silver)

      # A dictionary shelf carrying the form.
      DictionaryLink = Data.define(:slug, :urn, :headword, :gloss)

      # The edge of the dated range: century + label + the bases attesting it.
      Edge = Data.define(:century, :label, :bases)

      # +status+ :ok | :absent (no table: pre-migration catalog) | :unbuilt
      # (table empty) | :unattested (built, the form is not in it).
      Result = Data.define(:status, :form, :language, :languages, :first, :last, :curve,
                           :sources, :dictionary, :seconds)

      # const: render ceiling for the top-sources line — a UX bound, not a corpus claim
      TOP_SOURCES = 5
      # const: render ceiling for the dictionary links (`define` shows the full entry)
      DICTIONARY_LIMIT = 5
      ZERO = { occurrences: 0, documents: 0 }.freeze

      def initialize(catalog:)
        @catalog = catalog
      end

      def run(form, language: nil)
        started = clock
        result = ->(status, **fields) { empty_result(status, form, language, started, **fields) }
        return result.call(:absent) unless @catalog.table_exists?(Store::LemmaRollup::LEMMA_TABLE)
        return result.call(:unbuilt) if @catalog[Store::LemmaRollup::LEMMA_TABLE].empty?

        keys = folded_keys(form, language)
        rows = rollup_rows(keys, language)
        dictionary = dictionary_links(keys, language)
        return result.call(:unattested, dictionary: dictionary) if rows.empty?

        curve = build_curve(rows)
        dated = curve.reject { |point| point.century.nil? }
        Result.new(status: :ok, form: form, language: language,
                   languages: rows.map { |row| row[:language] }.uniq.sort,
                   first: edge(dated.first), last: edge(dated.last), curve: curve,
                   sources: top_sources(rows), dictionary: dictionary, seconds: clock - started)
      end

      private

      def empty_result(status, form, language, started, dictionary: [])
        Result.new(status: status, form: form, language: language, languages: [], first: nil, last: nil,
                   curve: [], sources: [], dictionary: dictionary, seconds: clock - started)
      end

      def folded_keys(form, language)
        keys = Nabu::Normalize.query_forms(form.to_s)
        keys |= Nabu::Languages.code_variants(language).map { |code| Nabu::Normalize.search_form(form, language: code) }
        keys.map(&:strip).reject(&:empty?).uniq
      end

      def rollup_rows(keys, language)
        ds = @catalog[Store::LemmaRollup::LEMMA_TABLE].where(lemma: keys)
        ds = ds.where(language: Nabu::Languages.code_variants(language)) if language
        ds.all
      end

      def build_curve(rows)
        rows.group_by { |row| row[:century] }
            .sort_by { |century, _| century.nil? ? Float::INFINITY : century }
            .map do |century, group|
              Point.new(century: century, label: century ? Nabu::Timeline.century_label(century) : "undated",
                        gold: tally(group, "gold"), silver: tally(group, "silver"),
                        bases: group.filter_map { |row| row[:basis] }.uniq.sort)
            end
      end

      # A document lives in one source with one basis, so summing documents
      # across rows is exact within a language; a profile spanning several
      # languages (no --language) may count a bilingual document once per
      # language — the per-language rows are what the rollup stores.
      def tally(group, grade)
        graded = group.select { |row| row[:grade] == grade }
        return ZERO if graded.empty?

        { occurrences: graded.sum { |row| row[:occurrences] }, documents: graded.sum { |row| row[:documents] } }
      end

      def edge(point)
        point && Edge.new(century: point.century, label: point.label, bases: point.bases)
      end

      def top_sources(rows)
        slugs = @catalog[:sources].where(id: rows.map { |row| row[:source_id] }.uniq).as_hash(:id, :slug)
        shares = rows.group_by { |row| row[:source_id] }.map do |source_id, group|
          SourceShare.new(slug: slugs.fetch(source_id, source_id.to_s),
                          gold: tally(group, "gold")[:occurrences], silver: tally(group, "silver")[:occurrences])
        end
        shares.sort_by { |share| [-(share.gold + share.silver), share.slug] }.first(TOP_SOURCES)
      end

      # The cheap dictionary hop: an indexed headword_folded equality, scoped
      # to the language's shelves when one was given. No shelf = no links.
      def dictionary_links(keys, language)
        return [] unless @catalog.table_exists?(:dictionary_entries)

        ds = @catalog[:dictionary_entries]
             .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
             .where(Sequel[:dictionary_entries][:headword_folded] => keys,
                    Sequel[:dictionary_entries][:withdrawn] => false)
        ds = ds.where(Sequel[:dictionaries][:language] => Nabu::Languages.code_variants(language)) if language
        ds.order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:entry_id])
          .limit(DICTIONARY_LIMIT)
          .select(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:urn],
                  Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:gloss])
          .map { |row| DictionaryLink.new(**row) }
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
