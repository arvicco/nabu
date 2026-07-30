# frozen_string_literal: true

require_relative "errors"

module Nabu
  # The pure-Ruby Classical Tibetan word segmenter behind xct/segmentation
  # (P51-W5, promoted out of the build rail in P54-1: the producer side
  # trains it to PUBLISH the dataset, Nabu::TibetanWords trains it to
  # CONSUME the dataset back — one model, two lives): unigram-cost Viterbi
  # over tsheg-bar units
  # with a closed attached-clitic class. Tsheg (་) delimits SYLLABLES, not
  # words, so the segmenter's job is twofold: MERGE syllable runs into
  # multi-syllable words (སངས་རྒྱས), and SPLIT the attached clitics that hide
  # inside one tsheg-bar (བླ་མའི = བླ་མ + genitive འི; དཔེར = དཔེ + terminative ར).
  #
  # == The design, spike-calibrated (2026-07-29, full SOAS gold corpus)
  #
  # Measured against the SOAS gold segmentation (991 lines / 318,230
  # tokens, leave-one-text-out boundary F1 over char positions):
  #
  #   tsheg-syllable baseline                       0.8266
  #   + unconditional འ-clitic rule                 0.8474
  #   greedy maximal-match, lexicon + gold counts   0.9544
  #   unigram Viterbi (this class)                  0.9622
  #
  # External lexica measured unhelpful or harmful and are deliberately NOT
  # consumed: wiktionary-bo + Tibetan-verbs headwords added +0.0001 F1;
  # Mahāvyutpatti glossary phrases cost ~2 points of recall (they merge
  # what the gold splits). The segmenter therefore trains on gold token
  # counts alone — which keeps the feature's inputs exactly the ratified
  # pair (derge-kangyur, soas-tibetan) and no share-alike lexicon material
  # enters the published dataset.
  #
  # == The model
  #
  # A token vocabulary with counts defines word costs -log(count/total);
  # an unknown single tsheg-bar costs -log(UNKNOWN_PSEUDO_COUNT/total).
  # Viterbi finds the min-cost segmentation over edges:
  #   - one unit as a token (known or unknown),
  #   - a run of up to MAX_SPAN units as one known word,
  #   - either of the above with a trailing attached clitic split off —
  #     legal only when the remaining stem is itself a known word (native
  #     words end in ས/ར too; a stemless split would be invention).
  # Punctuation units (shad, head marks, digits) are their own tokens at a
  # fixed nominal cost; whitespace separates but never becomes a token.
  class TibetanSegmenter
    # One output token: the exact substring of the input text at +offset+.
    Token = Data.define(:form, :offset)

    # Tibetan letters/vowels/subjoined (U+0F00 syllable OM, U+0F40–U+0FBC);
    # everything else in a text is punctuation or whitespace.
    LETTERS = /[ༀཀ-ྼ]/
    # Tsheg and non-breaking tsheg — the syllable delimiters, kept attached
    # to the syllable they close (the SOAS gold convention).
    TSHEG = /[་༌]/

    # The closed attached-clitic class (SOAS gold census 2026-07-29:
    # 30,861 of 318,230 tokens begin mid-tsheg-bar; these particles cover
    # all but a residue of restarts/typos): genitive འི, agentive འིས,
    # terminative ར, agentive ས, final འོ, and the clitic conjunctions
    # འང/འམ. Longest first so འིས wins over འི.
    CLITICS = %w[འིས འི འོ འང འམ ར ས].freeze

    # Longest word run considered, in tsheg-bar units. Spike: F1 flat from
    # span 5 upward (0.9622 at 5 and 7); 5 keeps the lattice small.
    MAX_SPAN = 5

    # Pseudo-count for an unknown single tsheg-bar. Spike sensitivity:
    # F1 0.9616–0.9627 across 0.01–0.2 — the model is robust here.
    UNKNOWN_PSEUDO_COUNT = 0.05

    # Floor count for the clitics: they are function morphemes the split
    # edges must always be able to price, even in a fold whose training
    # text happens to lack one.
    CLITIC_FLOOR_COUNT = 1

    # Fixed nominal cost of a punctuation token (structure, not choice).
    PUNCTUATION_COST = 0.0

    class << self
      # Normalize a raw token/headword to a vocabulary key: trailing tsheg
      # stripped (interior tshegs are part of the word), nil when nothing
      # letter-material remains (punctuation and digits are not words).
      def word_key(raw)
        key = raw.to_s.sub(/#{TSHEG}+\z/o, "")
        return nil if key.empty? || !LETTERS.match?(key)

        key
      end

      # Build a segmenter from { word => count }. Keys are normalized via
      # .word_key (non-word keys are dropped); the clitics get a floor
      # count so split edges always exist.
      def train(counts)
        vocabulary = Hash.new(0)
        counts.each do |raw, count|
          key = word_key(raw)
          vocabulary[key] += count if key
        end
        CLITICS.each { |clitic| vocabulary[clitic] = CLITIC_FLOOR_COUNT if vocabulary[clitic].zero? }
        total = vocabulary.values.sum.to_f
        costs = vocabulary.transform_values { |count| -Math.log(count / total) }
        new(costs: costs, unknown_cost: -Math.log(UNKNOWN_PSEUDO_COUNT / total))
      end
    end

    def initialize(costs:, unknown_cost:)
      @costs = costs
      @unknown_cost = unknown_cost
    end

    # Segment +text+ into Tokens (min-cost path). Whitespace units are
    # dropped from the output; every Token is text[offset, form.length].
    def segment(text)
      units = scan_units(text)
      best, back = viterbi(units)
      raise Error, "segmentation lattice failed to reach the end of #{text.inspect}" if best.last.infinite?

      read_tokens(units, back).reject { |token| token.form.strip.empty? }
    end

    private

    # -- the unit scan ------------------------------------------------------

    Unit = Data.define(:string, :offset, :syllable)
    private_constant :Unit

    # Tsheg-bar units (letter run + trailing tshegs) and single-char
    # punctuation/whitespace units.
    def scan_units(text)
      units = []
      i = 0
      while i < text.length
        if LETTERS.match?(text[i])
          j = i
          j += 1 while j < text.length && LETTERS.match?(text[j])
          j += 1 while j < text.length && TSHEG.match?(text[j])
          units << Unit.new(string: text[i...j], offset: i, syllable: true)
          i = j
        else
          units << Unit.new(string: text[i], offset: i, syllable: false)
          i += 1
        end
      end
      units
    end

    # -- the lattice --------------------------------------------------------

    # Edge = [length in units, cost, clitic cut char-length or nil].
    def viterbi(units)
      best = Array.new(units.length + 1, Float::INFINITY)
      back = Array.new(units.length + 1)
      best[0] = 0.0
      (0...units.length).each do |i|
        next if best[i].infinite?

        edges(units, i) do |length, cost, cut|
          j = i + length
          total = best[i] + cost
          next unless total < best[j]

          best[j] = total
          back[j] = [i, cut]
        end
      end
      [best, back]
    end

    def edges(units, start)
      unless units[start].syllable
        yield 1, PUNCTUATION_COST, nil
        return
      end

      limit = [MAX_SPAN, units.length - start].min
      (1..limit).each do |length|
        break unless units[start + length - 1].syllable

        key = self.class.word_key(units[start, length].map(&:string).join)
        next if key.nil?

        cost = @costs[key]
        yield length, cost, nil if cost
        yield length, @unknown_cost, nil if length == 1 && cost.nil?
        clitic_edges(key) { |ccost, cut| yield length, ccost, cut }
      end
    end

    # A split edge exists only when the stem is a known word (native words
    # end in ར/ས/འི-like material too; a stemless split would be invention).
    def clitic_edges(key)
      CLITICS.each do |clitic|
        next unless key.end_with?(clitic) && key.length > clitic.length

        stem_cost = @costs[key.delete_suffix(clitic)]
        yield stem_cost + @costs.fetch(clitic), key.length - clitic.length if stem_cost
      end
    end

    # -- readout ------------------------------------------------------------

    def read_tokens(units, back)
      tokens = []
      upto = units.length
      while upto.positive?
        from, cut = back[upto]
        start = units[from].offset
        text = units[from...upto].map(&:string).join
        if cut
          tokens << Token.new(form: text[cut..], offset: start + cut)
          tokens << Token.new(form: text[0, cut], offset: start)
        else
          tokens << Token.new(form: text, offset: start)
        end
        upto = from
      end
      tokens.reverse!
      tokens
    end
  end
end
