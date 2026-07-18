# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # AES — Ancient Egyptian Sentences (P28-0): the TLA/BBAW January-2018
    # snapshot (github.com/simondschweitzer/aes) — 101,796 lemmatized
    # sentences / 13,026 texts / 16 subcorpus JSON files (~342 MB) spanning
    # the Pyramid Texts, Book of the Dead, Amarna, Ramesside letters,
    # medical and the sawlit literary canon. Every word form carries Unicode
    # transliteration + MdC + Gardiner-number and Unicode-hieroglyph
    # encodings + the TLA gold lemmatization (lemmaID + lemma_form) + fine
    # morphology + German glosses — the Egyptian gold-lemma mint.
    #
    # == Layout and grain (censused whole, 2026-07-18)
    #
    # files/aes/_aes_<subcorpus>.json is one JSON object of
    # sentenceID → sentence; each sentence carries text (the AED text id),
    # owner (editor), corpus, date, findspot, sentence_translation (German)
    # and the token array. Census: sentences are CONTIGUOUS per text in
    # file order in all 16 files, a text never spans subcorpora, sentence
    # ids are globally unique, and owner/date/findspot are constant per
    # text — so document = the TEXT (upstream's own unit, the AED id),
    # passage = the sentence, sequence = file order.
    #
    # == Identity (FROZEN minting)
    #
    #   document urn  urn:nabu:aes:<subcorpus>:<AED text id>
    #   passage urn   <document-urn>:<sentence id>   (upstream's stable id)
    #   German urn    <document-urn>-de:<sentence id> (see Translations)
    #
    # Text ids are uppercase base32-ish ([A-Z0-9]) and sentence ids
    # mixed-case — neither ever ends in "-de", so the sibling suffix is
    # unambiguous (the Damaskini literal-tail stance).
    #
    # == Language (the honest verdict) and surface
    #
    # The JSON carries NO language or stage tags (censused: no such field
    # exists in the schema or the data); the corpus is the TLA "Earlier
    # Egyptian" snapshot but spans OK through Roman times. The honest tag is
    # uniform `egy` (ISO 639-2 Egyptian (Ancient)) — stage subtags are never
    # invented. Passage text is the Unicode TRANSLITERATION (written_form,
    # space-joined) — the scholarly citation surface, the ORACC-translit
    # precedent; hieroglyphs ride the token annotations (a future display
    # mode can render them — journaled, backlog P28-0).
    #
    # == Two boundary regressions (real bytes pinned in tests)
    #
    # - THE KNOWN TRAP: hiero_unicode is HTML-ENTITY-ENCODED ("&#x13099;";
    #   all 241,414 occurrences hex-numeric, zero literal hieroglyphs) —
    #   decoded here at the boundary, never stored encoded.
    # - 13,682 written forms carry the deprecated U+2329/U+232A math angle
    #   brackets (editorial 〈supplements〉), which NFC canonically maps to
    #   U+3008/U+3009 — the standard boundary Normalize.nfc handles it.
    #
    # == Annotations (lean; only present keys) — the P28-1 join contract
    #
    #   {"tokens" => [{"form","mdc","lemma","lemma_id","gloss","line","pos",
    #                  <fine morphology verbatim: name/number/voice/genus/
    #                  pronoun/numerus/epitheton/morphology/inflection/
    #                  adjective/particle/adverb/verbalClass/status>,
    #                  "hiero","hiero_unicode","hiero_inventar"}…]}
    #
    # "lemma" = lemma_form (the shared treebank contract → passage_lemmas,
    # tier GOLD: TLA lemmatization is editor-verified annotation).
    # "lemma_id" = the AED lemmaID VERBATIM ("123130") — the TLA lemma
    # space. P28-1's AED dictionary mints entry ids from the same space, so
    # the join is EXACT STRING EQUALITY lemma_id == entry_id — no folding,
    # no transliteration round-trip. Token _id and zaehler are deliberately
    # not ingested (zaehler is the position we already keep as order; _id
    # joins only the excluded relANNIS export — journaled).
    #
    # A token-less sentence (3 corpus-wide, never a whole text) has no
    # citable Egyptian surface: no original passage, though its German
    # translation still rides the sibling (a one-sided parallel row).
    #
    # == Translations (registry `translations: true`, default inert)
    #
    # sentence_translation is the editor's German, 100,633/101,796 = 98.9%
    # coverage — one `-de` sibling document per text with ≥1 translated
    # sentence (file-driven at discover, the Damaskini shape), language
    # `ger` (the Freising German tag), passages on the SAME sentence ids so
    # `show --parallel ger` renders verse pairs. Same CC BY-SA grant ("All
    # files") — no license override.
    #
    # == Dates/findspot → the axis, subcorpus/period/findspot → facets
    #
    # date is one of SIX values corpus-wide ("OK & FIP", "MK & SIP", "NK",
    # "TIP - Roman times", "unknown", degenerate "k" ×2 sentences);
    # findspot one of 8 coarse regions. The four real periods and seven
    # real regions ride as facets (frozen census-complete maps below;
    # unmapped values keep the verbatim metadata but mint no facet and no
    # axis row — Store::AxisBuilder::AesDates counts them undated).
    #
    # == License / fetch / freshness
    #
    # CC BY-SA 4.0, verbatim in the repo README: "All files: CC-BY-SA 4.0"
    # → attribution. Fetch = the sparse GitFetch recipe (P26-0) scoped to
    # files/aes + the root README (the license grant): the files/relANNIS
    # zips (~114 MB, an ANNIS re-export of the same data) stay outside the
    # cone. The snapshot is FROZEN (January 2018; TLA itself is at corpus
    # v20) → sync_policy manual; the official TLA Hugging Face datasets are
    # the freshness channel (P28-2's lane).
    class Aes < Nabu::Adapter
      REPO_URL = "https://github.com/simondschweitzer/aes"

      # The sparse cone: the 16 subcorpus JSON files (+ schema + dir README)
      # and the root README that carries the license grant.
      SPARSE_PATHS = ["files/aes", "README.md"].freeze

      DATA_DIR = File.join("files", "aes").freeze

      LANGUAGE = "egy"
      TRANSLATION_LANGUAGE = "ger"
      TRANSLATION_SUFFIX = "-de"

      MANIFEST = Nabu::SourceManifest.new(
        id: "aes",
        name: "AES — Ancient Egyptian Sentences (TLA/BBAW snapshot, January 2018)",
        license: "CC BY-SA 4.0 (verbatim, repo README: \"All files: CC-BY-SA 4.0\")",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "aes-json"
      )

      URN_PREFIX = "urn:nabu:aes:"

      # The corpus's date vocabulary → facet slugs (census-complete over all
      # 101,796 sentences; "unknown" and the degenerate "k" deliberately
      # unmapped — verbatim metadata only, no facet, no axis row).
      PERIOD_FACETS = {
        "OK & FIP" => "ok-fip",
        "MK & SIP" => "mk-sip",
        "NK" => "nk",
        "TIP - Roman times" => "tip-roman"
      }.freeze

      # The corpus's findspot vocabulary → facet slugs (census-complete;
      # "unknown" unmapped — not a place).
      FINDSPOT_FACETS = {
        "Upper Egypt (South of Assiut)" => "upper-egypt",
        "Middle Egypt (from Kairo to Assiut)" => "middle-egypt",
        "Delta" => "delta",
        "Nubia" => "nubia",
        "Eastern Desert" => "eastern-desert",
        "Western Desert" => "western-desert",
        "Western Asia and Europe" => "western-asia-and-europe"
      }.freeze

      # f-object fields copied verbatim onto the token annotation when
      # present (beyond the renamed form/lemma/lemma_id/gloss/line five).
      TOKEN_COPY_FIELDS = %w[
        mdc pos name number voice genus pronoun numerus epitheton morphology
        inflection adjective particle adverb verbalClass status hiero
        hiero_inventar
      ].freeze

      # Numeric HTML character references — the ONLY entity shape censused
      # in hiero_unicode (all hex; decimal accepted belt-and-braces).
      ENTITY = /&#(x[0-9a-fA-F]+|\d+);/

      def self.manifest
        MANIFEST
      end

      # +translations+: when true (the registry row's posture), discover
      # also yields one -de sibling ref per text with ≥1 translated
      # sentence, parsed from the same subcorpus file.
      def initialize(translations: false)
        super()
        @translations = translations
        @cache = nil
      end

      # One DocumentRef per AED text across files/aes/_aes_*.json (plus -de
      # siblings when opted in), sorted by urn. A workdir without the tree
      # yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Originals rebuild the transliteration passages from the text's
      # sentence run; -de refs (metadata "kind" => "translation") mint the
      # German sibling from the same slice.
      def parse(document_ref)
        sentences = text_sentences(document_ref)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref, sentences)
        else
          parse_original(document_ref, sentences)
        end
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sparse GitFetch (class note): only the files/aes cone + the root
      # README materialize; the attic/breaker choreography is the shared one.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, DATA_DIR, "_aes_*.json")).flat_map do |path|
          subcorpus = File.basename(path)[/\A_aes_(.+)\.json\z/, 1]
          subcorpus_texts(path).flat_map do |text_id, sentences|
            text_refs(path, subcorpus, text_id, sentences)
          end
        end.sort_by(&:id)
      end

      def text_refs(path, subcorpus, text_id, sentences)
        urn = "#{URN_PREFIX}#{subcorpus}:#{text_id}"
        metadata = { "subcorpus" => subcorpus, "text" => text_id }
        refs = [Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn,
                                      path: File.expand_path(path), metadata: metadata)]
        if @translations && sentences.any? { |_sid, sentence| translated?(sentence) }
          refs << Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{urn}#{TRANSLATION_SUFFIX}", path: File.expand_path(path),
            metadata: metadata.merge("kind" => "translation")
          )
        end
        refs
      end

      # -- the per-file text index (one JSON parse per subcorpus file) -------

      # { text id => [[sentence id, sentence], …] in file order }, cached for
      # the LAST file read: refs sort by urn, so a sequential parse pass
      # (loader, conformance) re-reads each subcorpus file once, not once
      # per text. A ~90 MB subcorpus parses to a few hundred MB of Ruby
      # objects — held one file at a time, never all sixteen.
      def subcorpus_texts(path)
        expanded = File.expand_path(path)
        return @cache[1] if @cache && @cache[0] == expanded

        texts = Hash.new { |hash, key| hash[key] = [] }
        read_json(expanded).each { |sid, sentence| texts[sentence["text"].to_s] << [sid, sentence] }
        raise ParseError, "#{path}: sentence(s) without a text id — not an AES subcorpus file" if texts.key?("")

        @cache = [expanded, texts]
        texts
      end

      def read_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed AES JSON: #{e.message}"
      end

      def text_sentences(document_ref)
        text_id = document_ref.metadata.fetch("text")
        sentences = subcorpus_texts(document_ref.path)[text_id]
        if sentences.nil? || sentences.empty?
          raise ParseError, "#{document_ref.path}: text #{text_id.inspect} not found"
        end

        sentences
      end

      # -- the original (transliteration) document ---------------------------

      def parse_original(document_ref, sentences)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          metadata: document_metadata(document_ref, sentences.first[1])
        )
        sequence = 0
        sentences.each do |sid, sentence|
          tokens = Array(sentence["token"])
          next if tokens.empty? # no citable Egyptian surface (3 corpus-wide; class note)

          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sid}", language: LANGUAGE,
            text: Normalize.nfc(tokens.map { |token| token["written_form"].to_s }.join(" ")),
            annotations: { "tokens" => tokens.map { |token| annotation_token(token) } },
            sequence: sequence
          )
          sequence += 1
        end
        raise ParseError, "#{document_ref.id}: no sentence carries any token" if document.empty?

        document
      end

      # owner/date/findspot are constant per text (censused) — read off the
      # first sentence; verbatim values always, facets only for the mapped
      # vocabularies (class note).
      def document_metadata(document_ref, sentence)
        facets = { "subcorpus" => facet(document_ref.metadata.fetch("subcorpus")) }
        date = sentence["date"].to_s
        findspot = sentence["findspot"].to_s
        facets["period"] = facet(PERIOD_FACETS[date], raw: date) if PERIOD_FACETS.key?(date)
        facets["findspot"] = facet(FINDSPOT_FACETS[findspot], raw: findspot) if FINDSPOT_FACETS.key?(findspot)
        {
          "subcorpus" => document_ref.metadata.fetch("subcorpus"),
          "text_id" => document_ref.metadata.fetch("text"),
          "owner" => presence(sentence["owner"]),
          "date" => presence(date),
          "findspot" => presence(findspot),
          "facets" => facets
        }.compact
      end

      def facet(value, raw: value)
        { "value" => value, "raw" => raw }
      end

      def presence(value)
        value = value.to_s
        value.empty? ? nil : Normalize.nfc(value)
      end

      # One lean token annotation: renamed core fields, the fine morphology
      # verbatim, hiero_unicode entity-decoded (the P28-0 trap).
      def annotation_token(token)
        result = {}
        result["form"] = Normalize.nfc(token["written_form"].to_s)
        result["lemma"] = Normalize.nfc(token["lemma_form"]) if token["lemma_form"]
        result["lemma_id"] = token["lemmaID"] if token["lemmaID"]
        result["gloss"] = Normalize.nfc(token["cotext_translation"]) if token["cotext_translation"]
        result["line"] = token["lineCount"] if token["lineCount"]
        TOKEN_COPY_FIELDS.each do |field|
          result[field] = Normalize.nfc(token[field]) if token[field]
        end
        result["hiero_unicode"] = decode_entities(token["hiero_unicode"]) if token["hiero_unicode"]
        result
      end

      # "&#x13099;" → 𓂙. Hex or decimal numeric character references —
      # anything else (none censused) is left byte-verbatim, never guessed.
      def decode_entities(value)
        Normalize.nfc(value.gsub(ENTITY) do
          code = Regexp.last_match(1)
          (code.start_with?("x") ? code[1..].to_i(16) : code.to_i).chr(Encoding::UTF_8)
        end)
      end

      # -- the -de German sibling --------------------------------------------

      def parse_translation(document_ref, sentences)
        document = Nabu::Document.new(
          urn: document_ref.id, language: TRANSLATION_LANGUAGE,
          canonical_path: document_ref.path,
          metadata: { "kind" => "translation",
                      "subcorpus" => document_ref.metadata.fetch("subcorpus"),
                      "text_id" => document_ref.metadata.fetch("text") }
        )
        sequence = 0
        sentences.each do |sid, sentence|
          next unless translated?(sentence) # honest absence (98.9% coverage censused)

          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sid}", language: TRANSLATION_LANGUAGE,
            text: Normalize.nfc(sentence["sentence_translation"]), sequence: sequence
          )
          sequence += 1
        end
        raise ParseError, "#{document_ref.id}: no translated sentence in the text" if document.empty?

        document
      end

      def translated?(sentence)
        !sentence["sentence_translation"].to_s.empty?
      end
    end
  end
end
