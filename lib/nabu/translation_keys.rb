# frozen_string_literal: true

require "json"

module Nabu
  # The per-source registry of ANNOTATION-HELD translations — the
  # translations index's extraction contract (Store::TranslationIndex,
  # architecture §5). Translation SIBLING documents (papyri, riig, etcsl,
  # lotsawa … — kind=translation) are ordinary passages and index with the
  # main fulltext machinery; this registry covers the other shape, where a
  # source carries its translation INSIDE the original passage's
  # annotations_json, under its own upstream key, verbatim (adapters never
  # rename upstream fields — the LemmaKeys precedent).
  #
  # Census of the live catalog, 2026-10-22 (passages carrying a registered
  # layer, of the source's live passages):
  #
  #   coptic-scriptorium  74,009 / 74,169   translation (+ _ar 1,052, _de 20,
  #                                          _horner 384)
  #   hittite-glossed     72,507 / 72,507   trans_de — German word glosses,
  #                                          " | "-joined in token order
  #   cdli                96,590 / 2.19M    tr.<code> — ATF #tr.en/de/it/fr/…
  #   ebl                 23,706 / 325,728  tr.<code> — the same ATF lines
  #   corph               17,818 / 17,942   translation
  #   ud                  11,857 / 329,980  translations.<comment key>
  #   tamilex              8,949 / 14,972   translation
  #   corpus-oudnederlands 5,274 / 5,745    translation
  #   stgall-priscian      3,527 / 13,395   translation (gloss renderings)
  #   aclt                 2,448 / 2,682    gloss — English word glosses,
  #                                          " | "-joined (the trans_de shape)
  #   diccas                 190 / 879      gloss_en (embedded English)
  #   old-nubian-ud          120 / 124      translations.translation (Russian)
  #   guaman-poma             43 / 5,911    translation (Spanish of Quechua)
  #   ko-wikisource-mk        29 / 159      modern (modern-Korean rendering)
  #
  # Deliberately NOT registered: itkc "translation_ref" (an id pointing at
  # the translation, not its text); corph "translation_notes" (editorial
  # notes); hittite-glossed "gloss" (grammatical tags, not a rendering);
  # the ATF "tr.ts" lane (a NORMALIZED TRANSCRIPTION of the original,
  # 9,172 cdli lines — not a translation); per-TOKEN gloss layers (aes,
  # bhsa, tlhdig … — the token-gloss lane's business, not passage-grain
  # translation text). rsti/ogham declare translation keys in their
  # adapters but carry none live (0 passages each, 2026-10-22).
  module TranslationKeys
    # One annotation key. +nested+: the value is a {sub-key => text} hash
    # (the ATF "tr" lane keyed by language code; the CoNLL-U sentence-
    # comment "translations" whitelist) — every sub-key is a layer except
    # +exclude+d ones. +reject+: a placeholder pattern whose matches mint
    # nothing (upstream's "still to translate" markers).
    Spec = Data.define(:key, :nested, :exclude, :reject) do
      def initialize(key:, nested: false, exclude: [].freeze, reject: nil) = super
    end

    # "[nog vertalen]" (331 live), "[nog te vertalen]", "[nog toevoegen]",
    # "[nog inkorten en vertalen]" … — the oudnederlands editors' to-do
    # markers; tamilex's "[translation to be added ]" likewise.
    OUDNEDERLANDS_TODO = /\A\[nog\b/i
    TAMILEX_TODO = /\A\[translation to be added/i

    ATF_TR = Spec.new(key: "tr", nested: true, exclude: %w[ts].freeze)
    CONLLU_TRANSLATIONS = Spec.new(key: "translations", nested: true)

    REGISTRY = {
      "aclt" => [Spec.new(key: "gloss")],
      "cdli" => [ATF_TR],
      "coptic-scriptorium" => %w[translation translation_ar translation_de translation_horner]
                              .map { |key| Spec.new(key: key) },
      "corph" => [Spec.new(key: "translation")],
      "corpus-oudnederlands" => [Spec.new(key: "translation", reject: OUDNEDERLANDS_TODO)],
      "diccas" => [Spec.new(key: "gloss_en")],
      "ebl" => [ATF_TR],
      "guaman-poma" => [Spec.new(key: "translation")],
      "hittite-glossed" => [Spec.new(key: "trans_de")],
      "ko-wikisource-mk" => [Spec.new(key: "modern")],
      "old-nubian-ud" => [CONLLU_TRANSLATIONS],
      "stgall-priscian" => [Spec.new(key: "translation")],
      "tamilex" => [Spec.new(key: "translation", reject: TAMILEX_TODO)],
      "ud" => [CONLLU_TRANSLATIONS]
    }.freeze

    # A layer must carry at least one letter: "...", "…", ". . .", and the
    # aclt/hittite " |  | " gap rows say "untranslated here", not text.
    LETTER = /\p{L}/

    module_function

    def slugs = REGISTRY.keys

    def registered?(slug) = REGISTRY.key?(slug)

    def specs_for(slug) = REGISTRY.fetch(slug, [])

    # The cheap substring probe run before a JSON parse — the vast
    # majority of a big source's passages (cdli: 96k of 2.19M) carry no
    # registered key at all.
    def probe?(json, specs) = specs.any? { |spec| json.include?("\"#{spec.key}\"") }

    # The passage's translation layers under +specs+: [[label, text], …]
    # in registry order (nested sub-keys in upstream order). The label is
    # the annotation key path ("translation", "tr.en",
    # "translations.text_en") — what the reader looks up in `nabu show`.
    # +annotations+ is the parsed hash or the stored JSON string.
    def layers(annotations, specs)
      return [] if specs.empty?

      if annotations.is_a?(String)
        return [] unless probe?(annotations, specs)

        annotations = JSON.parse(annotations)
      end
      return [] unless annotations.is_a?(Hash)

      specs.flat_map { |spec| spec_layers(annotations[spec.key], spec) }
    end

    def spec_layers(value, spec)
      if spec.nested
        return [] unless value.is_a?(Hash)

        value.filter_map do |sub, text|
          next if spec.exclude.include?(sub)

          layer("#{spec.key}.#{sub}", text, spec)
        end
      else
        [layer(spec.key, value, spec)].compact
      end
    end

    def layer(label, text, spec)
      return nil unless text.is_a?(String)

      text = text.strip
      return nil unless text.match?(LETTER)
      return nil if spec.reject&.match?(text)

      [label, text]
    end
  end
end
