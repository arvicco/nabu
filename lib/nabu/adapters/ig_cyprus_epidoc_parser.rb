# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "../timeline"

module Nabu
  module Adapters
    # Parser family "ig-cyprus-epidoc": one record of the Berlin academy's
    # Inscriptiones Graecae digital edition (telota.bbaw.de/ig) from IG XV
    # 1,1 — the Cypriot SYLLABARY fascicle (Karnava/Perna/Egetmeyer, Berlin
    # 2020). A DOM sibling of RiigEpidocParser (identity, header mining,
    # passage-per-line) with IsicilyEpidocParser's per-line language
    # honesty; records are ≤ a few KB, so the >5 MB Reader rule never
    # engages.
    #
    # == Content shape (censused on the fixture records, 2026-10-18)
    #
    #   div[@type="edition"] > ab > (div[@type="textpart" @subtype=
    #   "fragment" @n])? > lb[@n] + TEXT
    #
    # The edition text is FLAT: upstream renders its Leiden conventions as
    # characters, not markup — brackets "[ ]", underdots (U+0323 on the
    # syllabograms, often non-precomposable: "j̣"), lost syllables "..",
    # vacat/lacuna dashes "‒?‒", word dividers "|", and the editors'
    # writing-direction arrows (← → ↑). All of it rides VERBATIM (canonical
    # means canonical); whitespace runs fold (CelticLeiden.fold — the files
    # are xml:space="preserve" and carry tabs/double spaces as layout).
    # The only markup inside an edition is <hi>:
    # - rend="smallit": the editor's Latin descriptive notes ("linea" — a
    #   ruled line on the stone; "tit. evanidus" — the legend is faded).
    #   Never reading text: dropped from the line and kept as the
    #   "editorial_notes" annotation. A note on a line that mints nothing
    #   (the unnumbered <lb/> carrying only "linea") rides forward onto the
    #   next minted line of the same fragment.
    # - any other rend (letterspacing…): its text reads through.
    #
    # == Passage = the LINE (fragment-relative numbering)
    #
    #   urn = <document-urn>[:<fragment n>][:b<k>]:<lb n>
    #
    # Line numbers restart per fragment (record 1's I:1 and II:1), so the
    # fragment @n ("I", "II", "(a)"…) is the urn's path segment, verbatim.
    # A collision opens DdbdpParser's implicit :b<k> block. An unnumbered
    # line that folds empty (notes only) is the ruling-line idiom and drops;
    # an unnumbered CITABLE edition line is a ParseError (honest
    # quarantine — no invented numbering).
    #
    # == Languages: decided per LINE (no xml:lang anywhere in the editions)
    #
    # The records carry no language tag on the edition or its fragments
    # (the TEI root's xml:lang="en" is the header's), so the claim is read
    # off the text itself plus the title's own script label:
    # - Greek-alphabet letters in the majority → "grc" (alphabetic Greek;
    #   writing_system "greek-alphabet").
    # - Latin letters → the Cypriot syllabary, which upstream holds in its
    #   standard Latin TRANSLITERATION (a-ri-si-ta-se), never in the Unicode
    #   Cypriot block. The script subtag is therefore -Latn — the text's
    #   own script; a -Cprt subtag would claim characters the record does
    #   not contain (the tla_hf/ogham no-false-subtag doctrine). The
    #   language is the title's: "eteokyprisch" → "ecy-Latn" (Eteocypriot);
    #   "eteokyprisch" beside "syllabisch" cannot say which syllabic lines
    #   are which → "und-Latn"; otherwise → "grc-Latn" (Greek in the
    #   syllabary — the fascicle's default). writing_system
    #   "cypriot-syllabary".
    # - Neither (digits, private-use glyphs) → the document language.
    # Document language = the most frequent line language (ties → first).
    #
    # == Sibling layers
    #
    # div[@type="translation"] carries two layers, line-for-line under the
    # edition's own suffixes (fragment + lb n):
    # - xml:lang="GRC" — the editors' transcription of the syllabic text
    #   into alphabetic Greek (Ζωϝίyας ἐπέστασε…): layer "transcription",
    #   language grc, metadata {"layer" => "transcription"} (the isicily
    #   -translit shape).
    # - xml:lang="DE" — Klaus Hallof's German translation: layer "de",
    #   language deu, metadata {"kind" => "translation", "translator"}.
    # Bracketed italic placeholders ("[eteokyprisch]", "[Buchstaben]" —
    # "no translation: Eteocypriot / letters") are not translation and
    # mint nothing. #layers reports which layers a record can mint — the
    # discovery decision IS this extraction (the riig P25-3 rule); a layer
    # with an unnumbered citable line is not minted (no invented pairing).
    #
    # == Header → Document#metadata
    #
    #   {"idno" => "IG XV 1, 1",          # idno type=localId, stripped
    #    "uri" => edition page URL,       # idno type=URI (the link-back target)
    #    "facets" => {"genre"/"object_type"/"material" => {"value" => term}},
    #                                     # German terms as upstream writes
    #                                     # them; genre = the title's head
    #                                     # ("Weihinschrift") only when the
    #                                     # title is "<genre>, <script label>"
    #    "writing" => "eteokyprisch und griechisch",  # the title's label
    #    "writing_systems" => [...],      # measured over the minted lines
    #    "date" => {"not_before"/"not_after" (signed)/"raw"},
    #    "place" => {"ancient" => origPlace},  # ancient city names
    #                                     # (Amathus, Marion, Kurion); no
    #                                     # gazetteer refs in the records
    #    "provenance" => findspot + present repository, verbatim}
    #
    # == Dates (the fascicle is BCE by construction)
    #
    # origDate is German prose with UNSIGNED years: the Cypriot syllabary
    # went out of use in the Hellenistic period, so a bare year/century is
    # BCE ("330-310" = 330–310 BCE; "4.Jh." = 400–301 BCE); an explicit
    # "n.Chr." flips the era. The grammar (.date_bounds): years and year
    # ranges (a short tail takes the head's leading digits: "480-70"),
    # "um"/"ca." circa, "nach"/"vor" open ends, centuries and century
    # ranges with Anfang/Mitte/Ende/1.|2. Hälfte (the house early/mid/late
    # halves), and " / "-joined composites as one envelope (an open side
    # anywhere stays open). Anything else ("Zeit?") keeps raw only.
    #
    # == Identity
    #
    # The listing id "IG XV 1, 237(I)" ↔ file stem "237-I" (.stem_for /
    # .id_for — reversible over the censused shapes N, N(roman), N(digits));
    # urn = urn:nabu:ig-cyprus:<stem downcased>. The caller's urn must equal
    # the minting from <idno type="localId"> (mismatch → ParseError).
    class IgCyprusEpidocParser
      URN_PREFIX = "urn:nabu:ig-cyprus:"
      ID_PREFIX = "IG XV 1, "

      # The censused listing id shapes: 311 N, 280 N(digits), 2 N(roman).
      ID_SHAPE = /\AIG XV 1, (\d+)(?:\((\d+|[IVXLC]+)\))?\z/
      STEM_SHAPE = /\A(\d+)(?:-(\d+|[IVXLC]+))?\z/

      LAYERS = { "transcription" => "GRC", "de" => "DE" }.freeze
      LAYER_LANGUAGES = { "transcription" => "grc", "de" => "deu" }.freeze
      LAYER_TITLES = { "transcription" => "alphabetic transcription", "de" => "German translation" }.freeze

      SYLLABARY = "cypriot-syllabary"
      ALPHABET = "greek-alphabet"

      DIRECTIONS = { "←" => "sinistroverse", "→" => "dextroverse", "↑" => "upward", "↓" => "downward" }.freeze

      SCRIPT_LABEL = /syllabisch|eteokyprisch|alphabetisch|griechisch/i

      Line = Data.define(:urn_suffix, :text, :language, :annotations)
      private_constant :Line

      # The file stem for a listing id, nil outside the censused shapes.
      def self.stem_for(id)
        match = ID_SHAPE.match(id.to_s) or return nil
        match[2] ? "#{match[1]}-#{match[2]}" : match[1]
      end

      # The listing id for a file stem, nil outside the scheme.
      def self.id_for(stem)
        match = STEM_SHAPE.match(stem.to_s) or return nil
        match[2] ? "#{ID_PREFIX}#{match[1]}(#{match[2]})" : "#{ID_PREFIX}#{match[1]}"
      end

      # Parse one record file: the edition (default) or one sibling +layer+.
      def parse(path, urn:, layer: nil)
        doc = read_xml(path)
        base_urn = layer ? urn.delete_suffix("-#{layer}") : urn
        validate_identity!(doc, path: path, urn: base_urn)
        return layer_document(doc, path: path, urn: urn, layer: layer) if layer

        edition_document(doc, path: path, urn: urn)
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The sibling layers this record can mint (see class note).
      def layers(path)
        doc = read_xml(path)
        LAYERS.keys.select do |layer|
          lines = layer_lines(doc, path: path, layer: layer)
          !lines.nil? && lines.any?
        end
      end

      # -- dates ---------------------------------------------------------------

      CIRCA = /\A(?:um|ca\.|etwa)\s+/i
      CE_MARK = /\bn\.\s*Chr\.?/
      BCE_MARK = /\bv\.\s*Chr\.?/
      YEARS = /\A(\d{1,4})(?:\s*[-–]\s*(\d{1,4}))?\z/
      OPEN_END = /\A(nach|vor)\s+(\d{1,4})\z/i
      QUALIFIER = "(Anfang|Mitte|Ende|[12]\\.\\s*Hälfte)"
      CENTURY = "(?:#{QUALIFIER}\\s+)?(\\d{1,2})\\.\\s*".freeze
      CENTURIES = /\A#{CENTURY}(?:Jh\.?\s*)?(?:[-–]\s*#{CENTURY})?Jh\.?\z/

      # [not_before, not_after] signed years (either side may be nil — an
      # open end), or nil when the prose does not parse (class note).
      def self.date_bounds(raw)
        text = raw.to_s.strip
        ce = text.match?(CE_MARK)
        text = text.gsub(CE_MARK, "").gsub(BCE_MARK, "").strip
        parts = text.split(%r{\s+/\s+}).map { |part| part.sub(/\s*\([^)]*\)\z/, "").sub(CIRCA, "").strip }
        bounds = parts.map { |part| part_bounds(part, common_era: ce) }
        return nil if bounds.empty? || bounds.any?(&:nil?)

        lows = bounds.map(&:first)
        highs = bounds.map(&:last)
        [lows.any?(&:nil?) ? nil : lows.min, highs.any?(&:nil?) ? nil : highs.max]
      end

      def self.part_bounds(part, common_era:)
        sign = common_era ? 1 : -1
        if (match = YEARS.match(part))
          head = Integer(match[1], 10)
          tail = match[2] ? expand_tail(match[1], match[2]) : head
          return [head * sign, tail * sign].minmax
        end
        if (match = OPEN_END.match(part))
          year = Integer(match[2], 10) * sign
          return match[1].casecmp?("nach") ? [year, nil] : [nil, year]
        end
        match = CENTURIES.match(part) or return nil
        first = century_band(Integer(match[2], 10), match[1], sign)
        second = match[4] ? century_band(Integer(match[4], 10), match[3], sign) : first
        return nil if first.nil? || second.nil?

        [[first[0], second[0]].min, [first[1], second[1]].max]
      end

      # "480-70" → 470: the tail borrows the head's leading digits.
      def self.expand_tail(head, tail)
        return Integer(tail, 10) if tail.length >= head.length

        Integer(head[0, head.length - tail.length] + tail, 10)
      end

      # A century's [lo, hi] (Timeline.century_bounds), narrowed by the
      # house halves: early = first half, late = second, mid = middle half.
      def self.century_band(number, qualifier, sign)
        return nil if number.zero?

        lo, hi = Timeline.century_bounds(number * sign)
        case qualifier.to_s.gsub(/\s+/, "")
        when "Anfang", "1.Hälfte" then [lo, lo + 49]
        when "Ende", "2.Hälfte" then [lo + 50, hi]
        when "Mitte" then [lo + 25, hi - 25]
        else [lo, hi]
        end
      end
      private_class_method :part_bounds, :expand_tail, :century_band

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + header --------------------------------------------------

      def local_id(doc)
        doc.at_xpath("//publicationStmt/idno[@type='localId']")&.text.to_s.strip
      end

      def validate_identity!(doc, path:, urn:)
        id = local_id(doc)
        raise ParseError, "#{path}: no <idno type=\"localId\"> found in teiHeader" if id.empty?

        stem = self.class.stem_for(id)
        raise ParseError, "#{path}: localId #{id.inspect} is outside the IG XV 1,1 id shape" if stem.nil?

        minted = "#{URN_PREFIX}#{stem.downcase}"
        return if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "<idno type=\"localId\"> #{id.inspect} mints #{minted.inspect}"
      end

      def title_of(doc)
        presence(doc.at_xpath("//titleStmt/title")&.text)
      end

      def edition_document(doc, path:, urn:)
        title = title_of(doc)
        lines = extract(doc.xpath("//div[@type='edition']"), path: path, strict: true)
        raise ParseError, "#{path}: no div[@type=\"edition\"] found" if lines.nil?

        syllabic = syllabic_language(title)
        typed = lines.map { |line| type_line(line, syllabic) }
        language = majority_language(typed) || syllabic
        typed = typed.map { |line| line.language ? line : line.with(language: language) }
        document = Nabu::Document.new(urn: urn, language: language, title: title, canonical_path: path,
                                      metadata: metadata(doc, title: title, lines: typed))
        typed.each_with_index do |line, sequence|
          document << Nabu::Passage.new(urn: "#{urn}:#{line.urn_suffix}", language: line.language,
                                        text: line.text, annotations: line.annotations, sequence: sequence)
        end
        raise ParseError, "#{path}: no citable text found in div[@type=\"edition\"]" if document.empty?

        document
      end

      def layer_document(doc, path:, urn:, layer:)
        raise ParseError, "#{path}: unknown layer #{layer.inspect}" unless LAYERS.key?(layer)

        lines = layer_lines(doc, path: path, layer: layer)
        raise ParseError, "#{path}: layer #{layer} has no citable numbered lines" if lines.nil? || lines.empty?

        language = LAYER_LANGUAGES.fetch(layer)
        title = title_of(doc)
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path, metadata: layer_metadata(doc, layer),
          title: title ? "#{title} — #{LAYER_TITLES.fetch(layer)}" : nil
        )
        lines.each_with_index do |line, sequence|
          document << Nabu::Passage.new(urn: "#{urn}:#{line.urn_suffix}", language: language,
                                        text: line.text, annotations: line.annotations, sequence: sequence)
        end
        document
      end

      def layer_divs(doc, layer)
        doc.xpath("//div[@type='translation']").select do |div|
          div["lang"].to_s.casecmp?(LAYERS.fetch(layer))
        end
      end

      # nil when the layer has an unnumbered citable line (class note).
      def layer_lines(doc, path:, layer:)
        divs = layer_divs(doc, layer)
        return [] if divs.empty?

        extract(divs, path: path, strict: false)
      end

      def layer_metadata(doc, layer)
        return { "layer" => "transcription" } if layer == "transcription"

        translator = layer_divs(doc, layer).filter_map { |div| presence(div["resp"]) }.first
        { "kind" => "translation", "translator" => translator }.compact
      end

      # -- languages ------------------------------------------------------------

      def syllabic_language(title)
        return "grc-Latn" unless title.to_s.match?(/eteokypr/i)

        title.match?(/syllabisch/i) ? "und-Latn" : "ecy-Latn"
      end

      def type_line(line, syllabic)
        greek = line.text.scan(/\p{Greek}/).size
        latin = line.text.scan(/\p{Latin}/).size
        language, system = line_script(greek, latin, syllabic)
        annotations = line.annotations
        annotations = { "writing_system" => system }.merge(annotations) if system
        line.with(language: language, annotations: annotations)
      end

      def line_script(greek, latin, syllabic)
        return ["grc", ALPHABET] if greek.positive? && greek >= latin
        return [syllabic, SYLLABARY] if latin.positive?

        [nil, nil]
      end

      def majority_language(lines)
        counts = lines.filter_map(&:language).tally
        return nil if counts.empty?

        best = counts.values.max
        lines.map(&:language).find { |language| counts[language] == best }
      end

      # -- document metadata ---------------------------------------------------

      def metadata(doc, title:, lines:)
        result = { "idno" => local_id(doc) }
        uri = presence(doc.at_xpath("//publicationStmt/idno[@type='URI']")&.text)
        result["uri"] = uri if uri
        facets = facets(doc, title)
        result["facets"] = facets unless facets.empty?
        head, label = title_parts(title)
        result["writing"] = label if head
        systems = lines.filter_map { |line| line.annotations["writing_system"] }.uniq.sort
        result["writing_systems"] = systems unless systems.empty?
        date = date_of(doc)
        result["date"] = date if date
        place = presence(doc.at_xpath("//origin/origPlace")&.text)
        result["place"] = { "ancient" => place } if place
        provenance = presence(doc.at_xpath("//history/provenance")&.text)
        result["provenance"] = provenance if provenance
        result
      end

      def facets(doc, title)
        result = {}
        head, = title_parts(title)
        result["genre"] = { "value" => head } if head
        { "object_type" => "//physDesc//objectType", "material" => "//physDesc//material" }.each do |facet, xpath|
          value = presence(doc.at_xpath(xpath)&.text)
          result[facet] = { "value" => value } if value
        end
        result
      end

      # "Weihinschrift, eteokyprisch und griechisch" → [genre, label]; a
      # title without a script label after its comma ("Münzlegende des
      # Königs Stasioikos II.") is a description, not a genre — [nil, nil].
      def title_parts(title)
        head, label = title.to_s.split(/,\s*/, 2)
        return [nil, nil] if label.nil? || !label.match?(SCRIPT_LABEL)

        [presence(head), presence(label)]
      end

      def date_of(doc)
        raw = presence(doc.at_xpath("//origin/origDate")&.text) or return nil
        bounds = self.class.date_bounds(raw)
        result = {}
        if bounds
          result["not_before"] = bounds[0] if bounds[0]
          result["not_after"] = bounds[1] if bounds[1]
        end
        result["raw"] = raw
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- the line walk -----------------------------------------------------------

      # The minted lines of +divs+ (edition or one layer). +strict+: an
      # unnumbered citable line raises (edition); otherwise the walk answers
      # nil (the layer is not minted).
      def extract(divs, path:, strict:)
        return nil if divs.empty?

        walk = Walk.new
        divs.each { |div| walk.run(div) }
        finalize(walk.raw_lines, path: path, strict: strict)
      end

      def finalize(raw_lines, path:, strict:)
        seen = {}
        carried = Hash.new { |hash, key| hash[key] = [] }
        lines = []
        raw_lines.each do |raw|
          text = CelticLeiden.fold(raw[:buffer])
          if text.empty? || placeholder?(raw)
            carried[raw[:fragment]].concat(raw[:notes])
            next
          end
          if raw[:n].nil?
            raise ParseError, "#{path}: an <lb> carrying text is missing its @n" if strict

            return nil
          end

          notes = carried.delete(raw[:fragment]).to_a + raw[:notes]
          lines << Line.new(urn_suffix: mint_suffix(raw, seen), text: text, language: nil,
                            annotations: line_annotations(text, notes))
        end
        lines
      end

      # "[eteokyprisch]": every letter italic, the rest brackets/space.
      def placeholder?(raw)
        raw[:italic].positive? && raw[:plain].gsub(/[\[\]\s]/, "").empty?
      end

      def line_annotations(text, notes)
        result = {}
        directions = text.each_char.filter_map { |char| DIRECTIONS[char] }.uniq
        result["direction"] = directions unless directions.empty?
        result["editorial_notes"] = notes unless notes.empty?
        result
      end

      def mint_suffix(raw, seen)
        block = 1
        loop do
          suffix = ([raw[:fragment]] + (block > 1 ? ["b#{block}"] : []) + [raw[:n]]).compact.join(":")
          unless seen.key?(suffix)
            seen[suffix] = true
            return suffix
          end
          block += 1
        end
      end

      # The recursive DOM walk: fragment context, the open line, and the
      # smallit/italic bookkeeping (see class note).
      class Walk
        NO_NUMBER = {}.freeze

        attr_reader :raw_lines

        def initialize
          @raw_lines = []
          @fragment = nil
          @current = nil
          @italic = 0
        end

        def run(node)
          node.children.each { |child| walk(child) }
          @current = nil
        end

        private

        def walk(node)
          return text(node.text) if node.text?
          return unless node.element?

          case node.name
          when "div" then fragment(node)
          when "lb" then open_line(node)
          when "hi" then highlight(node)
          when "note", "bibl" then nil
          else node.children.each { |child| walk(child) }
          end
        end

        def fragment(node)
          return node.children.each { |child| walk(child) } unless node["type"] == "textpart"

          outer = @fragment
          @current = nil
          @fragment = node["n"].to_s.strip.then { |n| n.empty? ? nil : n }
          node.children.each { |child| walk(child) }
          @current = nil
          @fragment = outer
        end

        def open_line(node)
          n = node["n"].to_s.strip
          @current = { n: n.empty? ? nil : n, fragment: @fragment, buffer: +"", plain: +"", italic: 0, notes: [] }
          @raw_lines << @current
          @current
        end

        def highlight(node)
          if node["rend"] == "smallit"
            note = CelticLeiden.fold(node.text)
            ensure_line[:notes] << note unless note.empty?
            return
          end

          @italic += 1 if node["rend"] == "italic"
          node.children.each { |child| walk(child) }
          @italic -= 1 if node["rend"] == "italic"
        end

        def text(content)
          return if @current.nil? && content.strip.empty?

          line = ensure_line
          line[:buffer] << content
          if @italic.positive?
            line[:italic] += content.gsub(/\s/, "").size
          else
            line[:plain] << content
          end
        end

        # Text before the first <lb> opens an unnumbered line.
        def ensure_line
          @current || open_line(NO_NUMBER)
        end
      end
      private_constant :Walk
    end
  end
end
