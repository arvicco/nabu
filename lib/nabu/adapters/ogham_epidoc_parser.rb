# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"

module Nabu
  module Adapters
    # Parser family "ogham-epidoc" (P25-1): one OG(H)AM ("Ogham in 3D",
    # ogham.celt.dias.ie; GitHub lguariento/og-h-am) EpiDoc record —
    # Primitive Irish epigraphy in REAL Ogham codepoints (ᚑᚌᚐᚋ, U+1680–169F,
    # kept verbatim NFC). RiigEpidocParser's sibling: same DOM approach
    # (small files, freising precedent), same CelticLeiden reading-text
    # policy, its own layer machinery.
    #
    # == Layers: Document = (stone × edition layer) — the Freising design
    #
    # Each record carries PARALLEL edition divs by @subtype: "ogham" (the
    # inscription in Ogham script), "transliteration" (the same text in the
    # scholarly Latin-capital rendering), sometimes "roman" (a companion
    # Latin-alphabet inscription on the same stone), rarely "runic"/
    # "english". The OGHAM layer is the work itself → the bare urn
    # (urn:nabu:ogham:i-may-010); every other layer is a line-aligned
    # SIBLING document (…-translit, …-roman, …), so suffix-equality
    # alignment (`show --parallel`) works with no stored links — script
    # honesty by construction: the transliteration is a parallel RENDERING,
    # a document of its own, never a replacement surface for the Ogham
    # text. Stones with no ogham edition (the roman-only companion "X"
    # records) simply mint no bare-urn document.
    #
    # Repeated same-subtype divs (a stone with two ogham inscriptions) are
    # ONE layer document: their lines run on in document order, textpart
    # @n paths and the collision-triggered :b<k> block keeping suffixes
    # unique (the DdbdpParser mechanics).
    #
    # == Passage = the LINE
    #
    #   urn = <layer-document-urn>[:<textpart-n>…][:b<k>]:<lb n>
    #
    # <lb> without @n is a ParseError (two upstream transliteration layers
    # carry that defect today — honest quarantines, named in the fixture
    # README). A layer whose editions carry text but NO <lb> at all
    # (I-WAT-042's ogham side) falls back to ONE whole-layer passage under
    # the stable suffix :text — the EDH P23-3c whole-inscription precedent,
    # collision-free because it only fires when zero line suffixes were
    # minted. A layer that extracts nothing at all is a ParseError.
    #
    # == Text policy (CelticLeiden + the OG(H)AM dialect)
    #
    # - <g ref="#…"/> glyph refs (forfeda, letter variants, feather marks)
    #   RESOLVE through the repo's own charDecl glyph table: the ogham
    #   layer takes the "ogham" mapping (ᚕ, ᚖ …), every other layer the
    #   "diplomatic" mapping (Ӿ, Oᴵ, Ṯ …) — the letterform-faithful
    #   rendering; a @type attribute naming a specific mapping
    #   (type="interpretation_O") wins. Unmapped ref → ParseError (damage,
    #   the freising glyph rule). A ref-less <g> keeps its text if any
    #   (else drops — the DDbDP interpunct rationale).
    # - <space/> (deliberate spacing, unit/quantity attrs) reads as one
    #   space; <damage>/<sic>/<add> read through; choice → corr over sic
    #   (either order); del → ⟦…⟧; surplus → {…}; supplied/unclear count.
    # - <ab type="list"> (a derived one-line summary rendering some records
    #   append) is DROPPED — it duplicates the lb-grain text.
    # - DROP: note, bibl, figure, desc, rdg, certainty.
    #
    # == Tokens + inline languages (deep extraction)
    #
    # <w> (@lemma/@type — "maqqas", formula words) and <name> (@nymRef —
    # the normalized name form, "#dotagnas?") mint a per-line
    # {"words" => [{"form","lemma","type","nymRef"}, …]} annotation. An
    # element @xml:lang differing from the document language (E-DEV-001's
    # roman line "maqui" tagged pgl inside the Latin edition) rides as the
    # line's {"languages" => […]} — the DdbdpParser shape.
    #
    # == Languages (script honesty)
    #
    # Layer-document language = the layer's first edition-div @xml:lang,
    # mapped to ISO 639-3 (CelticLeiden), falling back to the header's
    # textLang @mainLang, else "und". The corpus tags honestly at the
    # record grain (pgl-Ogam, xpi-Ogam Pictish, la-Latn, sga-Ogam,
    # non-Runr…) — kept verbatim — EXCEPT that a non-ogham layer sheds a
    # copy-pasted "-Ogam" script subtag (E-DEV-001's transliteration div
    # says pgl-Ogam over Latin capitals; repeating a false script claim
    # would be dishonest, while inventing -Latn would claim what upstream
    # doesn't say).
    #
    # == Header layers → the PRIMARY document's metadata
    #
    # The stone-grain metadata rides once, on the primary (ref metadata
    # "primary", set by the adapter on each file's first layer):
    # {"facets" => {object_type/material/genre}, "place" => {townland/
    # county/country/geo verbatim/logainm refs}, "ciic"/"cisp"/"smr"
    # concordance idnos, "date" => origDate attrs+text when present,
    # "translation_en" => the translation div prose, "related" =>
    # ["https://dil.ie/<id>", …] — the commentary's word-level eDIL links,
    # the same dil.ie id space the corph packet bridges into (coordination
    # via the links journal's producer field, no code coupling)}. Sibling
    # layers stay lean ({"layer" => subtype}).
    #
    # == Identity
    #
    # <idno type="filename">I-MAY-010</idno> mints the base urn
    # urn:nabu:ogham:i-may-010 (downcased; verified equal to the file
    # basename across all 504 records) + the layer suffix; the caller's urn
    # must equal that minting (mismatch → ParseError).
    class OghamEpidocParser
      URN_PREFIX = "urn:nabu:ogham:"

      # subtype → urn suffix (nil = the primary, bare-urn layer). FROZEN.
      LAYER_SUFFIXES = {
        "ogham" => nil, "transliteration" => "translit", "roman" => "roman",
        "runic" => "runic", "english" => "english"
      }.freeze

      # The whole-layer fallback's stable urn suffix (class note).
      FALLBACK_SUFFIX = "text"

      DROPPED_ELEMENTS = %w[note bibl figure desc rdg certainty].freeze

      Line = Data.define(:urn_suffix, :text, :annotations)
      private_constant :Line

      # glyph id → {mapping type → replacement} from the repo's
      # XML/charDecl.xml (read per parse — the file is tiny).
      def self.glyph_map(chardecl_path)
        unless chardecl_path && File.file?(chardecl_path)
          raise ParseError, "charDecl #{chardecl_path.inspect} is missing — glyph refs cannot resolve"
        end

        doc = Nokogiri::XML(File.read(chardecl_path), &:strict)
        doc.remove_namespaces!
        doc.xpath("//charDecl/glyph").to_h do |glyph|
          [glyph["id"].to_s, glyph.xpath("./mapping").to_h { |m| [m["type"].to_s, m.text.to_s] }]
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{chardecl_path}: malformed XML: #{e.message}"
      end

      # The discovery census of one record (P25-3 hotfix — discovery shares
      # the parser's own extraction, the riig sibling of the same fix):
      # recognized layers split into +citable+ (would mint at least one
      # passage, OR are structurally broken — lb without @n, unresolvable
      # glyph — and must mint so parse can quarantine them honestly) and
      # +empty+ (declared but carrying no citable text: an honest absence,
      # the EDH lost-edition lesson — never a ref, never a quarantine).
      # +unknown+ collects unrecognized @subtype values (vocabulary drift,
      # loud in the adapter's discovery_skips). Commented-out edition divs
      # are invisible to the DOM and count nowhere — unlike the raw-byte
      # peek this census replaced. Order is first appearance.
      LayerCensus = Data.define(:citable, :empty, :unknown)

      def layer_census(path, glyphs:)
        doc = read_xml(path)
        recognized = []
        unknown = []
        doc.xpath("//div[@type='edition']").each do |div|
          subtype = div["subtype"].to_s
          list = LAYER_SUFFIXES.key?(subtype) ? recognized : unknown
          list << subtype unless list.include?(subtype)
        end
        citable, empty = recognized.partition { |layer| layer_citable?(doc, layer, glyphs: glyphs, path: path) }
        LayerCensus.new(citable: citable, empty: empty, unknown: unknown)
      end

      # The never-encoded stone (P25-3): a record with NO citable layer at
      # all is catalogued as a zero-passage bare-urn document carrying the
      # stone-grain header metadata plus the local-library metadata-only
      # marker ("text_layer" => "none") — catalogued, never quarantined.
      def parse_metadata_only(path, urn:)
        doc = read_xml(path)
        filename = doc.at_xpath("//idno[@type='filename']")&.text.to_s.strip
        raise ParseError, "#{path}: no <idno type=\"filename\"> found in teiHeader" if filename.empty?

        base = "#{URN_PREFIX}#{filename.downcase}"
        unless base == urn
          raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                            "<idno type=\"filename\"> #{filename.inspect} mints #{base.inspect}"
        end

        language = CelticLeiden.normalize_language(presence(doc.at_xpath("//textLang/@mainLang")&.value)) || "und"
        Nabu::Document.new(
          urn: urn, language: language, title: presence(doc.at_xpath("//titleStmt/title")&.text),
          canonical_path: path, metadata: stone_metadata(doc).merge("text_layer" => "none")
        )
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # Parse one record file's +layer+ into a Nabu::Document. +glyphs+ is
      # the .glyph_map table; +primary+ hangs the stone-grain metadata on
      # this layer's document (class note).
      def parse(path, urn:, layer:, glyphs:, primary: false)
        doc = read_xml(path)
        base = validate_identity!(doc, path: path, urn: urn, layer: layer)
        editions = layer_editions(doc, layer)
        raise ParseError, "#{path}: no div[@type=\"edition\" @subtype=#{layer.inspect}] found" if editions.empty?

        language = layer_language(doc, editions, layer)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc, layer, primary), canonical_path: path,
          metadata: metadata(doc, layer, primary)
        )
        append_passages(document, editions, path: path, urn: urn, language: language,
                                            glyphs: glyphs, layer: layer, base: base)
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

      def validate_identity!(doc, path:, urn:, layer:)
        filename = doc.at_xpath("//idno[@type='filename']")&.text.to_s.strip
        raise ParseError, "#{path}: no <idno type=\"filename\"> found in teiHeader" if filename.empty?

        suffix = LAYER_SUFFIXES.fetch(layer) do
          raise ParseError, "#{path}: unknown edition layer #{layer.inspect}"
        end
        base = "#{URN_PREFIX}#{filename.downcase}"
        minted = suffix ? "#{base}-#{suffix}" : base
        return base if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "<idno type=\"filename\"> #{filename.inspect} + layer #{layer.inspect} " \
                          "mints #{minted.inspect}"
      end

      def layer_editions(doc, layer)
        doc.xpath("//div[@type='edition']").select { |div| div["subtype"] == layer }
      end

      # Would this layer mint at least one passage? Runs the REAL extraction
      # (the whole point of P25-3: no cheaper approximation gets to
      # disagree with parse). A ParseError mid-extraction means broken, not
      # empty — report citable so the ref mints and quarantines honestly.
      def layer_citable?(doc, layer, glyphs:, path:)
        editions = layer_editions(doc, layer)
        extraction = Extraction.new(path: path, glyphs: glyphs, layer: layer,
                                    document_language: layer_language(doc, editions, layer))
        editions.each { |edition| extraction.edition(edition) }
        extraction.lines.any? || !extraction.whole_layer_line.nil?
      rescue ParseError
        true
      end

      # Class note "Languages": div @xml:lang → textLang @mainLang → und;
      # a non-ogham layer sheds a false -Ogam subtag.
      def layer_language(doc, editions, layer)
        tag = editions.filter_map { |div| presence(div["lang"]) }.first ||
              presence(doc.at_xpath("//textLang/@mainLang")&.value)
        mapped = CelticLeiden.normalize_language(tag) || "und"
        layer == "ogham" ? mapped : mapped.sub(/-Ogam\z/, "")
      end

      def title_of(doc, layer, primary)
        title = presence(doc.at_xpath("//titleStmt/title")&.text)
        return title if title.nil? || primary

        "#{title} — #{layer}"
      end

      # -- document metadata ---------------------------------------------------

      def metadata(doc, layer, primary)
        result = { "layer" => layer }
        return result unless primary

        result.merge(stone_metadata(doc))
      end

      # The stone-grain header block — on the primary layer document, or on
      # the whole metadata-only document of a never-encoded stone.
      def stone_metadata(doc)
        result = {}
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        concordance_idnos(doc).each { |key, value| result[key] = value }
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        translation = translation_prose(doc)
        result["translation_en"] = translation if translation
        related = dil_references(doc)
        result["related"] = related unless related.empty?
        result
      end

      FACET_SOURCES = {
        "object_type" => ["//physDesc//objectType", "key"],
        "material" => ["//physDesc//material", "type"],
        "genre" => ["//textClass//term", "ref"]
      }.freeze
      private_constant :FACET_SOURCES

      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, (xpath, raw_attribute)), facets|
          node = doc.at_xpath(xpath)
          value = presence(node&.text)
          next if value.nil?

          entry = { "value" => value }
          raw = presence(node[raw_attribute])
          entry["raw"] = raw if raw
          facets[facet] = entry
        end
      end

      # origPlace: townland/county/country placeNames, the logainm.ie
      # gazetteer refs, <geo> verbatim (canonical means canonical).
      def extract_place(doc)
        origin = doc.at_xpath("//origin/origPlace") or return {}
        result = {}
        %w[townland county country].each do |type|
          value = presence(origin.at_xpath("./placeName[@type='#{type}']")&.text)
          result[type] = value if value
        end
        geo = presence(origin.at_xpath(".//geo")&.text)
        result["geo"] = geo if geo
        logainm = origin.xpath(".//ref[@target]").filter_map do |ref|
          ref["target"] if ref["target"].include?("logainm.ie")
        end
        result["logainm"] = logainm.uniq unless logainm.empty?
        result
      end

      # CIIC (Macalister), CISP and SMR concordance numbers — non-empty only.
      def concordance_idnos(doc)
        { "ciic" => "CIIC", "cisp" => "CISP", "smr" => "SMR" }.filter_map do |key, type|
          value = presence(doc.at_xpath("//idno[@type='#{type}']")&.text)
          [key, value] if value
        end.to_h
      end

      # origDate is usually empty upstream (104/504 carry attrs); attrs +
      # text verbatim when present — the timeline promotion is a censused
      # follow-up, not this packet's claim.
      def extract_date(doc)
        node = doc.at_xpath("//origin/origDate") or return {}
        result = {}
        %w[notBefore notAfter when period evidence].each do |attribute|
          value = presence(node[attribute])
          result[attribute] = value if value
        end
        text = presence(node.text)
        result["text"] = text if text
        result
      end

      def translation_prose(doc)
        texts = doc.xpath("//div[@type='translation']//p").filter_map { |p| presence(p.text) }
        texts.empty? ? nil : texts.join(" · ")
      end

      # The commentary's word-level eDIL links, normalized into the stable
      # dil.ie citation URL space (class note).
      def dil_references(doc)
        doc.xpath("//ref[@target]")
           .filter_map { |ref| ref["target"].to_s[%r{dil\.ie/(\d+)}, 1] }
           .uniq.sort_by(&:to_i)
           .map { |id| "https://dil.ie/#{id}" }
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- passages -------------------------------------------------------------

      def append_passages(document, editions, path:, urn:, language:, glyphs:, layer:, base:)
        extraction = Extraction.new(path: path, glyphs: glyphs, layer: layer, document_language: language)
        editions.each { |edition| extraction.edition(edition) }
        lines = extraction.lines
        lines = [extraction.whole_layer_line].compact if lines.empty?
        lines.each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable text in the #{layer.inspect} edition layer of #{base}" if document.empty?

        document
      end

      # Recursive-descent extraction over one layer's edition divs:
      # textpart path, glyph resolution, the open line, the word stack.
      class Extraction
        def initialize(path:, glyphs:, layer:, document_language:)
          @path = path
          @glyphs = glyphs
          @layer = layer
          @document_language = document_language
          @raw_lines = []
          @current = nil
          @textparts = []
          @lb_ordinal = 0
          @words = []
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
          @seen_suffixes = {}
          @block = 1
          # The whole-layer accumulator behind the :text fallback (EDH
          # P23-3c): every kept emission lands here, line or no line.
          @whole = { buffer: +"", gaps: [], supplied: 0, unclear: 0, cancelled: false }
        end

        def edition(node)
          node.children.each { |child| walk(child) }
          close_line
          @textparts.clear
          @block = 1
        end

        def lines
          previous_scope = nil
          @raw_lines.filter_map do |line|
            text = CelticLeiden.fold(line[:buffer])
            next if CelticLeiden.gap_only?(text)

            # A textpart is its own line-numbering universe: the implicit
            # restart block resets at every textpart boundary (DdbdpParser
            # P5-1).
            @block = 1 if line[:textpath] != previous_scope
            previous_scope = line[:textpath]
            Line.new(urn_suffix: mint_suffix(line), text: text, annotations: annotations(line))
          end
        end

        # The fallback Line (class note): the layer's full extraction under
        # the stable :text suffix; nil when the layer carried nothing.
        def whole_layer_line
          text = CelticLeiden.fold(@whole[:buffer])
          return nil if CelticLeiden.gap_only?(text)

          Line.new(urn_suffix: OghamEpidocParser::FALLBACK_SUFFIX, text: text,
                   annotations: annotations(@whole.merge(words: [], languages: [])))
        end

        private

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?

          name = node.name
          return if OghamEpidocParser::DROPPED_ELEMENTS.include?(name)
          return if name == "ab" && node["type"] # the derived summary rendering (class note)

          record_language(node)
          dispatch(node, name)
        end

        def dispatch(node, name)
          case name
          when "div" then textpart(node)
          when "choice" then choice(node)
          when "lb" then line_break(node)
          when "gap" then gap(node)
          when "space" then emit(" ")
          when "g" then glyph(node)
          when "w", "name" then word(node)
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

        # -- structure -----------------------------------------------------------

        def textpart(node)
          return recurse(node) unless node["type"] == "textpart"

          n = node["n"].to_s
          raise ParseError, "#{@path}: div[@type=\"textpart\"] is missing its @n" if n.empty?

          close_line
          @textparts.push(n)
          @block = 1
          recurse(node)
          close_line
          @textparts.pop
          @block = 1
        end

        def line_break(node)
          @lb_ordinal += 1
          n = node["n"].to_s
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.empty?

          close_line
          @current = {
            n: n, textpath: @textparts.dup, buffer: +"", words: [], gaps: [], languages: [],
            supplied: 0, unclear: 0, cancelled: @del_depth.positive?
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # -- markers, glyphs, counted spans ----------------------------------------

        def gap(node)
          annotation = CelticLeiden.gap_annotation(node)
          @whole[:gaps] << annotation
          @current[:gaps] << annotation if @current
          emit(CelticLeiden::GAP_MARKER)
        end

        # Glyph resolution (class note): @type-named mapping wins, else the
        # layer default ("ogham" / "diplomatic"), else the glyph's ogham
        # mapping; an unknown ref is damage.
        def glyph(node)
          ref = node["ref"].to_s.delete_prefix("#")
          if ref.empty?
            text = node.text
            emit(text) unless text.empty?
            return
          end
          mappings = @glyphs[ref] or
            raise ParseError, "#{@path}: <g ref=\"##{ref}\"> has no charDecl glyph — canonical drift"
          emit(glyph_replacement(node, ref, mappings))
        end

        def glyph_replacement(node, ref, mappings)
          preferred = node["type"]
          candidate = (preferred && mappings[preferred]) ||
                      mappings[@layer == "ogham" ? "ogham" : "diplomatic"] ||
                      mappings["ogham"]
          candidate = presence_of(candidate)
          candidate or raise ParseError, "#{@path}: glyph #{ref.inspect} has no usable mapping for " \
                                         "the #{@layer.inspect} layer"
        end

        def presence_of(value)
          value = value.to_s.strip
          value.empty? ? nil : value
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
          emit(open)
          recurse(node)
          emit(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end

        # -- tokens + inline languages ----------------------------------------------

        def word(node)
          record = { attrs: word_attrs(node), form: +"", line: @current }
          @words.push(record)
          recurse(node)
          @words.pop
          attach_word(record)
        end

        def word_attrs(node)
          attrs = {}
          %w[lemma type].each do |attribute|
            value = presence_of(node[attribute])
            attrs[attribute] = value if value
          end
          nym = presence_of(node["nymRef"]&.delete_prefix("#"))
          attrs["nymRef"] = nym if nym
          attrs
        end

        def attach_word(record)
          line = record[:line] || @current
          form = CelticLeiden.fold(record[:form])
          return if line.nil? || form.empty?

          line[:words] << { "form" => form }.merge(record[:attrs])
        end

        def record_language(node)
          return unless @current

          mapped = CelticLeiden.normalize_language(node["lang"])
          return if mapped.nil? || mapped == @document_language

          @current[:languages] << mapped unless @current[:languages].include?(mapped)
        end

        # -- finalization ---------------------------------------------------------

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
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear], cancelled: line[:cancelled]
          )
          result["leiden"] = leiden unless leiden.empty?
          result["words"] = line[:words] unless line[:words].empty?
          result["languages"] = line[:languages] unless line[:languages].empty?
          result
        end
      end
      private_constant :Extraction
    end
  end
end
