# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  # One citation a dictionary entry makes (P11-4). Minted only for <bibl>
  # elements whose @n carries a urn:cts: value; the human-readable display
  # ("Il. 1.1", "Cic. Off. 1, 2, 4") also flows into the entry body as plain
  # text, so URN-less citations are not lost — they simply mint no row.
  #
  # - +urn_raw+: the upstream @n verbatim (edition tokens, malformations and
  #   all — canonical means canonical).
  # - +cts_work+: the work-level prefix (urn:cts:<namespace>:<tg>.<work>),
  #   the resolution key — upstream edition tokens are dropped here because
  #   the lexica cite editions we may not hold (LSJ cites perseus-grc1, the
  #   catalog holds grc2); resolution re-anchors to whatever in-catalog
  #   edition of the WORK exists, at query time.
  # - +citation+: the dot-joined citation suffix ("1.1"), nil for bare work
  #   references.
  # - +label+: the human-readable citation text.
  DictionaryCitation = Data.define(:urn_raw, :cts_work, :citation, :label) do
    def initialize(urn_raw:, cts_work:, citation:, label:)
      super(
        urn_raw: Model::Validation.present_string!(urn_raw, field: "urn_raw"),
        cts_work: cts_work.nil? ? nil : Model::Validation.present_string!(cts_work, field: "cts_work"),
        citation: citation.nil? ? nil : Model::Validation.present_string!(citation, field: "citation"),
        label: Model::Validation.present_string!(label, field: "label")
      )
    end
  end

  # One descendant reflex a reconstruction entry names (P14-1): a worded
  # node of the kaikki `descendants` tree, flattened depth-first — the
  # machine-readable edge of the reconstruction crosswalk. The citation
  # pattern exactly: the parser mints it, the loader persists it, and
  # resolution against in-catalog lemmas happens at QUERY time only
  # (architecture §12) — nothing resolved is ever stored.
  #
  # - +lang_code+: the upstream Wiktionary code verbatim ("cu", "la",
  #   "zlw-ocs", even the lone malformed "ML." — canonical means canonical).
  # - +language+: the catalog-side language tag the fold and the crosswalk
  #   join speak — the parser's map for codes that differ (cu→chu, la→lat,
  #   sa→san), identity for shape-valid codes, nil for unmappable ones
  #   (nil = display-only, never a join candidate).
  # - +word+: the reflex verbatim, NFC (proto-to-proto reflexes keep their
  #   leading asterisk — upstream writes "*bogъ" under a PIE entry).
  # - +roman+: the upstream romanization when present — load-bearing for
  #   scripts the catalog's gold lemmas romanize (Gothic 𐌲𐌿𐌸 is unfindable;
  #   its roman "guþ" is a gold lemma).
  # - +word_folded+/+roman_folded+: conventions §9 search forms (leading
  #   asterisk stripped first — the define/etym query convention), folded
  #   with +language+; nil when unfoldable or when the fold comes out empty.
  # - +borrowed+ (P17-3): true when the upstream node carries a loan marker
  #   in raw_tags/tags ("borrowed", "learned borrowing" — the parser's
  #   /borrow/i census), false when parsed without one. The stored column
  #   is additionally nullable — NULL = "row predates the flag-aware
  #   reparse", an honest absence the parser itself never mints.
  # - +lang_name+ (P18-4): the upstream node's human `lang` name verbatim
  #   (NFC) — "Old Ruthenian" next to lang_code "zle-ort". NOT persisted per
  #   row and NOT part of the entry ContentHash (display metadata, not
  #   content identity): the loader aggregates it into the language_names
  #   census, which is what `nabu language` reads.
  DictionaryReflex = Data.define(:lang_code, :language, :word, :roman,
                                 :word_folded, :roman_folded, :borrowed, :lang_name) do
    def initialize(lang_code:, word:, language: nil, roman: nil, word_folded: nil,
                   roman_folded: nil, borrowed: false, lang_name: nil)
      unless [true, false].include?(borrowed)
        raise ValidationError, "borrowed must be true or false (parser-minted reflexes are never NULL)"
      end

      super(
        lang_code: Model::Validation.present_string!(lang_code, field: "lang_code"),
        language: language.nil? ? nil : Model::Validation.language!(language),
        word: Model::Validation.nfc_text!(word, field: "word"),
        roman: roman.nil? ? nil : Model::Validation.nfc_text!(roman, field: "roman"),
        word_folded: word_folded.nil? ? nil : Model::Validation.nfc_text!(word_folded, field: "word_folded"),
        roman_folded: roman_folded.nil? ? nil : Model::Validation.nfc_text!(roman_folded, field: "roman_folded"),
        borrowed: borrowed,
        lang_name: lang_name.nil? ? nil : Model::Validation.nfc_text!(lang_name, field: "lang_name")
      )
    end
  end

  # One dictionary entry (P11-4): what the lexicon-tei parser yields and the
  # DictionaryLoader persists. NOT a passage — dictionaries are a separate
  # surface (improvements §1.3) with their own storage shape.
  #
  # - +entry_id+: the upstream entry id (@id, e.g. "n67485") — the stable
  #   upsert key within a dictionary.
  # - +key_raw+: the upstream @key verbatim (betacode in LSJ, homograph
  #   digits in Lewis & Short).
  # - +headword+: the Unicode NFC display form (betacode decoded).
  # - +headword_folded+: the lookup key, folded per conventions §9 with the
  #   entry's language — the same both-sides contract as lemma search, which
  #   is what lets a treebank lemma hit find its gloss.
  # - +gloss+: a short first gloss (best-effort; nil when the entry has none).
  # - +body+: the whole entry as structured plain text (sense labels on their
  #   own lines), Greek decoded, NFC.
  # - +citations+: DictionaryCitation values in entry order.
  # - +reflexes+: DictionaryReflex values in descendants-tree depth-first
  #   order (P14-1) — empty for every non-reconstruction shelf.
  #
  # The P26-3 hbo/arc NFC exemption applies HERE too (P30-2): Masoretic
  # pointing is not NFC-stable (dagesh ccc 21 written before vowel points
  # ccc 10-19 — 3,217 of SDBH's 7,932 lemmas measured non-NFC), so an
  # exempt-language entry's display text (headword/gloss/body) is validated
  # byte-verbatim exactly as Passage text is; headword_folded is a SEARCH
  # form and keeps the NFC contract for every language.
  DictionaryEntry = Data.define(:entry_id, :key_raw, :language, :headword,
                                :headword_folded, :gloss, :body, :citations, :reflexes) do
    def initialize(entry_id:, key_raw:, language:, headword:, headword_folded:, body:,
                   gloss: nil, citations: [], reflexes: [])
      unless citations.is_a?(Array) && citations.all?(Nabu::DictionaryCitation)
        raise ValidationError, "citations must be an Array of Nabu::DictionaryCitation"
      end
      unless reflexes.is_a?(Array) && reflexes.all?(Nabu::DictionaryReflex)
        raise ValidationError, "reflexes must be an Array of Nabu::DictionaryReflex"
      end

      language = Model::Validation.language!(language)
      display_text = if Normalize.nfc_exempt?(language)
                       Model::Validation.method(:verbatim_text!)
                     else
                       Model::Validation.method(:nfc_text!)
                     end
      super(
        entry_id: Model::Validation.present_string!(entry_id, field: "entry_id"),
        key_raw: Model::Validation.present_string!(key_raw, field: "key_raw"),
        language: language,
        headword: display_text.call(headword, field: "headword"),
        headword_folded: Model::Validation.nfc_text!(headword_folded, field: "headword_folded"),
        gloss: gloss.nil? ? nil : display_text.call(gloss, field: "gloss"),
        body: display_text.call(body, field: "body"),
        citations: citations.freeze,
        reflexes: reflexes.freeze
      )
    end
  end
end
