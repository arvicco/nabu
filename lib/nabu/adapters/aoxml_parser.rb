# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for one hethiter.net AOxml manuscript file — the project's
    # AOxml family (P31-1; namespace http://hethiter.net/ns/AO/1.0 — the
    # Hethitologie-Portal Mainz's own format, NOT TEI). A standalone,
    # individually tested component the Tlhdig adapter composes; the format
    # is shared HPM plumbing, so other hethiter.net corpora could register
    # against this family later (CDLI/eBL discipline: source policy stays
    # out of the family core — this class takes identity from the caller
    # and never reads the CTH folder layout).
    #
    # == The shape (probed on real Beta 0.3 files, never invented)
    #
    #   <AOxml><AOHeader><docID>KBo 43.277</docID><meta>…</meta></AOHeader>
    #   <body><div1 type="transliteration"><text xml:lang="Hit">
    #     <AO:Manuscripts><AO:TxtPubl>KBo 43.277</AO:TxtPubl>…</AO:Manuscripts>
    #     <lb txtid="…" lnr="Rs.? 3′" lg="Hit" cu="𒋻𒈾𒄴𒄭𒀭"/>
    #       <w trans="tarnaḫḫi" mrp0sel=" "
    #          mrp1="tarn=a-@lassen@1SG.PRS@II.3@"
    #          mrp2="tarn=aḫḫ-@lassen@3SG.PRS@II.9@">t<del_fin/>ar-na-aḫ-ḫi</w> …
    #
    # == Passage = the LINE (the ORACC precedent)
    #
    # The citable unit is the tablet line: one passage per <lb>, its words
    # the <w> elements up to the next <lb> in document order (a rare <lb>
    # NESTED inside <w> — 207 corpus-wide — also opens a new line; the word
    # carrying it stays whole on the line open at its start). Passage#text
    # is the TRANSLITERATION (conventions §4; the Unicode cuneiform of the
    # line's cu= attribute rides annotations["cuneiform"], never the
    # surface). Lines whose words render to nothing (pure <space>
    # indentation, bracket-only stubs) mint no passage; a document with
    # ZERO renderable lines is a ParseError (quarantine — honest damage;
    # 226 upstream files are line-less conversion casualties, and 224 more
    # are not well-formed XML — both quarantine loudly, censused by sync).
    #
    # == Rendering (the in-file conventions, made plain text)
    #
    # Damage and editorial marks render as the standard Hittitological
    # transliteration signs the XML encodes: del_in/del_fin → [ ]
    # (destroyed), laes_in/laes_fin → ⌈ ⌉ (damaged), ras_in/ras_fin → ⟦ ⟧
    # (rasure), add_in/add_fin → ⟨ ⟩ (editorial addition), surpl → ⟨⟨…⟩⟩
    # (superfluous sign), corr → its own mark verbatim (?, !, sic —
    # upstream's editorial flag appended after the sign it qualifies),
    # subscr → Unicode subscript where one exists (waₐ), verbatim
    # otherwise. Determinatives (<d>) wrap in °…° — upstream's OWN plain-
    # text convention inside its mrp analyses ("LÚ˽°GIŠ°GIDRU").
    # Sumerograms/Akkadograms (<sGr>/<aGr>) render their content verbatim
    # and are recorded per token. <space c="n"/> is physical layout, not
    # text — it renders nothing. Anything else (num, c, PARSER_ERROR —
    # upstream's own converter-damage marker — and stray OpenDocument junk
    # elements) renders its text content verbatim: canonical means
    # canonical, and the fixture files pin the behavior.
    #
    # == The candidate-analysis layer (the lemma-tier evidence)
    #
    # Each <w> may carry numbered CANDIDATE morphological analyses
    # (mrp1..mrpN, "lemma@gloss@morph@class@extra") plus a selector mrp0sel:
    #
    #   " 1a"/"2 "/"1"  a digit picks candidate mrpN; a trailing letter
    #                   picks the sub-alternative from the candidate's
    #                   "{ a → NOM.SG(UNM)} { b → …}" morph list
    #   " "             candidates offered, NONE selected (unresolved)
    #   "DEL"           word too damaged to analyze
    #   "AKK"/"HURR"    word marked Akkadian/Hurrian, not analyzed
    #   "???"           unknown
    #
    # ALL candidate strings ride the token verbatim ("analyses", with
    # "selection" beside them — upstream's hypothesis layer, never
    # flattened). A "lemma" key is minted ONLY when the data itself is
    # unambiguous: a digit selection, or a single candidate with no
    # selector mark; multi-candidate unresolved words contribute NO lemma
    # (the goo300k discipline — measured corpus-wide: 453,819 of 757,728
    # analyzed words digit-selected + 95,986 single-candidate = 72.6%
    # disambiguated). The citation form is a documented deterministic
    # derivation of the raw lemma field (marker ① off, first slash
    # variant, parens/= separators off, trailing stem hyphen off:
    # "ḫuw=ai-" → "ḫuwai") so the folded key joins dictionary-side reflex
    # folds (the starling member-fold convention); the raw field survives
    # verbatim inside "analyses". The TIER is source policy, not family
    # policy: Tlhdig registers lemma_tier: silver.
    #
    # == Language: per-line honest, per-document majority
    #
    # Every <lb> carries lg=; the CENSUSED clean values map (Hit→hit,
    # Akk→akk, Sum→sux, Hur→xhu, Hat/Hattian→xht, Luw→xlu, Pal→plq) and
    # nothing else is ever invented: an unmapped value ("5f_", "ign",
    # attribute damage) yields language "und" with the raw value riding
    # annotations["language_raw"]; an EMPTY lg inherits the document
    # language. The document language is the majority over the mapped
    # line languages (ties → first attested), falling back to the
    # <text xml:lang> mapping ("XXXlang", upstream's placeholder, maps to
    # nothing), then "und".
    class AoxmlParser
      AO_NS = "http://hethiter.net/ns/AO/1.0"

      # The censused lb/@lg → ISO 639-3 map. Values outside this table are
      # never guessed (class note).
      LINE_LANGUAGES = {
        "Hit" => "hit", "Akk" => "akk", "Sum" => "sux", "Hur" => "xhu",
        "Hat" => "xht", "Hattian" => "xht", "Luw" => "xlu", "Pal" => "plq"
      }.freeze

      # The <text xml:lang> fallback map adds the one censused spelling
      # variant ("Hitt", 1 file); "XXXlang" (4,638 files) is upstream's
      # placeholder and deliberately maps to nothing.
      DOCUMENT_LANGUAGES = LINE_LANGUAGES.merge("Hitt" => "hit").freeze

      # Empty damage/editorial elements → their transliteration signs.
      MARKS = {
        "del_in" => "[", "del_fin" => "]",
        "laes_in" => "⌈", "laes_fin" => "⌉",
        "ras_in" => "⟦", "ras_fin" => "⟧",
        "add_in" => "⟨", "add_fin" => "⟩"
      }.freeze

      # Sign-variant subscripts with a clean Unicode subscript form; any
      # other subscr value renders verbatim (censused: a/u/e/i cover 97%).
      SUBSCRIPTS = {
        "a" => "ₐ", "e" => "ₑ", "i" => "ᵢ", "o" => "ₒ", "u" => "ᵤ", "x" => "ₓ"
      }.freeze

      # Elements that render nothing into the surface: physical layout,
      # apparatus, and the mid-word line break (class note).
      SILENT = %w[space note gap materlect lb].freeze

      # Same signature family as the sibling XML parsers; +cth+ and
      # +project+ are caller-supplied identity metadata (the Tlhdig
      # adapter derives them from the folder layout — this family never
      # reads paths).
      def parse(path, urn:, cth: nil, project: nil)
        doc = read_xml(path)
        lines = extract_lines(doc, path)
        raise ParseError, "#{path}: no renderable transliteration lines (AOxml damage or a line-less stub)" if
          lines.empty?

        build_document(doc, lines, path: path, urn: urn, cth: cth, project: project)
      end

      private

      # Strict parse: 224 upstream files are not well-formed (broken
      # attribute syntax, mismatched tags — Beta reality, admitted by the
      # deposit's own description). Recovery would silently invent a tree;
      # quarantine is the honest fate.
      def read_xml(path)
        Nokogiri::XML(File.read(path), path, &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: not well-formed AOxml: #{e.message}"
      end

      Line = Struct.new(:lnr, :lg, :cu, :words, :gaps, :notes, :kola, :paragraph, keyword_init: true)
      private_constant :Line

      # One document-order walk over body. lb opens a line (nested-in-word
      # lbs included — class note); outermost <w> joins the open line;
      # gap/parsep/clb/note ride the open line's annotations. Anything
      # inside <AO:Manuscripts> is the witness block (or, in damaged files,
      # mangled transliteration wrapped there upstream) — never line
      # content.
      def extract_lines(doc, path)
        body = doc.at_xpath("//body") or raise ParseError, "#{path}: no <body>"
        lines = []
        body.xpath(".//*").each do |node|
          next if inside_manuscripts?(node)

          case node.name
          when "lb" then lines << open_line(node)
          when "w" then lines.last&.words&.push(node) unless node.ancestors.any? { |a| a.name == "w" }
          when "gap" then append_attr(lines.last&.gaps, node, "c")
          when "note" then lines.last&.notes&.push(note_entry(node))
          when "clb" then append_attr(lines.last&.kola, node, "nr")
          when "parsep", "parsep_dbl" then lines.last&.paragraph = true
          end
        end
        lines
      end

      def open_line(node)
        Line.new(lnr: node["lnr"], lg: node["lg"], cu: node["cu"],
                 words: [], gaps: [], notes: [], kola: [], paragraph: false)
      end

      def append_attr(list, node, attr)
        value = node[attr].to_s
        list << value if list && !value.empty?
      end

      def note_entry(node)
        { "n" => node["n"], "c" => node["c"] }.compact
      end

      def inside_manuscripts?(node)
        node.ancestors.any? { |a| a.name == "Manuscripts" }
      end

      def build_document(doc, lines, path:, urn:, cth:, project:)
        doc_id = doc.at_xpath("//AOHeader/docID")&.text&.strip
        document = Nabu::Document.new(
          urn: urn, language: document_language(doc, lines),
          title: document_title(doc_id, cth, path), canonical_path: File.expand_path(path),
          metadata: document_metadata(doc, doc_id, cth, project)
        )
        append_passages(document, lines, urn: urn)
        raise ParseError, "#{path}: every line rendered empty (AOxml damage)" if document.empty?

        document
      end

      def document_title(doc_id, cth, path)
        base = doc_id.nil? || doc_id.empty? ? File.basename(path, ".xml") : doc_id
        cth ? "#{base} (CTH #{cth})" : base
      end

      def document_metadata(doc, doc_id, cth, project)
        manuscripts = doc.xpath("//AO:Manuscripts/AO:TxtPubl", "AO" => AO_NS)
                         .map { |n| n.text.strip }.reject(&:empty?)
        inventory = doc.xpath("//AO:Manuscripts//AO:InvNr", "AO" => AO_NS)
                       .map { |n| n.text.strip }.reject(&:empty?)
        metadata = {
          "doc_id" => doc_id, "cth" => cth, "project" => project,
          "manuscripts" => (manuscripts unless manuscripts.empty?),
          "inventory" => (inventory unless inventory.empty?)
        }.compact
        metadata["facets"] = facets(cth, project) unless cth.nil? && project.nil?
        metadata
      end

      # The CTH folder layout → facets (catalog number + contributing HPM
      # sub-project — TLH/HFR/BESRIT/…; genre BANDS are deliberately not
      # derived: no in-data genre field exists, and inventing a CTH-range
      # table is not this parser's call).
      def facets(cth, project)
        {
          "cth" => cth && { "value" => cth, "raw" => "CTH #{cth}" },
          "project" => project && { "value" => project.downcase, "raw" => project }
        }.compact
      end

      def document_language(doc, lines)
        mapped = lines.filter_map { |line| LINE_LANGUAGES[line.lg] }
        return majority(mapped) unless mapped.empty?

        declared = doc.at_xpath("//div1/text")
                      &.attribute_with_ns("lang", "http://www.w3.org/XML/1998/namespace")&.value
        DOCUMENT_LANGUAGES[declared] || "und"
      end

      def majority(values)
        counts = values.tally
        values.max_by { |v| [counts[v], -values.index(v)] }
      end

      def append_passages(document, lines, urn:)
        sequence = 0
        lines.each do |line|
          tokens = line.words.map { |w| build_token(w) }.reject { |t| t["form"].empty? }
          text = tokens.map { |t| t["form"] }.join(" ").strip
          next if text.empty?

          sequence += 1
          document << Nabu::Passage.new(
            urn: "#{urn}:#{sequence}", sequence: sequence - 1,
            language: passage_language(line, document),
            text: Nabu::Normalize.nfc(text),
            annotations: line_annotations(line, tokens)
          )
        end
      end

      def passage_language(line, document)
        lg = line.lg.to_s
        return document.language if lg.empty?

        LINE_LANGUAGES[lg] || "und"
      end

      def line_annotations(line, tokens)
        annotations = { "location" => line.lnr, "tokens" => tokens }
        annotations["cuneiform"] = line.cu unless line.cu.to_s.empty?
        lg = line.lg.to_s
        annotations["language_raw"] = lg unless lg.empty? || LINE_LANGUAGES.key?(lg)
        annotations["gaps"] = line.gaps unless line.gaps.empty?
        annotations["notes"] = line.notes unless line.notes.empty?
        annotations["kola"] = line.kola unless line.kola.empty?
        annotations["paragraph_end"] = true if line.paragraph
        annotations.compact
      end

      # -- word rendering + the token annotation ------------------------------

      Rendering = Struct.new(:text, :sumerograms, :akkadograms, :determinatives, :materlect) do
        def initialize = super(+"", [], [], [], [])
      end
      private_constant :Rendering

      def build_token(word)
        rendering = Rendering.new
        render_children(word, rendering)
        token = { "form" => Nabu::Normalize.nfc(rendering.text.strip) }
        token["trans"] = word["trans"] if word["trans"] && !word["trans"].empty?
        token["sumerograms"] = rendering.sumerograms.uniq unless rendering.sumerograms.empty?
        token["akkadograms"] = rendering.akkadograms.uniq unless rendering.akkadograms.empty?
        token["determinatives"] = rendering.determinatives.uniq unless rendering.determinatives.empty?
        token["materlect"] = rendering.materlect.join(" ") unless rendering.materlect.empty?
        token.merge!(analysis_annotations(word))
        token
      end

      def render_children(node, rendering)
        node.children.each { |child| render_node(child, rendering) }
      end

      def render_node(node, rendering)
        return rendering.text << node.text if node.text?
        return unless node.element?

        case node.name
        when *SILENT then rendering.materlect << node["c"].to_s if node.name == "materlect"
        when "d" then render_wrapped(node, rendering, "°", "°", rendering.determinatives)
        when "sGr" then render_wrapped(node, rendering, "", "", rendering.sumerograms)
        when "aGr" then render_wrapped(node, rendering, "", "", rendering.akkadograms)
        when "corr" then rendering.text << node["c"].to_s
        when "subscr" then rendering.text << SUBSCRIPTS.fetch(node["c"].to_s, node["c"].to_s)
        when "surpl" then rendering.text << "⟨⟨#{node['c']}⟩⟩"
        when *MARKS.keys then rendering.text << MARKS.fetch(node.name)
        else render_children(node, rendering) # num, c, nested w, PARSER_ERROR, junk
        end
      end

      def render_wrapped(node, rendering, open, close, record)
        start = rendering.text.length
        rendering.text << open
        render_children(node, rendering)
        rendering.text << close
        record << rendering.text[start..].delete("[]⌈⌉⟦⟧⟨⟩°")
      end

      # -- the mrp candidate layer -------------------------------------------

      def analysis_annotations(word)
        analyses = word.attributes.keys.grep(/\Amrp[1-9]\d*\z/)
                       .sort_by { |k| k[3..].to_i }
                       .to_h { |k| [k[3..].to_i, word[k]] }
        selection = word["mrp0sel"]
        return {} if analyses.empty? && selection.nil?

        annotations = {}
        annotations["selection"] = selection if selection
        annotations["analyses"] = analyses.values unless analyses.empty?
        annotations.merge!(selected_analysis(analyses, selection))
        annotations
      end

      # The disambiguated subset (class note): digit selector, or a single
      # candidate with a blank selector. Everything else keeps its
      # hypotheses verbatim and mints NO lemma.
      def selected_analysis(analyses, selection)
        stripped = selection.to_s.strip
        if (match = stripped.match(/\A(\d+)([a-z]?)\z/))
          candidate = analyses[match[1].to_i]
          return candidate ? analysis_fields(candidate, match[2]) : {}
        end
        return analysis_fields(analyses.values.first, "") if analyses.size == 1 && stripped.empty?

        {}
      end

      def analysis_fields(candidate, variant)
        lemma_raw, gloss, morph, morph_class = candidate.to_s.split("@")
        fields = {}
        citation = lemma_citation(lemma_raw)
        fields["lemma"] = citation if citation
        fields["gloss"] = gloss unless gloss.to_s.empty?
        morph = resolve_variant(morph.to_s, variant)
        fields["morph"] = morph unless morph.empty?
        fields["morph_class"] = morph_class unless morph_class.to_s.strip.empty?
        fields
      end

      # "{ a → NOM.SG(UNM)} { b → ACC.SG(UNM)}" + selector letter "a" →
      # "NOM.SG(UNM)"; without a letter (or without a match) the field
      # stays verbatim.
      def resolve_variant(morph, variant)
        return morph.strip if variant.empty?

        match = morph.match(/\{\s*#{Regexp.escape(variant)}\s*→\s*([^}]*)\}/)
        match ? match[1].strip : morph.strip
      end

      # The documented deterministic citation derivation (class note):
      # selection marker off, first slash variant, parens characters and
      # "=" morph separators off, trailing stem hyphen off.
      def lemma_citation(raw)
        s = raw.to_s.sub(/\A[\s①-⑳]+/, "").strip
        s = s.split("/").first.to_s.delete("()⁽⁾=").sub(/-\z/, "")
        s.empty? ? nil : Nabu::Normalize.nfc(s)
      end
    end
  end
end
