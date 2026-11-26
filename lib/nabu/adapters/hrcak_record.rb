# frozen_string_literal: true

require "nokogiri"

require_relative "../errors"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # One Hrčak article record, read from the two OAI-PMH formats the
    # hrcak-marulana fetch holds per record: oai_openaire (the rich one —
    # datacite titles/creators/date, oaire file/volume/pages/type/licence)
    # and, optionally, oai_dc (the journal's rights statement). Pure
    # reading: no network, no normalization beyond NFC and whitespace
    # folding of single-line fields (abstract line breaks are kept).
    #
    # == The file ↔ language pairing (census 2026-11-25)
    #
    # A record lists its languages (dc:language, 639-2 codes), its page
    # ranges (oaire:citationStartPage/EndPage pairs) and its PDFs
    # (oaire:file) as PARALLEL sequences: file i is the version in
    # language i covering range i. Verified against the article landing
    # pages' own per-file citation_language for all 90 multi-file records
    # of the set (0 mismatches). A record may list MORE languages than
    # files (386 of 681: the summary in the second language is printed
    # inside the one PDF) — the extra languages are summary/apparatus
    # languages inside the last file, never a file of their own.
    class HrcakRecord
      NS = {
        "oai" => "http://www.openarchives.org/OAI/2.0/",
        "oaire" => "http://namespace.openaire.eu/schema/oaire",
        "datacite" => "http://datacite.org/schema/kernel-4",
        "dc" => "http://purl.org/dc/elements/1.1/",
        "oai_dc" => "http://www.openarchives.org/OAI/2.0/oai_dc/"
      }.freeze

      # The record-level licence conditions censused 2026-11-25 (91 of 681
      # records carry one; the rest fall under the journal statement).
      # nil = no grant: the record is gated out (never fetched, never a
      # document).
      LICENSES = {
        "http://creativecommons.org/licenses/by/4.0/" => "attribution",
        "http://creativecommons.org/licenses/by-sa/4.0/" => "attribution",
        "http://creativecommons.org/licenses/by-nc/4.0/" => "nc",
        "http://creativecommons.org/licenses/by-nc-nd/4.0/" => "nc",
        "http://rightsstatements.org/vocab/InC/1.0/" => nil
      }.freeze

      # The journal's statement (oai_dc dc:rights on all 681 records):
      # CC BY 4.0 for every record that carries no licence condition of
      # its own.
      JOURNAL_GRANT = "Creative Commons Attribution 4.0 International License (CC BY 4.0)"

      FileVersion = Data.define(:url, :file_id, :language, :first_page, :last_page)
      Creator = Data.define(:name, :affiliations, :orcid)

      attr_reader :id

      def self.from_files(openaire_path, dc_path = nil)
        openaire = SourceRead.utf8_file(openaire_path, label: "hrcak record")
        twin = dc_path && File.file?(dc_path) ? SourceRead.utf8_file(dc_path, label: "hrcak record (oai_dc)") : nil
        new(openaire: openaire, oai_dc: twin)
      end

      def initialize(openaire:, oai_dc: nil)
        @doc = Nokogiri::XML(openaire)
        @dc = oai_dc && Nokogiri::XML(oai_dc)
        identifier = @doc.at_xpath("//oai:header/oai:identifier", NS)
        raise Nabu::ParseError, "OAI record without a header identifier" if identifier.nil?

        @id = identifier.text.strip.split(":").last
        @resource = @doc.at_xpath("//oaire:resource", NS)
        raise Nabu::ParseError, "record #{@id}: no oai_openaire resource" if @resource.nil?
      end

      def datestamp = @doc.at_xpath("//oai:header/oai:datestamp", NS)&.text&.strip

      # [{ "lang" =>, "text" =>, "type" => }] in record order; the first is
      # the main title.
      def titles
        nodes = @resource.xpath("datacite:titles/datacite:title", NS).reject { |node| line(node.text).empty? }
        nodes.map do |node|
          { "lang" => node["xml:lang"] || node["lang"], "text" => line(node.text),
            "type" => node["titleType"] }.compact
        end
      end

      def creators
        named = @resource.xpath("datacite:creators/datacite:creator", NS).reject do |node|
          line(node.at_xpath("datacite:creatorName", NS)&.text).empty?
        end
        named.map do |node|
          Creator.new(
            name: line(node.at_xpath("datacite:creatorName", NS)&.text),
            affiliations: node.xpath("datacite:affiliation", NS).map { |a| line(a.text) }.reject(&:empty?).uniq,
            orcid: node.xpath("datacite:nameIdentifier", NS).find { |n| n["nameIdentifierScheme"] == "ORCID" }
                       &.text&.strip
          )
        end
      end

      def issued = text("datacite:date[@dateType='Issued']")
      def volume = text("oaire:citationVolume")&.delete_suffix(".")
      def issue = text("oaire:citationIssue")
      def resource_type = text("oaire:resourceType")
      def publisher = text("dc:publisher")
      def journal = text("oaire:citationTitle")
      def landing_url = text("datacite:identifier[@identifierType='URL']")
      def languages = @resource.xpath("dc:language", NS).map { |n| n.text.strip }.reject(&:empty?)

      def files = @resource.xpath("oaire:file", NS).map { |n| n.text.strip }

      def page_ranges
        starts = @resource.xpath("oaire:citationStartPage", NS).map { |n| n.text.strip }
        ends = @resource.xpath("oaire:citationEndPage", NS).map { |n| n.text.strip }
        starts.zip(ends)
      end

      # The record's PDFs paired with language and page range (the
      # parallel-sequence rule above). +file_id+ is upstream's permanent id.
      def file_versions
        ranges = page_ranges
        files.each_with_index.map do |url, index|
          first, last = ranges[index]
          FileVersion.new(url: url, file_id: url[%r{/file/(\d+)\z}, 1], language: languages[index] || languages.first,
                          first_page: first, last_page: last)
        end
      end

      # Languages listed beyond the PDFs: summaries/apparatus printed
      # inside the record's last PDF.
      def inner_languages = languages.drop(files.size)

      # { lang => abstract } — line breaks kept, CRs dropped.
      def abstracts
        @resource.xpath("dc:description", NS).each_with_object({}) do |node, out|
          body = Normalize.nfc(node.text.delete("\r").strip)
          out[node["xml:lang"] || node["lang"] || "und"] = body unless body.empty?
        end
      end

      def subjects
        @resource.xpath("datacite:subjects/datacite:subject", NS).map { |n| line(n.text) }.reject(&:empty?).uniq
      end

      def license_condition
        node = @resource.at_xpath("oaire:licenseCondition", NS) or return nil
        { "uri" => node["uri"].to_s.strip, "label" => line(node.text) }
      end

      # The house licence class for this record: its own licence condition
      # when present (nil for in-copyright or an unknown statement), else
      # the journal grant.
      def license_class
        condition = license_condition
        return "attribution" if condition.nil?

        LICENSES[condition["uri"]]
      end

      def known_license? = license_condition.nil? || LICENSES.key?(license_condition["uri"])

      # The oai_dc dc:rights statements, verbatim (empty without the twin).
      def dc_rights
        return [] unless @dc

        @dc.xpath("//dc:rights", NS).map { |n| line(n.text) }.reject(&:empty?)
      end

      # The journal statement carried by the oai_dc twin (nil when absent).
      def journal_rights_statement = dc_rights.find { |r| r.include?(JOURNAL_GRANT) }

      private

      def text(xpath)
        value = @resource.at_xpath(xpath, NS)&.text
        if value.nil?
          nil
        else
          line(value).then { |v| v.empty? ? nil : v }
        end
      end

      def line(value) = Normalize.nfc(value.to_s.gsub(/\s+/, " ").strip)
    end
  end
end
