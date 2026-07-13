# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for one EDH (Epigraphic Database Heidelberg) EpiDoc
    # file — DdbdpParser-adjacent (P17-2; docs/edh-survey.md §3/§5), the
    # documentary-epigraphy sibling of the papyrological family. A new family,
    # not DdbdpParser reuse: different header extraction (msDesc/origin/
    # textClass/particDesc), a per-source <del> policy divergence (below),
    # textpart-relative line restarts as the NORM rather than a quarantine
    # class, and a CSV side-join the adapter feeds in. Same call shape as the
    # siblings; the only Nokogiri entry point is Nokogiri::XML::Reader (the
    # family's structural streaming contract, enforced by the test suite).
    #
    # == The Leiden subset (survey §3 census, 12,747 files)
    #
    # EDH's markup is a SMALL subset of DDbDP's: expan/abbr/ex (abbreviations
    # read EXPANDED — "v(otum)" reads "votum"), supplied reason="lost" (read
    # through; grapheme count → annotations), gap (the single "[…]" marker,
    # length data → annotations), del rend="erasure" — and nothing else. No
    # choice/reg/orig, no unclear, no handShift (all censused at ZERO).
    # rdg/orig/note/figure still drop defensively (DDbDP keep/drop policy).
    #
    # == The <del> divergence: KEPT, wrapped ⟦…⟧ (per-source policy)
    #
    # EDH's <del rend="erasure"> is the damnatio-memoriae case — legible,
    # edited text that EDH's own atext prints inside [[…]] (HD000082, the
    # erased titles of Crassus). Blanket-dropping del (the DDbDP default)
    # would erase reading text the source itself publishes, so here EVERY del
    # renders in Leiden double brackets ⟦…⟧, not only the P6-2 zero-line
    # fallback — exactly the direction conventions §5's recorded future-work
    # note points, adopted per-source where no frozen urns exist yet. Every
    # line touched carries {"leiden" => {"cancelled" => true}}.
    #
    # == Passage = the LINE; textpart-relative numbering
    #
    # urn = <document-urn>[:<textpart-n>…][:b<k>]:<lb n>. Line numbers RESTART
    # per textpart (HD000082's Latin front and Greek back both count from 1),
    # so the textpart path is mandatory in the urn when textpart divs exist.
    # The collision-triggered implicit block (:b2…, the DdbdpParser P5-1
    # machinery) rides along defensively for restarts WITHOUT textparts.
    # A line whose extraction is ONLY gap markers (lb n="0", the lost-line-
    # before-text encoding — HD080825) is not citable text and is skipped.
    #
    # == Language: NEVER from the header (the survey's verified trap)
    #
    # EDH's <langUsage> is boilerplate (en/de/lat on every record, Greek
    # editions included), so the caller supplies the document language from
    # the CSV nl_text column. Bilinguals (nl_text GL) get per-PASSAGE
    # language by script: a line containing Greek codepoints is tagged grc
    # (the freising per-layer-language precedent), so text_normalized folds
    # each side under its own rules.
    #
    # == Header layers → Document#metadata (survey §4)
    #
    # The parser captures the EAGLE-vocabulary terms the EpiDoc carries —
    # inscription type (textClass keywords term), province (origPlace
    # placeName type="province"), material, objectType — and merges them with
    # the CSV-side raw codes (+csv+) and the pers-CSV person rows (+persons+)
    # the adapter joins in:
    #
    #   {"facets"  => {"genre" => {"value" => "epitaph", "raw" => "titsep"},
    #                  "province"/"material"/"object_type" => …},
    #    "persons" => [{"nomen" => "Nonia", …}, …],   # adapter-built, verbatim
    #    "tm_nr"/"verse"/"find_year"/"repository"/"findspot"/"literature"/
    #    "people_uris"/"godot_uris" => …}              # only non-empty keys
    #
    # Facet value = the record's own XML term (English/EAGLE where upstream
    # has one; German for material — the EpiDoc carries no English material
    # term, only a LOD URI), falling back to the CSV raw when the XML element
    # is absent; raw = the CSV code verbatim, `?`-certainty suffixes included.
    #
    # == Identity
    #
    # <idno type="localID">HD000001</idno> mints urn:nabu:edh:hd000001 (HD
    # numbers are the stable id every aggregator keys on; the <idno
    # type="URI"> points at a STAGING host in the 2021 dumps and is never
    # trusted — survey §1). The caller-supplied urn must equal the minting
    # (mismatch → ParseError, the conformance identity).
    class EdhEpidocParser
      # The single lacuna marker every <gap> contributes (DdbdpParser::
      # GAP_MARKER's policy, restated here — the families are siblings, not
      # a hierarchy).
      GAP_MARKER = "[…]"

      # Leiden double brackets — ancient erasure, legible text (see the <del>
      # divergence above).
      CANCELLATION_OPEN = "⟦"
      CANCELLATION_CLOSE = "⟧"

      URN_PREFIX = "urn:nabu:edh:"

      # One extracted line (same shape as the DdbdpParser sibling's).
      Line = Data.define(:urn_suffix, :text, :leiden)
      private_constant :Line

      # Same signature family as the sibling parsers; +csv+ is the record's
      # edh_data_text.csv row (string keys, the survey's canonical language/
      # raw-code source), +persons+ the adapter-built pers-CSV rows.
      def parse(source, urn:, language:, title: nil, csv: {}, persons: [], canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        extraction = extract(source, path: path, urn: urn)
        build_document(
          extraction, urn: urn, language: language,
                      title: title || extraction.header[:title], csv: csv, persons: persons, path: path
        )
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def extract(source, path:, urn:)
        with_io(source) do |io|
          Extraction.new(reader: Nokogiri::XML::Reader(io, path), path: path, urn: urn).call
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def with_io(source, &)
        source.is_a?(String) ? File.open(source, "r", &) : yield(source)
      end

      def build_document(extraction, urn:, language:, title:, csv:, persons:, path:)
        document = Document.new(
          urn: urn, language: language, title: title, canonical_path: path,
          metadata: metadata(extraction.header, csv, persons)
        )
        extraction.lines.each_with_index do |line, sequence|
          document << Passage.new(
            urn: "#{urn}:#{line.urn_suffix}",
            language: passage_language(line.text, language),
            text: line.text,
            annotations: line.leiden.empty? ? {} : { "leiden" => line.leiden },
            sequence: sequence
          )
        end
        raise ParseError, "#{path}: no citable lines (<lb>) found in div[@type=\"edition\"]" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # Script decides the passage language (the header lies — class note):
      # any Greek codepoint tags the line grc; everything else inherits the
      # document language.
      def passage_language(text, language)
        text.match?(/\p{Greek}/) ? "grc" : language
      end

      # -- document metadata (facets + prosopography + crosswalks) -----------

      def metadata(header, csv, persons)
        result = {}
        facets = build_facets(header, csv)
        result["facets"] = facets unless facets.empty?
        result["persons"] = persons unless persons.nil? || persons.empty?
        annotation_fields(csv).each { |key, value| result[key] = value }
        result
      end

      # value = the XML's own term (fallback: the CSV raw), raw = the CSV
      # code/term verbatim (`?` certainty survives). A facet with neither is
      # absent — honest sparsity, never a blank row.
      FACET_SOURCES = {
        "genre" => [:genre, "i_gattung"],
        "province" => [:province, "provinz"],
        "material" => [:material, "material"],
        "object_type" => [:object_type, "denkmaltyp"]
      }.freeze
      private_constant :FACET_SOURCES

      def build_facets(header, csv)
        FACET_SOURCES.each_with_object({}) do |(facet, (header_key, csv_key)), facets|
          value = presence(header[header_key])
          raw = presence(csv[csv_key])
          next if value.nil? && raw.nil?

          entry = { "value" => value || raw }
          entry["raw"] = raw if raw
          facets[facet] = entry
        end
      end

      # The cheap CSV riders the survey keeps as annotations (§4.6): only
      # non-empty keys, verbatim strings; literature splits on the upstream
      # " # " citation separator.
      def annotation_fields(csv)
        result = {}
        { "tm_nr" => "tm_nr", "verse" => "metrik", "find_year" => "fundjahr",
          "repository" => "aufbewahrung", "findspot" => "fundstelle",
          "people_uris" => "people_uris", "godot_uris" => "godot_uris" }.each do |key, csv_key|
          value = presence(csv[csv_key])
          result[key] = value if value
        end
        literature = presence(csv["literatur"])
        result["literature"] = literature.split("#").filter_map { |cite| presence(cite) } if literature
        result
      end

      def presence(value)
        return nil if value.nil?

        folded = Normalize.nfc(value.to_s.strip.gsub(/\s+/, " "))
        folded.empty? ? nil : folded
      end

      # The single-pass Reader state machine: header phase captures localID +
      # the EAGLE-term layers; body phase reacts only inside
      # div[@type="edition"] (textpart path, keep/drop state, line buffer).
      class Extraction
        READER = Nokogiri::XML::Reader
        TEXT_NODE_TYPES = [
          READER::TYPE_TEXT, READER::TYPE_CDATA,
          READER::TYPE_WHITESPACE, READER::TYPE_SIGNIFICANT_WHITESPACE
        ].freeze
        # Never reading text (the DDbDP policy minus <del> — the per-source
        # divergence keeps del). <gap> is handled separately: marker first,
        # then its children drop too.
        DROPPED_ELEMENTS = %w[rdg orig note figure].freeze
        # Header elements whose text is captured once (first occurrence wins;
        # placeName is special-cased on @type below).
        HEADER_CAPTURES = { "title" => :title, "objectType" => :object_type, "material" => :material,
                            "term" => :genre }.freeze
        private_constant :READER, :TEXT_NODE_TYPES, :DROPPED_ELEMENTS, :HEADER_CAPTURES

        # What the header phase collected: :title, :genre, :province,
        # :material, :object_type (whitespace-collapsed, NFC).
        attr_reader :header, :lines

        def initialize(reader:, path:, urn:)
          @reader = reader
          @path = path
          @urn = urn
          @header = {}
          @capture = nil # the header key currently accumulating, or :local_id
          @local_id = nil
          @edition_seen = false
          @edition_depth = nil
          @textparts = [] # [{n:, depth:}, …]
          @drop_depth = nil
          @supplied_depths = []
          @del_depths = []
          @current = nil
          @lb_ordinal = 0
          @lines = []
          @block = 1 # implicit restart-block ordinal (DdbdpParser P5-1)
          @seen_suffixes = {}
        end

        def call
          @reader.each { |node| process(node) }
          raise ParseError, "#{@path}: no div[@type=\"edition\"] found" unless @edition_seen

          self
        end

        private

        def process(node)
          case node.node_type
          when READER::TYPE_ELEMENT then start_element(node)
          when READER::TYPE_END_ELEMENT then end_element(node)
          when *TEXT_NODE_TYPES then text_node(node)
          end
        end

        def start_element(node)
          return if dropping?
          return edition_element(node) if in_edition?

          header_element(node)
        end

        # -- header phase -------------------------------------------------------

        def header_element(node)
          name = local_name(node)
          case name
          when "idno"
            @capture = :local_id if node.attribute("type") == "localID" && !node.empty_element?
          when "placeName"
            @capture = :province if node.attribute("type") == "province" && !node.empty_element?
          when "div"
            enter_edition(node) if node.attribute("type") == "edition"
          else
            key = HEADER_CAPTURES[name]
            @capture = key if key && @header[key].nil? && !node.empty_element?
          end
        end

        def capture_header(value)
          if @capture == :local_id
            @local_id = (@local_id || "") + value.strip
          else
            @header[@capture] = [@header[@capture], value].compact.join
          end
        end

        # -- body phase ---------------------------------------------------------

        # Element starts inside the edition div, keep-state only. Everything
        # not handled here (ab, expan, abbr, ex, num, supplied's children …)
        # keeps its text: the text nodes stream past and accumulate.
        def edition_element(node)
          name = local_name(node)
          return open_cancellation(node) if name == "del"

          if DROPPED_ELEMENTS.include?(name)
            @drop_depth = node.depth unless node.empty_element?
            return
          end

          case name
          when "lb" then start_line(node)
          when "gap" then add_gap(node)
          when "div" then push_textpart(node)
          when "supplied" then @supplied_depths << node.depth unless node.empty_element?
          end
        end

        def end_element(node)
          if dropping?
            @drop_depth = nil if node.depth == @drop_depth
            return
          end
          unless in_edition?
            @capture = nil
            return
          end

          case local_name(node)
          when "ab" then finish_line
          when "div" then end_div(node)
          when "del" then close_cancellation(node)
          when "supplied" then @supplied_depths.pop if @supplied_depths.last == node.depth
          end
        end

        def text_node(node)
          if @capture
            capture_header(node.value.to_s)
            return
          end
          return unless in_edition? && @current && !dropping?

          value = node.value.to_s
          @current[:buffer] << value
          count_supplied(value)
        end

        def count_supplied(value)
          return if @supplied_depths.empty?

          @current[:supplied] += value.gsub(/[[:space:]]/, "").grapheme_clusters.size
        end

        def dropping?
          !@drop_depth.nil?
        end

        def in_edition?
          !@edition_depth.nil?
        end

        # -- identity + edition entry --------------------------------------------

        def enter_edition(node)
          validate_identity!
          @edition_seen = true
          @edition_depth = node.depth unless node.empty_element?
        end

        def validate_identity!
          if @local_id.nil? || @local_id.empty?
            raise ParseError, "#{@path}: no <idno type=\"localID\"> found in teiHeader"
          end

          minted = "#{EdhEpidocParser::URN_PREFIX}#{@local_id.downcase}"
          return if minted == @urn

          raise ParseError, "#{@path}: urn mismatch: caller says #{@urn.inspect}, " \
                            "<idno type=\"localID\"> #{@local_id.inspect} mints #{minted.inspect}"
        end

        # -- lines ----------------------------------------------------------------

        def start_line(node)
          @lb_ordinal += 1
          n = node.attribute("n")
          raise ParseError, "#{@path}: <lb> ##{@lb_ordinal} (document order) is missing its @n" if n.nil? || n.empty?

          finish_line
          @current = {
            n: n, textpath: @textparts.map { |part| part[:n] },
            buffer: +"", gaps: [], supplied: 0,
            cancelled: !@del_depths.empty? # line opened inside a kept erasure
          }
        end

        def finish_line
          current = @current
          @current = nil
          return unless current

          text = Normalize.nfc(current[:buffer].gsub(/[[:space:]]+/, " ").strip)
          # Empty or gap-markers-only (lb n="0", a fully lost line): nothing
          # citable was read — not a passage (survey §3, line grain).
          return if text.gsub(EdhEpidocParser::GAP_MARKER, "").gsub(/[[:space:]]/, "").empty?

          @lines << Line.new(urn_suffix: mint_suffix(current), text: text, leiden: leiden(current))
        end

        # Restart-aware suffix minting (the DdbdpParser P5-1 mechanism):
        # textpart path first, then a collision-triggered implicit block for
        # restarts without textparts. Textparts reset the block counter — a
        # textpart is its own line-numbering universe.
        def mint_suffix(current)
          loop do
            block = @block > 1 ? ["b#{@block}"] : []
            suffix = (current[:textpath] + block + [current[:n]]).join(":")
            if @seen_suffixes.key?(suffix)
              @block += 1
            else
              @seen_suffixes[suffix] = true
              return suffix
            end
          end
        end

        def leiden(current)
          result = {}
          result["gaps"] = current[:gaps] unless current[:gaps].empty?
          result["supplied_chars"] = current[:supplied] if current[:supplied].positive?
          result["cancelled"] = true if current[:cancelled]
          result
        end

        # -- the kept <del> (per-source ⟦…⟧ policy — class note) -------------------

        def open_cancellation(node)
          return if node.empty_element?

          @del_depths << node.depth
          mark_cancelled(EdhEpidocParser::CANCELLATION_OPEN)
        end

        def close_cancellation(node)
          return unless @del_depths.last == node.depth

          @del_depths.pop
          mark_cancelled(EdhEpidocParser::CANCELLATION_CLOSE)
        end

        def mark_cancelled(marker)
          return unless @current

          @current[:buffer] << marker
          @current[:cancelled] = true
        end

        # -- leiden milestones ------------------------------------------------------

        def add_gap(node)
          if @current
            @current[:buffer] << EdhEpidocParser::GAP_MARKER
            @current[:gaps] << gap_annotation(node)
          end
          @drop_depth = node.depth unless node.empty_element?
        end

        def gap_annotation(node)
          gap = {}
          %w[reason quantity unit].each do |attribute|
            value = node.attribute(attribute)
            next if value.nil?

            gap[attribute] = value.match?(/\A\d+\z/) ? Integer(value, 10) : value
          end
          gap
        end

        # -- divs (edition exit, textparts) ------------------------------------------

        def push_textpart(node)
          return unless node.attribute("type") == "textpart"

          n = node.attribute("n")
          raise ParseError, "#{@path}: div[@type=\"textpart\"] is missing its @n" if n.nil? || n.empty?
          return if node.empty_element?

          @textparts << { n: n, depth: node.depth }
          @block = 1
        end

        def end_div(node)
          if node.depth == @edition_depth
            finish_line # defensive; </ab> normally closed the last line
            @edition_depth = nil
          elsif @textparts.last && @textparts.last[:depth] == node.depth
            finish_line # lines never span textparts
            @textparts.pop
            @block = 1
          end
        end

        def local_name(node)
          node.name.split(":").last
        end
      end
      private_constant :Extraction
    end
  end
end
