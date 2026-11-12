# frozen_string_literal: true

require "nokogiri"
require_relative "cllg_tei_parser"

module Nabu
  module Adapters
    # The shared Dapytains-catalog walk of the Inria CLLG corpora (the
    # Freed Corpus and Sources Chrétiennes share it verbatim): every
    # per-author `data/**/metadata.xml` collection is a catalog record whose
    # <resource identifier="urn:cts:…" filepath="./…"> entries name the
    # edition files. The root `cllg-<corpus>.xml` lists those metadata
    # files (2026-11 census: exactly the on-disk set, in both corpora); the
    # walk reads the metadata files directly, so a .attic replay — which
    # holds no root catalog — rediscovers by the same rule.
    #
    # One record per resource: the resource urn and file, its title and
    # description, the work collection's title and dublinCore (creator,
    # identifiers), and the author collection's title.
    class CllgCatalog
      Resource = Data.define(:urn, :path, :title, :description, :work_title, :creator, :author,
                             :identifiers, :spuria_of, :metadata_path)

      METADATA_GLOB = File.join("data", "**", "metadata.xml")
      EDITION_GLOB = File.join("data", "**", "*.xml")

      def initialize(workdir)
        @workdir = workdir
      end

      # Every catalogued resource, ordered by urn.
      def resources
        @resources ||= metadata_files.flat_map { |path| read(path) }.sort_by(&:urn)
      end

      # Edition files on disk that no resource claims (absolute paths).
      def uncatalogued
        claimed = resources.to_set(&:path)
        edition_files.reject { |path| claimed.include?(path) }
      end

      # Resources whose file is absent on disk.
      def missing
        resources.reject { |resource| File.file?(resource.path) }
      end

      def relative(path)
        path.delete_prefix("#{File.expand_path(@workdir)}#{File::SEPARATOR}")
      end

      private

      def metadata_files
        Dir.glob(File.join(@workdir, METADATA_GLOB))
      end

      def edition_files
        Dir.glob(File.join(@workdir, EDITION_GLOB)).reject { |path| File.basename(path) == "metadata.xml" }
                                                   .map { |path| File.expand_path(path) }.sort
      end

      def read(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "cllg metadata.xml"))
        doc.remove_namespaces!
        author = squash(doc.at_xpath("/collection/title")&.text)
        doc.xpath("//resource[@identifier][@filepath]").map do |node|
          work = node.ancestors("collection").first
          Resource.new(
            urn: node["identifier"].strip,
            path: File.expand_path(node["filepath"], File.dirname(path)),
            title: squash(node.at_xpath("title")&.text),
            description: squash(node.at_xpath("description")&.text),
            work_title: squash(work&.at_xpath("title")&.text),
            creator: squash(work&.at_xpath("dublinCore/creator")&.text),
            author: author,
            identifiers: work ? work.xpath("dublinCore/identifier").filter_map { |id| squash(id.text) } : [],
            spuria_of: squash(work&.at_xpath("extensions/isSpuriaOf")&.text),
            metadata_path: File.expand_path(path)
          )
        end
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::FetchError, "#{path}: malformed catalog record: #{e.message}"
      end

      def squash(value) = CllgTeiParser.squash(value)
    end
  end
end
