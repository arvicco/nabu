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
  # The sibling of TranslationKeys, with one law of difference: most of
  # these layers are in the passage's OWN language (a standardized
  # spelling of the same Latin chant, the same print's Slovene margin
  # glosses), so each key declares its fold — :passage, the passage
  # language's full search_form rules (lat v→u/j→i, sl ſ→s …) — where the
  # translations lane folds its foreign renderings generically. A layer
  # plainly in a metalanguage (an editor's English notes on a Coptic
  # page) declares that language instead, or :generic when it has none
  # single.
  #
  # Census of the live catalog, 2026-11-07 (layer-bearing live passages /
  # the source's live passages, layer text bytes; exact, through this
  # registry's own extraction):
  #
  #   cantus              142,206 / 156,519      standardized   10.6 MB
  #   korpus16              6,735 / 12,902       notes           1.1 MB
  #   ticha                 1,040 / 1,103        regularized     1.5 MB
  #   grand-tour              445 / 515          regularized     0.7 MB
  #   ninjal-textdb         8,943 / 22,105       normalized      0.4 MB
  #   emmo                    189 / 196          regularized     0.1 MB
  #   memis                   470 / 473          diplomatic     10.0 kB
  #   cbeta               635,623 / 10,867,827   notes          31.1 MB
  #   sefaria              50,371 / 1,073,004    footnotes      26.4 MB
  #   suda-translations    31,327 / 31,341       notes          11.0 MB
  #   statutes-realm        8,036 / 8,053        marginal_notes + heading 1.2 MB
  #   senie                 1,935 / 48,995       marginalia      0.3 MB
  #   suttacentral         29,450 / 699,511      comments + variants 4.0 MB
  #   socinian-letters      2,699 / 18,067       notes           1.2 MB
  #   corph                 7,278 / 17,942       textual_notes   0.6 MB
  #   litopys                 496 / 964          variants + notes 1.3 MB
  #   comenius                954 / 1,384        notes + marginalia 0.2 MB
  #   coptic-scriptorium    2,154 / 74,778       notes           0.1 MB
  #   oshb                  2,753 / 23,213       notes           0.1 MB
  #   osta                    223 / 5,177        notes          53.7 kB
  #
  # 933,327 layer-bearing passages, 91.3 MB folded layer text.
  #
  # Deliberately NOT registered (yet): the reading aids (phonetic
  # transcriptions, kana/kundoku readings, ruby glosses, parallel source
  # texts) and the object-shaped notes of the TEI editions — each is a
  # declaration decision of its own, not this registry's default.
  module AnnotationKeys
    # The fold choices a key may declare (class note), beside a DECLARED
    # language code (LANGUAGE_FOLD) for a layer plainly written in a
    # metalanguage other than its passage's — English notes on Coptic
    # manuscripts, German notes on Latin letters: such a layer folds by its
    # own language's rules, never the passage's.
    FOLDS = %i[passage generic].freeze
    LANGUAGE_FOLD = /\A[a-z]{2,3}\z/

    # The markup a key may declare its values to carry: :html — an HTML
    # fragment (suttacentral's comments) whose tags are stripped before
    # the text indexes or snippets.
    MARKUPS = %i[html].freeze

    # const: an inline HTML tag (open, close or empty), attributes included
    HTML_TAG = %r{</?[A-Za-z][A-Za-z0-9]*(?:\s[^<>]*)?/?>}

    # One annotation key. The value is a string, or an array of strings
    # (each item its own layer under the same label — korpus16's notes).
    # +field+: the value is instead a LIST OF OBJECTS, each holding its
    # text under this object key (grand-tour's {place:, text:}); every
    # object is its own layer, a non-object or an object without the
    # field mints nothing. +fold+: FOLDS or a LANGUAGE_FOLD code.
    # +reject+: a placeholder pattern whose matches mint nothing.
    # +markup+: nil or one of MARKUPS.
    Spec = Data.define(:key, :fold, :reject, :field, :markup) do
      def initialize(key:, fold: :passage, reject: nil, field: nil, markup: nil)
        unless FOLDS.include?(fold) || (fold.is_a?(String) && fold.match?(LANGUAGE_FOLD))
          raise ArgumentError, "annotation key #{key}: fold must be one of #{FOLDS.inspect} or a language code"
        end
        unless field.nil? || (field.is_a?(String) && !field.empty?)
          raise ArgumentError, "annotation key #{key}: field must be a non-empty object key"
        end
        unless markup.nil? || MARKUPS.include?(markup)
          raise ArgumentError, "annotation key #{key}: markup must be one of #{MARKUPS.inspect}"
        end

        super
      end
    end

    # Cantus' lost-text marker (55 live standardized values): it marks a
    # lacuna, it spells nothing.
    CANTUS_LACUNA = /\ALACUNA\z/

    # Each line's fold is the census verdict on the layer's language: the
    # passage's own unless the layer is plainly a metalanguage, which is
    # then DECLARED (class note).
    REGISTRY = {
      "cantus" => [Spec.new(key: "standardized", reject: CANTUS_LACUNA)],
      "korpus16" => [Spec.new(key: "notes")],
      # The spelling layers: the same text in an editor's regularized,
      # normalized or diplomatic form — the passage's own language.
      "ticha" => [Spec.new(key: "regularized")],
      "grand-tour" => [Spec.new(key: "regularized")],
      "ninjal-textdb" => [Spec.new(key: "normalized")],
      "emmo" => [Spec.new(key: "regularized")],
      "memis" => [Spec.new(key: "diplomatic")],
      # Notes in the passage's own language: CBETA's collation and
      # phonetic glosses (lzh), Sefaria's footnotes (English on the
      # English renderings, Hebrew on the Hebrew editions), the Suda
      # translators' notes on their own English, SuttaCentral's Pali
      # variant readings, the Statutes' marginal summaries and headings,
      # the Hypatian chronicle's witness readings, the prints' own margins
      # (SENIE, Comenius).
      "cbeta" => [Spec.new(key: "notes")],
      "sefaria" => [Spec.new(key: "footnotes")],
      "suda-translations" => [Spec.new(key: "notes")],
      "statutes-realm" => [Spec.new(key: "marginal_notes"), Spec.new(key: "heading")],
      "senie" => [Spec.new(key: "marginalia")],
      # Notes in a DECLARED metalanguage: the editors' English (Sujato's
      # comments, CorPH's textual notes, the Coptic SCRIPTORIUM, OSHB and
      # OSTA transcribers' remarks), German (the Socinian letters'
      # commentary on Latin, French and Italian letters), the 1908
      # edition's pre-reform Russian (litopys' notes). Comenius' editorial
      # notes are Czech on the Czech editions and Dutch on the Dutch one —
      # neither has fold rules, so :generic is their exact fold and keeps
      # the Latin passages' j/v rules off Czech prose.
      "suttacentral" => [Spec.new(key: "comments", fold: "eng", markup: :html), Spec.new(key: "variants")],
      "socinian-letters" => [Spec.new(key: "notes", fold: "deu")],
      "corph" => [Spec.new(key: "textual_notes", fold: "eng")],
      "litopys" => [Spec.new(key: "variants"), Spec.new(key: "notes", fold: "rus")],
      "comenius" => [Spec.new(key: "notes", fold: :generic), Spec.new(key: "marginalia")],
      "coptic-scriptorium" => [Spec.new(key: "notes", fold: "eng")],
      "oshb" => [Spec.new(key: "notes", fold: "eng")],
      "osta" => [Spec.new(key: "notes", fold: "eng")]
    }.freeze

    # A layer must carry at least one letter: "*" anchors, bare verse
    # numbers and "{#}" illegibility marks are not searchable text.
    LETTER = /\p{L}/

    module_function

    def slugs = REGISTRY.keys

    def registered?(slug) = REGISTRY.key?(slug)

    def specs_for(slug) = REGISTRY.fetch(slug, [])

    # The language whose rules fold +spec+'s layers on a passage in
    # +language+: the passage's own, nil (generic), or the declared code.
    def fold_language(spec, language)
      case spec.fold
      when :passage then language
      when :generic then nil
      else spec.fold
      end
    end

    # The search form of one layer's +text+ under +spec+'s fold choice,
    # +language+ being the passage's own.
    def fold(text, spec, language)
      Normalize.search_form(text, language: fold_language(spec, language))
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

    def layer_text(item, spec)
      text = spec.field ? (item[spec.field] if item.is_a?(Hash)) : item
      return nil unless text.is_a?(String)

      text = text.gsub(HTML_TAG, "") if spec.markup == :html
      text = text.strip
      return nil unless text.match?(LETTER)
      return nil if spec.reject&.match?(text)

      text
    end
  end
end
