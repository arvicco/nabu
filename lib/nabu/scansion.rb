# frozen_string_literal: true

require_relative "errors"
require_relative "normalize"

module Nabu
  # The SCANSION lane (P152): a rule-based syllabifier + quantitative scanner
  # for Greek and Latin dactylic verse — hexameter and the elegiac pentameter,
  # nothing else this phase. Honest and narrow by construction:
  #
  #   * quantities come ONLY from rules the text itself licenses — position
  #     (two consonants, x/z/ζ/ξ/ψ double), diphthongs, the Greek long/short
  #     letters and the marks that fix a dichronon (circumflex, iota
  #     subscript, macron, breve, the accent laws), Latin vocalis ante
  #     vocalem; every open syllable whose natural length the rules cannot
  #     know stays ANCEPS (no lexicon, no guessing);
  #   * muta cum liquida and epic correption are anceps (either reading);
  #   * elision is applied (Latin: final vowel / vowel+m before a vowel or
  #     h+vowel; Greek elides in writing, so the apostrophe already did it);
  #   * a line scans only when exactly ONE metrical template fits its
  #     quantities, or when the classical metrical laws (fifth-foot dactyl,
  #     a main caesura) leave exactly one — the result records which
  #     (`basis` :unique / :laws). No fit, an unbroken tie, a foreign
  #     script, an unsupported language: UNSCANNED with the reason, never
  #     a guess.
  #
  # What it cannot see (and so misses or, rarely, misreads): synizesis
  # (θεοί, Πηληϊάδεω, Lavinia as Lavinja), hiatus, metrical lengthening,
  # digamma effects, consonantal i/u in a u-only edition where the
  # orthography hides it (silua), Greek proper names with unusual vowel
  # lengths. The gold validation (Scansion::GoldCheck) measures the cost.
  module Scansion
    # Bumped whenever a rule changes what a line scans to — the shelf's
    # provenance stamp and its staleness test (MeterShelf) read it.
    VERSION = "nabu-scan/1"
    SCANNER = "nabu-scan"

    LANGUAGES = %w[lat grc].freeze

    # A passage longer than this is not a verse line (census 2026-11-02:
    # the longest gold-scanned line is 87 characters — pedecerto; 55 for
    # hypotactic): it is refused :too_long before any syllabification, so
    # a prose paragraph costs a length check.
    MAX_LINE_CHARS = 160

    # A line the syllabifier refuses (a foreign script, no letters): the
    # scanner turns it into an unscanned Result naming the reason.
    class Unscannable < Nabu::Error
      attr_reader :reason

      def initialize(message, reason: :unreadable)
        super(message)
        @reason = reason
      end
    end

    # One surviving syllable of a line: its letters, the quantity the rules
    # assign (:long / :short / :anceps — anceps = the rules cannot know),
    # the word it belongs to, whether it is the last SURVIVING syllable of
    # that word (caesurae read it), whether an elided syllable was dropped
    # right before it, and — for an anceps syllable only — the grammar
    # DEFAULT (:long / :short / nil) the tie-break tier may consult (Latin
    # final-syllable rules; Meters never lets it fail a template).
    Syllable = Data.define(:text, :quantity, :word, :word_final, :elided_before, :default) do
      def initialize(default: nil, **rest)
        super
      end
    end

    # One line's verdict. +meter+ :hexameter / :pentameter; +feet+ the
    # D/S string of the variable feet (hexameter feet 1-5, pentameter the
    # first hemiepes' two); +quantities+ one "-"/"u" per syllable in
    # template order (the final anceps shown as "-"); +basis+ :unique (one
    # template fit) or :laws (the metrical laws broke a tie). Unscanned:
    # +reason+ (:no_fit, :ambiguous, :ambiguous_meter, :foreign_script,
    # :unreadable, :unsupported_language, :too_long) and every metrical
    # field nil.
    Result = Data.define(:status, :meter, :feet, :quantities, :basis, :reason, :syllables) do
      def self.unscanned(reason, syllables: nil)
        new(status: :unscanned, meter: nil, feet: nil, quantities: nil, basis: nil,
            reason: reason, syllables: syllables)
      end

      def scanned? = status == :scanned

      # The quantities grouped by word ("-uu -- -uu" — the hypotactic
      # display), from the syllables' word indices.
      def word_pattern
        return nil unless scanned?

        groups = syllables.each_with_index.chunk_while { |(a, _), (b, _)| a.word == b.word }
        groups.map { |group| group.map { |(_, i)| quantities[i] }.join }.join(" ")
      end
    end

    module_function

    # Scan one line of +language+ ("lat" / "grc"). +meters+ restricts the
    # templates tried (both by default — a line's meter is the scanner's
    # finding, never an input).
    def scan(text, language:, meters: Meters::ALL)
      syllabifier = { "lat" => Latin, "grc" => Greek }[language.to_s]
      return Result.unscanned(:unsupported_language) unless syllabifier
      return Result.unscanned(:too_long) if text.to_s.length > MAX_LINE_CHARS

      syllables = syllabifier.syllables(text)
      Meters.choose(syllables, meters: meters)
    rescue Unscannable => e
      Result.unscanned(e.reason)
    end

    # Display text per nucleus over a flattened unit stream (units answer
    # #kind :v/:c and #text): a consonant run between two nuclei gives its
    # LAST consonant to the next syllable's onset (two when they are a
    # stop + liquid), the rest closing the previous one; the line's first
    # and last runs attach whole. Cosmetic — quantities never read it.
    def syllable_texts(stream, nuclei)
      texts = nuclei.map { |pos| +stream[pos].text }
      texts[0] = stream[0...nuclei[0]].map(&:text).join + texts[0]
      nuclei.each_cons(2).with_index do |(a, b), k|
        run = stream[(a + 1)...b].map(&:text)
        cut = run.size >= 2 && "bcdgptfπβφτδθκγχ".include?(run[-2]) && "lrλρ".include?(run[-1]) ? 2 : 1
        cut = [cut, run.size].min
        texts[k] << run[0...(run.size - cut)].join
        texts[k + 1] = run[(run.size - cut)..].join + texts[k + 1]
      end
      texts[-1] << stream[(nuclei[-1] + 1)..].map(&:text).join
      texts
    end
  end
end

require_relative "scansion/meters"
require_relative "scansion/latin"
require_relative "scansion/greek"
require_relative "scansion/gold_check"
