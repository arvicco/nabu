# frozen_string_literal: true

require "json"
require "nokogiri"

require_relative "celtic_leiden"
require_relative "source_read"
require_relative "../normalize"
require_relative "../pleiades"
require_relative "../timeline"

module Nabu
  module Adapters
    # Parser family "aio-record" (P154): one Attic Inscriptions Online
    # record — the PAIR AioFetch lands per inscription: records/aio-<n>.json
    # (the REST API record) + records/aio-<n>.html (the inscription page).
    # DOM-based deliberately: records are a few KB (the >5 MB Reader rule
    # never engages).
    #
    # == Two layers, two documents (the RIIG/damaskini sibling pattern)
    #
    # - the TRANSLATION (API "translation_epidoc", every record): AIO's own
    #   English translation, the site's raison d'être → urn:nabu:aio:<n>-en,
    #   language eng, metadata kind "translation" + translation_of the base
    #   urn (the papyri precedent: a translation whose edition is not held
    #   keeps the edition's urn and pairs the day it lands).
    # - the GREEK (API "greek_epidoc", only where AIO publishes its own
    #   text — the AIO/AIUK editions; the IG/SEG-based records translate a
    #   print edition and carry none) → urn:nabu:aio:<n>, the edition's
    #   language from its own div xml:lang (grc; la → lat).
    # The record's axis-shaped fields (date, place, the genre/object facets)
    # ride the PRIMARY document — the Greek when present, else the
    # translation — so a Greek-bearing record never counts twice. Upstream
    # carries no lect claim beyond the div's language tag.
    #
    # == Passage = the LINE, ordinal (the IIP rule)
    #
    #   urn = <document-urn>:p<textpart-ordinal>:<line-ordinal>
    #
    # Upstream labels only every fifth line (<lb n="5"/> in the Greek,
    # <milestone unit="line" n="5"/> in the translation), so lines number by
    # document-order ordinal and the upstream label rides the "line"
    # annotation; textparts number by ordinal too (n="1", n="b" ride the
    # "textpart" annotation). Lines open lazily; a gap-only line is dropped,
    # its ordinal honestly consumed. <lb break="no"/> delimits like any lb
    # (the print-margin rule).
    #
    # == Text policy (CelticLeiden)
    #
    # supplied/unclear read through and count; gap → "[…]"; del → ⟦…⟧;
    # surplus → {…}; space → one space; choice → corr > reg > lem > expan >
    # first; expan reads abbr+ex; DROP bibl/figure/desc/rdg/certainty/am.
    # Notes: a footnote marker (<note type="footnote">1</note>) never
    # enters the text — its number rides the line's "notes" annotation and
    # the footnote TEXT (the page's .ins_notes) rides document metadata
    # "notes". An inline rubric (<note type="inline">) is the translator's
    # display aside ("(341/0)", "relief"): in the TRANSLATION it reads in
    # parentheses exactly as the page renders it; in the GREEK (an English
    # rubric inside a Greek line) it rides the "rubrics" annotation only.
    # <term target> keeps the English and pairs it with the transliterated
    # Greek ("terms" annotation); persName/placeName read through, their
    # refs ride "persons"/"places" (Pleiades ids lifted).
    #
    # == The page layer → metadata
    #
    #   "citation" (#ins_source, "SEG 46.153"), "references" (the page's
    #   References block, display text), "reference_links" (the API's
    #   per-reference external links — PHI, IG Online), "translators",
    #   "date" => {"raw", "not_before", "not_after"} (the page's Date field
    #   through AioDate — clean shapes only; anything else rides raw),
    #   "place" => {"ancient", "pleiades"} (Original location when it names
    #   a place, else the first Findspot; "Unknown" places nothing),
    #   "findspots" / "original_location" verbatim, "facets" => {"genre"
    #   (Inscription type heads), "object_type" (Monument type)}, "notes",
    #   "added"/"updated", "url", "aio_key".
    #
    # == Identity
    #
    # The filename's number IS the identity (aio-<n>.json ↔ upstream's
    # aio_key "AIO_<n>", the page's own "ID: AIO_<n>"). The JSON's aio_key
    # and the page's ID must both agree with the filename; disagreement is
    # upstream drift → ParseError (quarantine, never repair).
    class AioRecordParser
      URN_PREFIX = "urn:nabu:aio:"
      TRANSLATION_SUFFIX = "-en"
      FILENAME = /\Aaio-(\d+)\.json\z/

      DROPPED_ELEMENTS = %w[bibl figure desc rdg certainty am].freeze

      # The page-layer fields read from the .ins_type_info blocks.
      INFO_LABELS = ["Monument type", "Inscription type", "Original location"].freeze

      # Place values that place nothing (upstream's own unknowns).
      NO_PLACE = /\A(?:unknown|uncertain|unclear|not known)\b/i

      Line = Data.define(:urn_suffix, :text, :annotations)
      private_constant :Line

      def self.number_of(path)
        FILENAME.match(File.basename(path))&.[](1)
      end

      def self.base_urn(number) = "#{URN_PREFIX}#{number}"

      def self.translation_urn(number) = "#{URN_PREFIX}#{number}#{TRANSLATION_SUFFIX}"

      # The layers a record's JSON carries text for — the discover-time
      # minting decision (["greek", "translation"], either may be absent).
      # An unreadable record still mints its -en ref, so #parse quarantines
      # it honestly instead of discovery skipping it as untranslated.
      def self.layers(path)
        data = JSON.parse(SourceRead.utf8_file(path, label: "aio record"))
        return ["translation"] unless data.is_a?(Hash)

        layers = []
        layers << "greek" unless data["greek_epidoc"].to_s.strip.empty?
        layers << "translation" unless data["translation_epidoc"].to_s.strip.empty?
        layers
      rescue JSON::ParserError, ParseError
        ["translation"]
      end

      # "Decree 1 (People?), Decree 2 (Cleruchy Hephaistia)" → ["Decree"];
      # "Statue base, Metrical (elegaic couplets)" → ["Statue base",
      # "Metrical"]; "1: Dedication (deme …)" → ["Dedication"]. Commas
      # inside parentheses never split; the qualifier and any ordinal drop.
      # Uncertainty marks stay (kind_map's global strip folds "Decree?").
      def self.type_heads(raw)
        depth = 0
        parts = [+""]
        raw.to_s.each_char do |char|
          depth += 1 if char == "("
          depth -= 1 if char == ")" && depth.positive?
          if char == "," && depth.zero?
            parts << +""
          else
            parts.last << char
          end
        end
        parts.filter_map do |part|
          head = part.split("(").first.to_s.sub(/\A\s*\d+\s*:\s*/, "").sub(/\s+\d+\s*\z/, "").strip
          head.empty? ? nil : head
        end.uniq
      end

      # The API's host-relative urls ("www.atticinscriptions.com/…") as https.
      def self.https(url)
        url = url.to_s.strip
        return nil if url.empty?

        url.match?(%r{\Ahttps?://}) ? url : "https://#{url}"
      end

      def parse(path, urn:)
        number = self.class.number_of(path) or raise ParseError, "#{path}: not an aio-<n>.json record"
        layer = urn.end_with?(TRANSLATION_SUFFIX) ? "translation" : "greek"
        expected = layer == "translation" ? self.class.translation_urn(number) : self.class.base_urn(number)
        unless urn == expected
          raise ParseError,
                "#{path}: urn mismatch: caller says #{urn.inspect}, the filename mints #{expected.inspect}"
        end

        data = read_json(path)
        validate_key!(data, number, path)
        page = read_page(path, number)
        build(data, page, number: number, layer: layer, path: path)
      end

      private

      # -- reading + identity ----------------------------------------------------

      def read_json(path)
        data = JSON.parse(SourceRead.utf8_file(path, label: "aio record"))
        raise ParseError, "#{path}: the API record is not a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed JSON: #{e.message}"
      end

      def validate_key!(data, number, path)
        key = data["aio_key"].to_s.strip
        return if key == "AIO_#{number}"

        raise ParseError, "#{path}: aio_key drift: the record says #{key.inspect}, the filename AIO_#{number}"
      end

      def read_page(path, number)
        html = path.sub(/\.json\z/, ".html")
        raise ParseError, "#{path}: the inscription page #{File.basename(html)} is missing" unless File.file?(html)

        page = Nokogiri::HTML(SourceRead.utf8_file(html, label: "aio page"))
        id = page.at_css("#CC")&.text.to_s[/ID:\s*AIO_(\d+)/, 1]
        if id && id != number
          raise ParseError, "#{html}: page ID drift: the page says AIO_#{id}, the filename AIO_#{number}"
        end

        page
      end

      def decode(data, key, path)
        # Base64 (RFC 2045) through String#unpack1 — no gem needed.
        bytes = SourceRead.utf8(data[key].to_s.unpack1("m"), label: "#{path}: #{key} (Base64-decoded)")

        doc = Nokogiri::XML(bytes, &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: #{key} is malformed EpiDoc: #{e.message}"
      end

      # -- documents --------------------------------------------------------------

      def build(data, page, number:, layer:, path:)
        has_greek = !data["greek_epidoc"].to_s.strip.empty?
        if layer == "greek"
          raise ParseError, "#{path}: no greek_epidoc — the record carries no Greek text" unless has_greek

          epidoc = decode(data, "greek_epidoc", path)
          div = epidoc.at_xpath("//div[@type='edition']")
          language = CelticLeiden.normalize_language(div&.[]("lang").to_s.strip) || "grc"
          urn = self.class.base_urn(number)
          metadata = record_metadata(data, page, number).merge(axis_metadata(page))
        else
          epidoc = decode(data, "translation_epidoc", path)
          div = epidoc.at_xpath("//div[@type='translation']")
          language = "eng"
          urn = self.class.translation_urn(number)
          metadata = record_metadata(data, page, number)
          metadata.merge!(axis_metadata(page)) unless has_greek
          metadata["kind"] = "translation"
          metadata["translation_of"] = self.class.base_urn(number)
          notes = footnotes(page)
          metadata["notes"] = notes unless notes.empty?
        end
        unless div
          raise ParseError,
                "#{path}: the #{layer} EpiDoc has no #{layer == 'greek' ? 'edition' : 'translation'} div"
        end

        document = Nabu::Document.new(urn: urn, language: language, title: title(data, page),
                                      canonical_path: path, metadata: metadata)
        extraction = Extraction.new(language: language, translation: layer == "translation")
        extraction.edition(div)
        extraction.lines.each_with_index do |line, sequence|
          document << Nabu::Passage.new(urn: "#{urn}:#{line.urn_suffix}", language: language,
                                        text: line.text, annotations: line.annotations, sequence: sequence)
        end
        document
      end

      def title(data, page)
        text = fold(Nokogiri::HTML.fragment(data["translation_title"].to_s).text)
        return text unless text.empty?

        citation = citation(page)
        citation.empty? ? nil : citation
      end

      def citation(page) = fold(page.at_css("#ins_source")&.text.to_s)

      # The record-grain metadata every document of the record carries.
      def record_metadata(data, page, number)
        meta = { "aio_key" => "AIO_#{number}", "url" => AioRecordParser.https(data["url"]),
                 "license" => "CC BY-SA 3.0" }
        citation = citation(page)
        meta["citation"] = citation unless citation.empty?
        references = page.css(".ins_alt_source").map { |node| fold(node.text) }.reject(&:empty?)
        meta["references"] = references unless references.empty?
        links = reference_links(data)
        meta["reference_links"] = links unless links.empty?
        translators = Array(data["translators"]).map { |name| fold(name.to_s) }.reject(&:empty?)
        meta["translators"] = translators unless translators.empty?
        stamps(page).each { |key, value| meta[key] = value }
        meta
      end

      # The API's references, verbatim per entry ("source reference" →
      # its external links; the translated-text flag).
      def reference_links(data)
        Array(data["references"]).filter_map do |ref|
          next unless ref.is_a?(Hash)

          entry = { "source" => ref["source"].to_s, "reference" => ref["reference"].to_s }
          links = Array(ref["external_links"]).map(&:to_s).reject(&:empty?)
          entry["external_links"] = links unless links.empty?
          entry["translated_text"] = true if ref["is_translation_source"]
          entry
        end
      end

      def stamps(page)
        text = fold(page.at_css("#CC")&.text.to_s)
        result = {}
        added = text[/Added:\s*(\d{1,2} \w+ \d{4})/, 1]
        updated = text[/Updated:\s*(\d{1,2} \w+ \d{4})/, 1]
        result["added"] = added if added
        result["updated"] = updated if updated
        result
      end

      # Date, place, facets — the primary document's axis fields.
      def axis_metadata(page)
        meta = {}
        date = date_of(page)
        meta["date"] = date if date
        info = info_fields(page)
        facets = facets(info)
        meta["facets"] = facets unless facets.empty?
        original = info["Original location"]
        meta["original_location"] = original[:text] if original
        findspots = findspots(page)
        meta["findspots"] = findspots.map { |spot| spot.except(:name).transform_keys(&:to_s) } unless findspots.empty?
        place = place_claim(original, findspots)
        meta["place"] = place if place
        meta
      end

      def date_of(page)
        raw = fold(page.at_css("#ins_date")&.text.to_s.sub(/\A\s*Date:/, ""))
        return nil if raw.empty?

        date = { "raw" => raw }
        bounds = AioDate.bounds(raw)
        date["not_before"], date["not_after"] = bounds if bounds
        date
      end

      # label => {text:, pleiades:} for the single-valued info blocks.
      def info_fields(page)
        page.css("div.ins_type_info").each_with_object({}) do |node, fields|
          text = fold(node.text)
          label = INFO_LABELS.find { |candidate| text.start_with?("#{candidate}:") } or next
          value = fold(text.delete_prefix("#{label}:"))
          next if value.empty?

          fields[label] = { text: value, pleiades: pleiades_in(node.inner_html) }
        end
      end

      # Every "Findspot:" segment of the page (one per fragment):
      # {fragment:, text:, pleiades:, name:}.
      def findspots(page)
        node = page.css("div.ins_type_info").find { |div| div.text.include?("Findspot:") } or return []
        pieces = node.inner_html.split("Findspot:")
        pieces.each_cons(2).filter_map do |before, segment|
          text = fold(Nokogiri::HTML.fragment(segment.split(/Fragment\s+\S+\s*-/).first.to_s).text)
          next if text.empty?

          fragment = fold(Nokogiri::HTML.fragment(before).text)[/Fragment\s+(\S+)\s*-\z/, 1]
          spot = { text: text, name: place_name(text) }
          spot[:fragment] = fragment if fragment
          pleiades = pleiades_in(segment)
          spot[:pleiades] = pleiades if pleiades
          spot
        end
      end

      def pleiades_in(html)
        id = html.to_s[%r{pleiades\.stoa\.org/places/(\d+)}, 1]
        id && Nabu::Pleiades.ref_id(id)
      end

      # The name part of a place value: up to the first " (" or "," —
      # "Eleusis (By [gateway of the sanctuary])" → "Eleusis"; "Loutsa (=
      # Halai Araphenides), ca. 500 m. …" → "Loutsa". Unknowns → nil.
      def place_name(text)
        name = text.split(/\s*\(|,/).first.to_s.strip
        name.empty? || name.match?(NO_PLACE) ? nil : name
      end

      # The first field (Original location, then each Findspot) that names a
      # place AND links it to Pleiades; failing that, the first that names
      # one. The Pleiades id always rides from the same field as the name
      # ("[Diogeneion?]" with a ToposText link yields to "Athens" →
      # pleiades 579885).
      def place_claim(original, findspots)
        candidates = []
        candidates << { name: place_name(original[:text]), pleiades: original[:pleiades] } if original
        candidates.concat(findspots.map { |spot| { name: spot[:name], pleiades: spot[:pleiades] } })
        named = candidates.select { |candidate| candidate[:name] }
        chosen = named.find { |candidate| candidate[:pleiades] } || named.first or return nil
        place = { "ancient" => chosen[:name] }
        place["pleiades"] = chosen[:pleiades] if chosen[:pleiades]
        place
      end

      def facets(info)
        result = {}
        if (type = info["Inscription type"])
          heads = AioRecordParser.type_heads(type[:text])
          result["genre"] = { "values" => heads, "raw" => type[:text] } unless heads.empty?
        end
        if (monument = info["Monument type"])
          result["object_type"] = { "values" => [monument[:text]], "raw" => monument[:text] }
        end
        result
      end

      def footnotes(page)
        page.css(".ins_notes .note").each_with_object({}) do |node, notes|
          number = node["id"].to_s[/\Anote-(\w+)\z/, 1] or next
          text = fold(node.text).sub(/\A\[#{Regexp.escape(number)}\]\s*/, "")
          notes[number] = text unless text.empty?
        end
      end

      def fold(text) = CelticLeiden.fold(text.to_s)

      # Recursive-descent extraction over one EpiDoc layer (class note).
      class Extraction
        def initialize(language:, translation:)
          @language = language
          @translation = translation
          @raw_lines = []
          @current = nil
          @pending_label = nil
          @path = []
          @textpart_info = []
          @line_counters = [0]
          @textpart_counters = [0]
          @supplied_depth = 0
          @unclear_depth = 0
          @del_depth = 0
        end

        def edition(node)
          node.children.each { |child| walk(child) }
          close_line
        end

        def lines
          @raw_lines.filter_map do |line|
            text = SourceRead.nfc(line[:buffer].gsub(/[[:space:]]+/, " ").strip, language: @language)
            next if CelticLeiden.gap_only?(text)

            Line.new(urn_suffix: line[:suffix], text: text, annotations: annotations(line))
          end
        end

        private

        def walk(node)
          return emit(node.text) if node.text?
          return unless node.element?
          return if AioRecordParser::DROPPED_ELEMENTS.include?(node.name)

          case node.name
          when "div" then division(node)
          when "choice" then choice(node)
          when "lb" then line_break(node)
          when "milestone" then milestone(node)
          when "gap" then gap(node)
          when "space" then emit_marker(" ")
          when "supplied" then counted(node, :@supplied_depth)
          when "unclear" then counted(node, :@unclear_depth)
          when "del" then wrapped(node, CelticLeiden::CANCELLATION_OPEN, CelticLeiden::CANCELLATION_CLOSE)
          when "surplus" then wrapped(node, CelticLeiden::SURPLUS_OPEN, CelticLeiden::SURPLUS_CLOSE)
          when "note" then note(node)
          when "term" then term(node)
          when "persName" then named(node, "persons")
          when "placeName" then named(node, "places")
          else recurse(node)
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        # -- lazy ordinal lines ---------------------------------------------------

        def emit(text)
          return if text.empty?
          return if @current.nil? && text.strip.empty?

          open_line
          @current[:buffer] << text
          count_certainty(text)
        end

        def emit_marker(marker)
          open_line
          @current[:buffer] << marker
        end

        def open_line
          return if @current

          ordinal = (@line_counters[-1] += 1)
          @current = {
            suffix: (@path + [ordinal.to_s]).join(":"), buffer: +"", gaps: [], supplied: 0,
            unclear: 0, cancelled: @del_depth.positive?, textpart: @textpart_info.last,
            label: @pending_label, notes: [], terms: [], persons: [], places: [], rubrics: []
          }
          @pending_label = nil
          @raw_lines << @current
        end

        def close_line
          @current = nil
        end

        # <lb n="5"/>: the label belongs to the line the lb opens.
        def line_break(node)
          close_line
          label = node["n"].to_s.strip
          @pending_label = label unless label.empty?
        end

        # <milestone unit="line" n="5"/> sits at the head of the line it
        # labels (open or about to open).
        def milestone(node)
          label = node["n"].to_s.strip
          return if label.empty? || node["unit"].to_s != "line"

          if @current && @current[:label].nil? && @current[:buffer].strip.empty?
            @current[:label] = label
          elsif @current
            @current[:label] ||= label
          else
            @pending_label = label
          end
        end

        def count_certainty(text)
          return if @supplied_depth.zero? && @unclear_depth.zero?

          count = CelticLeiden.grapheme_count(text)
          @current[:supplied] += count if @supplied_depth.positive?
          @current[:unclear] += count if @unclear_depth.positive?
        end

        # -- textparts ------------------------------------------------------------

        def division(node)
          return recurse(node) unless node["type"] == "textpart"

          close_line
          @path.push("p#{@textpart_counters[-1] += 1}")
          @textpart_info.push(%w[subtype n].each_with_object({}) do |attribute, label|
            value = node[attribute].to_s.strip
            label[attribute] = value unless value.empty?
          end)
          @line_counters.push(0)
          @textpart_counters.push(0)
          recurse(node)
          close_line
          @path.pop
          @textpart_info.pop
          @line_counters.pop
          @textpart_counters.pop
        end

        # -- markers, notes, names -----------------------------------------------

        def gap(node)
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
          @current[:cancelled] = true if cancelling
          recurse(node)
          emit_marker(close)
          @del_depth -= 1 if cancelling
        end

        def choice(node)
          branch = CelticLeiden.choice_branch(node)
          walk(branch) if branch
        end

        def note(node)
          text = CelticLeiden.fold(node.text)
          return if text.empty?

          if node["type"] == "footnote"
            target = @current || @raw_lines.last
            target[:notes] << text if target
          elsif @translation
            emit_marker(text.start_with?("(") && text.end_with?(")") ? text : "(#{text})")
          else
            target = @current || @raw_lines.last
            target[:rubrics] << text if target
          end
        end

        def term(node)
          recurse(node)
          english = CelticLeiden.fold(node.text)
          translit = node["target"].to_s.strip
          return if @current.nil? || english.empty? || translit.empty?

          @current[:terms] << { "text" => english, "translit" => translit }
        end

        def named(node, bucket)
          recurse(node)
          ref = node["ref"].to_s.strip
          return if @current.nil? || ref.empty?

          entry = { "name" => CelticLeiden.fold(node.text), "ref" => ref }
          pleiades = bucket == "places" && ref[%r{pleiades\.stoa\.org/places/(\d+)}, 1]
          entry["pleiades"] = pleiades if pleiades
          @current[bucket.to_sym] << entry
        end

        # -- finalization ---------------------------------------------------------

        def annotations(line)
          result = {}
          leiden = CelticLeiden.leiden_annotations(gaps: line[:gaps], supplied: line[:supplied],
                                                   unclear: line[:unclear], cancelled: line[:cancelled])
          result["leiden"] = leiden unless leiden.empty?
          result["textpart"] = line[:textpart] unless line[:textpart].to_h.empty?
          result["line"] = line[:label] if line[:label]
          %i[notes terms persons places rubrics].each do |key|
            result[key.to_s] = line[key] unless line[key].empty?
          end
          result
        end
      end
      private_constant :Extraction
    end

    # The AIO page's "Date:" field → signed [not_before, not_after], or nil
    # when the prose is not one of the clean shapes (the raw always rides).
    # Shapes (the 80-page sample census, 2026-11-02): archon years "352/1
    # BC" (the Athenian year straddles two Julian years → -352..-351),
    # single years, ranges ("ca. 350-325 BC", "153/2–144/3 BC", "286–262?
    # BC"), decades ("220s-230s AD"), centuries in ordinal or roman form
    # with the house halves (early = first half, late/end = second, mid =
    # the middle half: "Mid-iv BC", "Early 4th cent. BC", "1st-3rd century
    # AD", "ii-iii AD"), and "or" alternatives as their envelope ("30/29 BC
    # or 17/6 BC"). The era (BC/AD) may sit once at the end and governs
    # every part; a part with no era anywhere fails. Open-ended prose
    # ("Before …", "Shortly after …", "… or later") and mixed-era ranges
    # parse to nil — declared residue. Uncertainty marks ("?", "(?)") and
    # "ca." strip (the envelope is upstream's own claim either way).
    module AioDate
      ERA_BC = /\b(?:BCE?|B\.C\.)(?![a-z])/i
      ERA_AD = /\b(?:AD|A\.D\.|CE)(?![a-z])/i
      OPEN_ENDED = /\b(?:before|after|later|earlier|unknown|uncertain|undated)\b/i
      QUALIFIER = "(?:(early|beginning|mid|middle|late|end|first half|second half|1st half|2nd half)[\\s-]+)?"
      CENTURY_WORD = "(?:\\s*(?:centur(?:y|ies)|cent\\.?|c\\.))?"
      NUMBER = "(?:s\\.\\s*)?(\\d{1,2}(?:st|nd|rd|th)|[ivx]+)"
      CENTURIES = /\A#{QUALIFIER}#{NUMBER}#{CENTURY_WORD}(?:\s*[-–]\s*#{QUALIFIER}#{NUMBER}#{CENTURY_WORD})?\z/i
      YEAR = %r{(\d{1,4})(?:/(\d{1,2}))?(s)?}
      YEARS = /\A#{YEAR}(?:\s*[-–]\s*#{YEAR})?\z/
      ROMAN = { "i" => 1, "v" => 5, "x" => 10 }.freeze

      module_function

      def bounds(raw)
        text = raw.to_s.strip
        return nil if text.empty? || text.match?(OPEN_ENDED)

        parts = text.split(/\s+or\s+/i)
        signs = parts.map { |part| era_of(part) }
        return nil if signs.include?(:mixed)

        # A part without its own era inherits the next part's (the era is
        # written once, at the end: "ca. 354/3 or 344/3 BC").
        (signs.size - 2).downto(0) { |index| signs[index] ||= signs[index + 1] }
        return nil if signs.any?(&:nil?)

        spans = parts.zip(signs).map { |part, sign| part_bounds(clean(part), sign) }
        return nil if spans.any?(&:nil?)

        [spans.map(&:first).min, spans.map(&:last).max]
      rescue Timeline::InvalidYear
        nil
      end

      def era_of(part)
        bc = part.match?(ERA_BC)
        ad = part.match?(ERA_AD)
        return :mixed if bc && ad
        return -1 if bc

        ad ? 1 : nil
      end

      def clean(part)
        part.gsub(ERA_BC, " ").gsub(ERA_AD, " ").gsub("(?)", " ").delete("?")
            .sub(/\A\s*(?:ca\.|c\.|circa)\s*/i, "").gsub(/\s+/, " ").strip
      end

      def part_bounds(part, sign)
        if (match = YEARS.match(part))
          first = year_span(match[1], match[2], match[3])
          last = match[4] ? year_span(range_end(match[1], match[4], sign), match[5], match[6]) : first
          values = (first + last).map { |magnitude| signed(magnitude, sign) }
          return values.minmax
        end
        match = CENTURIES.match(part) or return nil
        first = century_band(match[2], match[1], sign)
        second = match[4] ? century_band(match[4], match[3], sign) : first
        return nil if first.nil? || second.nil?

        [[first[0], second[0]].min, [first[1], second[1]].max]
      end

      # A range end shorter than its head borrows the head's leading digits
      # ("480-70 BC" → 470) — but only when the borrowed reading runs in the
      # era's direction: "101-88 BC" stays 88 (188 would run backwards).
      def range_end(head, tail, sign)
        borrowed = expand(head, tail)
        return tail if borrowed == tail

        borrowed_year = Integer(borrowed, 10)
        head_year = Integer(head, 10)
        forward = sign.negative? ? borrowed_year <= head_year : borrowed_year >= head_year
        forward ? borrowed : tail
      end

      # The magnitudes one year token covers: "352/1" → [352, 351] (the
      # archon year straddles two Julian years); "220s" → [220, 229].
      def year_span(year, slash, decade)
        magnitude = Integer(year, 10)
        return [magnitude, magnitude + 9] if decade
        return [magnitude] unless slash

        [magnitude, Integer(expand(year, slash), 10)]
      end

      def expand(head, tail)
        return tail if tail.length >= head.length

        head[0, head.length - tail.length] + tail
      end

      def signed(magnitude, sign)
        raise Timeline::InvalidYear, "year 0" if magnitude.zero?

        magnitude * sign
      end

      def century_band(token, qualifier, sign)
        number = token.match?(/\A\d/) ? Integer(token[/\d+/], 10) : roman(token)
        return nil if number.nil? || number.zero? || number > 20

        lo, hi = Timeline.century_bounds(number * sign)
        case qualifier.to_s.downcase.gsub(/\s+/, " ")
        when "early", "beginning", "first half", "1st half" then [lo, lo + 49]
        when "late", "end", "second half", "2nd half" then [lo + 50, hi]
        when "mid", "middle" then [lo + 25, hi - 25]
        else [lo, hi]
        end
      end

      def roman(token)
        values = token.downcase.chars.map { |char| ROMAN[char] }
        return nil if values.any?(&:nil?)

        values.each_with_index.sum do |value, index|
          following = values[index + 1]
          following && following > value ? -value : value
        end
      end
    end
  end
end
