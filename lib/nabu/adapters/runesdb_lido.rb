# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The RuneS-DB per-find LIDO record (https://www.runesdb.de/lido/<id>,
    # LIDO v1.1, CC BY-SA 4.0 — the record's own recordRights; harvested by
    # RunesdbLidoFetch into <workdir>/lido/<id>.xml) read into the find
    # document's metadata. Census basis: 27 records fetched 2026-11-05
    # across every siglum family (stones, brooches, combs, rune sticks, the
    # Franks casket, runica manuscripta).
    #
    # == What a record carries, and where it lands
    #
    #   Production event earliestDate/latestDate  → "date" {not_before,
    #     not_after, raw} — the ARTIFACT's dating (signed CE years; the
    #     MetadataDates :structured lane). "0"/"0" is upstream's unknown
    #     sentinel (the Kylver and Rö stones carry it — the house model has
    #     no year 0) and "-" an empty field: both mint no bound. A reversed
    #     pair is order-normalized (all-CE unsigned years, the swap is safe).
    #   Finding event eventPlace (name + gml:pos) → "place" {"ancient" =>
    #     the find place verbatim, "geo" => "lat, lon"} — the findspot claim
    #     nabu-places matches by name; the GML point is "lat lon" (EPSG:4326
    #     axis order, checked against Hackness 54.32 N −0.54) and rides in
    #     the house "lat, lon" form, both-or-nothing. EXCEPT a manuscript
    #     (objectWorkType "manuscript"): its finding event names the HOLDING
    #     LIBRARY (Nordisk Forskningsinstitut, Kungliga biblioteket …, with
    #     the library's own point), a present location, never a findspot —
    #     it rides repository.find_event_place (the rundata/menota stance on
    #     holding institutions), declared coarse in the places posture.
    #   Finding event dates → "find_date" raw ("1835", "1840 ca.",
    #     "1848>F", "1857+1890") — the DISCOVERY date, never the
    #     inscription's (the ociana stance; MINING_EXEMPT).
    #   repositorySet → "repository" {name, geo} (the present holder;
    #     metadata only); workID → "sigla" (upstream's concordance — "Sj 73",
    #     "DR 232", "KJ9": the rundata crosswalk keys).
    #   objectWorkType → "object_type" + facet object_type; classification
    #     (find context — burial/settlement/single find; a manuscript's
    #     host-text class) → "classification" + facet; termMaterialsTech
    #     lido00132 → "material" (+ facet), lido00131 → "technique";
    #     measurements → "measurements"; objectDescription → "description".
    #   inscriptionTranscription → "transcription" (the editorial
    #     transcription, lines kept); inscriptionDescription[@type=
    #     translation] → "translation_en" / "translation_de" verbatim ("-" =
    #     none). The English one also mints the -en sibling document when it
    #     is a real rendering (Runesdb#translation_text).
    #   recordRights → "lido_license" + "lido_license_url".
    #
    # Never read: recordMetadataDate (the SERVING timestamp — every GET
    # restamps it), the resource/image wrap (photographs carry their
    # holders' terms).
    module RunesdbLido
      NS = {
        "lido" => "http://www.lido-schema.org", "skos" => "http://www.w3.org/2004/02/skos/core#",
        "gml" => "http://www.opengis.net/gml", "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      }.freeze

      PRODUCTION = "http://terminology.lido-schema.org/lido00007"
      FINDING = "http://terminology.lido-schema.org/lido00002"
      MATERIAL = "http://terminology.lido-schema.org/lido00132"
      TECHNIQUE = "http://terminology.lido-schema.org/lido00131"

      # upstream's empty-field marks ("-" everywhere; "None" on an unnamed
      # repository location).
      EMPTY = ["", "-", "None"].freeze
      # A production side that states no year: the empty marks plus "0"
      # (no year 0 in the house model — upstream's unknown sentinel).
      UNKNOWN_YEAR = ["", "-", "0"].freeze
      YEAR = /\A-?\d{1,4}\z/
      GML_POS = /\A(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\z/

      module_function

      # The record's metadata hash (compact — absent fields are absent).
      # Raises Nabu::ParseError on a malformed record or one whose
      # recordID is not +find_id+ (a mis-filed harvest is loud, never
      # silently mined onto the wrong find).
      def read(path, find_id:)
        xml = Nokogiri::XML(SourceRead.utf8_file(path, label: "runesdb lido"), &:strict)
        root = xml.at_xpath("/lido:lido", NS) or raise ParseError, "#{path}: not a LIDO record"
        record_id = text(root.at_xpath(".//lido:recordWrap/lido:recordID", NS))
        unless record_id == find_id.to_s
          raise ParseError, "#{path}: LIDO recordID #{record_id.inspect} is not find #{find_id}"
        end

        mine(root)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed LIDO: #{e.message}"
      end

      def mine(root)
        manuscript = labels(root, ".//lido:objectWorkType").include?("manuscript")
        repository = repository(root)
        finding = event(root, FINDING)
        place = finding && event_place(finding)
        if manuscript && place
          repository = (repository || {}).merge("find_event_place" => place)
          place = nil
        end
        {
          "object_type" => labels(root, ".//lido:objectWorkType").first,
          "classification" => labels(root, ".//lido:classification").first,
          "lido_title" => value(root, ".//lido:titleSet/lido:appellationValue[@xml:lang='en']"),
          "transcription" => transcription(root),
          "translation_en" => translation(root, "en"),
          "translation_de" => translation(root, "de"),
          "sigla" => list(root.xpath(".//lido:repositorySet/lido:workID", NS).map { |node| text(node) }),
          "repository" => repository,
          "description" => list(root.xpath(".//lido:objectDescriptionSet/lido:descriptiveNoteValue[@xml:lang='en']",
                                           NS).map { |node| text(node) }),
          "material" => list(materials(root, MATERIAL)),
          "technique" => list(materials(root, TECHNIQUE)),
          "measurements" => list(measurements(root)),
          "date" => (production = event(root, PRODUCTION)) && production_date(production),
          "find_date" => finding && date_raw(finding),
          "place" => place,
          "lido_license" => labels(root, ".//lido:recordRights/lido:rightsType").first,
          "lido_license_url" => root.at_xpath(".//lido:recordRights/lido:rightsType/skos:Concept/@rdf:about", NS)
                                    &.value
        }.compact
      end

      # The production envelope: {not_before, not_after, raw}. nil when both
      # sides are empty marks (the "0" sentinel, "-", blank); a non-year
      # value rides raw-only — the claim kept verbatim, no bound guessed.
      def production_date(event)
        sides = bounds(event)
        return nil if sides.all? { |side| UNKNOWN_YEAR.include?(side) }

        low, high = sides.map { |side| year(side) }
        low, high = high, low if low && high && low > high
        raw = sides.reject { |side| UNKNOWN_YEAR.include?(side) }.uniq.join("–")
        { "not_before" => low, "not_after" => high, "raw" => raw }.compact
      end

      # A finding event's date verbatim ("1848>F"; "a–b" when the sides
      # differ), nil when empty.
      def date_raw(event)
        sides = bounds(event).reject { |side| EMPTY.include?(side) }.uniq
        sides.empty? ? nil : sides.join("–")
      end

      def bounds(event)
        %w[earliestDate latestDate].map { |name| text(event.at_xpath("./lido:eventDate//lido:#{name}", NS)) }
      end

      def year(side)
        return nil unless side.match?(YEAR)

        value = Integer(side, 10)
        value.zero? ? nil : value
      end

      def event(root, type)
        root.xpath(".//lido:event", NS).find do |event|
          event.at_xpath("./lido:eventType/skos:Concept/@rdf:about", NS)&.value == type
        end
      end

      def event_place(event)
        node = event.at_xpath("./lido:eventPlace/lido:place", NS) or return nil
        named(text(node.at_xpath("./lido:namePlaceSet/lido:appellationValue", NS)), node, key: "ancient")
      end

      def repository(root)
        set = root.at_xpath(".//lido:repositorySet", NS) or return nil
        name = value(set, "./lido:repositoryName//lido:appellationValue[@xml:lang='en']") ||
               value(set, "./lido:repositoryLocation/lido:namePlaceSet/lido:appellationValue[@xml:lang='en']")
        named(name, set.at_xpath("./lido:repositoryLocation", NS), key: "name")
      end

      # {key => name, "geo" => "lat, lon"} — either half may be absent;
      # nil when both are.
      def named(name, node, key:)
        geo = node && geo(node)
        name = nil if EMPTY.include?(name.to_s)
        return nil if name.nil? && geo.nil?

        { key => name && Normalize.nfc(name), "geo" => geo }.compact
      end

      def geo(node)
        match = GML_POS.match(text(node.at_xpath(".//gml:pos", NS))) or return nil

        "#{match[1]}, #{match[2]}"
      end

      def transcription(root)
        node = root.at_xpath(".//lido:inscriptions/lido:inscriptionTranscription", NS) or return nil
        lines = node.text.lines.map { |line| line.gsub(/\s+/, " ").strip }.reject(&:empty?)
        lines.empty? ? nil : Normalize.nfc(lines.join("\n"))
      end

      def translation(root, lang)
        node = root.at_xpath(".//lido:inscriptionDescription[@lido:type='translation']/" \
                             "lido:descriptiveNoteValue[@xml:lang='#{lang}']", NS) or return nil
        lines = node.text.lines.map { |line| line.gsub(/\s+/, " ").strip }.reject(&:empty?)
        text = lines.join("\n")
        EMPTY.include?(text) ? nil : Normalize.nfc(text)
      end

      def materials(root, type)
        root.xpath(".//lido:termMaterialsTech[@lido:type='#{type}']/skos:Concept/" \
                   "skos:prefLabel[@xml:lang='en']", NS).map { |node| text(node) }
      end

      def measurements(root)
        root.xpath(".//lido:measurementsSet", NS).filter_map do |set|
          entry = {
            "type" => value(set, "./lido:measurementType//skos:prefLabel[@xml:lang='en']"),
            "value" => value(set, "./lido:measurementValue"),
            "unit" => value(set, "./lido:measurementUnit//skos:prefLabel[@xml:lang='en']")
          }.compact
          entry if entry["value"]
        end
      end

      # The English prefLabels under +xpath+'s Concepts, "-" dropped.
      def labels(root, xpath)
        list(root.xpath("#{xpath}//skos:Concept/skos:prefLabel[@xml:lang='en']", NS).map { |node| text(node) }) || []
      end

      def value(node, xpath)
        found = text(node.at_xpath(xpath, NS))
        EMPTY.include?(found) ? nil : Normalize.nfc(found)
      end

      # Non-empty, de-duplicated, NFC — nil when nothing is left.
      def list(values)
        kept = values.reject { |item| item.is_a?(String) && EMPTY.include?(item) }
                     .map { |item| item.is_a?(String) ? Normalize.nfc(item) : item }.uniq
        kept.empty? ? nil : kept
      end

      def text(node) = node&.text.to_s.gsub(/\s+/, " ").strip
    end
  end
end
