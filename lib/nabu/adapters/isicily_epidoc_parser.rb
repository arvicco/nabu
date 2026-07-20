# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "../date_axis"

module Nabu
  module Adapters
    # Parser family "isicily-epidoc" (P29-4): one I.Sicily (Prag, Oxford /
    # ERC Crossreads; github.com/ISicily/ISicily) EpiDoc TEI record — the
    # epigraphy of ancient Sicily across all its languages. A sibling of
    # EdhEpidocParser (whose header/facet/date extraction it mirrors) and
    # RiigEpidocParser (whose DOM shape and CelticLeiden reading-text
    # policy it shares — the module is the house Leiden doctrine, not a
    # Celtic-only one). DOM-based deliberately: 5,120 files, median
    # 12.7 KB, max 716 KB (the >5 MB Reader rule never engages), and
    # choice-branch selection needs name-based lookahead.
    #
    # == Content shape (full-corpus census, 2026-07-18, commit db1a4959)
    #
    #   div[@type="edition" @subtype="primary" @xml:space="preserve"
    #       @xml:lang] > (div[@type="textpart" @n])? > ab > lb/w/supplied/
    #   gap/unclear/expan/choice/orig/g/num/hi/persName…
    #
    # Sibling edition divs carry derivative layers: simple-lemmatized
    # (1,014 — mined for the words annotation below), transliteration
    # (631), PHI (10). Citable text = the primary layers only
    # (subtype "primary", plus the 13 records whose only edited text is
    # subtype "transliteration-primary").
    #
    # == --parallel siblings (P34-0)
    #
    # Two families of sibling document ride --parallel (adapter-minted,
    # registry-declared `siblings: ["-en", "-it", "-translit"]`):
    #   * -translit — the "transliteration" edition (a Latin-script
    #     RENDERING of a Greek-script carving), lines under the primary's
    #     OWN suffixes (line-for-line pairing), a bare layer marker. Minted
    #     on the 54 records whose transliteration edition carries citable
    #     letters (of 631 declared; 576 are empty <ab/> placeholders → mint
    #     nothing, the ogham/riig skip-by-rule discipline).
    #   * -en / -it — the <div type="translation"> prose (translations: true
    #     gates these). One passage per non-empty <p>, cited p<ordinal>; the
    #     first paragraph anchors at the primary's first line via a
    #     synthesized "corresp" (whole-text coarse block — the ETCSL
    #     loose-alignment mechanism, never per-line invention). 1,178 en /
    #     387 it records. Comment-placeholder and language-less divs mint
    #     nothing.
    #
    # == Passage = the LINE; textpart-relative numbering (the EDH shape)
    #
    #   urn = <document-urn>[:<textpart-n>…][:b<k>]:<lb n>
    #
    # Line numbers restart per textpart (ISic001895's two sections both
    # count from 1), so the textpart @n path is mandatory when textparts
    # exist; the collision-triggered implicit block (:b2…, DdbdpParser
    # P5-1) rides along defensively. <lb break="no"/> delimits like any lb
    # (the print-margin rule; upstream nests them INSIDE kept choice
    # branches — ISic000451's annu|s). An lb missing @n is a ParseError
    # (honest quarantine; 8 records corpus-wide).
    #
    # == Text policy (CelticLeiden + the I.Sicily dialect)
    #
    # - xml:space="preserve" on every edition div: whitespace between
    #   elements is REAL word division (no word-internal stripping — the
    #   opposite of RIIG's pretty-printed corpus); runs fold to one space
    #   at line finalization.
    # - choice → corr > reg > lem > expan (CelticLeiden). A BARE <orig>
    #   OUTSIDE any choice is KEPT: it is the letters-only edited text the
    #   Sicel/Elymian records publish (1,912 bare origs corpus-wide —
    #   dropping them would erase most of the scx corpus), where the
    #   DDbDP-family drop applies only to the choice-superseded branch.
    # - expan/abbr/ex read expanded; <am> (the abbreviation MARK itself)
    #   drops — the expanded reading excludes the graphical siglum.
    # - supplied/unclear read through and count; gap → "[…]"; del → ⟦…⟧;
    #   surplus → {…}; g/num/hi/persName/name/roleName/placeName/orgName/
    #   rs/seg keep their text (a SELF-CLOSED <g ref="#ivy-leaf"/> — 431
    #   corpus-wide — contributes nothing; decorative glyphs are not
    #   reading text, while a text-bearing <g>·</g> interpunct is).
    # - DROP: note, bibl, figure, desc, rdg, certainty (apparatus).
    #
    # == Metadata-only records (759 corpus-wide — the corpus's own shape)
    #
    # A record whose primary editions mint ZERO citable lines and whose
    # whole-edition extraction is empty is a catalogued monument, not a
    # parse failure: it parses to a zero-passage document marked
    # "text_layer" => "none" (the ogham/local-library precedent) so its
    # dating/findspot header and concordances still enter the catalog —
    # for Sicel (212/299 records) and Punic (53/67) the header IS most of
    # the machine-readable value. A record that extracts real text but
    # opens no line falls back to ONE whole-edition passage under the
    # stable :text suffix (the EDH P23-3c mechanism) — ZERO records at
    # the pinned commit (the one lb-less prose candidate, ISic002950,
    # keeps its words in a dropped <note>), kept so upstream adding
    # lb-less text can never silently vanish into a metadata-only stub.
    # Full-corpus quarantine floor at commit db1a4959: 46 — 34 lb without
    # @n, 7 textparts without @n, 5 records whose filename and in-file
    # <idno type="filename"> disagree (upstream drift, e.g. ISic001733's
    # idno says ISic001737) — all honest, none silent.
    #
    # == Languages (honest mapping, script subtags kept)
    #
    # Document language = msContents/textLang/@mainLang: la→lat, he→heb,
    # the explicit unknown "xx"→und, absent→und (2 records); grc/xly/scx/
    # xpu/osc are already ISO 639-3 and pass through. Passage language =
    # the edition div's @xml:lang, same mapping, keeping a VALID script
    # subtag ("osc-Grek", "scx-Grek", "xly-Grek" — Greek-script carvings
    # of non-Greek languages, the corpus's unique layer); a malformed
    # subtag ("scx-grc", 3 records — "grc" is a language, not a script) is
    # shed rather than invented. Fallback: the document language.
    #
    # == The lemma layer (1,005 records; 993/994 join cleanly)
    #
    # div[@subtype="simple-lemmatized"] repeats the text as <w n= lemma=>
    # tokens whose @n values match the primary edition's <w n=> — an
    # upstream lemmatization (Crellin) too good to drop. Each line's
    # annotations carry {"words" => [{"form", "n", "lemma"}, …]} for the
    # primary words whose @n finds a lemma; a word opened on one line
    # belongs to the line it STARTED on. No layer, no annotation.
    #
    # == Header layers → Document#metadata (the EDH/RIIG shape)
    #
    #   {"facets" => {"genre"/"material"/"object_type" =>
    #                   {"value" => term text, "raw" => vocabulary URI}},
    #    "tm"/"edr"/"edh"/"edcs"/"phi" => "…",   # non-empty idnos only
    #    "doi" => "10.5281/zenodo…", "uri" => "http://sicily…",
    #    "related" => ["tm:491696", "urn:nabu:edh:hd015282", …],
    #    "date" => {"not_before"/"not_after" (signed years via
    #               notBefore-custom/notAfter-custom, datingMethod
    #               "#julian"; plain notBefore/notAfter fallback)/"raw"/
    #               "cert"/"evidence"},
    #    "place" => {"region"/"ancient"/"modern"/"ancient_ref" (Pleiades)/
    #                "modern_ref" (GeoNames)/"geo" (verbatim WGS84)}}
    #
    # The EDH concordance target is the CATALOG urn (urn:nabu:edh:hd…):
    # I.Sicily's Latin records may intersect EDH's Sicily holdings, and
    # the standing doctrine keeps both as provenance-distinct witnesses —
    # the edge documents the overlap instead of hiding it (8 explicit EDH
    # idnos corpus-wide; the wider latent intersection is EDCS/TM-shaped
    # and stays un-guessed).
    #
    # == Identity
    #
    # <idno type="filename">ISic000001</idno> mints
    # urn:nabu:isicily:isic000001 (downcased); the caller-supplied urn
    # must equal the minting (mismatch → ParseError, the conformance
    # identity).
    class IsicilyEpidocParser
      URN_PREFIX = "urn:nabu:isicily:"

      # The whole-edition fallback's stable suffix (EDH P23-3c): minted
      # only when zero line suffixes exist — collision-free by rule.
      FALLBACK_SUFFIX = "text"

      DROPPED_ELEMENTS = %w[note bibl figure desc rdg certainty am].freeze

      # Edition subtypes whose text is the record's own edited reading.
      PRIMARY_SUBTYPES = %w[primary transliteration-primary].freeze

      # The transliteration edition (P34-0): a parallel Latin-script
      # RENDERING of the primary carving, minted as a -translit SIBLING
      # (the ogham/itant layer-sibling shape — suffix-equal to the primary,
      # so --parallel pairs line-for-line). Its own subtype, distinct from
      # the "transliteration-primary" records whose ONLY edited text it is.
      TRANSLITERATION_SUBTYPE = "transliteration"

      # The -translit sibling's urn suffix (abbreviated, the ogham -translit
      # precedent) — distinct from the edition SUBTYPE spelling above.
      TRANSLITERATION_URN_SUFFIX = "translit"

      # The parse layers: the base document (its primary editions + lemma
      # words + full header metadata) and the -translit layer sibling.
      PRIMARY_LAYER = :primary
      TRANSLITERATION_LAYER = :transliteration

      # <div type="translation"> @xml:lang spellings → ISO 639-3, the only
      # served translation languages (P34-0; 1,178 records mint an -en
      # sibling, 387 an -it, measured over the parser at commit db1a4959 —
      # the journal's div-count contract was 1,182 en / 389 it, the small
      # gap being multi-div records + divs whose prose folds empty).
      # Other-language and language-less divs (comment placeholders) mint
      # nothing.
      TRANSLATION_LANGUAGES = { "en" => "eng", "it" => "ita" }.freeze

      # The sibling census discovery reads: which -translit / translation
      # siblings a record's editions actually support (declared-but-empty
      # layers mint nothing — the ogham/riig discipline).
      Siblings = Data.define(:transliteration, :translations)

      # Upstream tags → ISO 639-3. "xx" is upstream's explicit unknown;
      # grc/xly/scx/xpu/osc/heb are already 639-3 and pass through.
      LANGUAGE_MAP = { "la" => "lat", "he" => "heb", "xx" => "und" }.freeze

      # A well-formed BCP-47 script subtag (Grek, Latn…). Anything else
      # after the hyphen ("scx-grc") is shed, never repaired.
      SCRIPT_SUBTAG = /\A[A-Z][a-z]{3}\z/

      # Concordance idno types → (metadata key, edge target builder).
      # EDH resolves inside the catalog (class note); the rest use their
      # compact stable-id schemes (the rig:/dil.ie precedent).
      CONCORDANCES = {
        "TM" => ["tm", ->(id) { "tm:#{id}" }],
        "EDR" => ["edr", ->(id) { "edr:#{id}" }],
        "EDH" => ["edh", ->(id) { "urn:nabu:edh:hd#{id.downcase}" }],
        "EDCS" => ["edcs", ->(id) { "edcs:#{id}" }],
        "PHI" => ["phi", ->(id) { "phi:#{id}" }]
      }.freeze

      # One extracted line of one edition.
      Line = Data.define(:urn_suffix, :text, :language, :annotations)
      private_constant :Line

      # Parse one record file's +layer+ into a Nabu::Document. The primary
      # layer (default) is the base document: zero citable lines → the
      # metadata-only document (class note), never a quarantine, and it
      # carries the lemma words + full header metadata. The transliteration
      # layer is the -translit SIBLING (P34-0): the Latin-script rendering's
      # lines under the SAME suffixes as the primary, a bare layer marker
      # for metadata, no lemma join, no metadata-only fallback (discovery
      # only mints the ref when the layer is citable).
      def parse(path, urn:, layer: PRIMARY_LAYER)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn, layer: layer)
        language = document_language(doc)
        return transliteration_document(doc, urn: urn, path: path, language: language) if layer == TRANSLITERATION_LAYER

        extraction = extract(doc, path: path, document_language: language)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc), canonical_path: path,
          metadata: metadata(doc, text_layer: extraction.any?)
        )
        append_lines(document, extraction, urn: urn)
        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The served translation prose as { "eng" => [[cite, text, corresp],
      # …], "ita" => … } — one entry per non-empty <p> of each served
      # translation div, cited "p<ordinal>". The FIRST paragraph anchors at
      # +anchor_suffix+ (the primary's first line — a whole-text coarse
      # block, the ETCSL corresp mechanism); later paragraphs carry nil
      # (no invented alignment). Empty/comment-only and other-language divs
      # yield nothing.
      def translations(path, anchor_suffix:)
        doc = read_xml(path)
        translation_pairs(doc, anchor_suffix: anchor_suffix)
      end

      # The sibling census for discovery (class note): the -translit layer's
      # citability + the served translation languages. Malformed XML raises
      # ParseError — the adapter turns that into the metadata-only ref whose
      # parse re-raises the honest quarantine.
      def siblings(path)
        doc = read_xml(path)
        language = document_language(doc)
        Siblings.new(
          transliteration: transliteration_citable?(doc, path: path, language: language),
          translations: translation_pairs(doc, anchor_suffix: nil).keys
        )
      end

      private

      def append_lines(document, extraction, urn:)
        extraction.each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: line.language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
      end

      # The -translit sibling document: the transliteration edition's lines
      # under the primary's own suffixes (line-for-line --parallel), a bare
      # layer marker, the record's mainLang identity.
      def transliteration_document(doc, urn:, path:, language:)
        document = Nabu::Document.new(
          urn: urn, language: language,
          title: transliteration_title(title_of(doc)), canonical_path: path,
          metadata: { "layer" => TRANSLITERATION_SUBTYPE }
        )
        extraction = extract(doc, path: path, document_language: language,
                                  subtypes: [TRANSLITERATION_SUBTYPE], fallback: false)
        append_lines(document, extraction, urn: urn)
        document
      end

      def transliteration_title(title)
        title ? "#{title} — transliteration" : "Transliteration"
      end

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + header ----------------------------------------------------

      # Validates the caller urn against the record's <idno filename>,
      # allowing the -translit sibling suffix, and returns the BARE base
      # urn (the primary document's urn).
      def validate_identity!(doc, path:, urn:, layer: PRIMARY_LAYER)
        filename = doc.at_xpath("//idno[@type='filename']")&.text.to_s.strip
        raise ParseError, "#{path}: no <idno type=\"filename\"> found in teiHeader" if filename.empty?

        minted = "#{URN_PREFIX}#{filename.downcase}"
        suffix = layer == TRANSLITERATION_LAYER ? "-#{TRANSLITERATION_URN_SUFFIX}" : ""
        return minted if "#{minted}#{suffix}" == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "<idno type=\"filename\"> #{filename.inspect} mints #{"#{minted}#{suffix}".inspect}"
      end

      def document_language(doc)
        normalize_language(doc.at_xpath("//msContents/textLang/@mainLang")&.value) || "und"
      end

      # LANGUAGE_MAP over the primary subtag; a valid script subtag
      # survives, a malformed one is shed (class note).
      def normalize_language(tag)
        tag = tag.to_s.strip
        return nil if tag.empty?

        primary, rest = tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary, primary)
        rest&.match?(SCRIPT_SUBTAG) ? "#{mapped}-#{rest}" : mapped
      end

      def title_of(doc)
        presence(doc.at_xpath("//titleStmt/title[not(@type)]")&.text) ||
          presence(doc.at_xpath("//titleStmt/title")&.text)
      end

      # -- document metadata ----------------------------------------------------

      def metadata(doc, text_layer:)
        result = {}
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        concordances(doc, result)
        %w[DOI URI].each do |type|
          value = presence(doc.at_xpath("//publicationStmt/idno[@type='#{type}']")&.text)
          result[type.downcase] = value if value
        end
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        result["text_layer"] = "none" unless text_layer
        result
      end

      FACET_SOURCES = {
        "genre" => "//textClass/keywords/term",
        "material" => "//physDesc//material",
        "object_type" => "//physDesc//objectType"
      }.freeze
      private_constant :FACET_SOURCES

      # value = the record's own EAGLE/I.Sicily term, raw = the vocabulary
      # URI (@ref, else @ana) when declared.
      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, xpath), facets|
          node = doc.at_xpath(xpath)
          value = presence(node&.text)
          next if value.nil?

          entry = { "value" => value }
          raw = presence(node["ref"] || node["ana"])
          entry["raw"] = raw if raw
          facets[facet] = entry
        end
      end

      # Non-empty concordance idnos → metadata keys + the links-journal
      # edge targets (adapter capability; class note for the EDH urn).
      def concordances(doc, result)
        related = []
        CONCORDANCES.each do |type, (key, target)|
          value = presence(doc.at_xpath("//publicationStmt/idno[@type='#{type}']")&.text)
          next if value.nil?

          result[key] = value
          related << target.call(value)
        end
        result["related"] = related unless related.empty?
      end

      # origDate → signed years. I.Sicily writes notBefore-custom/
      # notAfter-custom (datingMethod="#julian", signed historical years,
      # zero-padded; 2,117 BCE records); 3 records use the plain
      # attributes — the fallback. A year-0 bound ("-0000", 1 record) or
      # an unparseable one keeps raw/cert/evidence and drops the bounds
      # (the axis builder counts it invalid).
      def extract_date(doc)
        node = doc.at_xpath("//origin/origDate") or return {}
        result = {}
        begin
          not_before = DateAxis.parse_year(node["notBefore-custom"] || node["notBefore"])
          not_after = DateAxis.parse_year(node["notAfter-custom"] || node["notAfter"])
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue DateAxis::InvalidYear
          nil # bounds dropped; raw/cert/evidence still recorded below
        end
        { "raw" => presence(node.text), "cert" => presence(node["cert"]),
          "evidence" => presence(node["evidence"]) }.each { |key, value| result[key] = value if value }
        result
      end

      # origPlace: region + the ancient/modern placeName pair with their
      # gazetteer refs (Pleiades on ancient, GeoNames on modern — verbatim
      # strings, no gazetteer resolution); <geo> stays VERBATIM (canonical
      # means canonical — 27 records carry a "..." placeholder).
      def extract_place(doc)
        origin = doc.at_xpath("//origin/origPlace") or return {}
        ancient = origin.at_xpath("./placeName[@type='ancient']")
        modern = origin.at_xpath("./placeName[@type='modern']")
        result = {}
        { "region" => origin.at_xpath("./region")&.text,
          "ancient" => ancient&.text, "modern" => modern&.text,
          "geo" => origin.at_xpath("./geo")&.text }.each do |key, value|
          folded = presence(value)
          result[key] = folded if folded
        end
        { "ancient_ref" => ancient, "modern_ref" => modern }.each do |key, node|
          ref = node && presence(node["ref"])
          result[key] = ref if ref
        end
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- the edition walk -----------------------------------------------------

      # All citable lines of the record's +subtypes+ editions, in document
      # order; the whole-edition :text fallback (when +fallback+) if text
      # exists but no line opened; [] otherwise. The lemma join applies to
      # the primary layer only (the transliteration layer carries no
      # simple-lemmatized twin).
      def extract(doc, path:, document_language:, subtypes: PRIMARY_SUBTYPES, fallback: true)
        editions = doc.xpath("//div[@type='edition']").select do |div|
          subtypes.include?(div["subtype"])
        end
        lemmas = subtypes == PRIMARY_SUBTYPES ? lemma_index(doc) : {}
        extraction = Extraction.new(path: path, document_language: document_language)
        editions.each do |edition|
          language = normalize_language(edition["lang"]) || document_language
          extraction.edition(edition, language: language, lemmas: lemmas)
        end
        extraction.lines(fallback: fallback)
      end

      # True when the transliteration edition opens ≥1 citable LINE. Of the
      # 631 transliteration edition divs corpus-wide (commit db1a4959), 576
      # carry NO text (declared-but-empty `<ab/>` — the placeholders the
      # editors have not filled) and mint nothing (the ogham/riig skip-by-
      # rule discipline); the 54 with citable Latin-script letters mint a
      # -translit sibling. (The gap between 631 and 54 is the P34-0 census
      # honesty: the journal's "631 transliteration editions" counted every
      # declared layer, not the filled ones.)
      def transliteration_citable?(doc, path:, language:)
        extract(doc, path: path, document_language: language,
                     subtypes: [TRANSLITERATION_SUBTYPE], fallback: false).any?
      end

      # { "eng" => [[cite, text, corresp], …], "ita" => … } over the served
      # translation divs' non-empty <p>s (class note). The first paragraph
      # anchors at +anchor_suffix+ (nil during census, when only the served
      # languages matter), the rest at nil.
      def translation_pairs(doc, anchor_suffix:)
        pairs = {}
        doc.xpath("//div[@type='translation']").each do |div|
          language = TRANSLATION_LANGUAGES[div["lang"].to_s.strip]
          next if language.nil?

          seen = 0
          div.xpath("./p").each do |paragraph|
            text = presence(paragraph.text)
            next if text.nil?

            seen += 1
            (pairs[language] ||= []) << ["p#{seen}", text, seen == 1 ? anchor_suffix : nil]
          end
        end
        pairs
      end

      # @n → @lemma over the simple-lemmatized layer's tokens (class
      # note). {} when the record carries no layer.
      def lemma_index(doc)
        doc.xpath("//div[@type='edition'][@subtype='simple-lemmatized']//w")
           .each_with_object({}) do |word, index|
          n = word["n"].to_s.strip
          lemma = word["lemma"].to_s.strip
          index[n] = lemma unless n.empty? || lemma.empty?
        end
      end

      # Recursive-descent extraction state over the primary editions: the
      # textpart path, the open line, the word stack, the whole-edition
      # fallback buffer (see the class note).
      class Extraction
        def initialize(path:, document_language:)
          @path = path
          @document_language = document_language
          @raw_lines = []
          @current = nil
          @textparts = []
          @lb_ordinal = 0
          @words = [] # open <w> stack: {n:, form:, line:}
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
          @seen_suffixes = {}
          @block = 1
          @whole = { buffer: +"", gaps: [], supplied: 0, unclear: 0, cancelled: false }
        end

        def edition(node, language:, lemmas:)
          @language = language
          @lemmas = lemmas
          node.element_children.each { |child| walk(child) }
          close_line
        end

        def lines(fallback: true)
          previous_scope = :none
          result = @raw_lines.filter_map do |line|
            text = CelticLeiden.fold(line[:buffer])
            next if CelticLeiden.gap_only?(text)

            # A textpart is its own line-numbering universe: the implicit
            # restart block resets at its boundary (the EDH rule).
            scope = line[:textpath]
            @block = 1 if scope != previous_scope
            previous_scope = scope
            Line.new(urn_suffix: mint_suffix(line), text: text,
                     language: line[:language], annotations: annotations(line))
          end
          return result if !result.empty? || !fallback

          whole_edition_fallback
        end

        private

        # The :text fallback (class note): the editions' full extraction
        # when real text exists but no citable line was minted; [] when
        # nothing was extracted at all — the metadata-only document.
        def whole_edition_fallback
          text = CelticLeiden.fold(@whole[:buffer])
          return [] if CelticLeiden.gap_only?(text)

          leiden = CelticLeiden.leiden_annotations(
            gaps: @whole[:gaps], supplied: @whole[:supplied],
            unclear: @whole[:unclear], cancelled: @whole[:cancelled]
          )
          [Line.new(urn_suffix: IsicilyEpidocParser::FALLBACK_SUFFIX, text: text,
                    language: @language || @document_language,
                    annotations: leiden.empty? ? {} : { "leiden" => leiden })]
        end

        def walk(node)
          return text_node(node) if node.text?
          return unless node.element?

          name = node.name
          return if IsicilyEpidocParser::DROPPED_ELEMENTS.include?(name)

          case name
          when "div" then division(node)
          when "choice" then choice(node)
          when "lb" then line_break(node)
          when "gap" then gap(node)
          when "space" then emit(" ")
          when "w" then word(node)
          when "supplied" then counted(node, :supplied)
          when "unclear" then counted(node, :unclear)
          when "del" then wrapped(node, CelticLeiden::CANCELLATION_OPEN, CelticLeiden::CANCELLATION_CLOSE)
          when "surplus" then wrapped(node, CelticLeiden::SURPLUS_OPEN, CelticLeiden::SURPLUS_CLOSE)
          else recurse(node)
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        def text_node(node)
          emit(node.text)
        end

        def emit(text)
          return if text.empty?

          @whole[:buffer] << text
          @current[:buffer] << text if @current
          @words.last[:form] << text unless @words.empty?
          count_certainty(text)
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          if @supplied_depth.positive?
            @whole[:supplied] += count
            @current[:supplied] += count if @current
          end
          return unless @unclear_depth.positive?

          @whole[:unclear] += count
          @current[:unclear] += count if @current
        end

        # -- textparts ----------------------------------------------------------

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          n = node["n"].to_s.strip
          raise ParseError, "#{@path}: div[@type=\"textpart\"] is missing its @n" if n.empty?

          close_line
          @textparts.push(n)
          @block = 1
          recurse(node)
          close_line
          @textparts.pop
          @block = 1
        end

        # -- lines ----------------------------------------------------------------

        def line_break(node)
          @lb_ordinal += 1
          n = node["n"].to_s
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.empty?

          close_line
          @current = {
            n: n, textpath: @textparts.dup, buffer: +"", words: [], gaps: [],
            supplied: 0, unclear: 0, cancelled: @del_depth.positive?,
            language: @language
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # -- markers + counted spans ----------------------------------------------

        def gap(node)
          annotation = CelticLeiden.gap_annotation(node)
          @whole[:gaps] << annotation
          @current[:gaps] << annotation if @current
          gap_emit(CelticLeiden::GAP_MARKER)
        end

        # The marker bypasses certainty counting (it is notation, not
        # letters) but still lands in every open buffer.
        def gap_emit(marker)
          @whole[:buffer] << marker
          @current[:buffer] << marker if @current
          @words.last[:form] << marker unless @words.empty?
        end

        def counted(node, kind)
          variable = kind == :supplied ? :@supplied_depth : :@unclear_depth
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def wrapped(node, open, close)
          cancelling = open == CelticLeiden::CANCELLATION_OPEN
          if cancelling
            @del_depth += 1
            @whole[:cancelled] = true
            @current[:cancelled] = true if @current
          end
          gap_emit(open)
          recurse(node)
          gap_emit(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end

        # -- tokens ---------------------------------------------------------------

        def word(node)
          record = { n: node["n"].to_s.strip, form: +"", line: @current }
          @words.push(record)
          recurse(node)
          @words.pop
          attach_word(record)
        end

        # A word joins its line's words annotation iff the lemma layer
        # knows its @n (class note); it belongs to the line it started on.
        def attach_word(record)
          line = record[:line] || @current
          form = CelticLeiden.fold(record[:form])
          lemma = @lemmas[record[:n]]
          return if line.nil? || form.empty? || record[:n].empty? || lemma.nil?

          line[:words] << { "form" => form, "n" => record[:n], "lemma" => lemma }
        end

        # -- finalization ---------------------------------------------------------

        # [<textpart path>]:[b<k>]:<lb n>, collision-safe (DdbdpParser P5-1).
        def mint_suffix(line)
          loop do
            block = @block > 1 ? ["b#{@block}"] : []
            suffix = (line[:textpath] + block + [line[:n]]).join(":")
            if @seen_suffixes.key?(suffix)
              @block += 1
            else
              @seen_suffixes[suffix] = true
              return suffix
            end
          end
        end

        def annotations(line)
          result = {}
          leiden = CelticLeiden.leiden_annotations(
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear],
            cancelled: line[:cancelled]
          )
          result["leiden"] = leiden unless leiden.empty?
          result["words"] = line[:words] unless line[:words].empty?
          result
        end
      end
      private_constant :Extraction
    end
  end
end
