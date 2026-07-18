# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"

module Nabu
  module Adapters
    # Parser family "itant-epidoc" (P29-2): one Corpus_ItAnt (DigItAnt,
    # CNR-ILC/UniFI PRIN 2017 — cite Murano et al., JOCCH 16.3 (2023),
    # 10.1145/3606703) EpiDoc 9.4/9.5 TEI record — Sabellic and Lepontic
    # epigraphy of ancient Italy, the RiigEpidocParser sibling (whose
    # header/date/place shape it mirrors) under the shared CelticLeiden
    # reading-text policy. DOM-based deliberately: 510 files of ≤91 KB (the
    # >5 MB streaming rule never engages).
    #
    # == Content shape (whole-corpus census, 2026-07-18, 510 files)
    #
    #   div[@type="edition" @subtype="interpretative"] (all 510 files)
    #     > div[@type="textpart" @n @style="text-direction:…"
    #           @rend="ductus:…"] > ab > lb/name/w/pc/expan/gap …
    #   div[@type="edition" @subtype="diplomatic"] (the 9 Lepontic files
    #     ONLY) > same textparts > ab > lb + the raw character stream.
    #
    # The two subtypes are parallel renderings of the SAME lines — the
    # ogham layer-sibling precedent, not the riig multiple-readings shape —
    # so the interpretative layer is the bare-urn document and the
    # diplomatic layer mints a `-dipl` SIBLING document (parse layer:
    # "diplomatic"), both citable. Ten Oscan records (lost inscriptions)
    # carry a completely EMPTY edition div: they parse through
    # #parse_metadata_only into catalogued, zero-passage documents (the
    # ogham text_layer:none precedent), never quarantines. Which layers are
    # citable is the parser's OWN extraction (#census — the P25-3 lesson:
    # never a cheap byte peek).
    #
    # == Passage = the LINE within a TEXTPART
    #
    #   urn = <document-urn>:<textpart n>:<lb n>
    #
    # textpart @n is always present upstream (censused 547/547) and unique
    # within a file; lb @n restarts per textpart (face_a:1 / face_b:1b).
    # A missing lb @n is a ParseError (riig rule; censused 0/642).
    # Collisions (defensive) open DdbdpParser's implicit :b<k> block,
    # scoped per textpart.
    #
    # == Text policy (CelticLeiden + the ItAnt dialect)
    #
    # - Word tokens are <name> (onomastic: praenomen/gentilicium/
    #   patronymic/individual/…) and <w>/<num>; their word-internal
    #   whitespace is markup noise, stripped (riig rule); tokens separate
    #   with single spaces (the fold collapses the pretty-print runs).
    # - <pc unit="word"> interpuncts are the stone's own word dividers:
    #   kept, GLUED to the preceding token ("pakis: heleviis") — a floating
    #   ":" would misread as a token.
    # - choice → corr over sic (CelticLeiden preference); expan/abbr/ex
    #   read expanded, plainly; supplied/unclear read through and count;
    #   gap → "[…]"; del → ⟦…⟧; surplus → {…}.
    # - <hi rend="ligature"> keeps its letters; the count rides the line's
    #   leiden annotations ("ligatures") — the packet's ligature promise.
    # - Textpart direction markup (@style "text-direction:r-to-l", @rend
    #   "ductus:sinistrorse") rides every line's annotations verbatim.
    # - DROP: note, bibl, figure, desc, certainty (apparatus/metadata).
    #
    # == Languages (script honesty, the riig doctrine)
    #
    # No msContents/textLang upstream (censused 0/510); the document
    # language is langUsage's own most specific ident — the script-tagged
    # private tag sharing the first ident's primary subtag:
    # "osc-Ital-x-oscetr" (Oscan, national alphabet), "xcg-Ital-x-xcglep"
    # (Lepontic — upstream's OWN langUsage calls it Cisalpine Gaulish xcg;
    # ISO "lep" is Lepcha, so the packet-spec spelling is corrected here).
    # Passage language = the lb's @xml:lang mapped (CelticLeiden), falling
    # back to the textpart's, then the document's; a token whose language
    # differs from its line (the bilingual records' la → lat) carries it in
    # its word hash.
    #
    # == Header layers → Document#metadata (the riig/EDH shape)
    #
    #   {"facets" => {"genre" (EAGLE typeins term) / "object_type" /
    #                 "material" (Getty AAT @ana) / "script" (writingSystem
    #                 rs) => {"value", "raw" => vocabulary URI}},
    #    "tm" => "170774",              # Trismegistos, digits (32 records
    #                                   #   write bare digits or suffixes)
    #    "concordances" => ["ST Sa 36", "ImIt Bouianum 98", …],  # verbatim
    #    "related" => ["tm:170774", "imit:bouianum-98"],  # the reference-
    #                                   #   edge targets: TM + the compact
    #                                   #   Imagines Italicae citation form
    #    "date" => {"not_before"/"not_after" (signed years from the
    #               notBefore-custom/notAfter-custom pair)/"raw"/"cert"/
    #               "evidence"},
    #    "place" => {"ancient"/"modern"/"pleiades"/"geonames"},  # findspot
    #    "location" => {"settlement"/"ref"/"institution"},  # current home
    #    "editors" => ["Francesca Murano"]}
    #
    # == Translations
    #
    # Non-empty div[@type="translation"] prose (censused: ita 336 files,
    # eng 336; one stray xml:lang="wng" div — an upstream typo — is outside
    # the served set and extracts nothing) → #translations, cited by the
    # div's @subtype (the Lepontic per-textpart pairs) or ordinal; the
    # adapter builds -ita/-eng sibling documents from these. The eng divs'
    # own CC BY-SA <ref> is recorded in the fixture README; the siblings
    # keep the source-level nc class (restrictive reading).
    #
    # == Identity
    #
    # TEI/@xml:id "ItAnt_Oscan_2" mints urn:nabu:itant:oscan-2 (ItAnt_
    # prefix dropped, downcased, underscores to hyphens); the caller's urn
    # must equal the minting (ParseError otherwise, the conformance
    # identity).
    class ItantEpidocParser
      URN_PREFIX = "urn:nabu:itant:"

      INTERPRETATIVE = "interpretative"
      DIPLOMATIC = "diplomatic"

      TRANSLATION_LANGUAGES = %w[ita eng].freeze

      DROPPED_ELEMENTS = %w[note bibl figure desc certainty].freeze

      # The parser's own citable-layer census for one record (the discovery
      # decision — P25-3: the extraction itself, never a byte peek).
      Census = Data.define(:interpretative, :diplomatic, :translations)

      # One extracted line of one textpart.
      Line = Data.define(:urn_suffix, :text, :language, :annotations)
      private_constant :Line

      # Parse one record file's +layer+ into a Nabu::Document. The
      # interpretative layer (default) is the bare-urn document and carries
      # the full header metadata; the diplomatic layer is the -dipl sibling
      # and carries only its layer marker.
      def parse(path, urn:, layer: INTERPRETATIVE)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn, suffix: layer == DIPLOMATIC ? "-dipl" : "")
        language = document_language(doc)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_for(doc, layer), canonical_path: path,
          metadata: layer == DIPLOMATIC ? { "layer" => DIPLOMATIC } : metadata(doc)
        )
        extract_lines(doc, layer, path: path, document_language: language).each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: line.language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable text in div[@type=\"edition\"][@subtype=\"#{layer}\"]" if
          document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The catalogued zero-passage document for a record whose editions
      # are empty (the ten lost inscriptions; ogham text_layer:none
      # precedent) — header metadata intact, never a quarantine.
      def parse_metadata_only(path, urn:)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn, suffix: "")
        Nabu::Document.new(
          urn: urn, language: document_language(doc), title: title_for(doc, INTERPRETATIVE),
          canonical_path: path, metadata: metadata(doc).merge("text_layer" => "none")
        )
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # Which layers of this record the parser's own extraction finds
      # citable, and which translation languages carry prose — what
      # discovery mints refs from.
      def census(path)
        doc = read_xml(path)
        language = document_language(doc)
        Census.new(
          interpretative: layer_citable?(doc, INTERPRETATIVE, path: path, language: language),
          diplomatic: layer_citable?(doc, DIPLOMATIC, path: path, language: language),
          translations: translation_pairs(doc).keys
        )
      end

      # The translation prose as { "ita" => [[cite, text], …], … } — one
      # pair per non-empty <p> of every served-language translation div,
      # cited by the div's @subtype (Lepontic per-textpart) or ordinal.
      def translations(path)
        translation_pairs(read_xml(path))
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + language ------------------------------------------------

      # Validates and returns the BARE minted urn (no sibling suffix).
      def validate_identity!(doc, path:, urn:, suffix:)
        xml_id = doc.root&.[]("id").to_s.strip
        raise ParseError, "#{path}: no xml:id on the TEI root" if xml_id.empty?

        base = URN_PREFIX + xml_id.delete_prefix("ItAnt_").downcase.tr("_", "-")
        return base if "#{base}#{suffix}" == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "xml:id #{xml_id.inspect} mints #{"#{base}#{suffix}".inspect}"
      end

      # langUsage's most specific ident: the longest tag sharing the first
      # ident's primary subtag (osc + osc-Ital-x-oscetr → the latter). The
      # extra idents (a bilingual record's lat/grc-Grek) stay token-grain.
      def document_language(doc)
        idents = doc.xpath("//langUsage/language/@ident").map(&:value).reject(&:empty?)
        return "und" if idents.empty?

        primary = idents.first.split("-", 2).first
        own = idents.select { |ident| ident.split("-", 2).first == primary }
        CelticLeiden.normalize_language(own.max_by(&:length)) || "und"
      end

      def title_for(doc, layer)
        title = presence(doc.at_xpath("//titleStmt/title")&.text)
        return title unless layer == DIPLOMATIC

        title ? "#{title} — diplomatic" : "diplomatic"
      end

      # -- document metadata ---------------------------------------------------

      def metadata(doc)
        result = {}
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        result.merge!(concordance_metadata(doc))
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        location = extract_location(doc)
        result["location"] = location unless location.empty?
        editors = doc.xpath("//editionStmt/editor/persName").filter_map { |node| presence(node.text) }
        result["editors"] = editors unless editors.empty?
        result
      end

      FACET_SOURCES = {
        "genre" => "//textClass//term",
        "object_type" => "//physDesc//objectType",
        "material" => "//physDesc//material",
        "script" => "//scriptDesc//rs[@type='writingSystem']"
      }.freeze
      private_constant :FACET_SOURCES

      # value = the record's own term, raw = the LOD vocabulary URI (EAGLE
      # typeins / Getty AAT / the project's alphabet page) when declared.
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

      # TM digits + every traditionalID verbatim; related = the two stable
      # citation spaces (tm:, imit: — the compact Imagines Italicae form).
      def concordance_metadata(doc)
        result = {}
        related = []
        tm = presence(doc.at_xpath("//msIdentifier//altIdentifier[@type='trismegistos']/idno")&.text)
        if tm && (digits = tm[/\d+/])
          result["tm"] = digits
          related << "tm:#{digits}"
        end
        concordances = doc.xpath("//msIdentifier//altIdentifier[@type='traditionalID']/idno")
                          .filter_map { |idno| presence(idno.text) }
        result["concordances"] = concordances unless concordances.empty?
        related.concat(concordances.filter_map { |entry| imit_target(entry) })
        result["related"] = related.uniq unless related.empty?
        result
      end

      # "ImIt Bouianum 104, 21" → "imit:bouianum-104-21" — deterministic
      # compact slug of the citation (non-alphanumerics fold to one hyphen).
      def imit_target(entry)
        return nil unless entry.start_with?("ImIt ")

        slug = entry.delete_prefix("ImIt ").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
        slug.empty? ? nil : "imit:#{slug}"
      end

      # origDate's notBefore-custom/notAfter-custom signed years (DateAxis
      # semantics — all 510 records carry the pair); raw/cert/evidence ride
      # verbatim.
      def extract_date(doc)
        node = doc.at_xpath("//origin/origDate") or return {}
        result = {}
        begin
          not_before = DateAxis.parse_year(node["notBefore-custom"] || node["notBefore"])
          not_after = DateAxis.parse_year(node["notAfter-custom"] || node["notAfter"])
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue DateAxis::InvalidYear
          nil # bounds dropped; the raw fields below stay honest
        end
        { "raw" => presence(node.text), "cert" => presence(node["cert"]),
          "evidence" => presence(node["evidence"]) }.each { |key, value| result[key] = value if value }
        result
      end

      # The findspot (origPlace): ancient name + Pleiades ref, modern name
      # + GeoNames ref — the axis-places layer.
      def extract_place(doc)
        origin = doc.at_xpath("//origin/origPlace") or return {}
        ancient = origin.at_xpath("./placeName[@type='ancient']")
        modern = origin.at_xpath("./placeName[@type='modern']")
        result = {}
        { "ancient" => ancient&.text, "modern" => modern&.text }.each do |key, value|
          folded = presence(value)
          result[key] = folded if folded
        end
        pleiades = ancient && presence(ancient["ref"])
        result["pleiades"] = pleiades if pleiades
        geonames = modern && presence(modern["ref"])
        result["geonames"] = geonames if geonames
        result
      end

      # The current home (msIdentifier's DIRECT settlement/institution —
      # never the altIdentifier[@type="cancelled"] nest).
      def extract_location(doc)
        identifier = doc.at_xpath("//msIdentifier") or return {}
        settlement = identifier.at_xpath("./settlement")
        result = {}
        name = settlement && presence(settlement.text)
        result["settlement"] = name if name
        ref = settlement && presence(settlement["ref"])
        result["ref"] = ref if ref
        institution = presence(identifier.at_xpath("./institution")&.text)
        result["institution"] = institution if institution
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- translations --------------------------------------------------------

      def translation_pairs(doc)
        pairs = {}
        ordinals = Hash.new(0)
        doc.xpath("//div[@type='translation']").each do |div|
          language = CelticLeiden.normalize_language(div["lang"])
          next unless TRANSLATION_LANGUAGES.include?(language)

          ordinals[language] += 1
          base = presence(div["subtype"]) || "t#{ordinals[language]}"
          append_prose(pairs, language, base, div)
        end
        pairs.each_value(&:freeze)
        TRANSLATION_LANGUAGES.each_with_object({}) { |lang, out| out[lang] = pairs[lang] if pairs.key?(lang) }
      end

      def append_prose(pairs, language, base, div)
        seen = 0
        div.xpath("./p").each do |paragraph|
          text = CelticLeiden.fold(paragraph.text)
          next if text.empty?

          seen += 1
          (pairs[language] ||= []) << [seen == 1 ? base : "#{base}.#{seen}", text]
        end
      end

      # -- the edition walk ----------------------------------------------------

      def editions(doc, layer)
        doc.xpath("//div[@type='edition']").select { |division| division["subtype"] == layer }
      end

      def layer_citable?(doc, layer, path:, language:)
        divisions = editions(doc, layer)
        return false if divisions.empty?

        extraction = Extraction.new(path: path, document_language: language)
        divisions.each { |division| extraction.edition(division) }
        extraction.lines.any?
      end

      def extract_lines(doc, layer, path:, document_language:)
        divisions = editions(doc, layer)
        raise ParseError, "#{path}: no div[@type=\"edition\"][@subtype=\"#{layer}\"] found" if divisions.empty?

        extraction = Extraction.new(path: path, document_language: document_language)
        divisions.each { |division| extraction.edition(division) }
        extraction.lines
      end

      # Recursive-descent extraction state for one record's edition layer:
      # the textpart context, the open line, the word stack (riig's
      # Extraction, transposed to textparts + the ItAnt token dialect).
      class Extraction
        WORD_ELEMENTS = %w[w name num].freeze
        WORD_ATTRIBUTES = %w[type subtype lemma pos msd].freeze

        def initialize(path:, document_language:)
          @path = path
          @document_language = document_language
          @raw_lines = []
          @current = nil
          @textpart = nil # {n:, direction:, ductus:, language:}
          @lb_ordinal = 0
          @words = []
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
          @seen_suffixes = {}
          @block = 1
        end

        def edition(node)
          node.element_children.each { |child| walk(child) }
          close_line
        end

        def lines
          previous_scope = :none
          @raw_lines.filter_map do |line|
            text = CelticLeiden.fold(line[:buffer])
            next if CelticLeiden.gap_only?(text)

            # Each textpart is its own line-numbering universe: the
            # implicit collision block resets at every textpart boundary.
            scope = line[:textpart]&.fetch(:n)
            @block = 1 if scope != previous_scope
            previous_scope = scope
            Line.new(urn_suffix: mint_suffix(line), text: text,
                     language: line[:language], annotations: annotations(line))
          end
        end

        private

        def walk(node)
          return text_node(node) if node.text?
          return unless node.element?

          name = node.name
          return if ItantEpidocParser::DROPPED_ELEMENTS.include?(name)
          return word(node) if WORD_ELEMENTS.include?(name)

          case name
          when "div" then division(node)
          when "choice" then choice(node)
          when "lb" then line_break(node)
          when "gap" then gap(node)
          when "space" then emit(" ", literal: true)
          when "pc" then interpunct(node)
          when "hi" then highlight(node)
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

        # Word-internal whitespace is markup noise (class note); +literal+
        # marks explicit separators and Leiden markers.
        def emit(text, literal: false)
          text = text.gsub(/[[:space:]]+/, "") if !literal && !@words.empty?
          return if text.empty?

          @current[:buffer] << text if @current
          @words.last[:form] << text unless @words.empty?
          count_certainty(text)
        end

        def count_certainty(text)
          return if @current.nil? || (@supplied_depth.zero? && @unclear_depth.zero?)

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
        end

        # -- textparts ---------------------------------------------------------

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          close_line
          previous = @textpart
          @textpart = {
            n: presence(node["n"]),
            direction: styled_value(node["style"], "text-direction"),
            ductus: styled_value(node["rend"], "ductus"),
            language: CelticLeiden.normalize_language(node["lang"])
          }
          recurse(node)
          close_line
          @textpart = previous
        end

        # "text-direction:r-to-l" → "r-to-l" (nil-safe, key-scoped).
        def styled_value(attribute, key)
          attribute.to_s.split(";").filter_map do |declaration|
            name, value = declaration.split(":", 2)
            value&.strip if name&.strip == key
          end.first
        end

        # -- lines -------------------------------------------------------------

        def line_break(node)
          @lb_ordinal += 1
          n = node["n"].to_s
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.empty?

          close_line
          @current = {
            n: n, textpart: @textpart, buffer: +"", words: [], gaps: [], ligatures: 0,
            supplied: 0, unclear: 0, cancelled: @del_depth.positive?,
            language: CelticLeiden.normalize_language(node["lang"]) ||
                      @textpart&.fetch(:language) || @document_language
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # -- markers + counted spans -------------------------------------------

        def gap(node)
          annotation = CelticLeiden.gap_annotation(node)
          @current[:gaps] << annotation if @current
          emit(CelticLeiden::GAP_MARKER, literal: true)
        end

        # The stone's own word divider: glued to the preceding token (a
        # floating ":" would misread as a token of the text).
        def interpunct(node)
          @current[:buffer].sub!(/[[:space:]]+\z/, "") if @current
          recurse(node)
        end

        def highlight(node)
          @current[:ligatures] += 1 if @current && node["rend"] == "ligature"
          recurse(node)
        end

        def counted(node, kind)
          variable = kind == :supplied ? :@supplied_depth : :@unclear_depth
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def wrapped(node, open, close)
          @del_depth += 1 if open == CelticLeiden::CANCELLATION_OPEN
          @current[:cancelled] = true if @current && open == CelticLeiden::CANCELLATION_OPEN
          emit(open, literal: true)
          recurse(node)
          emit(close, literal: true)
          @del_depth -= 1 if open == CelticLeiden::CANCELLATION_OPEN
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end

        # -- tokens ------------------------------------------------------------

        def word(node)
          record = { attrs: word_attrs(node), form: +"", line: @current }
          @words.push(record)
          recurse(node)
          @words.pop
          attach_word(record)
        end

        def word_attrs(node)
          attrs = WORD_ATTRIBUTES.each_with_object({}) do |attribute, hash|
            value = presence(node[attribute])
            hash[attribute] = value if value
          end
          language = CelticLeiden.normalize_language(node["lang"])
          attrs["lang"] = language if language && @current && language != @current[:language]
          attrs
        end

        def attach_word(record)
          line = record[:line] || @current
          form = CelticLeiden.fold(record[:form])
          return if line.nil? || CelticLeiden.gap_only?(form)

          line[:words] << { "form" => form }.merge(record[:attrs])
        end

        # -- finalization ------------------------------------------------------

        # <textpart n?>:<b-block?>:<lb n>, collision-safe (DdbdpParser P5-1).
        def mint_suffix(line)
          textpart = line[:textpart]&.fetch(:n)
          loop do
            block = @block > 1 ? ["b#{@block}"] : []
            suffix = ([textpart].compact + block + [line[:n]]).join(":")
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
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear], cancelled: line[:cancelled]
          )
          leiden["ligatures"] = line[:ligatures] if line[:ligatures].positive?
          result["leiden"] = leiden unless leiden.empty?
          result["words"] = line[:words] unless line[:words].empty?
          direction = line[:textpart]&.fetch(:direction)
          result["direction"] = direction if direction
          ductus = line[:textpart]&.fetch(:ductus)
          result["ductus"] = ductus if ductus
          result
        end

        def presence(value)
          value = value.to_s.strip
          value.empty? ? nil : value
        end
      end
      private_constant :Extraction
    end
  end
end
