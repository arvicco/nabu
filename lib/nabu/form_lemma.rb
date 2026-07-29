# frozen_string_literal: true

require "csv"

require_relative "normalize"

module Nabu
  # The Sanskrit form→lemma table (P51-W6): a pure READ seam over the
  # `san/form-lemma` dataset Nabu itself PUBLISHES to the nabu-data repo —
  # the two-way loop closed: `nabu data build` derives the table from the
  # held DCS gold annotations, the owner publishes it, and `nabu sync
  # nabu-data` lands the published dataset back under canonical/nabu-data/
  # where this resolver reads it. There is NO catalog table and NO
  # migration: nabu-data is a feature module (kind: module) in the
  # CldfSpine/Lila posture — absent file = lane off, byte-identical
  # behavior.
  #
  # == The dataset shape (grounded in the published bytes, repo @ c50ef93)
  #
  # form-lemma.csv (428,825 rows at v1.0.0):
  #   ID,Language_ID,Form,Unsandhied,Lemma,Lemma_ID,Part_Of_Speech,Count,Source
  # Form is the SURFACE (sandhied) token as attested, Unsandhied the DCS
  # unsandhied analysis (`_` = not recorded), Lemma/Lemma_ID the DCS gold
  # lemma, Count the attestation count for that exact row. One form maps to
  # MANY lemmas (tapa → tap VERB, tapa NOUN, tapas NOUN) and one lemma is
  # reached by many forms (the whole tapas paradigm). 2,988 rows carry an
  # EMPTY Form with Unsandhied `_` (lemma-only occurrences upstream) — they
  # index nothing here, honestly unreachable by form lookup.
  #
  # == Lookup contract
  #
  # Both Form and Unsandhied are indexed under the house Sanskrit fold
  # (Normalize.search_form, language "san" — NFC + downcase + diacritic
  # strip), the SAME key the define shelf and query side fold to, so a
  # query typed in IAST or its ASCII fold reaches the row either way
  # (tapasā and tapasa both fold to "tapasa"). #lookup returns Candidate
  # values aggregated per (lemma, lemma_id, pos) with counts summed,
  # attestation-count descending — the caller widens its query expansion
  # with the lemmas; nothing is labeled differently (the table feeds
  # LOOKUP, not attestation, so tier laundering is structurally impossible).
  #
  # The bulk fold takes a fast path: rows whose text is entirely the IAST
  # lowercase alphabet (the overwhelming majority) fold by a 1:1 tr table
  # PROVEN byte-identical to Normalize.search_form over the full published
  # file (1.27M strings, 0 mismatches, 2026-07-29); anything else — avagraha
  # apostrophes are fast-path, but upstream quirks like the mis-encoded
  # `kﾱp` rows or pluta `'gnī3r` are not — takes the house fold verbatim.
  class FormLemma
    # One lemma candidate for a queried form. +lemma_id+ is the DCS lemma id
    # (String, as published); +count+ sums every indexed row that reaches
    # this (lemma, lemma_id, pos) under the queried form's fold.
    Candidate = Data.define(:lemma, :lemma_id, :pos, :count)

    DATASET_FILE = File.join("san", "form-lemma", "form-lemma.csv")
    SLUG = "nabu-data"
    LANGUAGE = "san"

    # The IAST fast-path alphabet: 1:1 precomposed diacritic → base letter,
    # exactly what NFD + Mn-strip + downcase produces on these characters
    # (equality proven over the full published file, class note).
    TR_FROM = "āīūṛṝḷḹṃḥśṣṭḍṇñṅ"
    TR_TO   = "aiurrllmhsstdnnn"
    FAST_FOLDABLE = /\A[a-z '\-#{TR_FROM}]*\z/

    # Build a resolver from a canonical/nabu-data-shaped directory. A
    # missing dataset file loads empty (a partial tree stays honest).
    def self.load(dir)
      new(index: build_index(File.join(dir, DATASET_FILE)))
    end

    # Feature-detect the table from the owner's canonical tree: nil when
    # `nabu sync nabu-data` has not landed the dataset, so a corpus without
    # it behaves byte-identically (the lila/cldf-spine posture).
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, SLUG)
      File.file?(File.join(dir, DATASET_FILE)) ? load(dir) : nil
    end

    # The house Sanskrit fold — the SAME key the define shelf and query side
    # fold to (fast tr path where provably identical, class note).
    def self.fold(form)
      text = form.to_s
      return text.tr(TR_FROM, TR_TO) if FAST_FOLDABLE.match?(text)

      Nabu::Normalize.search_form(text, language: LANGUAGE)
    end

    # folded form => { [lemma, lemma_id, pos] => summed count }. Form and
    # Unsandhied both index the row; `_`/empty sides index nothing.
    def self.build_index(csv_path)
      return {} unless File.file?(csv_path)

      index = Hash.new { |h, k| h[k] = Hash.new(0) }
      CSV.foreach(csv_path, headers: true, encoding: Encoding::UTF_8) do |row|
        keys = %w[Form Unsandhied].filter_map do |column|
          value = row[column]
          fold(value) unless value.nil? || value.empty? || value == "_"
        end
        keys.uniq.each do |key|
          index[key][[row["Lemma"], row["Lemma_ID"], row["Part_Of_Speech"]]] += row["Count"].to_i
        end
      end
      index
    end

    def initialize(index:)
      @index = index
    end

    # Every lemma candidate whose Form or Unsandhied folds to +form+'s fold,
    # aggregated per (lemma, lemma_id, pos), attestation count descending
    # (lemma, then lemma_id break ties). [] when the table holds no such form.
    def lookup(form)
      grouped = @index.fetch(self.class.fold(form), nil) or return []
      grouped.map { |(lemma, lemma_id, pos), count| Candidate.new(lemma:, lemma_id:, pos:, count:) }
             .sort_by { |c| [-c.count, c.lemma, c.lemma_id] }
    end

    # How many distinct folded forms the table indexed (a diagnostic count —
    # Form and Unsandhied spellings of one row may share a key).
    def size
      @index.size
    end
  end
end
