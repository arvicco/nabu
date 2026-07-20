# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"

module Nabu
  module Adapters
    # Parser family "riig-epidoc" (P25-1): one RIIG (Recueil informatisé des
    # inscriptions gauloises, riig.huma-num.fr) EpiDoc TEI record — Gaulish
    # epigraphy, the documentary sibling between EdhEpidocParser (whose
    # header/date/place extraction it mirrors) and DdbdpParser (whose Leiden
    # keep/drop doctrine it applies, via the shared CelticLeiden policy).
    # DOM-based like FreisingTeiParser, deliberately NOT a Reader machine:
    # the corpus is 428 files of ≤70 KB (the >5 MB streaming rule never
    # engages), and RIIG's <choice> branches need name-based selection that
    # a one-pass stream cannot do without buffering.
    #
    # == Content shape (fixture-censused, 4 records + the corpus map)
    #
    #   div[@type="edition"] > div[@type="textpart"] (no @n; ignored — see
    #   below) > ab > seg (one per EDITORIAL READING: @xml:id "PLT-a",
    #   @resp "#PLT", @cert, @xml:lang) > lb/w/gap.
    #
    # RIIG records commonly carry SEVERAL parallel readings of the same
    # stone (AHP-01-01: Lambert's καρε[…]μ beside καρβ[…]μ), with no marked
    # preferred one — the apparatus/translation divs point at readings by
    # id. Every seg therefore mints passages: dropping the non-first
    # readings would erase edited text the source itself publishes.
    #
    # == Passage = the LINE within a READING
    #
    #   urn = <document-urn>:<seg id>:<lb n>
    #
    # seg @xml:id is unique per file (XML-enforced) and stable upstream, so
    # the reading id alone disambiguates — textpart divs carry no @n in this
    # corpus and add nothing (GAR-10-03's textparts are told apart by their
    # segs, MLE-1-a vs MLE-2-a). A seg without @xml:id gets "seg<ordinal>"
    # (document order); lines outside any seg mint without the reading
    # segment. Collisions (defensive: an lb @n repeated within one reading)
    # open DdbdpParser's implicit :b<k> block. Minting is FROZEN once used.
    #
    # == Text policy (CelticLeiden + the RIIG dialect)
    #
    # - choice → reg (the regularized reading; orig — the letter-forms
    #   branch, with its per-glyph <g> facsimile refs — is apparatus).
    # - WORD-INTERNAL whitespace is formatting noise, stripped: RIIG files
    #   are pretty-printed with NO xml:space="preserve", so the indentation
    #   inside <w><choice><reg>… would otherwise tear words apart
    #   ("nanton{t}icnos", not "nanto n{t} icn os"). Upstream marks REAL
    #   word division inside <w> with explicit <space/> elements, which
    #   contribute one space ("v(otum) s(olvit)…" → "votum solvit…").
    # - expan/abbr/ex read expanded; supplied/unclear read through and
    #   count; gap → "[…]"; del → ⟦…⟧; surplus → {…}; rs/hi/num/g keep
    #   their text.
    # - DROP: note, bibl, figure, desc, rdg, certainty (apparatus/metadata).
    # - <lb break="no"/> delimits like any lb (the DDbDP print-margin rule):
    #   EPAÐATEXTO|RICI ends line 3 and continues on line 4.
    #
    # A line whose extraction is empty or gap-markers-only is skipped; a
    # record minting ZERO lines is a ParseError (honest quarantine — the
    # corpus map lists 5 "Indéterminé" records that may hit this; triage at
    # first sync, the EDH precedent).
    #
    # == Tokens: the msd layer (deep extraction)
    #
    # Every <w> carries morphosyntax (@msd "sg m 2", @pos NOM/DAT, @type
    # idionym/patronym/theonym/votive_formula, @subtype) — the packet's
    # msd-to-annotations promise. Each line's annotations carry
    # {"words" => [{"form", "msd", "pos", "type", "subtype"}, …]} (non-empty
    # keys only; a word split across lines belongs to the line it STARTED
    # on, its form spanning the break).
    #
    # == Languages (script honesty)
    #
    # Document language = msContents/textLang/@mainLang, mapped to ISO 639-3
    # (CelticLeiden): "xtg-Grek" (Gallo-Greek) / "xtg-Latn" (Gallo-Latin)
    # pass through with their honest script subtags — RIIG's own langUsage
    # distinguishes the scripts, so no facet workaround is needed. A record
    # without a mainLang reads "und" (the EDH honest-undetermined
    # precedent). Passage language = the seg's @xml:lang mapped (GAR-10-03's
    # Latin readings carry xml:lang="la" → lat beside the Gaulish), falling
    # back to the document language.
    #
    # == Header layers → Document#metadata (the EDH shape)
    #
    #   {"facets" => {"genre"/"object_type"/"material" =>
    #                   {"value" => text, "raw" => vocabulary URI}},
    #    "rig" => ["G593", …],          # RIG concordance, msIdentifier idno
    #                                   #   type="localID" (hyphen variants
    #                                   #   deduped on the compact spelling)
    #    "tm" => "978943",              # Trismegistos text id
    #    "date" => {"not_before"/"not_after" (signed years)/"raw"/"cert"/
    #               "evidence"},
    #    "place" => {"name"/"settlement"/"district"/"region"/"country"/
    #                "ref" (Trismegistos/RIIG places URL)/"geo" (verbatim,
    #                decimal-comma WGS84 as upstream writes it)},
    #    "related" => ["rig:G593", …]}  # the links-journal reference-edge
    #                                   #   targets (adapter capability)
    #
    # == Identity
    #
    # <idno type="filename">AHP-01-01</idno> mints
    # urn:nabu:riig:ahp-01-01 (downcased); the caller-supplied urn must
    # equal the minting (mismatch → ParseError, the conformance identity).
    class RiigEpidocParser
      URN_PREFIX = "urn:nabu:riig:"

      DROPPED_ELEMENTS = %w[note bibl figure desc rdg certainty].freeze

      # One extracted line of one reading.
      Line = Data.define(:urn_suffix, :text, :language, :annotations)
      private_constant :Line

      # Parse one record file into a Nabu::Document (original text only —
      # the -fr sibling goes through #translations).
      def parse(path, urn:)
        doc = read_xml(path)
        validate_identity!(doc, path: path, urn: urn)
        language = document_language(doc)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title_of(doc), canonical_path: path,
          metadata: metadata(doc)
        )
        extract_lines(doc, path: path, document_language: language).each_with_index do |line, sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{line.urn_suffix}", language: line.language,
            text: line.text, annotations: line.annotations, sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable text found in div[@type=\"edition\"]" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # The French translation prose as [citation, text] pairs — one per
      # non-empty <p> of every div[@type="translation"], cited by the
      # reading the div's @corresp points at ("MLE-a"; second p of the same
      # div → "MLE-a.2"; no corresp → "t<ordinal>"). The adapter builds the
      # -fr sibling document from these.
      def translations(path)
        doc = read_xml(path)
        pairs = []
        seen = Hash.new(0)
        doc.xpath("//div[@type='translation']").each_with_index do |div, index|
          base = div["corresp"].to_s.split(/\s+/).first.to_s.delete_prefix("#")
          base = "t#{index + 1}" if base.empty?
          div.xpath(".//p").each do |paragraph|
            text = CelticLeiden.fold(paragraph.text)
            next if text.empty?

            seen[base] += 1
            pairs << [seen[base] == 1 ? base : "#{base}.#{seen[base]}", text]
          end
        end
        pairs
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # -- identity + header --------------------------------------------------

      def validate_identity!(doc, path:, urn:)
        filename = doc.at_xpath("//idno[@type='filename']")&.text.to_s.strip
        raise ParseError, "#{path}: no <idno type=\"filename\"> found in teiHeader" if filename.empty?

        minted = "#{URN_PREFIX}#{filename.downcase}"
        return if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "<idno type=\"filename\"> #{filename.inspect} mints #{minted.inspect}"
      end

      def document_language(doc)
        CelticLeiden.normalize_language(doc.at_xpath("//msContents/textLang/@mainLang")&.value) || "und"
      end

      def title_of(doc)
        presence(doc.at_xpath("//titleStmt/title[not(@type)]")&.text) ||
          presence(doc.at_xpath("//titleStmt/title")&.text)
      end

      # -- document metadata ---------------------------------------------------

      def metadata(doc)
        result = {}
        facets = build_facets(doc)
        result["facets"] = facets unless facets.empty?
        rig = rig_concordance(doc)
        unless rig.empty?
          result["rig"] = rig
          result["related"] = rig.map { |siglum| "rig:#{siglum.delete('-')}" }.uniq
        end
        tm = presence(doc.at_xpath("//msIdentifier//idno[@type='TM']")&.text)
        result["tm"] = tm if tm
        date = extract_date(doc)
        result["date"] = date unless date.empty?
        place = extract_place(doc)
        result["place"] = place unless place.empty?
        result
      end

      FACET_SOURCES = {
        "genre" => "//msContents/summary",
        "object_type" => "//physDesc//objectType",
        "material" => "//physDesc//material"
      }.freeze
      private_constant :FACET_SOURCES

      # value = the record's own term (French, as upstream has it), raw =
      # the LOD vocabulary URI (EAGLE / AusoHNum / frantiq) when declared.
      def build_facets(doc)
        FACET_SOURCES.each_with_object({}) do |(facet, xpath), facets|
          node = doc.at_xpath(xpath)
          value = presence(node&.text)
          next if value.nil?

          entry = { "value" => value }
          raw = presence(node["ref"] || node["corresp"])
          entry["raw"] = raw if raw
          facets[facet] = entry
        end
      end

      # RIG sigla from msIdentifier localID idnos (altIdentifier's hyphen
      # variant of the same number dedupes on the compact spelling: G593 and
      # G-593 are one concordance).
      def rig_concordance(doc)
        doc.xpath("//msIdentifier//idno[@type='localID']")
           .filter_map { |idno| presence(idno.text) }
           .uniq { |siglum| siglum.delete("-").downcase }
      end

      # origDate → signed years (Timeline semantics: RIIG writes signed
      # historical years, "-0100"). The raw text ("-Ier siècle"), cert and
      # evidence ride verbatim. A malformed year 0 keeps the raw fields and
      # drops the bounds (the timeline builder counts it invalid).
      def extract_date(doc)
        node = doc.at_xpath("//origin/origDate") or return {}
        result = {}
        begin
          not_before = Timeline.parse_year(node["notBefore"] || node["when"])
          not_after = Timeline.parse_year(node["notAfter"] || node["when"])
          result["not_before"] = not_before if not_before
          result["not_after"] = not_after if not_after
        rescue Timeline::InvalidYear
          nil # bounds dropped; raw/cert/evidence still recorded below
        end
        { "raw" => presence(node.text), "cert" => presence(node["cert"]),
          "evidence" => presence(node["evidence"]) }.each { |key, value| result[key] = value if value }
        result
      end

      # origPlace: the untyped placeName is the findspot ("Chastelard de
      # Lardiers"); settlement carries the modern commune + the gazetteer
      # refs (Trismegistos via @corresp, RIIG places via @ref); <geo> stays
      # VERBATIM (decimal-comma WGS84, canonical means canonical).
      def extract_place(doc)
        origin = doc.at_xpath("//origin/origPlace") or return {}
        settlement = origin.at_xpath("./settlement")
        findspot = origin.at_xpath("./placeName[not(@type)]")
        result = {}
        { "name" => findspot&.text, "settlement" => settlement&.at_xpath("./placeName")&.text,
          "district" => origin.at_xpath("./district")&.text, "region" => origin.at_xpath("./region")&.text,
          "country" => origin.at_xpath("./country")&.text,
          "geo" => origin.at_xpath(".//geo")&.text }.each do |key, value|
          folded = presence(value)
          result[key] = folded if folded
        end
        ref = settlement && presence(settlement["corresp"] || settlement["ref"])
        ref ||= findspot && presence(findspot["ref"])
        result["ref"] = ref if ref
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # -- the edition walk ------------------------------------------------------

      def extract_lines(doc, path:, document_language:)
        editions = doc.xpath("//div[@type='edition']")
        raise ParseError, "#{path}: no div[@type=\"edition\"] found" if editions.empty?

        extraction = Extraction.new(path: path, document_language: document_language)
        editions.each { |edition| extraction.edition(edition) }
        extraction.lines
      end

      # Recursive-descent extraction state for one record's editions: the
      # seg (reading) context, the open line, the word stack (see the class
      # note's token layer).
      class Extraction
        def initialize(path:, document_language:)
          @path = path
          @document_language = document_language
          @raw_lines = [] # accumulation hashes, finalized in #lines
          @current = nil
          @seg = nil # {key:, resp:, cert:, language:}
          @seg_ordinal = 0
          @lb_ordinal = 0
          @words = [] # open <w> stack: {attrs:, form:, line:}
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

            # A reading is its own line-numbering universe: the implicit
            # restart block resets at every seg boundary (the DdbdpParser
            # textpart rule, transposed to readings).
            scope = line[:seg]&.fetch(:key)
            @block = 1 if scope != previous_scope
            previous_scope = scope
            Line.new(urn_suffix: mint_suffix(line), text: text,
                     language: line[:language], annotations: annotations(line, text))
          end
        end

        private

        def walk(node)
          return text_node(node) if node.text?
          return unless node.element?

          name = node.name
          return if RiigEpidocParser::DROPPED_ELEMENTS.include?(name)

          case name
          when "seg" then seg(node)
          when "choice" then choice(node)
          when "lb" then line_break(node)
          when "gap" then gap(node)
          when "space" then emit(" ", literal: true)
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

        # Word-internal whitespace is pretty-print noise (class note);
        # +literal+ marks the explicit <space/> word divider.
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

        # -- readings ------------------------------------------------------------

        def seg(node)
          close_line
          @seg_ordinal += 1
          key = presence(node["id"]) || "seg#{@seg_ordinal}"
          @seg = { key: key, resp: presence(node["resp"]&.delete_prefix("#")), cert: presence(node["cert"]),
                   language: CelticLeiden.normalize_language(node["lang"]) }
          recurse(node)
          close_line
          @seg = nil
        end

        # -- lines ----------------------------------------------------------------

        def line_break(node)
          @lb_ordinal += 1
          n = node["n"].to_s
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.empty?

          close_line
          @current = {
            n: n, seg: @seg, buffer: +"", words: [], gaps: [],
            supplied: 0, unclear: 0, cancelled: @del_depth.positive?,
            language: @seg&.dig(:language) || @document_language
          }
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # -- markers + counted spans ------------------------------------------------

        def gap(node)
          annotation = CelticLeiden.gap_annotation(node)
          @current[:gaps] << annotation if @current
          emit(CelticLeiden::GAP_MARKER, literal: true)
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

        # -- tokens -------------------------------------------------------------

        def word(node)
          record = { attrs: word_attrs(node), form: +"", line: @current }
          @words.push(record)
          recurse(node)
          @words.pop
          attach_word(record)
        end

        def word_attrs(node)
          %w[msd pos type subtype].each_with_object({}) do |attribute, attrs|
            value = presence(node[attribute])
            attrs[attribute] = value if value
          end
        end

        def attach_word(record)
          line = record[:line] || @current
          form = CelticLeiden.fold(record[:form])
          return if line.nil? || form.empty?

          line[:words] << { "form" => form }.merge(record[:attrs])
        end

        # -- finalization --------------------------------------------------------

        # <seg-key?>:<b-block?>:<lb n>, collision-safe (DdbdpParser P5-1).
        def mint_suffix(line)
          seg_key = line[:seg]&.fetch(:key)
          loop do
            block = @block > 1 ? ["b#{@block}"] : []
            suffix = ([seg_key].compact + block + [line[:n]]).join(":")
            if @seen_suffixes.key?(suffix)
              @block += 1
            else
              @seen_suffixes[suffix] = true
              return suffix
            end
          end
        end

        def annotations(line, _text)
          result = {}
          leiden = CelticLeiden.leiden_annotations(
            gaps: line[:gaps], supplied: line[:supplied], unclear: line[:unclear], cancelled: line[:cancelled]
          )
          result["leiden"] = leiden unless leiden.empty?
          result["words"] = line[:words] unless line[:words].empty?
          reading = reading_annotation(line[:seg])
          result["reading"] = reading if reading
          result
        end

        def reading_annotation(seg)
          return nil if seg.nil?

          { "id" => seg[:key], "resp" => seg[:resp], "cert" => seg[:cert] }.compact
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
