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
  #   cantus              142,206 / 156,519      standardized             10.6 MB
  #   korpus16              6,735 / 12,902       notes                     1.1 MB
  #   ticha                 1,040 / 1,103        regularized               1.5 MB
  #   grand-tour              489 / 515          regularized + marginalia
  #                                              + editorial_notes         0.7 MB
  #   ninjal-textdb        20,875 / 22,105       normalized + kanji_kana   1.0 MB
  #   emmo                    189 / 196          regularized               0.1 MB
  #   memis                   470 / 473          diplomatic               10.0 kB
  #   cbeta               635,623 / 10,867,827   notes                    31.1 MB
  #   sefaria              50,371 / 1,073,004    footnotes                26.4 MB
  #   suda-translations    31,327 / 31,341       notes                    11.0 MB
  #   statutes-realm        8,036 / 8,053        marginal_notes + heading  1.2 MB
  #   senie                 1,935 / 48,995       marginalia                0.3 MB
  #   evans-tcp            63,790 / 1,724,124    notes                    14.6 MB
  #   ecco-tcp            100,164 / 2,697,714    notes                    28.0 MB
  #   suttacentral         29,450 / 699,511      comments + variants       4.0 MB
  #   socinian-letters      2,699 / 18,067       notes                     1.2 MB
  #   corph                13,765 / 17,942       textual_notes + latin_text 3.6 MB
  #   litopys                 496 / 964          variants + notes          1.3 MB
  #   comenius                954 / 1,384        notes + marginalia        0.2 MB
  #   coptic-scriptorium    2,154 / 74,778       notes                     0.1 MB
  #   oshb                  2,753 / 23,213       notes                     0.1 MB
  #   osta                    223 / 5,177        notes                    53.7 kB
  #   perseus-greek        28,453 / 394,706      notes                     5.8 MB
  #   perseus-latin        28,801 / 405,989      notes                     6.0 MB
  #   first1k-greek        67,682 / 260,088      notes                    45.7 MB
  #   pta                      64 / 8,778        notes                    31.0 kB
  #   ja-wikisource         4,407 / 88,745       kundoku + kana            1.0 MB
  #   aozora              965,896 / 2,983,332    ruby                     29.9 MB
  #   ko-wikisource-mk         33 / 159          reading                   3.3 kB
  #   stgall-priscian      13,381 / 13,395       priscian                  0.9 MB
  #   lotsawa-house       111,994 / 413,067      phonetics                 3.9 MB
  #
  # 31 sources, 2,336,455 layer-bearing passages, 228.5 MB folded layer
  # text (a 194.7 MB lane, trial-built).
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
    # then DECLARED (class note). Grouped by layer kind below; a source
    # carrying several kinds lists them on its one line.
    #
    # The spelling layers — the same text in an editor's regularized,
    # normalized or diplomatic form, the passage's own language: cantus,
    # ticha, grand-tour, ninjal-textdb normalized, emmo, memis.
    #
    # Notes in the passage's own language: CBETA's collation and phonetic
    # glosses (lzh), Sefaria's footnotes (English on the English
    # renderings, Hebrew on the Hebrew editions), the Suda translators'
    # notes on their own English, SuttaCentral's Pali variant readings,
    # the Statutes' marginal summaries and headings, the Hypatian
    # chronicle's witness readings, the prints' own margins (korpus16,
    # SENIE, Comenius, grand-tour's {place:, text:} objects, and the TCP
    # prints' marginalia — evans, ecco — as {place:, n:, text:} objects).
    #
    # Notes in a DECLARED metalanguage: the editors' English (Sujato's
    # comments, CorPH's textual notes, the Coptic SCRIPTORIUM, OSHB and
    # OSTA transcribers' remarks), German (the Socinian letters'
    # commentary on Latin, French and Italian letters). :generic where the
    # metalanguage varies: Comenius' editorial notes (Czech on the Czech
    # editions, Dutch on the Dutch one — neither has fold rules, so
    # :generic is their exact fold and keeps the Latin passages' j/v rules
    # off Czech prose) and the TEI editions' <note> apparatus objects
    # (perseus' Loeb/English notes, First1K's and PTA's Latin, German and
    # Greek apparatus).
    #
    # litopys' notes are the 1908 edition's PRE-REFORM RUSSIAN; they fold
    # by orv deliberately — a folding-rule choice for findability, not a
    # language claim: orv's Cyrillic neutralization meets both the ѣ/і/ъ
    # spellings the notes carry and a modern-spelling query (имеется finds
    # имѣется), where rus (no rules) would miss them.
    #
    # The reading aids: the kanji-kana transcription of NINJAL's romanized
    # Amakusa prints (passage jpn), the Man'yōshū's kundoku and kana
    # readings (jpn — the readings are Japanese, the passages Old Japanese
    # man'yōgana), Aozora's ruby readings ({base:, reading:} — the kana a
    # reader types for the kanji the text prints), the hangul readings of
    # the Korean wikisource's hanmun (kor), the Latin text CorPH's and the
    # St Gall Priscian's Old Irish glosses sit on (lat), Lotsawa House's
    # recitation phonetics for its Tibetan verse (:generic — the site's own
    # phonetic system, not EWTS).
    #
    # HELD: stgall-priscian notes (manuscript cross-references, "= E
    # 12r4") and terms (the glossed Latin lemmata — a LemmaKeys candidate,
    # not an annotation layer); eebo-tcp notes (2.45M note-bearing
    # passages extrapolate to hundreds of MB — its own sizing decision).
    # DROPPED: otdo readings — {surface:, reading:} records how each
    # Tibetan letter-stack is written ("b +ng" for dbang), a paleographic
    # decomposition no reader types as a search.
    REGISTRY = {
      "cantus" => [Spec.new(key: "standardized", reject: CANTUS_LACUNA)],
      "korpus16" => [Spec.new(key: "notes")],
      "ticha" => [Spec.new(key: "regularized")],
      "grand-tour" => [Spec.new(key: "regularized"), Spec.new(key: "marginalia", field: "text"),
                       Spec.new(key: "editorial_notes", field: "text")],
      "ninjal-textdb" => [Spec.new(key: "normalized"), Spec.new(key: "kanji_kana")],
      "emmo" => [Spec.new(key: "regularized")],
      "memis" => [Spec.new(key: "diplomatic")],
      "cbeta" => [Spec.new(key: "notes")],
      "sefaria" => [Spec.new(key: "footnotes")],
      "suda-translations" => [Spec.new(key: "notes")],
      "statutes-realm" => [Spec.new(key: "marginal_notes"), Spec.new(key: "heading")],
      "senie" => [Spec.new(key: "marginalia")],
      "evans-tcp" => [Spec.new(key: "notes", field: "text")],
      "ecco-tcp" => [Spec.new(key: "notes", field: "text")],
      "suttacentral" => [Spec.new(key: "comments", fold: "eng", markup: :html), Spec.new(key: "variants")],
      "socinian-letters" => [Spec.new(key: "notes", fold: "deu")],
      "corph" => [Spec.new(key: "textual_notes", fold: "eng"), Spec.new(key: "latin_text", fold: "lat")],
      "litopys" => [Spec.new(key: "variants"), Spec.new(key: "notes", fold: "orv")],
      "comenius" => [Spec.new(key: "notes", fold: :generic), Spec.new(key: "marginalia")],
      "coptic-scriptorium" => [Spec.new(key: "notes", fold: "eng")],
      "oshb" => [Spec.new(key: "notes", fold: "eng")],
      "osta" => [Spec.new(key: "notes", fold: "eng")],
      "perseus-greek" => [Spec.new(key: "notes", field: "text", fold: :generic)],
      "perseus-latin" => [Spec.new(key: "notes", field: "text", fold: :generic)],
      "first1k-greek" => [Spec.new(key: "notes", field: "text", fold: :generic)],
      "pta" => [Spec.new(key: "notes", field: "text", fold: :generic)],
      "ja-wikisource" => [Spec.new(key: "kundoku", fold: "jpn"), Spec.new(key: "kana", fold: "jpn")],
      "aozora" => [Spec.new(key: "ruby", field: "reading")],
      "ko-wikisource-mk" => [Spec.new(key: "reading", fold: "kor")],
      "stgall-priscian" => [Spec.new(key: "priscian", fold: "lat")],
      "lotsawa-house" => [Spec.new(key: "phonetics", fold: :generic)]
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
