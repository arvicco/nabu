# frozen_string_literal: true

module Nabu
  # The per-source lemma-key registry (P118-R4 S1). The lemma index
  # (Store::Indexer, passage_lemmas) reads a token's dictionary form from
  # the "lemma" key — the treebank families' (CoNLL-U LEMMA, PROIEL
  # @lemma) shape. Some gold sources store their lexemes under their OWN
  # upstream names instead, verbatim (the adapters never rename upstream
  # features), and were therefore invisible to `search --lemma`:
  #
  # - bhsa: "lex_utf8" — the consonantal Hebrew/Aramaic lexeme ("אדם").
  #   "lex" is the ETCBC transliteration id (">DM/"), not a typable
  #   dictionary form; lex_utf8 is the same lexeme in the script users
  #   query in (homographs merge — the deliberate coarseness of a
  #   consonantal key; the passage still shows the pointed surface form).
  # - dss: Abegg's "lex" (pointed, verbatim with "_N" homograph suffixes
  #   and "#" uncertainty placeholders for unreadable letters) AND
  #   "lex_utf8_etcbc", the ETCBC-harmonized crosswalk into BHSA's lexeme
  #   space. Both mint keys; they fold together wherever they agree. The
  #   "_N" suffix is stripped (a homograph index, not part of the word); a
  #   lex carrying "#" is a partial reconstruction and mints nothing.
  #
  # NOT here (measured 2026-10-11 against the live catalog): peshitta and
  # cuc carry no lexeme layer at all — peshitta's "etcbc" is the surface
  # word's transliteration, cuc tokens carry signs only — so neither has a
  # key to register.
  #
  # A registered source reads ONLY its declared keys (never "lemma"), the
  # equivalence-tier discipline. Everything else keeps the default.
  module LemmaKeys
    Spec = Data.define(:keys, :reject, :strip)

    DEFAULT = Spec.new(keys: %w[lemma].freeze, reject: nil, strip: nil)

    REGISTRY = {
      "bhsa" => Spec.new(keys: %w[lex_utf8].freeze, reject: nil, strip: nil),
      "dss" => Spec.new(keys: %w[lex lex_utf8_etcbc].freeze, reject: "#", strip: /_\d+\z/)
    }.freeze

    module_function

    def spec_for(slug) = REGISTRY.fetch(slug, DEFAULT)

    # The token's dictionary forms under +spec+ (raw, upstream spelling
    # minus the declared homograph suffix), in key order.
    def lemmas(token, spec)
      return [] unless token.is_a?(Hash)

      spec.keys.filter_map do |key|
        value = token[key]
        next unless value.is_a?(String)

        next if spec.reject && value.include?(spec.reject)

        # Only a cleaning spec trims; the default keeps the lemma verbatim
        # (byte-identical rows for every pre-registry source).
        value = value.strip.sub(spec.strip, "") if spec.strip
        value.empty? ? nil : value
      end
    end

    # The cheap substring probe the indexer runs before a JSON parse.
    def probe?(json, spec) = spec.keys.any? { |key| json.include?("\"#{key}\"") }
  end
end
