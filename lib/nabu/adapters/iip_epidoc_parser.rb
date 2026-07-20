# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "../timeline"
require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "iip-epidoc" (P30-6): one Inscriptions of Israel/
    # Palestine (Brown University; github.com/Brown-University-Library/
    # iip-texts) EpiDoc TEI record — Hebrew/Aramaic/Greek/Latin epigraphy
    # of the southern Levant, ~500 BCE–640 CE. A sibling of
    # IsicilyEpidocParser (whose header/facet/date discipline it mirrors)
    # sharing the CelticLeiden reading-text policy. DOM-based
    # deliberately: 5,535 records, largest 30 KB (the >5 MB Reader rule
    # never engages).
    #
    # == Content shape (full-corpus census, 2026-07-18, commit 0b7dc835)
    #
    #   div[@type="edition" @subtype="diplomatic"|"transcription"|
    #       "transcription_segmented"] > (div[@type="textpart"])? > p >
    #     lb/supplied/gap/unclear/expan/choice/orig/g/foreign/num/hi/del…
    #
    # Three sibling edition layers: transcription (5,349 — the edited
    # reading text with word division and expansions), diplomatic (4,159 —
    # letters as carved), transcription_segmented (5,160 — a <w id lang>
    # re-tokenization carrying NO lemmas; nothing to mine, not read).
    # div[@type="translation"] (5,213 English translations) is not minted
    # (the I.Sicily precedent). Citable text = the TRANSCRIPTION; a record
    # whose transcription is missing or empty falls back to the DIPLOMATIC
    # when that carries text (361 records at the pinned full-clone parse —
    # the letters-only edition is then the record's only machine-readable
    # text) and says so via
    # metadata "text_layer" => "diplomatic". Neither layer with text →
    # the metadata-only document ("text_layer" => "none", 77 records —
    # the ogham/isicily precedent, never a quarantine).
    #
    # == Passage = the LINE, ordinal (the corpus carries NO numbers)
    #
    #   urn = <document-urn>[:p<textpart-ordinal>…]:<line-ordinal>
    #
    # ZERO of the corpus's 15,968 <lb> carry @n, and only 44 of 132
    # textpart divs do — so both levels number by DOCUMENT-ORDER ORDINAL,
    # uniformly (mixing upstream @n with ordinals would collide; upstream
    # labels ride as the "textpart" annotation instead). Text before the
    # first <lb/> is line 1; <lb break="no"/> delimits like any lb (the
    # print-margin rule). Lines open LAZILY on the first non-whitespace
    # emission, so a leading <lb/> opens no phantom empty line and a
    # stray <lb/> between textparts (caes0022) mints nothing; a line that
    # folds to gap-markers-only is dropped, its ordinal honestly consumed.
    #
    # == Text policy (CelticLeiden + the IIP dialect)
    #
    # - Pretty-printed corpus (the RIIG shape, no xml:space): whitespace
    #   runs fold to one space at line finalization.
    # - choice → corr > reg > lem > expan > first (CelticLeiden): IIP's
    #   1,377 corr+sic pairs read corr, 440 orig+reg read reg, 215
    #   choices of bare <unclear> alternatives read the first.
    # - A bare <orig> OUTSIDE any choice is KEPT (2,818 corpus-wide —
    #   the letters-only edited text, the I.Sicily doctrine).
    # - expan reads abbr+ex expanded; <am> (197) drops — the expanded
    #   reading excludes the graphical siglum.
    # - supplied/unclear read through and count; gap → "[…]"; del → ⟦…⟧;
    #   surplus → {…}; space → one space; g/num/hi/foreign keep their
    #   text (the word-dividing-dot <g>·</g> is reading text; inline
    #   <foreign> spans — Greek inside Aramaic lines — read through, the
    #   line keeps ONE language).
    # - DROP: note, bibl, figure, desc, rdg, certainty, am (defensive;
    #   the census found none of note/desc inside editions).
    #
    # == Languages (honest mapping; the div tag is NOT trusted)
    #
    # Document language = msContents/textLang/@mainLang: he→heb, la→lat,
    # geo→kat (639-2B→3), upstream's explicit unknowns
    # ("x-unknown"/"Other")→und, empty/absent→und; grc/arc/phn/syc/xcl/
    # heb/lat pass through; tags case-fold (BCP-47: "Geo"→kat). Passage
    # language = the DOCUMENT language: upstream tags Hebrew-SCRIPT
    # edition divs lang="heb" even on Aramaic (arc) records, so the
    # edition div's tag would systematically misfile the corpus's second
    # language — the curated textLang/@mainLang is the only honest
    # per-passage statement. @otherLangs (171 records) rides as mapped
    # metadata "other_languages". arc records inherit the P26-3 NFC
    # exemption: their passage text stays byte-verbatim (whitespace-folded
    # only); everything else normalizes NFC at this boundary.
    #
    # == Header layers → Document#metadata (the I.Sicily shape)
    #
    #   {"facets" => {"genre" (msItem @class)/"religion" (msItem @ana)/
    #                 "object_type" (objectDesc @ana)/"execution"
    #                 (handNote @ana) =>
    #                   {"values" => ["#"-stripped tokens], "raw" => verbatim}},
    #    "summary" => msItem/p ("Bethennim …, 300 CE - 700 CE. Mosaic."),
    #    "other_languages" => ["grc", …],
    #    "date" => {"not_before"/"not_after" (signed years via plain
    #               notBefore/notAfter; zero year-0 in the corpus, the
    #               Timeline tripwire drops bounds if one appears)/
    #               "raw"/"period" (@period verbatim — 4,903 Periodo
    #               URIs, 622 text values)},
    #    "place" => {"region"/"settlement" (own text, excluding the
    #                embedded <geo> child)/"site" (geogName type=site)/
    #                "locus" (geogFeat)/"geo" (verbatim WGS84, 470
    #                records)},
    #    "text_layer" => "diplomatic"|"none" (only when not transcription)}
    #
    # NO concordance idnos exist corpus-wide (the only idno/@type is IIP
    # itself) — no reference edges, honestly.
    #
    # == Identity: the FILENAME, and only the filename
    #
    # In-file identity is demonstrably unreliable: publicationStmt
    # <idno type="IIP"> is absent from 3,744 records (their
    # publicationStmt is an unresolved xi:include) and DISAGREES with the
    # filename on 29 (all four arch000N say jeri0017 — minting from it
    # would collide); root @xml:id drifts too (hkur0001's says hamm0071).
    # So <basename>.xml mints urn:nabu:iip:<basename> (the site's own
    # record ids), the caller-supplied urn must equal that minting, and a
    # PRESENT publicationStmt idno that names a different record is
    # upstream drift → ParseError (honest quarantine, never repair);
    # absence is the corpus norm and never quarantined.
    class IipEpidocParser
      URN_PREFIX = "urn:nabu:iip:"

      DROPPED_ELEMENTS = %w[note bibl figure desc rdg certainty am].freeze

      # Edition subtypes, in citability order (class note): transcription
      # is the edited reading; diplomatic answers only when no
      # transcription text exists. transcription_segmented and
      # translation divs are never read.
      LAYERS = %w[transcription diplomatic].freeze

      # Upstream tags → ISO 639-3, case-folded (BCP-47). "x-unknown" and
      # "Other" are upstream's explicit unknowns; grc/arc/phn/syc/xcl/
      # heb/lat are already 639-3 and pass through.
      LANGUAGE_MAP = {
        "he" => "heb", "la" => "lat", "geo" => "kat",
        "x-unknown" => "und", "other" => "und"
      }.freeze

      # A well-formed BCP-47 script subtag survives; anything else after
      # the hyphen is shed, never repaired (the I.Sicily rule — the
      # corpus's header tags carry none today).
      SCRIPT_SUBTAG = /\A[A-Z][a-z]{3}\z/

      # Facet name → [header node xpath, attribute]. Tokens are the
      # attribute split on whitespace, "#" pointers stripped to their
      # taxonomy keys; raw keeps the attribute verbatim.
      FACET_SOURCES = {
        "genre" => ["//msContents/msItem", "class"],
        "religion" => ["//msContents/msItem", "ana"],
        "object_type" => ["//physDesc/objectDesc", "ana"],
        "execution" => ["//physDesc//handNote", "ana"]
      }.freeze

      # One extracted line of one edition layer.
      Line = Data.define(:urn_suffix, :text, :annotations)
      private_constant :Line

      # Parse one record file into a Nabu::Document. Zero citable lines →
      # the metadata-only document (class note), never a quarantine.
      def parse(path, urn:)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn)
        language = document_language(doc)
        layer, lines = extract(doc, language: language)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc), canonical_path: path,
          metadata: metadata(doc, layer: layer)
        )
        lines.each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
        document
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + header ----------------------------------------------------

      def validate_identity!(doc, path:, urn:)
        minted = "#{URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        unless minted == urn
          raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                            "the filename mints #{minted.inspect}"
        end
        idno = doc.at_xpath("//publicationStmt/idno[@type='IIP']")&.text.to_s.strip
        return if idno.empty? || idno.downcase == File.basename(path, ".xml").downcase

        raise ParseError, "#{path}: in-file idno drift: <idno type=\"IIP\"> says " \
                          "#{idno.inspect} (upstream copy-paste — 29 records at the " \
                          "2026-07-18 census; quarantined, never repaired)"
      end

      def document_language(doc)
        normalize_language(doc.at_xpath("//msContents/textLang/@mainLang")&.value) || "und"
      end

      # LANGUAGE_MAP over the case-folded primary subtag; a valid script
      # subtag survives, a malformed one is shed (class note).
      def normalize_language(tag)
        tag = tag.to_s.strip
        return nil if tag.empty?

        # "x-unknown" is one upstream token, not a private-use subtag tree.
        primary, rest = tag.downcase == "x-unknown" ? [tag, nil] : tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary.downcase, primary)
        rest&.match?(SCRIPT_SUBTAG) ? "#{mapped}-#{rest}" : mapped
      end

      # The msIdentifier display idno ("Abur 0001") — the only per-record
      # title the corpus carries (titleStmt/title is the project name).
      def title_of(doc)
        presence(doc.at_xpath("//msIdentifier/idno")&.text)
      end

      # -- document metadata ----------------------------------------------------

      def metadata(doc, layer:)
        result = {}
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        summary = presence(doc.at_xpath("//msContents/msItem/p")&.text)
        result["summary"] = summary if summary
        other = other_languages(doc)
        result["other_languages"] = other unless other.empty?
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        result["text_layer"] = layer unless layer == "transcription"
        result
      end

      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, (xpath, attribute)), facets|
          raw = doc.at_xpath(xpath)&.attr(attribute).to_s.strip
          next if raw.empty?

          values = raw.split(/\s+/).map { |token| token.delete_prefix("#") }.reject(&:empty?)
          next if values.empty?

          facets[facet] = { "values" => values, "raw" => raw }
        end
      end

      def other_languages(doc)
        tags = doc.at_xpath("//msContents/textLang/@otherLangs")&.value.to_s
        tags.split(/\s+/).filter_map { |tag| normalize_language(tag) }
      end

      # origin/date → signed years (plain notBefore/notAfter — the corpus
      # has no -custom dialect and zero year-0 bounds; the Timeline
      # tripwire drops bounds, keeping raw/period, if one ever appears).
      # @period rides verbatim: 4,903 Periodo URIs, 622 text values
      # ("Talmudic", "Unknown").
      def extract_date(doc)
        node = doc.at_xpath("//history/origin/date") or return {}
        result = {}
        begin
          not_before = Timeline.parse_year(node["notBefore"])
          not_after = Timeline.parse_year(node["notAfter"])
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue Timeline::InvalidYear
          nil # bounds dropped; raw/period still recorded below
        end
        { "raw" => presence(node.text), "period" => presence(node["period"]) }
          .each { |key, value| result[key] = value if value }
        result
      end

      # origin/placeName: region + settlement (its OWN text — upstream
      # nests <geo> inside <settlement>, which must not leak into the
      # name) + site (geogName type=site) + locus (geogFeat); <geo> stays
      # VERBATIM (canonical means canonical).
      def extract_place(doc)
        origin = doc.at_xpath("//history/origin/placeName") or return {}
        settlement = origin.at_xpath("./settlement")
        result = {}
        { "region" => origin.at_xpath("./region")&.text,
          "settlement" => settlement && own_text(settlement),
          "site" => origin.at_xpath("./geogName[@type='site']")&.text,
          "locus" => origin.at_xpath("./geogFeat")&.text,
          "geo" => origin.at_xpath(".//geo")&.text }.each do |key, value|
          folded = presence(value)
          result[key] = folded if folded
        end
        result
      end

      # A node's text without its element children's (settlement holds a
      # <geo> child whose coordinates are not part of the name).
      def own_text(node)
        node.xpath("./text()").map(&:text).join
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- the layer ladder + edition walk --------------------------------------

      # [layer, lines]: the transcription's citable lines, else the
      # diplomatic's, else ["none", []] — the metadata-only document.
      def extract(doc, language:)
        LAYERS.each do |layer|
          divs = doc.xpath("//div[@type='edition'][@subtype='#{layer}']")
          next if divs.empty?

          extraction = Extraction.new(language: language)
          divs.each { |div| extraction.edition(div) }
          lines = extraction.lines
          return [layer, lines] unless lines.empty?
        end
        ["none", []]
      end

      # Recursive-descent extraction over one edition layer: the ordinal
      # textpart path, the lazily-opened ordinal line, the Leiden
      # counters (see the class note).
      class Extraction
        def initialize(language:)
          @language = language
          @raw_lines = []
          @current = nil
          @path = []
          @textpart_info = []
          @line_counters = [0]
          @textpart_counters = [0]
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
        end

        def edition(node)
          node.element_children.each { |child| walk(child) }
          close_line
        end

        # Finalized lines in document order: whitespace-folded (NFC unless
        # the language is exempt — the P26-3 byte-verbatim rule),
        # gap-only lines dropped (their ordinal stays consumed).
        def lines
          @raw_lines.filter_map do |line|
            text = fold(line[:buffer])
            next if CelticLeiden.gap_only?(text)

            Line.new(urn_suffix: line[:suffix], text: text, annotations: annotations(line))
          end
        end

        private

        # CelticLeiden.fold NFC-normalizes unconditionally; the exempt
        # languages (arc here) keep their bytes, whitespace-folded only.
        def fold(text)
          folded = text.gsub(/[[:space:]]+/, " ").strip
          Normalize.nfc_exempt?(@language) ? folded : Normalize.nfc(folded)
        end

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?

          name = node.name
          return if IipEpidocParser::DROPPED_ELEMENTS.include?(name)

          case name
          when "div" then division(node)
          when "choice" then choice(node)
          when "lb" then close_line
          when "gap" then gap(node)
          when "space" then emit_marker(" ")
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

        # -- lazy ordinal lines ---------------------------------------------------

        # Whitespace with no line open is inter-element formatting (the
        # pretty-printed corpus) — it must not open a line, or a leading
        # <lb/> would mint a phantom empty line 1.
        def emit(text)
          return if text.empty?
          return if @current.nil? && text.strip.empty?

          open_line
          @current[:buffer] << text
          count_certainty(text)
        end

        # Markers (gap "[…]", del/surplus brackets, explicit <space/>)
        # open lines too but bypass certainty counting — notation, not
        # letters.
        def emit_marker(marker)
          open_line
          @current[:buffer] << marker
        end

        def open_line
          return if @current

          ordinal = (@line_counters[-1] += 1)
          @current = {
            suffix: (@path + [ordinal.to_s]).join(":"), buffer: +"",
            gaps: [], supplied: 0, unclear: 0, cancelled: @del_depth.positive?,
            textpart: @textpart_info.last
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
        end

        # -- textparts (ordinal path) ---------------------------------------------

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          close_line
          segment = "p#{@textpart_counters[-1] += 1}"
          @path.push(segment)
          @textpart_info.push(textpart_label(node))
          @line_counters.push(0)
          @textpart_counters.push(0)
          recurse(node)
          close_line
          @path.pop
          @textpart_info.pop
          @line_counters.pop
          @textpart_counters.pop
        end

        # Upstream's own labels ("obverse", n="a") — annotation material,
        # never urn material (88 of 132 textparts carry no @n).
        def textpart_label(node)
          label = {}
          %w[subtype n].each do |attribute|
            value = node[attribute].to_s.strip
            label[attribute] = value unless value.empty?
          end
          label
        end

        # -- markers + counted spans ----------------------------------------------

        def gap(node)
          annotation = CelticLeiden.gap_annotation(node)
          emit_marker(CelticLeiden::GAP_MARKER)
          @current[:gaps] << annotation
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
          @current[:cancelled] = true if cancelling
          recurse(node)
          emit_marker(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end

        # -- finalization ---------------------------------------------------------

        def annotations(line)
          result = {}
          leiden = CelticLeiden.leiden_annotations(
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear],
            cancelled: line[:cancelled]
          )
          result["leiden"] = leiden unless leiden.empty?
          result["textpart"] = line[:textpart] unless line[:textpart].to_h.empty?
          result
        end
      end
      private_constant :Extraction
    end
  end
end
