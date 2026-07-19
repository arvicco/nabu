# frozen_string_literal: true

require "nokogiri"

require_relative "../errors"
require_relative "../normalize"
require_relative "../model/document"
require_relative "../model/passage"

module Nabu
  module Adapters
    # Parser family "etcsl-tei" (P31-5): one ETCSL corpus file — a Sumerian
    # composite transliteration (transliterations/c.<num>.xml) or its paired
    # English prose translation (translations/t.<num>.xml) — into a
    # Nabu::Document.
    #
    # == The upstream shape (censused 2026-07-19 over all 394 c + 381 t files)
    #
    # TEI P4 ("TEI.2") in "XML ASCII Windows pc format" (upstream readme):
    # CRLF, no XML declaration, no DOCTYPE, named entities defined externally
    # (etcsl-sux.ent — NOT shipped inside the per-file bytes), so the files
    # are only well-formed XML after entity substitution: #decode replaces
    # every ETCSL entity from a closed table derived from etcsl-sux.ent and
    # the ISO sets actually used (census: 23 ISO names), and an UNKNOWN
    # entity raises ParseError — drift is loud, never silently dropped.
    #
    # Composites: <text lang="sux"> holds <l> lines — directly under <body>
    # (flat catalogues), under <div1 type="segment"> (narratives), under
    # <lg> line-groups (hymns) and inside <trailer> rubrics; the parser
    # walks //text/body//l uniformly in document order. Every l carries the
    # upstream id (c1821.A.1) whose after-prefix suffix (A.1) is the cite,
    # and usually corresp (t1821.p1) — the pointer to the paired translation
    # paragraph, kept as the "corresp" annotation. Every <w> carries the
    # hand-assigned lemma layer (lemma/pos/label + optional type, emesal,
    # det, bound, npart, form-type) — the "tokens" annotation, the same
    # per-token "lemma" contract the treebank families and OraccJsonParser
    # emit, so the P7-5 lemma index reads it for free. Tokens whose lemma is
    # upstream's illegibility placeholder (&X; → "…", or literal "X") carry
    # no lemma claim and are excluded from tokens; their surface stays in
    # the line text.
    #
    # Line text = the l subtree's text with editorial <note> subtrees (English,
    # with their xrefs) removed, whitespace collapsed: <supplied>/<damage>
    # milestone pairs and <corr>/<unclear>/<phr>/<distinct> wrappers
    # contribute exactly their textual content, so damage-split words stay
    # whole (ul<damageEnd/>-e → "ul-e"). ETCSL ASCII stays VERBATIM (c = š,
    # j = ĝ as upstream writes Sumerian) — canonical means canonical; only
    # ENTITIES decode, per the .ent file's own comments. Determinative
    # entities render in ORACC-style braces ({d}, {ki}, {jic}) — the closed
    # .ent list, kept in ETCSL's own ASCII spelling — so the second witness
    # reads beside epsd2/literary without pretending to be it.
    #
    # Translations: <text lang="eng"> holds <p> paragraphs (under body, div1,
    # lg or trailer — same uniform walk), each with id (t1821.p1 → cite p1),
    # n (the line-range, kept as "lines") and corresp (the anchor line in
    # the composite, kept as "corresp"). Paragraph text drops <note>
    # footnote apparatus, keeps <q>/<w>/<foreign>/<ref> content. Gap-only
    # paragraphs (367 upstream) parse to empty text and are skipped
    # honestly; the rare id-less prose paragraph (2 upstream) cites by
    # document position ("x<ordinal>").
    #
    # == Concordance (reference edges)
    #
    # Document metadata "related" carries the compact "etcsl:<num>" key
    # space: the file's OWN composition number first (the anchor the
    # epsd2/literary sibling's Q-number concordance meets), then every
    # //body//xref[@doc] target (the OB catalogues' incipit citations, the
    # narratives' catalogue cross-references), deduped in document order.
    class EtcslTeiParser
      URN_PREFIX = "urn:nabu:etcsl:"

      # The illegibility placeholders upstream lemmatizes as themselves
      # ("…" is the decoded &X;): surface text keeps them, the lemma layer
      # does not claim them.
      NON_LEMMAS = ["…", "X"].freeze

      # The five XML built-ins #decode leaves for Nokogiri.
      XML_BUILTINS = %w[amp lt gt quot apos].freeze

      # Character entities, per etcsl-sux.ent's own comments ("Latin letter
      # s with caron" etc.); &X; is upstream's horizontal ellipsis, &hr; a
      # physical tablet ruling (dropped — it is layout, not text). The
      # damb/dame/suppb/suppe/qryb/qrye helpers occur only inside corr/@sic
      # values (censused); they decode to the conventional epigraphic
      # brackets so a surfaced sic reads naturally.
      CHAR_ENTITIES = {
        "aleph" => "ʾ", "C" => "Š", "c" => "š", "G" => "G̃", "g" => "g̃",
        "H" => "Ḫ", "h" => "ḫ", "s" => "ṣ", "S" => "Ṣ", "t" => "ṭ", "T" => "Ṭ",
        "X" => "…", "hr" => "",
        "damb" => "[", "dame" => "]", "suppb" => "⟨", "suppe" => "⟩",
        "qryb" => "", "qrye" => "?", "subb" => "", "sube" => ""
      }.freeze

      # The ISO Latin/numeric/publishing entities the corpus actually uses
      # (census 2026-07-19: exactly these 23 names).
      ISO_ENTITIES = {
        "aacute" => "á", "oacute" => "ó", "eacute" => "é", "iacute" => "í",
        "egrave" => "è", "ecirc" => "ê", "icirc" => "î", "ucirc" => "û",
        "auml" => "ä", "ouml" => "ö", "uuml" => "ü",
        "amacr" => "ā", "emacr" => "ē", "imacr" => "ī", "umacr" => "ū",
        "Imacr" => "Ī", "Eacute" => "É", "Ccedil" => "Ç", "ccedil" => "ç",
        "commat" => "@", "sect" => "§", "times" => "×", "plus" => "+"
      }.freeze

      # Determinatives (the closed etcsl-sux.ent list), in ORACC-style
      # braces with ETCSL's own ASCII spelling (class note).
      DETERMINATIVES = %w[
        ance d dug f gi jic id2 e2 gud iku itid ki im kac ku6 kur kuc lu2
        m mu mul mucen na4 ninda sa sar cah2 tug2 tum9 u2 udu urud uzu zabar
      ].freeze

      # Subscript numerals ₀–₉ (&s0;–&s9;, translations only upstream).
      SUBSCRIPTS = (0..9).to_h { |d| ["s#{d}", [0x2080 + d].pack("U")] }.freeze

      ENTITIES = CHAR_ENTITIES
                 .merge(ISO_ENTITIES)
                 .merge(SUBSCRIPTS)
                 .merge(DETERMINATIVES.to_h { |name| [name, "{#{name}}"] })
                 .freeze

      # The w attributes that ride each token when present (the DTD's
      # lemma-layer surface; absent attributes are absent keys — the DTD's
      # "unspecified" defaults are never materialized).
      TOKEN_ATTRIBUTES = %w[form lemma pos type label emesal det bound npart form-type note].freeze

      # A composite (c.<num>.xml) into a sux Document at +urn+
      # (urn:nabu:etcsl:<num>).
      def parse_composite(path, urn:)
        document = build_document(path, urn: urn, expected_prefix: "c",
                                        language: "sux", kind: "composite") do |xml, doc|
          xml.xpath("//text/body//l").each_with_index do |line, index|
            append_line(doc, line, index: index, path: path)
          end
        end
        raise ParseError, "#{path}: no transliteration lines with text" if document.empty?

        document
      end

      # A translation (t.<num>.xml) into an eng Document at +urn+
      # (urn:nabu:etcsl:<num>-en).
      def parse_translation(path, urn:)
        document = build_document(path, urn: urn, expected_prefix: "t",
                                        language: "eng", kind: "translation") do |xml, doc|
          sequence = 0
          xml.xpath("//text/body//p").each_with_index do |paragraph, index|
            sequence += 1 if append_paragraph(doc, paragraph, index: index, sequence: sequence)
          end
        end
        raise ParseError, "#{path}: no translation prose found" if document.empty?

        document
      end

      # The translation paragraphs of a t file as [cite, text] pairs —
      # what the adapter's sibling-minting decision runs on (the riig
      # P25-3 doctrine: the minting decision IS the parser's own
      # extraction).
      def translation_paragraphs(path)
        xml = read(path)
        xml.xpath("//text/body//p").each_with_index.filter_map do |paragraph, index|
          text = content_text(paragraph)
          [cite_for(paragraph, fallback: "x#{index + 1}"), text] unless text.empty?
        end
      end

      private

      def build_document(path, urn:, expected_prefix:, language:, kind:)
        xml = read(path)
        number = composition_number(xml, path: path, expected_prefix: expected_prefix)
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path,
          title: title(xml),
          metadata: { "kind" => kind, "etcsl_no" => number, "related" => related(xml, number) }
        )
        yield xml, document
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # Strict Nokogiri over the entity-decoded bytes; XML damage quarantines
      # the document, never the sync.
      def read(path)
        xml = Nokogiri::XML(decode(File.read(path, encoding: "UTF-8"), path: path), &:strict)
        fatal = xml.errors.select { |e| e.error? || e.fatal? }
        raise ParseError, "#{path}: not well-formed XML: #{fatal.first}" unless fatal.empty?

        xml
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: not well-formed XML: #{e.message}"
      end

      def decode(raw, path:)
        raw.gsub(/&([A-Za-z][A-Za-z0-9]*);/) do
          name = Regexp.last_match(1)
          next "&#{name};" if XML_BUILTINS.include?(name)

          ENTITIES.fetch(name) do
            raise ParseError, "#{path}: unknown ETCSL entity &#{name}; (not in etcsl-sux.ent or the ISO census)"
          end
        end
      end

      # The TEI.2/@id ("c.1.8.2.1") minus its c./t. prefix — the ETCSL
      # composition number, which must agree with the file kind.
      def composition_number(xml, path:, expected_prefix:)
        id = xml.root&.[]("id").to_s
        number = id[/\A#{expected_prefix}\.(.+)\z/, 1]
        raise ParseError, "#{path}: TEI.2 id #{id.inspect} is not #{expected_prefix}.<number>" unless number

        number
      end

      def title(xml)
        raw = xml.xpath("//teiHeader//titleStmt/title").first&.text.to_s
        text = Nabu::Normalize.nfc(raw.gsub(/\s+/, " ").strip)
        text.empty? ? nil : text
      end

      # The //body//xref[@doc] targets as FULL urns, deduped in document
      # order — every target is an in-catalog etcsl document, and in-catalog
      # targets mint resolvable urns (the isicily→EDH precedent; compact
      # keys are for external id spaces like tm:). No self-loop: the
      # document's own number is metadata["etcsl_no"], and the epsd2
      # concordance producers target these same urns.
      def related(xml, number)
        keys = []
        xml.xpath("//text/body//xref[@doc]").each do |xref|
          target = xref["doc"][/\A[ct]\.(\d.*)\z/, 1]
          keys << "urn:nabu:etcsl:#{target}" if target && target != number
        end
        keys.uniq
      end

      def append_line(document, line, index:, path:)
        id = line["id"].to_s
        raise ParseError, "#{path}: l element without id (line #{index + 1} in document order)" if id.empty?

        text = content_text(line)
        return if text.empty? # gap/damage-only lines (censused: 15 upstream)

        annotations = {}
        tokens = lemma_tokens(line)
        annotations["tokens"] = tokens unless tokens.empty?
        corresp = cite_suffix(line["corresp"])
        annotations["corresp"] = corresp if corresp
        document << Nabu::Passage.new(
          urn: "#{document.urn}:#{cite_for(line, fallback: nil)}",
          language: document.language, text: text,
          annotations: annotations, sequence: document.count
        )
      end

      # Returns the appended document, or nil for a gap-only paragraph
      # (censused: 367 upstream) — the caller advances sequence only on nil-free
      # appends.
      def append_paragraph(document, paragraph, index:, sequence:)
        text = content_text(paragraph)
        return if text.empty?

        annotations = {}
        annotations["lines"] = paragraph["n"] if paragraph["n"]
        corresp = cite_suffix(paragraph["corresp"])
        annotations["corresp"] = corresp if corresp
        document << Nabu::Passage.new(
          urn: "#{document.urn}:#{cite_for(paragraph, fallback: "x#{index + 1}")}",
          language: document.language, text: text,
          annotations: annotations, sequence: sequence
        )
      end

      # The element's cite: its upstream id minus the document prefix
      # (c1821.A.1 → A.1, t1821.p1 → p1); +fallback+ covers the censused
      # id-less prose paragraphs.
      def cite_for(element, fallback:)
        cite_suffix(element["id"]) || fallback
      end

      def cite_suffix(id)
        id&.[](/\A[^.]+\.(.+)\z/, 1)
      end

      # The subtree's textual content with editorial <note> subtrees (English,
      # incl. their xrefs) removed and whitespace collapsed — milestones and
      # wrappers contribute exactly their text (class note).
      def content_text(element)
        pruned = element.dup
        pruned.xpath(".//note").each(&:remove)
        Nabu::Normalize.nfc(pruned.text.gsub(/\s+/, " ").strip)
      end

      # The lemma layer: every descendant w carrying a real lemma claim
      # (class note), attributes passed through under their own names.
      def lemma_tokens(line)
        line.xpath(".//w[@lemma]").filter_map do |w|
          next if NON_LEMMAS.include?(w["lemma"])

          TOKEN_ATTRIBUTES.each_with_object({}) do |name, token|
            token[name] = Nabu::Normalize.nfc(w[name]) if w[name]
          end
        end
      end
    end
  end
end
