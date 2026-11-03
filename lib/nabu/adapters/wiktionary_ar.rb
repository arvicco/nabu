# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # Wiktionary-Arabic: English Wiktionary's Arabic entries via the kaikki.org
    # wiktextract extraction — the wiktionary-fa mold on the shared
    # WiktionaryKaikki base, for the held Arabic text (openiti, kitab,
    # diccas, and the Arabic layers riding other sources). What it adds:
    # the library's first general Arabic
    # dictionary, vocalized headwords with Proto-Semitic, Aramaic, Akkadian,
    # Syriac and Greek etymons and descendant trees into Ottoman Turkish,
    # Persian, Urdu, Swahili, Maltese and the Arabic vernaculars.
    #
    # Stored language ara — the codemap's ar → ara, the registry's Arabic
    # anchor every held Arabic source writes. No classical/modern split is
    # minted here: Wiktionary's Arabic header covers both, and the senses'
    # own labels ride verbatim in the bodies ("(Classical)", "(Modern
    # Standard Arabic)" context labels from raw_glosses).
    #
    # == The parse rule: glossless records skip by rule
    #
    # The Arabic extract is mostly inflected-form STUBS: wiktextract emits
    # one record per Wiktionary form section, and Arabic verb paradigms
    # surface as hundreds of thousands of pages whose only sense is tagged
    # `form-N`, `no-gloss` — no gloss, no descendants, no etymon. Two shapes,
    # one rule (the record's first-glossed-sense gloss comes out nil, the
    # parser's own gloss column test):
    #
    # - the lemma-pointer stub: etymology "See the etymology of the
    #   corresponding lemma form.", sense tags form-N + no-gloss;
    # - the bare stub: no etymology at all, sense tags form-N + no-gloss
    #   (plus a handful of glossless nouns/adjectives and English-headword
    #   thesaurus records).
    #
    # Both are SKIPPED BY RULE in this subclass (never a family edit: the
    # shared parser and base stay byte-identical, so no other kaikki shelf's
    # derivation stamp moves) and censused in discovery_skips — the
    # wilkens-oui record-grain precedent: the count rides the parse on this
    # instance. Glossed form-of entries ("feminine singular of …") are kept
    # even when they carry the lemma-pointer etymology — the rule reads the
    # gloss, never the etymology text.
    #
    # == Upstream (verified 2026-11-03)
    #
    # https://kaikki.org/dictionary/Arabic/ — "177029 distinct words";
    # 868,082,330 B (Last-Modified 2026-10-30), 233,417 records by the
    # earlier full-file census, of which 196,443 glossless. Census here over
    # twenty 2 MB byte ranges (10,144 whole records, fixture README): 1,724
    # glossed / 8,171 lemma-pointer stubs / 249 bare stubs; 0 non-NFC; 0
    # duplicate ids; glossless records carry 0 reflex rows. Byte-scaled the
    # sample extrapolates to ≈37,400 glossed entries (s.e. ≈8,800) — the
    # full-file 36,974 sits inside it. Deprecation caveat and license: the
    # WiktionaryKaikki class note; fallback = filter the full extract by
    # lang_code == "ar".
    class WiktionaryAr < WiktionaryKaikki
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-ar",
        name: "Wiktionary Arabic — kaikki.org machine-readable extract",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Arabic/kaikki.org-dictionary-Arabic.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Arabic.jsonl"
      DICTIONARY_SLUG = "wiktionary-ar"
      LANGUAGE = "ara"
      TITLE = "Wiktionary — Arabic (kaikki.org extract)"

      # The lemma-pointer stub's etymology sentence, as the parser renders it
      # at the head of the body (verbatim upstream).
      LEMMA_POINTER = "See the etymology of the corresponding lemma form."

      # The record-grain census of the last parse on this instance (sync
      # calls this right after its load). Without a parse it says so.
      def discovery_skips(_workdir)
        census = @census or
          return DiscoverySkips.new(notes: ["record-grain census rides the parse — none ran on this instance"])

        skipped = census[:pointer] + census[:bare]
        DiscoverySkips.new(
          skipped_by_rule: skipped,
          notes: ["#{skipped} glossless record(s) skipped by rule — #{census[:pointer]} inflected-form " \
                  "stub(s) pointing at the corresponding lemma form, #{census[:bare]} bare no-gloss " \
                  "stub(s); #{census[:kept]} glossed entries kept"]
        )
      end

      def parse(document_ref)
        parsed = super
        document = Nabu::DictionaryDocument.new(
          slug: parsed.slug, language: parsed.language, title: parsed.title, canonical_path: parsed.canonical_path
        )
        census = { pointer: 0, bare: 0 }
        parsed.each do |entry|
          next document << entry unless entry.gloss.nil?

          census[entry.body.start_with?(LEMMA_POINTER) ? :pointer : :bare] += 1
        end
        @census = census.merge(kept: document.size)
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{manifest.id}: #{document_ref.id}: #{e.message}"
      end
    end
  end
end
