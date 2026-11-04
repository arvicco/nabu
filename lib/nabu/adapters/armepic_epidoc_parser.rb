# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "armepic-epidoc": one inscription record of ArmEpiC /
    # ArtsakhEpiC (EPFL DHLAB; Zenodo 10.5281/zenodo.23501516, v7) — the
    # Armenian inscriptions of Artsakh, 12th–20th c., TEI/EpiDoc 9.7. A
    # sibling of the IIP/I.Sicily/RIIG epigraphy families sharing the
    # CelticLeiden reading-text policy (composed, never copied). DOM-based
    # deliberately: 50 records, the largest 47 KB.
    #
    # == Content shape (full-deposit census, 2026-11-04)
    #
    #   div[@type="edition"] > (div[@type="textpart"]…)? > ab >
    #     lb/w[@lemma @pos]/expan(abbr+ex)/hi[@rend=ligature]/persName/
    #     placeName/roleName/choice(orig+reg)/num/date/g/supplied/gap/
    #     surplus/space/add/seg/milestone[@unit=face]/join
    #
    # One edition div per record; ART0001–ART0010 (the first vintage) are
    # pretty-printed with formatting whitespace INSIDE <w> (the root
    # declares xml:space="preserve", but "Կ\n<hi>ամ</hi>\n<hi>աւ</hi>" is one
    # carved word) — so text inside a <w> loses ALL whitespace (census: every
    # whitespace run inside a <w>, 260 of them, is a line-break indent
    # around a <lb break="no"/> or a <hi>); between words it folds to one
    # space.
    #
    # == Passage = the LINE, keyed by upstream's own lb @n
    #
    #   urn = <document-urn>[:<subtype><n>…]:<lb @n>
    #
    # Every line carries its @n (371 lbs), restarting inside each textpart
    # (section › column, ART0013) — so the textpart path ("section1",
    # "column2", from @subtype + @n) prefixes the line key. A textpart with
    # no lb at all (ART0026's three monograms) is ONE passage keyed by its
    # path alone; text before the first lb of a record without textparts
    # keys "pre" (none at the census). Lines open lazily on the first
    # non-whitespace emission; a gap-only line mints nothing; a repeated key
    # takes "+2"/"+3" (none at the census).
    #
    # == Text policy (CelticLeiden + the ArmEpiC dialect)
    #
    # - DIPLOMATIC, per the records' own editorialDecl ("Diplomatic
    #   transcription; no silent normalization"): <choice> keeps <orig>
    #   when present — all 9 corpus choices are orig = the carved Armenian
    #   letter-numeral, reg = the editor's arithmetic ("720 (1271)"); the
    #   reg rides the "regularized" annotation. A choice without orig falls
    #   back to CelticLeiden.choice_branch.
    # - expan reads abbr+ex (the house expanded reading); <am> drops (the
    #   graphical monogram glyph — ART0026's monograms read their <ex>).
    # - supplied/unclear read through and count; gap → "[…]"; del → ⟦…⟧;
    #   surplus → {…}; space → one space; g/hi/num/add/seg read through
    #   (the vertical-dot word dividers ":" and crosses "†" are carved).
    # - DROP: note, bibl, figure, desc, rdg, certainty, am, join.
    #
    # == Line annotations (present keys only)
    #
    #   "tokens"      [{"form","lemma","upos"}] — every <w lemma pos>, on the
    #                 line the word OPENS (a word broken by <lb break="no"/>
    #                 keeps its whole form there); CoNLL-U key names.
    #   "entities"    [{"type" person|place, "text", "ref"?}] — persName/
    #                 placeName as inscribed; ref verbatim (urn:armepic:…).
    #   "numerals"    [{"text","value"}] — <num value> letter-numerals.
    #   "regularized" [{"orig","reg"}] — the choice pairs (see above).
    #   "faces"       ["1",…] — <milestone unit="face"> crossed on the line.
    #   "textpart"    [{"subtype","n"}…] — the enclosing textpart path.
    #   "leiden"      the CelticLeiden gaps/supplied/unclear/cancelled hash.
    #
    # == Languages
    #
    # The edition div says xml:lang="hy" (40 records) or nothing (10); the
    # root's "en" is the RECORD's language. ISO 639-1 "hy" has no stage, and
    # the registry's hy node is MODERN Armenian — wrong for a 13th-century
    # grabar inscription — so the edition maps to the Classical Armenian
    # anchor xcl (grabar, the written norm of the corpus, with Middle
    # Armenian vernacular features; the staging question rides the source's
    # lect posture, never this parser). Any other edition tag is outside the
    # census → ParseError. Translation paragraphs map hy → hye (the editors'
    # Modern Eastern Armenian) and en → eng.
    #
    # == Header → Document#metadata
    #
    #   "armepic_id" (publicationStmt idno type=armepic), "url" (the Artsakh
    #   Epigraphy Atlas address), "title_hy",
    #   "date" => {"not_before","not_after" (when-custom → a one-year
    #     envelope; notBefore-custom/notAfter-custom → bounds; all CE),
    #     "raw" (origDate text), "evidence","precision","calendar"},
    #   "place" => {"ancient" (origPlace settlement, English name — else the
    #     found-provenance name), "name_hy", "armepic_ref", "geo" ("lat,
    #     lon" from the decimal coordinates note whose @corresp is the
    #     settlement's own ref — upstream writes "lat lon"), "findspot",
    #     "findspot_ref" (the found provenance: the monument)},
    #   "monument" (msIdentifier institution), "monument_part",
    #   "facets" => {"genre" (keywords, English), "object_type", "material",
    #     "technique", "condition", "script_style"} each {"values","raw"},
    #   "script_refs", "layout", "written_lines",
    #   "translations"/"commentary" => {"eng","hye"}, "bibliography" =>
    #   [{"ref","range"}].
    #
    # == Identity
    #
    # The filename ART<nnnn>.xml mints urn:nabu:armepic:art<nnnn>; the
    # caller's urn must equal it, and the in-file idnos (type=filename,
    # type=armepic) must name the same record — drift → ParseError
    # (quarantine, never repair).
    class ArmepicEpidocParser
      URN_PREFIX = "urn:nabu:armepic:"
      FILENAME = /\AART\d{4}\.xml\z/

      DROPPED_ELEMENTS = %w[note bibl figure desc rdg certainty am join].freeze

      # The edition tags the census found (40 "hy", 10 untagged).
      EDITION_LANGUAGES = [nil, "hy"].freeze
      LANGUAGE = "xcl"

      # Translation/commentary paragraph tags → ISO 639-3.
      PARAGRAPH_LANGUAGES = { "en" => "eng", "hy" => "hye" }.freeze

      Line = Data.define(:urn_suffix, :text, :annotations)
      private_constant :Line

      def self.urn_for(path)
        "#{URN_PREFIX}#{File.basename(path, '.xml').downcase}"
      end

      def parse(path, urn:)
        name = File.basename(path)
        raise ParseError, "#{path}: not an ART<nnnn>.xml record" unless FILENAME.match?(name)

        minted = self.class.urn_for(path)
        unless minted == urn
          raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, the filename mints #{minted.inspect}"
        end

        doc = read_xml(path)
        validate_identity!(doc, path)
        edition = doc.at_xpath("//text/body/div[@type='edition']") or
          raise ParseError, "#{path}: no edition div"
        validate_language!(edition, path)

        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, title: title_of(doc, "en"), canonical_path: path,
          metadata: metadata(doc)
        )
        Extraction.new.run(edition).each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: LANGUAGE,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: the edition has no citable text" if document.empty?

        document
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "armepic record"), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def validate_identity!(doc, path)
        stem = File.basename(path, ".xml")
        filename = doc.at_xpath("//publicationStmt/idno[@type='filename']")&.text.to_s.strip
        armepic = doc.at_xpath("//publicationStmt/idno[@type='armepic']")&.text.to_s.strip
        drift = []
        drift << "idno filename #{filename.inspect}" unless filename.empty? || filename == "#{stem}.xml"
        drift << "idno armepic #{armepic.inspect}" unless armepic.empty? || armepic == "urn:armepic:inscription:#{stem}"
        return if drift.empty?

        raise ParseError, "#{path}: in-file identity drift (#{drift.join(', ')}) — quarantined, never repaired"
      end

      def validate_language!(edition, path)
        tag = edition["lang"]
        return if EDITION_LANGUAGES.include?(tag)

        raise ParseError, "#{path}: edition language #{tag.inspect} is outside the censused set " \
                          "#{EDITION_LANGUAGES.compact.inspect} — classify it before ingesting"
      end

      def title_of(doc, lang)
        presence(doc.at_xpath("//titleStmt/title[@lang='#{lang}']")&.text)
      end

      # -- document metadata ----------------------------------------------------

      def metadata(doc)
        result = {}
        { "armepic_id" => doc.at_xpath("//publicationStmt/idno[@type='armepic']")&.text,
          "url" => doc.at_xpath("//publicationStmt/idno[@type='URI']")&.text,
          "title_hy" => title_of(doc, "hy"),
          "monument" => doc.at_xpath("//sourceDesc/msDesc/msIdentifier/institution")&.text,
          "monument_part" => doc.at_xpath("//msPart/msIdentifier/objectName[@lang='en']")&.text,
          "layout" => doc.at_xpath("//layoutDesc/layout[@lang='en']")&.text }.each do |key, value|
          folded = presence(value)
          result[key] = folded if folded
        end
        lines = doc.at_xpath("//layoutDesc/layout[@writtenLines]")&.[]("writtenLines").to_s
        result["written_lines"] = Integer(lines, 10) if lines.match?(/\A\d+\z/)
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        scripts = doc.at_xpath("//handDesc/handNote/@scriptRef")&.value.to_s.split
        result["script_refs"] = scripts unless scripts.empty?
        %w[translations commentary].each do |key|
          paragraphs = paragraphs_of(doc, key == "translations" ? "translation" : "commentary")
          result[key] = paragraphs unless paragraphs.empty?
        end
        bibliography = doc.xpath("//div[@type='bibliography']//bibl").filter_map do |bibl|
          ref = bibl.at_xpath("./ptr/@target")&.value.to_s.strip
          next if ref.empty?

          range = presence(bibl.at_xpath("./citedRange")&.text)
          { "ref" => ref, "range" => range }.compact
        end
        result["bibliography"] = bibliography unless bibliography.empty?
        result
      end

      # when-custom is a single CE year (the Armenian-era date converted —
      # datingMethod gregorian); notBefore-custom/notAfter-custom are CE
      # bounds. Bare 1–4 digit years only (the census: all four-digit).
      def extract_date(doc)
        node = doc.at_xpath("//history/origin/origDate") or return {}
        result = {}
        when_year = year(node["when-custom"])
        not_before = when_year || year(node["notBefore-custom"])
        not_after = when_year || year(node["notAfter-custom"])
        result["not_before"] = not_before if not_before
        result["not_after"] = not_after if not_after
        { "raw" => presence(node.text), "evidence" => presence(node["evidence"]),
          "precision" => presence(node["precision"]), "calendar" => presence(node["calendar"]) }
          .each { |key, value| result[key] = value if value }
        result
      end

      def year(value)
        value = value.to_s.strip
        value.match?(/\A\d{1,4}\z/) ? Integer(value, 10) : nil
      end

      def extract_place(doc)
        result = {}
        settlement = doc.at_xpath("//history/origin/origPlace/placeName")
        found = doc.at_xpath("//history/provenance[@type='found']/placeName")
        if settlement
          ref = settlement["ref"].to_s.strip
          { "ancient" => settlement.at_xpath("./name[@lang='en']")&.text,
            "name_hy" => settlement.at_xpath("./name[@lang='hy']")&.text,
            "armepic_ref" => ref }.each do |key, value|
            folded = presence(value)
            result[key] = folded if folded
          end
          geo = settlement_geo(doc, ref)
          result["geo"] = geo if geo
        end
        if found
          findspot = presence(found.at_xpath("./name[@lang='en']")&.text)
          result["findspot"] = findspot if findspot
          findspot_ref = presence(found["ref"])
          result["findspot_ref"] = findspot_ref if findspot_ref
          result["ancient"] ||= findspot if findspot
        end
        result
      end

      # The decimal coordinates note pointing at the settlement itself
      # (a second note may point at the monument); "lat lon" → "lat, lon".
      def settlement_geo(doc, ref)
        return nil if ref.empty?

        note = doc.xpath("//history/origin/origPlace/note[@type='coordinates'][@subtype='decimal']")
                  .find { |candidate| candidate["corresp"] == ref }
        geo = note && note.at_xpath("./geo")&.text.to_s.strip
        match = geo&.match(/\A(-?\d+(?:\.\d+)?)[\s,]+(-?\d+(?:\.\d+)?)\z/)
        match && "#{match[1]}, #{match[2]}"
      end

      FACET_SOURCES = {
        "genre" => "//profileDesc//keywords/term[@lang='en']",
        "object_type" => "//supportDesc/support/objectType[@lang='en']",
        "material" => "//supportDesc/support/material[@lang='en']",
        "technique" => "//supportDesc/support/rs[@type='technique'][@lang='en']",
        "condition" => "//supportDesc/condition/term[@lang='en']",
        "script_style" => "//handDesc/handNote/term[@lang='en']"
      }.freeze
      private_constant :FACET_SOURCES

      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, xpath), facets|
          values = doc.xpath(xpath).filter_map { |node| presence(node.text) }.uniq
          next if values.empty?

          facets[facet] = { "values" => values, "raw" => values.join("; ") }
        end
      end

      def paragraphs_of(doc, type)
        doc.xpath("//text/body/div[@type='#{type}']//p").each_with_object({}) do |p, result|
          lang = PARAGRAPH_LANGUAGES[p["lang"]] or next
          text = presence(p.text) or next
          result[lang] = result[lang] ? "#{result[lang]}\n\n#{text}" : text
        end
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # Recursive-descent extraction over the edition div (see the class
      # note): textpart path, lazily-opened lb-keyed lines, word tokens and
      # entity spans that may cross line breaks.
      class Extraction
        def initialize
          @lines = []
          @current = nil
          @path = []
          @textparts = []
          @key = nil
          @word = nil
          @spans = []
          @faces = []
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
        end

        def run(edition)
          recurse(edition)
          finalize
        end

        private

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?
          return if DROPPED_ELEMENTS.include?(node.name)

          case node.name
          when "div" then division(node)
          when "lb" then line_break(node)
          when "w" then word(node)
          when "persName", "placeName" then entity(node)
          when "choice" then choice(node)
          when "num" then numeral(node)
          when "milestone" then milestone(node)
          when "gap" then gap(node)
          when "space" then emit_marker(" ")
          when "supplied" then counted(node, :@supplied_depth)
          when "unclear" then counted(node, :@unclear_depth)
          when "del" then wrapped(node, CelticLeiden::CANCELLATION_OPEN, CelticLeiden::CANCELLATION_CLOSE)
          when "surplus" then wrapped(node, CelticLeiden::SURPLUS_OPEN, CelticLeiden::SURPLUS_CLOSE)
          when "ab", "p" then block(node)
          else recurse(node)
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        # -- lines ----------------------------------------------------------------

        def emit(text)
          text = text.gsub(/[[:space:]]+/, "") if @word
          return if text.empty?
          return if @current.nil? && text.strip.empty?

          open_line
          @current[:buffer] << text
          @word[:form] << text if @word
          @spans.each do |span|
            span[:buffer] << text
            span[:line] ||= @current
          end
          count_certainty(text)
        end

        def emit_marker(marker)
          open_line
          @current[:buffer] << marker
        end

        def open_line
          return if @current

          @current = {
            path: @path.dup, key: @key, buffer: +"", tokens: [], entities: [], numerals: [],
            regularized: [], faces: @faces.dup, gaps: [], supplied: 0, unclear: 0,
            cancelled: @del_depth.positive?, textpart: @textparts.map(&:dup)
          }
          @faces.clear
          @lines << @current
        end

        def line_break(node)
          @current = nil
          @key = node["n"].to_s.strip
          @key = nil if @key.empty?
        end

        # A block boundary separates words but never ends the line.
        def block(node)
          @current[:buffer] << " " if @current
          recurse(node)
          @current[:buffer] << " " if @current
        end

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          @current = nil
          saved_key = @key
          @key = nil
          @path.push("#{node['subtype']}#{node['n']}")
          @textparts.push({ "subtype" => node["subtype"], "n" => node["n"] }.compact)
          recurse(node)
          @current = nil
          @path.pop
          @textparts.pop
          @key = saved_key
        end

        # -- words, entities, numerals --------------------------------------------

        def word(node)
          return recurse(node) if @word

          open_line
          @word = { form: +"", line: @current }
          recurse(node)
          token = { "form" => CelticLeiden.fold(@word[:form]), "lemma" => node["lemma"], "upos" => node["pos"] }
          token = token.reject { |_, value| value.nil? || value.empty? }
          @word[:line][:tokens] << token unless token["form"].to_s.empty?
          @word = nil
        end

        # The text emitted while the block runs, and the line it OPENED on
        # (a span crossing a line break belongs to its first line).
        def capture
          span = { buffer: +"", line: nil }
          @spans << span
          yield
          @spans.delete(span)
          [CelticLeiden.fold(span[:buffer]), span[:line]]
        end

        def entity(node)
          text, line = capture { recurse(node) }
          return if text.empty? || line.nil?

          record = { "type" => node.name == "persName" ? "person" : "place", "text" => text }
          ref = node["ref"].to_s.strip
          record["ref"] = ref unless ref.empty?
          line[:entities] << record
        end

        def numeral(node)
          text, line = capture { recurse(node) }
          value = node["value"].to_s
          return if text.empty? || line.nil? || !value.match?(/\A\d+\z/)

          line[:numerals] << { "text" => text, "value" => Integer(value, 10) }
        end

        def choice(node)
          orig = node.element_children.find { |child| child.name == "orig" }
          unless orig
            branch = CelticLeiden.choice_branch(node)
            walk(branch) if branch
            return
          end

          text, line = capture { walk(orig) }
          reg = node.element_children.find { |child| child.name == "reg" }
          return unless reg && line

          line[:regularized] << { "orig" => text, "reg" => CelticLeiden.fold(reg.text) }
        end

        def milestone(node)
          return unless node["unit"] == "face" && node["n"]

          @current ? @current[:faces] << node["n"] : @faces << node["n"]
        end

        # -- Leiden markers + counted spans ---------------------------------------

        def gap(node)
          emit_marker(CelticLeiden::GAP_MARKER)
          @current[:gaps] << CelticLeiden.gap_annotation(node)
        end

        def counted(node, variable)
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
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

        # -- finalization ---------------------------------------------------------

        def finalize
          used = Hash.new(0)
          @lines.filter_map do |line|
            text = CelticLeiden.fold(line[:buffer])
            next if text.empty? || CelticLeiden.gap_only?(text)

            suffix = suffix_of(line)
            used[suffix] += 1
            suffix = "#{suffix}+#{used[suffix]}" if used[suffix] > 1
            Line.new(urn_suffix: suffix, text: text, annotations: annotations(line))
          end
        end

        def suffix_of(line)
          parts = line[:path] + [line[:key]].compact
          parts.empty? ? "pre" : parts.join(":")
        end

        def annotations(line)
          result = {}
          { "tokens" => line[:tokens], "entities" => line[:entities], "numerals" => line[:numerals],
            "regularized" => line[:regularized], "faces" => line[:faces],
            "textpart" => line[:textpart] }.each { |key, value| result[key] = value unless value.empty? }
          leiden = CelticLeiden.leiden_annotations(
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear], cancelled: line[:cancelled]
          )
          result["leiden"] = leiden unless leiden.empty?
          result
        end
      end
      private_constant :Extraction
    end
  end
end
