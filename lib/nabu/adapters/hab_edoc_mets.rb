# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # One edition's mets.xml on diglib.hab.de/edoc/<id>/ — the WDB's own
    # per-edition manifest, read for the three things the hab-edoc
    # adapter needs (census 2026-11-27, 256 METS files):
    #
    # - the TRANSCRIPTS: every relative .xml FLocat of the fileSec whose
    #   basename follows the WDB transcript convention
    #   ("tei-transcript.xml", "tei-transcript-pnr.xml",
    #   "tei-transcript_Augsburg_1530.xml", "Brief001-D_tei-transcript.xml",
    #   "tei-transcription.xml"), in fileSec order, deduplicated;
    # - each transcript's RIGHTS: the structMap divs that point at the
    #   file (mets:fptr or a parallel-view mets:area) carry an ADMID —
    #   inherited from an ancestor div when the pointing div has none —
    #   naming one of the template's three amdSec rightsMD segments,
    #   whose LABEL is the statement: "CC BY-SA 3.0" (the template's own
    #   comment: "CC Standardlizenz, wenn der Autor zugestimmt hat"),
    #   "rights restricted" ("wenn der Autor/Institution der weiteren
    #   Nutzung zustimmen muss") or "Benutzungsordnung" (the library's
    #   terms for its retro-digitized images). No ADMID anywhere = the
    #   edition assigns nothing;
    # - the edition TITLE (mods:title, else the wdb:title line).
    #
    # The METS files are hand-kept: one carries an invalid UTF-8 byte in
    # a comment (ed000238), several list files upstream no longer serves
    # (ed000008's tei-transcript.xml, ed000132's copy-pasted
    # tei-transcript-pnr.xml) — so the DOM parse is the recovering one and
    # a listed file is only a claim, settled by the fetch.
    class HabEdocMets
      TRANSCRIPT_NAME = /\A(?:.+[-_])?tei-transcri(?:ption|pt)(?:[-_].+)?\.xml\z/

      Transcript = Data.define(:href, :rights)

      def self.read(path) = new(File.binread(path))

      def self.transcript_name?(href) = TRANSCRIPT_NAME.match?(File.basename(href.to_s))

      def initialize(xml)
        @doc = Nokogiri::XML(xml.dup.force_encoding(Encoding::UTF_8).scrub(""))
        @doc.remove_namespaces!
      end

      def title
        mods = text(@doc.at_xpath("//dmdSec//mods/titleInfo/title"))
        mods || text(@doc.at_xpath("//dmdSec//title"))
      end

      # Every relative .xml file the fileSec lists (the census reads the
      # non-transcript ones for the rejected-grain note).
      def xml_files
        @xml_files ||= begin
          hrefs = @doc.xpath("//fileSec//file/FLocat/@href").map { |a| a.value.strip }
          hrefs.select { |href| href.end_with?(".xml") && !href.match?(%r{\A[a-z]+://}i) }.uniq
        end
      end

      def transcripts
        @transcripts ||= begin
          ids = file_ids
          xml_files.select { |href| self.class.transcript_name?(href) }
                   .map { |href| Transcript.new(href: href, rights: rights_for(ids.fetch(href, []))) }
        end
      end

      private

      # href → the fileSec file IDs that locate it.
      def file_ids
        @doc.xpath("//fileSec//file").each_with_object(Hash.new { |h, k| h[k] = [] }) do |file, map|
          href = file.at_xpath("./FLocat/@href")&.value&.strip
          map[href] << file["ID"] if href && file["ID"]
        end
      end

      # The rightsMD LABELs of every structMap div that points at one of
      # +ids+ (its own ADMID, else the nearest ancestor's).
      def rights_for(ids)
        return [] if ids.empty?

        labels = rights_labels
        pointers = @doc.xpath("//structMap//fptr[@FILEID] | //structMap//area[@FILEID]")
        pointers.select { |ptr| ids.include?(ptr["FILEID"]) }.filter_map do |ptr|
          admid = ptr.ancestors("div").map { |div| div["ADMID"] }.compact.first
          admid && labels[admid]
        end.uniq
      end

      def rights_labels
        @rights_labels ||= @doc.xpath("//amdSec/rightsMD").to_h do |md|
          [md["ID"], md.at_xpath("./mdRef/@LABEL")&.value.to_s.strip]
        end
      end

      def text(node)
        return nil if node.nil?

        value = node.text.gsub(/[[:space:]]+/, " ").strip
        value.empty? ? nil : Normalize.nfc(value)
      end
    end
  end
end
