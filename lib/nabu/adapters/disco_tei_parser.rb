# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for the DISCO per-author TEI files (P77-4) — the disco-tei
    # family: TEI P5 with an RDFa-attributed header (title/author,
    # prosopography with birth/death centuries and birthplace, source
    # bibl) and a body of <lg type="sonnet" xml:id="sNNNx_NNNN"> blocks —
    # cuarteto/terceto child stanzas of <l met rhyme [enjamb]> lines with
    # inline <w type="rhyme"> marks that flatten seamlessly.
    #
    # Passage = one sonnet, cited by the corpus's OWN trailing ordinal
    # (s002g_0002 → :2 — the id space is corpus-wide per author, never
    # per-file-1-based; the house :b2 belt covers any collision). Text =
    # the lines with their breaks, no blank lines; the sonnet title and
    # the stanza architecture ride annotations, and so do the per-line
    # met/rhyme/enjamb values — AUTOMATIC layers by the encodingDesc's
    # own words (ADSO scansion, RhymeTagger, ANJA), carried labeled,
    # never presented as gold.
    class DiscoTeiParser
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze

      SONNET_ID = /_(\d+)\z/

      def parse(path, urn:, language:, period:)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
        raise ParseError, "#{path}: #{doc.errors.first}" unless doc.errors.empty?

        document = Nabu::Document.new(
          urn: urn, language: language, title: squish(doc.at_xpath("//tei:titleStmt/tei:title", TEI_NS)&.text),
          canonical_path: File.expand_path(path), metadata: metadata(doc, period)
        )
        append_sonnets(doc, document, urn, language, path)
        raise ParseError, "#{path}: no sonnets parsed" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def metadata(doc, period)
        meta = { "period" => period }
        meta["author"] = squish(doc.at_xpath("//tei:titleStmt/tei:author", TEI_NS)&.text)
        person = doc.at_xpath("//tei:particDesc//tei:person", TEI_NS)
        if person
          meta["birth_century"] = date_century(person, "tei:birth")
          meta["death_century"] = date_century(person, "tei:death")
          meta["birthplace"] = squish(person.at_xpath(".//tei:settlement", TEI_NS)&.text)
        end
        meta["source"] = squish(doc.at_xpath("//tei:sourceDesc/tei:bibl", TEI_NS)&.text)
        meta.compact.reject { |_k, v| v.respond_to?(:empty?) && v.empty? }
      end

      def date_century(person, arm)
        squish(person.at_xpath("#{arm}/tei:date[@type='century']", TEI_NS)&.text)
      end

      def append_sonnets(doc, document, urn, language, path)
        citations = Hash.new(0)
        doc.xpath("//tei:body//tei:lg[@type='sonnet']", TEI_NS).each do |sonnet|
          id = sonnet["xml:id"].to_s
          match = SONNET_ID.match(id) or
            raise ParseError, "#{path}: sonnet id #{id.inspect} carries no trailing ordinal"
          citations[match[1].to_i] += 1
          count = citations[match[1].to_i]
          citation = count == 1 ? match[1].to_i.to_s : "#{match[1].to_i}:b#{count}"
          document << passage(sonnet, id, urn: urn, language: language,
                                          citation: citation, sequence: document.size)
        end
      end

      def passage(sonnet, id, urn:, language:, citation:, sequence:)
        lines = sonnet.xpath(".//tei:l", TEI_NS)
        annotations = { "sonnet_id" => id }
        title = squish(sonnet.at_xpath("./tei:head", TEI_NS)&.text)
        annotations["title"] = title unless title.to_s.empty?
        annotations["stanzas"] = stanzas(sonnet)
        annotations["lines"] = lines.map { |line| line_note(line) }
        Nabu::Passage.new(
          urn: "#{urn}:#{citation}", language: language,
          text: Normalize.nfc(lines.map { |line| squish(line.text) }.join("\n")),
          annotations: annotations, sequence: sequence
        )
      end

      def stanzas(sonnet)
        sonnet.xpath("./tei:lg", TEI_NS).map do |stanza|
          { "type" => stanza["type"], "lines" => stanza.xpath("./tei:l", TEI_NS).size }
        end
      end

      # Present-only keys — an unmarked line carries no empty fields.
      def line_note(line)
        %w[met rhyme enjamb].each_with_object({}) do |key, note|
          note[key] = line[key] if line[key]
        end
      end

      def squish(text)
        text&.gsub(/\s+/, " ")&.strip
      end
    end
  end
end
