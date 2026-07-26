# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "../timeline"
require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "edr-epidoc" (P46-4): one EDR (Epigraphic Database Roma;
    # edr-edr.it) EpiDoc record from the project's own Zenodo data release —
    # the inscriptions of Italy, the geographic complement of EDH's provinces.
    # A sibling of IipEpidocParser/IsicilyEpidocParser sharing the
    # CelticLeiden reading-text policy. DOM-based deliberately: 115,591
    # records, median 5.3 KB, largest 966 KB (the >5 MB Reader rule never
    # engages).
    #
    # == Content shape (full-zip census, 2026-07-26, Zenodo record 18468635)
    #
    #   div[@type="edition" @xml:lang] > (div[@type="textpart" @n])? > ab >
    #     lb[@n]/expan/abbr/ex/gap/supplied/unclear/choice/corr/sic/
    #     certainty/g/hi/name/am/del/surplus/note
    #
    # That element list is the CLOSED corpus-wide set (censused over every
    # well-formed record). Every record has exactly ONE edition div; every
    # <lb> carries a purely numeric @n; every textpart div carries @n.
    # bibliography/apparatus/commentary divs are apparatus, never read.
    #
    # == Passage = the LINE; upstream numbers, textpart-relative
    #
    #   urn = <document-urn>[:<textpart-n>]:<lb n>[:b<k>]
    #
    # Line numbers restart per textpart (3,917 textpart divs corpus-wide),
    # so the textpart @n joins the suffix. <lb n="0"> is EDR's lost-line
    # milestone (the EDH convention: a gap-only line 0 before/after the
    # text); repeats of any citable (scope, n) pair take the house :b2
    # positional disambiguator (the ReM/DdbdpParser precedent — 331 records
    # carry duplicate pairs at the census, nearly all n="0" notation lines).
    # <lb break="no"> delimits like any lb (the print-margin rule); the word
    # stays split across the two line passages.
    #
    # == Citability: letters required (the EDR notation quirk)
    #
    # A line is citable only when, gap markers removed, it still carries a
    # letter or digit. This is CelticLeiden.gap_only? sharpened for EDR:
    # upstream writes LITERAL 〚 〛 erasure brackets (U+301A/B, 1,606
    # records) and stray punctuation around lost-line gaps, so "〚[…]〛"
    # and "[…]." are notation, not text. Zero citable lines → ONE
    # whole-inscription passage under the stable :text suffix (the EDH
    # fallback; 170 minted at the 2026-07-26 full parse): the per-line
    # extractions joined with single spaces, document-wide leiden
    # annotations attached. An edition with NOTHING extractable at all —
    # a symbol-only carving, its one self-closed <g type="fulmen"/> et
    # al. carrying no letters (88 records) — is a METADATA-ONLY document
    # ("text_layer" => "none", the isicily/ogham precedent): catalogued,
    # zero passages, never a quarantine.
    #
    # == Text policy (CelticLeiden + the EDR dialect)
    #
    # - choice → corr > sic (51,464 corr+sic pairs read corr; 1,223
    #   corr-only choices read their corr).
    # - expan reads abbr+ex expanded ("P(ublius)" reads "Publius"); <am>
    #   drops — the doubled-letter siglum ("PP." = plural) is excluded from
    #   the expanded reading (the IIP policy). A small residue of converter
    #   mis-nestings (aEDR200012: an <am> swallowing following prose) reads
    #   imperfectly either way and is left as upstream wrote it.
    # - supplied/unclear read through and count; gap → "[…]" with
    #   reason/quantity/extent/unit riding annotations; del → ⟦…⟧ +
    #   cancelled; surplus → {…}; g/hi/name keep their text (EDR spells
    #   symbols out: <g type="mulieris">mulieris</g> — the ((mulieris))
    #   siglum as reading text).
    # - DROP: note (161, editorial), head (the "Text" label on every
    #   edition), certainty (attribute-only milestones, 26,136), am.
    # - The root TEI declares xml:space="preserve" but the corpus is
    #   pretty-printed (template indentation after every first <lb>) —
    #   whitespace runs fold to one space at line finalization, NFC.
    #
    # == Language: the EDITION div's xml:lang, never the root's
    #
    # Every record's root <TEI xml:lang="la"> — Greek editions included
    # (the EDH boilerplate-header trap, verified: root la on all 115,590
    # well-formed records). The edition div's own xml:lang is the curated
    # truth: la 110,006 → lat, grc 5,584 → grc (anything else → honest
    # und). Per-passage, a line carrying Greek codepoints inside a Latin
    # record is tagged grc (the EDH script rule; 721 such bilingual records
    # censused).
    #
    # == Header layers → Document#metadata (the EDH/I.Sicily shape)
    #
    #   {"facets" => {"genre" (textClass term)/"region" (origPlace
    #                 placeName type="provinceItalicRegion" — Italy's
    #                 regiones, EDH's province analog)/"material"/
    #                 "object_type" => {"value" => the element's own text,
    #                 "ref" => its EAGLE LOD URI when present}},
    #    "place" => {"ancient" (origPlace untyped placeName)},
    #    "findspot" (provenance placeName type="locus"),
    #    "repository" (msIdentifier repository),
    #    "date" => {"not_before"/"not_after" (signed years from the
    #               Julian notBefore-custom/notAfter-custom attrs)/
    #               "raw" (origDate text verbatim)},
    #    "tm_nr" (idno type="TM" — 60,477 filled / 55,113 empty)}
    #   — only non-empty keys (honest sparsity).
    #
    # == Identity + licence pin
    #
    # <idno type="localID">EDR<nnnnnn></idno> mints
    # urn:nabu:edr:edr<nnnnnn> (EDR numbers are the stable id EAGLE/
    # Trismegistos/EDH concordances key on); the caller-supplied urn — the
    # adapter mints it from the filename, aEDR<nnnnnn>.xml — must equal
    # the in-file minting (drift → ParseError; zero mismatches censused).
    # Every record's <licence> carries the EAGLE-era "Reserved Rights -
    # Free access via Epigraphic Database Roma" statement (uniform across
    # all 115,590); parse RE-VERIFIES it per document and quarantines
    # drift (the rem discipline), so a future re-release that changes the
    # in-file terms gets noticed, not silently ingested. The dataset's
    # redistribution grant is DEPOSIT-level (Zenodo CC BY 4.0) — see the
    # adapter manifest.
    class EdrEpidocParser
      URN_PREFIX = "urn:nabu:edr:"

      # The whole-inscription fallback's stable urn suffix (class note):
      # flat, textpart-free, minted only when zero line suffixes exist.
      FALLBACK_SUFFIX = "text"

      # The uniform in-file licence statement (class note). Drift
      # quarantines.
      LICENCE_PIN = "Reserved Rights - Free access via Epigraphic Database Roma"

      DROPPED_ELEMENTS = %w[note head certainty am].freeze

      # Edition xml:lang → ISO 639-3; grc is already 639-3 and passes
      # through, anything unmapped and un-639-3-looking reads und via
      # the honest fallback below.
      LANGUAGE_MAP = { "la" => "lat", "grc" => "grc" }.freeze

      # Facet name → [xpath under the de-namespaced document]. value = the
      # element's own text; ref = its EAGLE LOD @ref when present.
      FACET_SOURCES = {
        "genre" => "//profileDesc//textClass//term",
        "region" => "//origPlace/placeName[@type='provinceItalicRegion']",
        "material" => "//physDesc//material",
        "object_type" => "//physDesc//objectType"
      }.freeze

      # One extracted line: the citation suffix parts, the folded text,
      # the leiden counters.
      Line = Data.define(:suffix_base, :text, :gaps, :supplied, :unclear, :cancelled)
      private_constant :Line

      # Parse one record file into a Nabu::Document.
      def parse(path, urn:)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn)
        verify_licence!(doc, path: path)
        edition = doc.at_xpath("//div[@type='edition']") or
          raise ParseError, "#{path}: no div[@type=\"edition\"] found"
        language = edition_language(edition)
        build_document(edition, doc, path: path, urn: urn, language: language)
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + licence ---------------------------------------------------

      def validate_identity!(doc, path:, urn:)
        local_id = doc.at_xpath("//publicationStmt/idno[@type='localID']")&.text.to_s.strip
        raise ParseError, "#{path}: no <idno type=\"localID\"> found in teiHeader" if local_id.empty?

        minted = "#{URN_PREFIX}#{local_id.downcase}"
        return if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "<idno type=\"localID\"> #{local_id.inspect} mints #{minted.inspect}"
      end

      def verify_licence!(doc, path:)
        licence = doc.at_xpath("//publicationStmt//licence")&.text.to_s
        return if licence.include?(LICENCE_PIN)

        raise ParseError, "#{path}: <licence> drifted from the EDR pin " \
                          "(got #{licence.strip.inspect}); re-verify upstream terms before ingesting"
      end

      # -- language -------------------------------------------------------------

      # The edition div's xml:lang (class note — the root tag lies).
      def edition_language(edition)
        tag = edition["lang"].to_s.strip.downcase
        return "und" if tag.empty?

        LANGUAGE_MAP.fetch(tag) { tag.match?(/\A[a-z]{3}\z/) ? tag : "und" }
      end

      # Script decides the passage language for bilinguals (the EDH rule):
      # any Greek codepoint tags the line grc; everything else inherits
      # the document language.
      def passage_language(text, language)
        text.match?(/\p{Greek}/) ? "grc" : language
      end

      # -- document assembly ----------------------------------------------------

      def build_document(edition, doc, path:, urn:, language:)
        extraction = Extraction.new
        extraction.edition(edition)
        lines = citable_lines(extraction)
        lines = [fallback_line(extraction)].compact if lines.empty?
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc),
          canonical_path: path, metadata: metadata(doc, text_layer: !lines.empty?)
        )
        lines.each_with_index do |(suffix, text, annotations), sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{suffix}", language: passage_language(text, language),
            text: text, annotations: annotations, sequence: sequence
          )
        end
        document
      end

      # Citable lines with their minted suffixes: letters required (class
      # note), repeats of a (scope, n) suffix take :b2, :b3, … in document
      # order.
      def citable_lines(extraction)
        seen = Hash.new(0)
        extraction.lines.filter_map do |line|
          next unless citable?(line.text)

          count = (seen[line.suffix_base] += 1)
          suffix = count == 1 ? line.suffix_base : "#{line.suffix_base}:b#{count}"
          [suffix, line.text, annotations_for(line)]
        end
      end

      # Gap markers removed, a letter or digit must remain (the 〚…〛 /
      # stray-punctuation notation lines are not citable — class note).
      def citable?(text)
        text.gsub(CelticLeiden::GAP_MARKER, "").match?(/[\p{L}\p{N}]/)
      end

      # The whole-inscription :text fallback (class note): every line's
      # extraction joined, document-wide leiden annotations aggregated;
      # nil when the edition carried nothing at all.
      def fallback_line(extraction)
        lines = extraction.lines
        text = lines.map(&:text).reject(&:empty?).join(" ")
        return nil if text.empty?

        leiden = CelticLeiden.leiden_annotations(
          gaps: lines.flat_map(&:gaps), supplied: lines.sum(&:supplied),
          unclear: lines.sum(&:unclear), cancelled: lines.any?(&:cancelled)
        )
        [FALLBACK_SUFFIX, text, leiden.empty? ? {} : { "leiden" => leiden }]
      end

      def annotations_for(line)
        leiden = CelticLeiden.leiden_annotations(
          gaps: line.gaps, supplied: line.supplied,
          unclear: line.unclear, cancelled: line.cancelled
        )
        leiden.empty? ? {} : { "leiden" => leiden }
      end

      # -- header → metadata ----------------------------------------------------

      def title_of(doc)
        presence(doc.at_xpath("//titleStmt/title")&.text)
      end

      def metadata(doc, text_layer:)
        result = {}
        # Zero extraction at all (a symbol-only carving — a self-closed
        # <g/> and no letters, 88 records at the 2026-07-26 full parse):
        # the metadata-only document (the isicily/ogham precedent),
        # catalogued with zero passages, never a quarantine.
        result["text_layer"] = "none" unless text_layer
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        ancient = presence(doc.at_xpath("//origPlace/placeName[not(@type)]")&.text)
        result["place"] = { "ancient" => ancient } if ancient
        { "findspot" => "//provenance/placeName[@type='locus']",
          "repository" => "//msIdentifier/repository" }.each do |key, xpath|
          value = presence(doc.at_xpath(xpath)&.text)
          result[key] = value if value
        end
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        tm_nr = presence(doc.at_xpath("//publicationStmt/idno[@type='TM']")&.text)
        result["tm_nr"] = tm_nr if tm_nr
        result
      end

      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, xpath), facets|
          node = doc.at_xpath(xpath) or next
          value = presence(node.text) or next

          entry = { "value" => value }
          ref = presence(node["ref"])
          entry["ref"] = ref if ref
          facets[facet] = entry
        end
      end

      # origin/origDate → signed years from the Julian -custom attrs
      # (the isicily dialect; a year-0 bound would drop both via the
      # Timeline tripwire, keeping raw). Empty origDate → no date at all.
      def extract_date(doc)
        node = doc.at_xpath("//origin/origDate") or return {}
        result = {}
        begin
          not_before = Timeline.parse_year(node["notBefore-custom"])
          not_after = Timeline.parse_year(node["notAfter-custom"])
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue Timeline::InvalidYear
          result = {} # bounds dropped; raw still recorded below
        end
        raw = presence(node.text)
        result["raw"] = raw if raw
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # Recursive-descent extraction over the one edition div: upstream
      # <lb n> lines, the textpart @n path, the CelticLeiden counters.
      # ALL lines are kept here (citability is the caller's cut, because
      # the :text fallback needs the notation lines too).
      class Extraction
        # Finalized lines in document order (folded NFC; the corpus is
        # lat/grc only — no NFC exemption engages).
        attr_reader :lines

        def initialize
          @raw_lines = []
          @current = nil
          @path = []
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
          @lines = nil
        end

        def edition(node)
          node.element_children.each { |child| walk(child) }
          close_line
          @lines = @raw_lines.map do |line|
            Line.new(
              suffix_base: line[:suffix_base], text: CelticLeiden.fold(line[:buffer]),
              gaps: line[:gaps], supplied: line[:supplied],
              unclear: line[:unclear], cancelled: line[:cancelled]
            )
          end
        end

        private

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?

          name = node.name
          return if EdrEpidocParser::DROPPED_ELEMENTS.include?(name)

          case name
          when "div" then division(node)
          when "choice" then choice(node)
          when "lb" then start_line(node)
          when "gap" then gap(node)
          when "supplied" then counted(node, :@supplied_depth)
          when "unclear" then counted(node, :@unclear_depth)
          when "del" then wrapped(node, CelticLeiden::CANCELLATION_OPEN, CelticLeiden::CANCELLATION_CLOSE)
          when "surplus" then wrapped(node, CelticLeiden::SURPLUS_OPEN, CelticLeiden::SURPLUS_CLOSE)
          else recurse(node)
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        # -- lines (upstream @n, eager — every lb carries one) -------------------

        def start_line(node)
          n = node["n"].to_s.strip
          raise ParseError, "<lb> without @n (censused zero corpus-wide)" if n.empty?

          close_line
          @current = {
            suffix_base: (@path + [n]).join(":"), buffer: +"",
            gaps: [], supplied: 0, unclear: 0, cancelled: @del_depth.positive?
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # Text before the first <lb> is template whitespace (every edition
        # opens with a numbered lb — censused); it is not emitted anywhere.
        def emit(text)
          return if @current.nil? || text.empty?

          @current[:buffer] << text
          count_certainty(text)
        end

        def emit_marker(marker)
          return if @current.nil?

          @current[:buffer] << marker
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
        end

        # -- textparts (upstream @n path) -----------------------------------------

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          n = node["n"].to_s.strip
          raise ParseError, "div[@type=\"textpart\"] without @n (censused zero corpus-wide)" if n.empty?

          close_line # lines never span textparts
          @path.push(n)
          recurse(node)
          close_line
          @path.pop
        end

        # -- markers + counted spans ----------------------------------------------

        def gap(node)
          return if @current.nil? # a gap before any line has nowhere to land

          emit_marker(CelticLeiden::GAP_MARKER)
          @current[:gaps] << CelticLeiden.gap_annotation(node)
        end

        def counted(node, variable)
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def wrapped(node, open, close)
          cancelling = open == CelticLeiden::CANCELLATION_OPEN
          @del_depth += 1 if cancelling
          emit_marker(open)
          @current[:cancelled] = true if cancelling && @current
          recurse(node)
          emit_marker(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end
      end
      private_constant :Extraction
    end
  end
end
