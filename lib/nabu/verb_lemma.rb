# frozen_string_literal: true

require "csv"

require_relative "normalize"

module Nabu
  # The Tibetan verb stem→lemma table (P54-3): the SECOND consume-back seam
  # over a dataset Nabu itself PUBLISHES to the nabu-data repo — the
  # FormLemma posture exactly. `nabu data build` derives `xct/verb-lemma`
  # from the held Tibetan Verbs Database, the owner publishes it, and `nabu
  # sync nabu-data` lands it back under canonical/nabu-data/ where this
  # resolver reads it. There is NO catalog table and NO migration: nabu-data
  # is a feature module (kind: module) — absent file = lane off,
  # byte-identical behavior. The table feeds LOOKUP widening only, never
  # attestation, so tier laundering is structurally impossible.
  #
  # == The dataset shape (censused whole-file, repo @ 4640f73)
  #
  # verb-lemma.csv (3,889 rows at v1.0.0):
  #   ID,Language_ID,Lemma,Present,Past,Future,Imperative,Analysis_Source,Comment,Source
  # Lemma is ALWAYS the Present cell verbatim (3,889/3,889 rows), Tibetan
  # script. One lemma appears in multiple rows — one per Analysis_Source
  # (GT ×1,181, TDC ×1,236, PH ×683, KN ×789; 1,062 of 1,580 lemmas carry
  # 2+ sources): different grammarians' analyses, deliberately uncollapsed
  # upstream, and deliberately uncollapsed here — #lookup returns ALL of
  # them. Tense cells may be empty (14,672 of 15,556 are not); 1 corrupt
  # cell (row v-06fcdfbd2d45-KN carries the source token "TDC" as its
  # Imperative) indexes verbatim, the FormLemma kﾱp precedent.
  #
  # == The bracket notation (censused: 775 cells, 784 top-level groups)
  #
  # Stem cells ride TVD's ༼…༽ (U+0F3C/U+0F3D) notation, two flavors:
  #
  # - ༼ད༽ (685 groups) — the optional da-drag suffix: `ཀེར༼ད༽` is ཀེར
  #   or ཀེརད. Both variants index.
  # - ༼<form>༽ (99 groups) — an ALTERNATE form: `འཆོར༼ཤོར༽` is འཆོར
  #   or ཤོར; 6 groups NEST an optional suffix (`༼ཤོར༼ད༽༽` = ཤོར or
  #   ཤོརད), and 9 cells carry two top-level groups
  #   (`སྐྱོལ༼ད༽༼སྐྱོལ༽`). Alternates expand recursively.
  #
  # Every cell is base-then-trailing-groups (whole-file verified — no text
  # between or after groups, brackets always balanced); no other notation
  # exists (no separators, no spaces, no multi-variant cells beyond the
  # brackets). 84 Lemma cells are themselves bracketed — Candidate#lemma
  # keeps the published spelling verbatim (display honesty); callers widen
  # shelf lookups through .expand, which strips the notation.
  #
  # == Lookup contract (the fold decision)
  #
  # Every concrete variant of every non-empty tense cell is indexed under
  # the house Tibetan fold (Normalize.search_form, language "xct" — the
  # EWTS transcode; Tibetan script has no diacritic-strip fold, the
  # transcode IS the fold), the SAME key the define shelf and query side
  # produce for xct/bod/otb, so a query typed in Tibetan script or in
  # Wylie reaches the row either way (བཀོངས and bkongs are one key).
  # Brackets are expanded BEFORE folding — the transcoder would otherwise
  # carry them into the key (`ཀེར༼ད༽` folds to "ker༼da༽", reachable by
  # nobody).
  class VerbLemma
    # One paradigm-lemma candidate for a queried tense stem. +lemma+ is the
    # published Lemma spelling verbatim (possibly bracketed); +tense+ one of
    # TENSES; +analysis_source+ the grammarian attribution (GT/TDC/PH/KN).
    # Aggregated per distinct (lemma, tense, analysis_source) — every
    # analysis stays visible.
    Candidate = Data.define(:lemma, :tense, :analysis_source)

    DATASET_FILE = File.join("xct", "verb-lemma", "verb-lemma.csv")
    SLUG = "nabu-data"
    LANGUAGE = "xct"
    TENSES = %w[Present Past Future Imperative].freeze

    # The one bracketed SUFFIX the census found (685 of 784 groups): the
    # optional da-drag. Any other group content is an alternate form.
    SUFFIX_LETTER = "ད"

    # Build a resolver from a canonical/nabu-data-shaped directory. A
    # missing dataset file loads empty (a partial tree stays honest).
    def self.load(dir)
      new(index: build_index(File.join(dir, DATASET_FILE)))
    end

    # Feature-detect the table from the owner's canonical tree: nil when
    # `nabu sync nabu-data` has not landed the dataset, so a corpus without
    # it behaves byte-identically (the lila/form_lemma posture).
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, SLUG)
      File.file?(File.join(dir, DATASET_FILE)) ? load(dir) : nil
    end

    # The house Tibetan fold — the SAME key the define shelf and query side
    # fold xct/bod/otb text to (class note).
    def self.fold(form)
      Nabu::Normalize.search_form(form, language: LANGUAGE)
    end

    # Expand a published cell into its concrete variants (class note):
    # base first, then per group either the suffix-applied variant
    # (content == ད) or the recursively expanded alternate.
    def self.expand(cell)
      base, groups = split_groups(cell)
      variants = [base]
      groups.each do |content|
        if content == SUFFIX_LETTER
          variants << (base + SUFFIX_LETTER)
        else
          variants.concat(expand(content))
        end
      end
      variants.reject(&:empty?).uniq
    end

    # [base, top-level bracket groups] — depth-tracked so nested groups
    # stay inside their parent's content (balance whole-file verified;
    # an unclosed group, should upstream ever ship one, keeps its text).
    def self.split_groups(cell)
      base = +""
      groups = []
      buffer = nil
      depth = 0
      cell.each_char do |char|
        case char
        when "༼"
          depth += 1
          depth == 1 ? (buffer = +"") : (buffer << char)
        when "༽"
          depth -= 1 if depth.positive?
          if depth.zero? && buffer
            groups << buffer
            buffer = nil
          elsif buffer
            buffer << char
          else
            base << char
          end
        else
          buffer ? buffer << char : base << char
        end
      end
      groups << buffer if buffer
      [base, groups]
    end

    # folded variant => { [lemma, tense, analysis_source] => true }. Every
    # concrete bracket variant of every non-empty tense cell indexes.
    def self.build_index(csv_path)
      return {} unless File.file?(csv_path)

      index = Hash.new { |h, k| h[k] = {} }
      CSV.foreach(csv_path, headers: true, encoding: Encoding::UTF_8) do |row|
        TENSES.each do |tense|
          cell = row[tense]
          next if cell.nil? || cell.empty?

          expand(cell).each do |variant|
            index[fold(variant)][[row["Lemma"], tense, row["Analysis_Source"]]] = true
          end
        end
      end
      index
    end

    def initialize(index:)
      @index = index
    end

    # Every (lemma, tense, analysis_source) candidate whose stem cell — any
    # bracket variant — folds to +form+'s fold, ordered (lemma, tense in
    # TENSES order, source) for determinism. [] for an unknown form.
    def lookup(form)
      triples = @index.fetch(self.class.fold(form), nil) or return []
      triples.keys
             .map { |lemma, tense, source| Candidate.new(lemma:, tense:, analysis_source: source) }
             .sort_by { |c| [c.lemma, TENSES.index(c.tense), c.analysis_source.to_s] }
    end

    # How many distinct folded stem variants the table indexed (a
    # diagnostic count).
    def size
      @index.size
    end
  end
end
