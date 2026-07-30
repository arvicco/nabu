# frozen_string_literal: true

require "csv"

require_relative "tibetan_segmenter"

module Nabu
  # Classical Tibetan word segmentation (P54-1): a pure READ seam over the
  # `xct/segmentation` dataset Nabu itself PUBLISHES to the nabu-data repo —
  # the consume-back loop closed: `nabu data build xct/segmentation` derives
  # the dataset from the held gold (SOAS) and curated Kangyur slice, the
  # owner publishes it, and `nabu sync nabu-data` lands it back under
  # canonical/nabu-data/ where this seam reads it. There is NO catalog table
  # and NO migration: nabu-data is a feature module (kind: module) in the
  # FormLemma posture — absent file = lane off, byte-identical behavior.
  #
  # == The dataset shape (grounded in the published bytes, repo @ 4640f73)
  #
  # segmentation.csv (319,162 rows):
  #   ID,URN,Passage_SHA256,Position,Form,Offset,Tier,Source
  # One row per token of a segmented passage, in order; Form is the token
  # exactly as segmented (gold tokens verbatim from the SOAS deposit, silver
  # tokens from the build-time segmenter), trailing tsheg included where the
  # source text carries one. Only the Form column matters here: token counts
  # over it ARE the vocabulary the promoted Nabu::TibetanSegmenter trains
  # on (the same unigram-cost Viterbi model the producer side calibrated at
  # boundary F1 0.9622 against the SOAS gold, leave-one-text-out).
  #
  # The CSV is read once at load; the trained segmenter is held for the
  # seam's lifetime. #segment returns the segmenter's own Token values
  # (Data.define(:form, :offset) — every form is the exact substring of the
  # input at its offset).
  class TibetanWords
    DATASET_FILE = File.join("xct", "segmentation", "segmentation.csv")
    SLUG = "nabu-data"

    # Build a seam from a canonical/nabu-data-shaped directory. A missing
    # dataset file loads empty (a partial tree stays honest): no vocabulary,
    # so segmentation falls back to tsheg-bar grain.
    def self.load(dir)
      new(counts: build_counts(File.join(dir, DATASET_FILE)))
    end

    # Feature-detect the dataset from the owner's canonical tree: nil when
    # `nabu sync nabu-data` has not landed it, so a corpus without it
    # behaves byte-identically (the lila/cldf-spine posture).
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, SLUG)
      File.file?(File.join(dir, DATASET_FILE)) ? load(dir) : nil
    end

    # Token counts over the published Form column. Punctuation and other
    # non-word forms stay in the tally here; TibetanSegmenter.train drops
    # them at vocabulary time (its word_key discipline).
    def self.build_counts(csv_path)
      return {} unless File.file?(csv_path)

      counts = Hash.new(0)
      CSV.foreach(csv_path, headers: true, encoding: Encoding::UTF_8) do |row|
        form = row["Form"]
        counts[form] += 1 unless form.nil? || form.empty?
      end
      counts
    end

    def initialize(counts:)
      @counts = counts
      @segmenter = TibetanSegmenter.train(counts)
    end

    # Segment +text+ into the segmenter's Token values (min-cost path over
    # the published vocabulary; clitic splits and multi-syllable merges
    # priced exactly as the producer side prices them).
    def segment(text)
      @segmenter.segment(text)
    end

    # How many distinct published Form spellings fed the vocabulary (a
    # diagnostic count — punctuation rows included; train drops those).
    def size
      @counts.size
    end
  end
end
