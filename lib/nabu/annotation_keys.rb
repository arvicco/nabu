# frozen_string_literal: true

require "json"

require_relative "normalize"

module Nabu
  # The per-source registry of SEARCHABLE annotation layers — the
  # annotations index's extraction contract (Store::AnnotationIndex,
  # architecture §5). Some sources keep passage-grain TEXT a reader
  # searches for inside the passage's annotations_json, under its own
  # upstream key (verbatim — adapters never rename upstream fields, the
  # LemmaKeys / TranslationKeys precedent), where the main fulltext index
  # never reaches it. Declared, never sniffed: a key reaches search only by
  # a line here.
  #
  # The sibling of TranslationKeys, with one law of difference: these
  # layers are in the passage's OWN language (a standardized spelling of
  # the same Latin chant, the same print's Slovene margin glosses), so
  # each key declares its fold — :passage, the passage language's full
  # search_form rules (lat v→u/j→i, sl ſ→s …) — where the translations
  # lane folds its foreign renderings generically. :generic stays
  # available for a future layer in a metalanguage.
  #
  # Census of the live catalog, 2026-11-06 (layer-bearing live passages /
  # the source's live passages, layer text bytes):
  #
  #   cantus    142,290 / 156,519   standardized — Cantus' normalized
  #                                 spelling beside the manuscript's own
  #                                 (fulltext_standardized; 10.6 MB)
  #   korpus16    6,749 / 12,902    notes — the print's marginal notes,
  #                                 33,471 items (scripture references,
  #                                 Dalmatin's loanword glosses
  #                                 "Tabernakèl ali Cerkou"; 1.2 MB)
  #
  # Deliberately NOT registered (yet): the other string-valued layers the
  # census turned up (regularized/normalized spellings, margin notes and
  # footnotes, reading aids in other sources) — each is a declaration
  # decision of its own, not this registry's default.
  module AnnotationKeys
    # The fold choices a key may declare (class note).
    FOLDS = %i[passage generic].freeze

    # One annotation key. The value is a string, or an array of strings
    # (each item its own layer under the same label — korpus16's notes).
    # +fold+: FOLDS. +reject+: a placeholder pattern whose matches mint
    # nothing.
    Spec = Data.define(:key, :fold, :reject) do
      def initialize(key:, fold: :passage, reject: nil)
        raise ArgumentError, "annotation key #{key}: fold must be one of #{FOLDS.inspect}" unless FOLDS.include?(fold)

        super
      end
    end

    # Cantus' lost-text marker (55 live standardized values): it marks a
    # lacuna, it spells nothing.
    CANTUS_LACUNA = /\ALACUNA\z/

    REGISTRY = {
      "cantus" => [Spec.new(key: "standardized", reject: CANTUS_LACUNA)],
      "korpus16" => [Spec.new(key: "notes")]
    }.freeze

    # A layer must carry at least one letter: "*" anchors, bare verse
    # numbers and "{#}" illegibility marks are not searchable text.
    LETTER = /\p{L}/

    module_function

    def slugs = REGISTRY.keys

    def registered?(slug) = REGISTRY.key?(slug)

    def specs_for(slug) = REGISTRY.fetch(slug, [])

    # The search form of one layer's +text+ under +spec+'s fold choice,
    # +language+ being the passage's own.
    def fold(text, spec, language)
      Normalize.search_form(text, language: spec.fold == :passage ? language : nil)
    end

    # The cheap substring probe run before a JSON parse.
    def probe?(json, specs) = specs.any? { |spec| json.include?("\"#{spec.key}\"") }

    # The passage's searchable layers under +specs+: [[label, text], …] in
    # registry order (array items in upstream order). +annotations+ is the
    # parsed hash or the stored JSON string.
    def layers(annotations, specs) = spec_layers(annotations, specs).map { |label, text, _spec| [label, text] }

    # As +layers+, each entry carrying its Spec third (the fold choice).
    def spec_layers(annotations, specs)
      return [] if specs.empty?

      if annotations.is_a?(String)
        return [] unless probe?(annotations, specs)

        annotations = JSON.parse(annotations)
      end
      return [] unless annotations.is_a?(Hash)

      specs.flat_map do |spec|
        Array(annotations[spec.key]).filter_map do |text|
          text = layer_text(text, spec)
          [spec.key, text, spec] if text
        end
      end
    end

    def layer_text(text, spec)
      return nil unless text.is_a?(String)

      text = text.strip
      return nil unless text.match?(LETTER)
      return nil if spec.reject&.match?(text)

      text
    end
  end
end
