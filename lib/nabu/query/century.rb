# frozen_string_literal: true

require_relative "../timeline"
require_relative "../normalize"

module Nabu
  module Query
    # `nabu vocab --by-century [QUERY]` (P15-2, design doc §3 — the linguist
    # payoff): the diachronic shape of the DATED corpus. Without a query, a
    # per-century histogram of dated documents; WITH a text query, "plot this
    # word across centuries" — how many dated documents attest the term in each
    # century. Composes with --lang/--license/--from/--to/--place.
    #
    # == Document-grained, bucketed by earliest year (the reviewed bias, stated)
    #
    # The count is per DOCUMENT (a document attests the term or it doesn't). A
    # ranged document is bucketed in its not_before (earliest possible) century
    # only — deterministic, no fake midpoint, no double-counting — which the
    # fable review flagged as a systematic earlier-shift for HGV's numerous
    # precision="low" century-ranges. Honesty over hiding it: +multi_century+
    # counts the documents whose range spans more than one century, so the CLI
    # prints "bucketed by earliest year; N span multiple centuries".
    #
    # The signed century index (Nabu::Timeline) is the bucket key AND the
    # chronological sort key (-2 < -1 < 1 < 2 = 2c BCE, 1c BCE, 1c CE, 2c CE),
    # so buckets need only be sorted by index.
    class Century
      # One century's tally: signed index, human label, document count.
      Bucket = Data.define(:index, :label, :documents)

      # The histogram + the honest denominators. +query+ echoes the term when
      # one was given (nil otherwise); +multi_century+ is the earlier-shift note.
      Result = Data.define(:buckets, :total_documents, :multi_century, :query)

      # Passage-id slices for the IN lookup (SQLite bound-variable ceiling), the
      # vocab/parallels precedent.
      SLICE = 500

      def initialize(catalog:, fulltext: nil)
        @catalog = catalog
        @fulltext = fulltext
      end

      def run(query: nil, lang: nil, license: nil, from: nil, to: nil, place: nil)
        rows = dated_documents(lang: lang, license: license, from: from, to: to, place: place)
        term = query.to_s.strip
        rows = restrict_to_term(rows, term, lang: lang) unless term.empty?
        build_result(rows, term.empty? ? nil : term)
      end

      private

      # Every dated, visible document as { document_id, not_before, not_after },
      # with the optional language/license/date/place filters applied directly
      # on the timeline join (one table, so no correlated EXISTS needed here).
      # DOCUMENT-grain rows only (passage_seq_from NULL): a chronicle's
      # passage-grain annal rows (P16-3) would count one document dozens of
      # times in a histogram labelled "documents" — its document-grain
      # envelope row represents it here instead.
      def dated_documents(lang:, license:, from:, to:, place:)
        axes = Sequel[:document_axes]
        ds = @catalog[:document_axes]
             .join(:documents, id: axes[:document_id])
             .join(:sources, id: Sequel[:documents][:source_id])
             .where(Sequel[:documents][:withdrawn] => false)
             .where(axes[:passage_seq_from] => nil)
        ds = ds.where(Sequel[:documents][:language] => lang) if lang
        ds = ds.where(license_expr => license) if license
        ds = ds.where(Sequel.expr(axes[:not_after] => nil) | (axes[:not_after] >= from)) if from
        ds = ds.where(Sequel.expr(axes[:not_before] => nil) | (axes[:not_before] <= to)) if to
        ds = ds.where(Sequel.ilike(axes[:place_name], place)) if place
        ds.select(axes[:document_id].as(:document_id),
                  axes[:not_before].as(:not_before),
                  axes[:not_after].as(:not_after)).all
      end

      # Keep only timeline rows whose document attests the term (any live passage,
      # language-scoped, matches the folded FTS query).
      def restrict_to_term(rows, term, lang:)
        matching = matching_document_ids(term, lang: lang)
        rows.select { |row| matching.include?(row.fetch(:document_id)) }
      end

      # The set of document_ids with a live passage matching the folded query —
      # the same fold-both-sides FTS contract as Search, unbounded (a histogram
      # needs every match, not a page).
      def matching_document_ids(term, lang:)
        return Set.new if @fulltext.nil?

        variants = Nabu::Normalize.query_forms(term)
        return Set.new if variants.first.strip.empty?

        match = variants.one? ? variants.first : variants.map { |v| "(#{v})" }.join(" OR ")
        passage_ids = @fulltext[Store::Indexer::TABLE]
                      .where(Sequel.lit("passages_fts MATCH ?", match)).select_map(:passage_id)
        document_ids_for(passage_ids, lang: lang)
      end

      def document_ids_for(passage_ids, lang:)
        ids = Set.new
        passage_ids.each_slice(SLICE) do |slice|
          ds = @catalog[:passages]
               .where(Sequel[:passages][:id] => slice, Sequel[:passages][:withdrawn] => false)
          ds = ds.where(Sequel[:passages][:language] => lang) if lang
          ds.select_map(:document_id).each { |id| ids << id }
        end
        ids
      end

      def build_result(rows, query)
        buckets = Hash.new(0)
        multi = 0
        total = 0
        rows.each do |row|
          nb = row.fetch(:not_before)
          na = row.fetch(:not_after)
          year = nb || na
          next if year.nil?

          buckets[Nabu::Timeline.century_index(year)] += 1
          total += 1
          multi += 1 if nb && na && Nabu::Timeline.century_index(nb) != Nabu::Timeline.century_index(na)
        end
        ordered = buckets.sort_by { |index, _| index }
                         .map { |index, n| Bucket.new(index: index, label: Nabu::Timeline.century_label(index), documents: n) }
        Result.new(buckets: ordered, total_documents: total, multi_century: multi, query: query)
      end

      def license_expr
        Sequel.function(:coalesce, Sequel[:documents][:license_override], Sequel[:sources][:license_class])
      end
    end
  end
end
