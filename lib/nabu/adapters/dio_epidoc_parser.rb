# frozen_string_literal: true

require "nokogiri"

require_relative "celtic_leiden"
require_relative "source_read"
require_relative "../normalize"
require_relative "../timeline"

module Nabu
  module Adapters
    # Parser family "dio-epidoc": one article of the Deutsche Inschriften
    # (DI) EpiDoc volume dumps published on Epigraf (Akademie der
    # Wissenschaften und der Literatur Mainz), one file per printed
    # catalogue number — "Encoded by transforming Epigraf data, following
    # EpiDoc guidelines 9.6 where possible. Version 1.0-beta of the Epigraf
    # transformation workflow." DOM-based deliberately: 978 files, the
    # largest 40 KB. A sibling of the CelticLeiden epigraphy families
    # (composed, never copied).
    #
    # == Content shape (full-dump census of DI 7 / 77 / 102, 2026-11-27)
    #
    #   div[@type="edition"] > div[@type="textpart" @n="A1"]… > head +
    #     ab[@type="block"] > lb[@rend @type]/g[@rend]/hi[@rend]/
    #     supplied[@reason="omitted"]/add/del>gap/unclear/app>note/note/
    #     q/ref/space
    #
    # Every article divides into textparts named by the printed edition's
    # inscription siglum + part (A1, B1, B2 …; 2,699 in 978 articles, n
    # unique per article). The header keys its per-inscription rows by the
    # siglum letter alone: langUsage/language[@n], keywords/term[@n],
    # scriptDesc/p[@n].
    #
    # == The Epigraf markup dialect (verified against the same articles'
    # own rendered transcriptions in the TTL dump, schema:text)
    #
    # The transformation does NOT use the EpiDoc elements the way the
    # Leiden table in docs/conventions.md §5 reads them:
    #
    # - <supplied reason="omitted"> is the EXPANDED ABBREVIATION — the
    #   print's round brackets: FV<supplied>N</supplied>DAT… renders
    #   "FV(N)DAT(A)". Read through (the house expan reading), never counted.
    # - <add> is the RESTORED lost text — the print's square brackets:
    #   c<add>uius anima requie</add>scat renders "c[uius anima requie]scat".
    #   Read through and counted as supplied_chars (the house's "letters
    #   restored").
    # - <del> only ever wraps a <gap> (1,764 of 1,764: the print's
    #   "[…]" lost-text bracket) — it is NOT a cancellation, so it never
    #   renders ⟦…⟧; the gap inside is the house GAP_MARKER "[…]". A del
    #   carrying text would be a new upstream shape → ParseError.
    # - gap quantity="0" (1,357 of 1,764) is Epigraf's UNKNOWN extent →
    #   the annotation says extent "unknown", never quantity 0.
    # - <unclear> reads through and counts unclear_chars.
    # - <g> (interpuncts, crosses, rosettes — carved word dividers) and
    #   <hi> (superscript, ligature, versal, chronogram letters) read
    #   through: the text they carry IS carved.
    # - <app>/<note> are the print's letter and number footnotes →
    #   the passage's "notes" annotation [{"type","text"}], never text.
    # - <head> ("Inschrift A1") is a label, dropped.
    # - Anything else inside the edition → ParseError (outside the census).
    #
    # == Passage = the TEXTPART (the printed inscription), urn …:A1
    #
    # <lb> carries no @n (upstream numbers no lines) and mixes physical
    # line ends with verse lines, field changes, fragment changes and the
    # interruptions by coats of arms or house marks (lb/@rend verbatim,
    # @type="verse"), and 258 articles carry no lb at all — so the line is
    # no stable grain, while the textpart is upstream's own citable unit.
    # The passage text joins the lines exactly as Epigraf's renderer joins
    # them (its schema:text prints "fe/ria", "m / • cccc"): a mid-word
    # break has no whitespace on either side, so the lines concatenate with
    # NO separator and the word survives whole ("feria"); a whitespace-only
    # text node directly after an lb is the pretty-printer's indentation
    # and drops, one before an lb is a real space. The printed layout rides
    # the "lines" annotation [{"text","break","verse"}] (≥ 2 lines only).
    # A textpart whose text is empty or only gap markers mints nothing; an
    # article with no citable textpart at all is a text-less record —
    # .citable? lets discovery skip it by rule.
    #
    # == Languages (per inscription, from langUsage)
    #
    # Upstream writes German labels with an empty @ident (18 distinct, all
    # censused); the label's FIRST named language decides (the mixed
    # labels — "hochdeutsch-niederdeutsche Mischsprache", "niederdeutsch
    # mit hochdeutschen Elementen", "lateinisch-griechisch" — fold on their
    # base, the full label rides "language_raw"): lateinisch → lat,
    # hochdeutsch and deutsch → deu (the de anchor; date-band inference
    # stages Early New High German by date), niederdeutsch → gml (Middle
    # Low German — the period of the whole corpus), griechisch → grc,
    # hebräisch → heb. A label outside the base table → ParseError. A
    # textpart whose siglum has no language row (numbers, initials, names,
    # house-mark captions: 775 of 2,699 — upstream assigns them no
    # language) is "und", never guessed; when a siglum has two rows (9
    # articles, bilingual inscriptions) the first decides and both ride
    # raw. The document language is the first language row's, else "und".
    #
    # == Header → Document#metadata
    #
    #   "dio_id" (the Epigraf article id, nsn~3212), "iri", "urn_nbn",
    #   "citation" ("DI 7, Nr. 1"), "volume" {"di","title"}, "author",
    #   "revised",
    #   "date" {"not_before","not_after","raw","circa","uncertain"} (.date_of),
    #   "place" {"ancient" (origPlace verbatim — Epigraf's location
    #     string), "locations" (its "; "-separated parts), "settlement"
    #     (the first location's last comma part)},
    #   "facets" {"genre" (keywords), "object_type" (objectType split on
    #     ", "), "material", "condition", "script_style", "technique"}
    #     each {"values","raw"},
    #   "description" (the support prose, footnotes dropped), "dimensions",
    #   "heraldry", "commentary", "bibliography".
    #
    # Per passage: "inscription" (the siglum), "language_raw", "genre",
    # "script", "letter_height", "technique" (that siglum's header rows),
    # "translation" {"deu"} (the translation textpart of the same n),
    # "lines", "notes", "leiden".
    #
    # Deliberate coarseness, declared: the place is Epigraf's LOCATION —
    # the church/building and town where the object is or was, a present
    # repository (museum) included; no gazetteer ref or coordinate exists
    # in the dump. Footnote references to the literature (properties/
    # literature/…) are not resolved beyond their text.
    #
    # == Identity
    #
    # article-<sigil>-<nnn>-<db>~<id>.xml: the volume sigil (BSS / hgw /
    # HST), the printed catalogue number and the Epigraf article id. The urn
    # is the PRINT citation — urn:nabu:dio-epidoc:<volume>-<nnn> (DI 7,
    # Nr. 1 → di7-001), immutable once the book is printed; the caller's
    # urn must equal the minting, the sigil must be the volume's, and the
    # in-file issue number and article IRI must name the same article —
    # drift → ParseError (quarantine, never repair).
    class DioEpidocParser
      URN_PREFIX = "urn:nabu:dio-epidoc:"
      FILENAME = /\Aarticle-([A-Za-z]+)-(\d{3})-([a-z]+~\d+)\.xml\z/
      IRI_BASE = "https://epigraf.inschriften.net/iri/"

      # volume dir => [DI volume number, the files' sigil] (the dumps page,
      # read 2026-11-27).
      VOLUMES = { "di7" => [7, "BSS"], "di77" => [77, "hgw"], "di102" => [102, "HST"] }.freeze

      # The base of every censused language label → ISO 639-3 (class note).
      BASE_LANGUAGES = {
        "lateinisch" => "lat", "hochdeutsch" => "deu", "deutsch" => "deu",
        "niederdeutsch" => "gml", "griechisch" => "grc", "hebräisch" => "heb"
      }.freeze

      # scriptDesc "Label: value" rows → passage annotation keys.
      SCRIPT_LABELS = { "Schriftart" => "script", "Schrifthöhe" => "letter_height",
                        "Ausführung" => "technique" }.freeze

      # The element names the edition census found (class note).
      READ_THROUGH = %w[supplied g hi q ref].freeze

      def self.urn_for(path, volume:)
        match = FILENAME.match(File.basename(path))
        number = match ? match[2] : File.basename(path, ".xml")
        "#{URN_PREFIX}#{volume}-#{number}"
      end

      def self.language_code(label)
        base = label.to_s.strip.downcase[/\A\p{L}+/]
        BASE_LANGUAGES[base]
      end

      # Does the article carry any citable text? A shape error answers
      # true, so the parse reports it loud instead of discovery skipping it.
      def self.citable?(path)
        doc = new.send(:read_xml, path)
        doc.xpath("//text/body/div[@type='edition']/div[@type='textpart']").any? do |part|
          text = Extraction.new(path).run(part)[:text]
          !text.empty? && !CelticLeiden.gap_only?(text)
        end
      rescue ParseError
        true
      end

      # -- the origDate grammar ---------------------------------------------------

      YEAR = /\A(\d{3,4})\z/
      # A century side: [qualifier] century "." ["Jh."] — the qualifier is
      # A./M./E. (Anfang/Mitte/Ende) or n.H./n.V./n.D. (half/quarter/third).
      CENTURY_SIDE = /\A(?:(A|M|E|\d\.[HVD])\.)?(\d{1,2})\.(?:Jh\.)?\z/
      # "2.–3.V.15.Jh." — a range of fractions of ONE century.
      FRACTION_RANGE = /\A(\d)\.–(\d)\.([HVD])\.(\d{1,2})\.Jh\.\z/
      PARTS = { "H" => 2, "V" => 4, "D" => 3 }.freeze

      # {"not_before","not_after","raw"} (a side may be absent — an open
      # end), "circa"/"uncertain" flags when upstream writes "um"/"?";
      # {"raw"} alone when the prose does not parse.
      def self.date_of(raw)
        text = raw.to_s.strip
        result = { "raw" => text }
        uncertain = text.end_with?("?")
        text = text.delete_suffix("?").strip
        circa = text.start_with?("um ")
        text = text.delete_prefix("um ").strip
        bounds = date_bounds(text) or return result

        result["not_before"] = bounds[0] if bounds[0]
        result["not_after"] = bounds[1] if bounds[1]
        result["circa"] = true if circa
        result["uncertain"] = true if uncertain
        result.slice("not_before", "not_after", "raw", "circa", "uncertain")
      end

      def self.date_bounds(text)
        if (match = text.match(/\A(.+?) o\. (früher|später)\z/))
          year = side_bounds(match[1]) or return nil
          return match[2] == "früher" ? [nil, year[1]] : [year[0], nil]
        end
        if (match = text.match(/\A(vor|nach) (\d{3,4})\z/))
          year = Integer(match[2], 10)
          return match[1] == "vor" ? [nil, year] : [year, nil]
        end
        if (match = FRACTION_RANGE.match(text))
          century = Integer(match[4], 10)
          first = fraction(century, Integer(match[1], 10), match[3])
          last = fraction(century, Integer(match[2], 10), match[3])
          return first && last ? [first[0], last[1]] : nil
        end
        left, right = text.split("–", 2)
        low = side_bounds(left) or return nil
        return low if right.nil?

        high = side_bounds(right) or return nil
        [[low[0], high[0]].min, [low[1], high[1]].max]
      end

      def self.side_bounds(side)
        side = side.to_s.strip
        if (match = YEAR.match(side))
          year = Integer(match[1], 10)
          return [year, year]
        end
        match = CENTURY_SIDE.match(side) or return nil
        century = Integer(match[2], 10)
        return nil if century.zero?

        qualified(century, match[1])
      end

      # A century's [lo, hi] narrowed by its qualifier: the house halves
      # for Anfang/Ende (first/second half) and Mitte (the middle half),
      # exact halves, quarters and thirds for n.H./n.V./n.D.
      def self.qualified(century, qualifier)
        lo, hi = Timeline.century_bounds(century)
        case qualifier
        when nil then [lo, hi]
        when "A" then [lo, lo + 49]
        when "E" then [lo + 50, hi]
        when "M" then [lo + 25, hi - 25]
        else fraction(century, Integer(qualifier[0], 10), qualifier[-1])
        end
      end

      def self.fraction(century, ordinal, unit)
        parts = PARTS.fetch(unit)
        return nil unless ordinal.between?(1, parts)

        lo, hi = Timeline.century_bounds(century)
        size = 100 / parts
        start = lo + (size * (ordinal - 1))
        [start, ordinal == parts ? hi : start + size - 1]
      end
      private_class_method :date_bounds, :side_bounds, :qualified, :fraction

      # -- parse ------------------------------------------------------------------

      def parse(path, urn:, volume:)
        identity = validate_file!(path, urn: urn, volume: volume)
        doc = read_xml(path)
        validate_identity!(doc, path, identity)
        languages = language_rows(doc, path)
        document = Nabu::Document.new(
          urn: urn, language: languages.values.flatten.first&.fetch(:code) || "und",
          title: presence(doc.at_xpath("//titleStmt/title")&.text), canonical_path: path,
          metadata: metadata(doc, identity)
        )
        add_passages(document, doc, path, urn, languages)
        raise ParseError, "#{path}: the edition has no citable text" if document.empty?

        document
      end

      private

      def read_xml(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "dio-epidoc article"), &:strict)
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def validate_file!(path, urn:, volume:)
        match = FILENAME.match(File.basename(path)) or
          raise ParseError, "#{path}: not an article-<sigil>-<nnn>-<id>.xml file"

        number, sigil = VOLUMES.fetch(volume) { raise ParseError, "#{path}: unknown volume #{volume.inspect}" }
        unless match[1] == sigil
          raise ParseError, "#{path}: sigil #{match[1].inspect} is not volume #{volume}'s (#{sigil})"
        end

        minted = self.class.urn_for(path, volume: volume)
        unless minted == urn
          raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, the filename mints #{minted.inspect}"
        end

        { number: match[2], dio_id: match[3], di: number }
      end

      def validate_identity!(doc, path, identity)
        issue = doc.at_xpath("//sourceDesc/bibl/biblScope[@unit='issue']")&.text.to_s.strip
        iri = doc.at_xpath("//msIdentifier/idno[@type='iri']")&.text.to_s.strip
        drift = []
        drift << "issue #{issue.inspect}" unless issue == identity[:number]
        drift << "iri #{iri.inspect}" unless iri.end_with?("/#{identity[:dio_id]}")
        return if drift.empty?

        raise ParseError, "#{path}: in-file identity drift (#{drift.join(', ')}) — quarantined, never repaired"
      end

      # siglum letter => [{code:, raw:}] in upstream order.
      def language_rows(doc, path)
        doc.xpath("//profileDesc/langUsage/language").each_with_object({}) do |node, rows|
          raw = presence(node.text) or next
          code = self.class.language_code(raw) or
            raise ParseError, "#{path}: language label #{raw.inspect} is outside the censused set — classify it first"
          (rows[node["n"].to_s] ||= []) << { code: code, raw: raw }
        end
      end

      def add_passages(document, doc, path, urn, languages)
        terms = rows_by_letter(doc.xpath("//profileDesc//keywords/term")) { |node| genre_values(node.text) }
        script = script_rows(doc)
        translations = translations(doc)
        sequence = 0
        doc.xpath("//text/body/div[@type='edition']/div[@type='textpart']").each do |part|
          extracted = Extraction.new(path).run(part)
          text = extracted[:text]
          next if text.empty? || CelticLeiden.gap_only?(text)

          n = part["n"].to_s
          letter = n[/\A[A-Z]+/].to_s
          rows = languages[letter] || []
          annotations = passage_annotations(extracted, letter: letter, rows: rows, genre: terms[letter],
                                                       script: script[letter], translation: translations[n])
          document << Nabu::Passage.new(urn: "#{urn}:#{n}", language: rows.first&.fetch(:code) || "und",
                                        text: text, annotations: annotations, sequence: sequence)
          sequence += 1
        end
      end

      def passage_annotations(extracted, letter:, rows:, genre:, script:, translation:)
        result = { "inscription" => letter }
        result["language_raw"] = rows.map { |row| row[:raw] }.join("; ") unless rows.empty?
        result["genre"] = genre.flatten.uniq if genre
        result.merge!(script) if script
        result["translation"] = { "deu" => translation } if translation
        result["lines"] = extracted[:lines] if extracted[:lines].size > 1
        result["notes"] = extracted[:notes] unless extracted[:notes].empty?
        leiden = CelticLeiden.leiden_annotations(gaps: extracted[:gaps], supplied: extracted[:supplied],
                                                 unclear: extracted[:unclear], cancelled: false)
        result["leiden"] = leiden unless leiden.empty?
        result
      end

      def rows_by_letter(nodes)
        nodes.each_with_object({}) do |node, rows|
          values = yield(node)
          next if values.empty?

          (rows[node["n"].to_s] ||= []) << values
        end
      end

      # "Wappenbeischrift / Wappenbeischrift", "historische Nachricht /
      # Historische Nachricht": the " / " doublets fold once (first spelling).
      def genre_values(text)
        values = presence(text).to_s.split(" / ").filter_map { |value| presence(value) }
        values.uniq(&:downcase)
      end

      # letter => {"script" => [...], "letter_height" => [...], "technique" => [...]}
      def script_rows(doc)
        doc.xpath("//physDesc/scriptDesc/p").each_with_object({}) do |node, rows|
          label, value = presence(node.text).to_s.split(":", 2).map { |part| presence(part) }
          key = SCRIPT_LABELS[label]
          next unless key && value

          bucket = (rows[node["n"].to_s] ||= {})
          (bucket[key] ||= []) << value unless bucket[key]&.include?(value)
        end
      end

      def translations(doc)
        doc.xpath("//text/body/div[@type='translation']/div[@type='textpart']").each_with_object({}) do |part, result|
          text = prose(part.xpath("./ab"))
          result[part["n"].to_s] = text if text
        end
      end

      # -- document metadata ------------------------------------------------------

      def metadata(doc, identity)
        iri = doc.at_xpath("//msIdentifier/idno[@type='iri']")&.text.to_s.strip
        result = {
          "dio_id" => identity[:dio_id], "iri" => "#{IRI_BASE}#{iri}",
          "urn_nbn" => presence(doc.at_xpath("//msIdentifier/idno[@type='urn']")&.text),
          "citation" => "DI #{identity[:di]}, Nr. #{Integer(identity[:number], 10)}",
          "volume" => { "di" => identity[:di], "title" => volume_title(doc) }.compact,
          "author" => presence(doc.at_xpath("//titleStmt/author")&.text),
          "revised" => doc.at_xpath("//revisionDesc/change/@when")&.value.to_s[0, 10]
        }
        result["date"] = self.class.date_of(doc.at_xpath("//history/origin/origDate")&.text)
        place = place_of(doc)
        result["place"] = place if place
        facets = facets_of(doc)
        result["facets"] = facets unless facets.empty?
        result.merge!(object_metadata(doc))
        result.reject { |_, value| value.nil? || value == "" || value == {} || value == [] || value == { "raw" => "" } }
      end

      def volume_title(doc)
        presence(doc.at_xpath("//sourceDesc/bibl/biblScope[@unit='volume']")&.text)
      end

      def place_of(doc)
        raw = presence(doc.at_xpath("//history/origin/origPlace")&.text) or return nil
        locations = raw.split(";").filter_map { |part| presence(part) }
        { "ancient" => raw, "locations" => locations,
          "settlement" => presence(locations.first.to_s.split(",").last) }.compact
      end

      def facets_of(doc)
        genre = doc.xpath("//profileDesc//keywords/term").flat_map { |node| genre_values(node.text) }.uniq(&:downcase)
        script = script_rows(doc).values
        sources = {
          "genre" => [genre, genre.join("; ")],
          "object_type" => split_facet(doc.at_xpath("//supportDesc/support/objectType")&.text),
          "material" => single_facet(doc.at_xpath("//supportDesc/support/material")&.text),
          "condition" => single_facet(doc.at_xpath("//supportDesc/condition")&.text),
          "script_style" => list_facet(script.flat_map { |row| row["script"] || [] }),
          "technique" => list_facet(script.flat_map { |row| row["technique"] || [] })
        }
        sources.each_with_object({}) do |(facet, (values, raw)), facets|
          facets[facet] = { "values" => values, "raw" => raw } unless values.nil? || values.empty?
        end
      end

      def split_facet(text)
        raw = presence(text) or return nil
        [raw.split(",").filter_map { |part| presence(part) }.uniq, raw]
      end

      def single_facet(text)
        raw = presence(text) or return nil
        [[raw], raw]
      end

      def list_facet(values)
        values = values.uniq
        values.empty? ? nil : [values, values.join("; ")]
      end

      def object_metadata(doc)
        support = doc.at_xpath("//supportDesc/support")
        {
          "description" => support && prose(support.xpath("./p")),
          "dimensions" => dimensions(support),
          "heraldry" => doc.xpath("//physDesc/decoDesc//heraldry").filter_map { |node| presence(node.text) },
          "commentary" => prose(doc.xpath("//text/body/div[@type='commentary']/p")),
          "bibliography" => doc.xpath("//text/body/div[@type='bibliography']//bibl").filter_map do |node|
            presence(node.text)
          end
        }
      end

      def dimensions(support)
        return [] unless support

        support.xpath("./dimensions/*").filter_map do |node|
          quantity = node["quantity"].to_s
          next if quantity.empty?

          number = if quantity.match?(/\A\d+\z/) then Integer(quantity, 10)
                   elsif quantity.match?(/\A\d+\.\d+\z/) then Float(quantity)
                   else quantity
                   end
          { "dimension" => node.name, "quantity" => number, "unit" => presence(node["unit"]) }.compact
        end
      end

      # Paragraph prose with the footnotes dropped, paragraphs joined by a
      # blank line; nil when empty.
      def prose(nodes)
        texts = nodes.filter_map do |node|
          copy = node.dup
          copy.xpath(".//note").each(&:remove)
          presence(copy.text)
        end
        texts.empty? ? nil : texts.join("\n\n")
      end

      def presence(value)
        return nil if value.nil?

        folded = CelticLeiden.fold(value.to_s)
        folded.empty? ? nil : folded
      end

      # The recursive walk of ONE textpart (class note): lines split at lb,
      # the Epigraf dialect read per the class note, footnotes collected.
      class Extraction
        def initialize(path)
          @path = path
          @segments = [{ text: +"" }]
          @after_break = false
          @gaps = []
          @notes = []
          @supplied = 0
          @unclear = 0
          @supplied_depth = 0
          @unclear_depth = 0
        end

        def run(textpart)
          recurse(textpart)
          text = CelticLeiden.fold(@segments.map { |segment| segment[:text] }.join)
          { text: text, lines: lines, gaps: @gaps, notes: @notes, supplied: @supplied, unclear: @unclear }
        end

        private

        def walk(node)
          return text(node.text) if node.text?
          return unless node.element?

          case node.name
          when "head" then nil
          when "ab" then block(node)
          when "lb" then line_break(node)
          when "del" then deletion(node)
          when "gap" then gap(node)
          when "app" then apparatus(node)
          when "note" then note(node)
          when "add" then counted(node, :@supplied_depth)
          when "unclear" then counted(node, :@unclear_depth)
          when "space" then append(" ")
          when *READ_THROUGH then recurse(node)
          else
            raise ParseError, "#{@path}: <#{node.name}> inside the edition is outside the censused markup"
          end
        end

        def recurse(node)
          node.children.each { |child| walk(child) }
        end

        def text(value)
          if value.match?(/\A[[:space:]]*\z/)
            append(" ") unless @after_break
            return
          end

          @after_break = false
          append(value)
          count(value)
        end

        def append(value)
          @segments.last[:text] << value
        end

        def count(value)
          letters = CelticLeiden.grapheme_count(value)
          @supplied += letters if @supplied_depth.positive?
          @unclear += letters if @unclear_depth.positive?
        end

        def block(node)
          append(" ")
          recurse(node)
          append(" ")
        end

        def line_break(node)
          rend = node["rend"].to_s.strip
          segment = { text: +"" }
          segment[:break] = rend unless rend.empty?
          segment[:verse] = true if node["type"] == "verse"
          @segments << segment
          @after_break = true
        end

        def deletion(node)
          node.children.each do |child|
            next if child.text? && child.text.match?(/\A[[:space:]]*\z/)
            next gap(child) if child.element? && child.name == "gap"

            raise ParseError, "#{@path}: a <del> carrying text is outside the census (every censused del wraps a gap)"
          end
        end

        def gap(node)
          @after_break = false
          append(CelticLeiden::GAP_MARKER)
          annotation = CelticLeiden.gap_annotation(node)
          if annotation["quantity"] == 0 # rubocop:disable Style/NumericPredicate -- may be absent or a string
            annotation.delete("quantity")
            annotation["extent"] = "unknown"
          end
          @gaps << annotation
        end

        def apparatus(node)
          node.element_children.each do |child|
            unless child.name == "note"
              raise ParseError, "#{@path}: <app> holding <#{child.name}> is outside the census"
            end

            note(child)
          end
        end

        def note(node)
          text = CelticLeiden.fold(node.text)
          @notes << { "type" => node["type"], "text" => text }.compact unless text.empty?
        end

        def counted(node, variable)
          instance_variable_set(variable, instance_variable_get(variable) + 1)
          recurse(node)
          instance_variable_set(variable, instance_variable_get(variable) - 1)
        end

        def lines
          @segments.filter_map do |segment|
            text = CelticLeiden.fold(segment[:text])
            next if text.empty?

            { "text" => text, "break" => segment[:break], "verse" => segment[:verse] }.compact
          end
        end
      end
      private_constant :Extraction
    end
  end
end
