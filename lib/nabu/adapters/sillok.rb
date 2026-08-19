# frozen_string_literal: true

require_relative "nikh_xml_parser"
require_relative "../zip_fetch"
require_relative "../data_go_kr_fetch"

module Nabu
  module Adapters
    # The sillok adapter (P78-1 — the korean axis's anchor): 조선왕조실록
    # 원문, the Veritable Records of the Joseon Dynasty in the original
    # hanmun, NIKH's bulk XML via data.go.kr — dataset 15053647
    # (Taejo–Cheoljong, the 25 dynastic reigns, ~137 MB zip / 674 files)
    # + 15053646 (Gojong/Sunjong, the two colonial-era supplements,
    # ~9 MB). License: 이용허락범위 제한 없음 per both dataset pages
    # (verified 2026-07-26 by the P47-s4 survey, re-verified 2026-08-18
    # — the whole NIKH family answers useScopeCode COEX07), ruled
    # D47-a → attribution, credit the institute. The query-only website
    # (sillok.history.go.kr) is ARR; the dump is the sanctioned channel.
    #
    # HANMUN-ONLY HONESTY: the dumps carry the 원문 (original Literary
    # Chinese) — the modern Korean translation layer is possibly
    # separately copyrighted and is NOT in them; never fetched. The
    # level5 editorial headline (modern Korean, NIKH's own apparatus,
    # part of the licensed dump) rides as annotation title, never as
    # passage text. Language: lzh — Literary Chinese as read in Korea,
    # the kanripo precedent; lect posture codemap (lzh → zho/lit).
    #
    # Document = one volume file (urn:nabu:sillok:<file id>, e.g.
    # wzc_121 — reign code + volume number); passage = one leaf of the
    # level tree (the level5 기사 day article, or the deepest text-
    # bearing node in preface/appendix members), urn-suffixed with the
    # leaf's own upstream id. The seven-calendar date apparatus rides
    # raw in annotations; the volume's 서기 year feeds the timeline
    # through the MetadataDates :structured shape.
    class Sillok < Nabu::Adapter
      LANGUAGE = "lzh"

      # The two data.go.kr datasets, each fetched into its own subdir
      # (its own ZipFetch state + attic — one zip owns one dir).
      DATASETS = [
        { pk: "15053647", subdir: "taejo-cheoljong" },
        { pk: "15053646", subdir: "gojong-sunjong" }
      ].freeze

      ATTIC_DIRNAME = ".attic"

      MANIFEST = Nabu::SourceManifest.new(
        id: "sillok",
        name: "조선왕조실록 원문 — Veritable Records of the Joseon Dynasty (NIKH)",
        license: "이용허락범위 제한 없음 (data.go.kr datasets 15053647 + 15053646, " \
                 "useScopeCode COEX07, verified 2026-08-18; KOGL framework) — owner ruling " \
                 "D47-a: attribution, credit the institute",
        license_class: "attribution",
        upstream_url: "https://www.data.go.kr/data/15053647/fileData.do",
        parser_family: "nikh-xml",
        credit: "국사편찬위원회 (National Institute of Korean History), 조선왕조실록 원문 " \
                "bulk XML via data.go.kr (datasets 15053647, 15053646)"
      )

      def self.manifest
        MANIFEST
      end

      # +resolver+/+zip_fetch_factory+ exist for the tests (no network in
      # the suite, ever); no-arg construction stays the registry contract.
      def initialize(resolver: Nabu::DataGoKrFetch.method(:resolve),
                     zip_fetch_factory: Nabu::ZipFetch.method(:new))
        super()
        @resolver = resolver
        @zip_fetch_factory = zip_fetch_factory
      end

      # Per dataset: resolve the CURRENT download URL (the atchFileId
      # bumps on every upstream replacement — resolution is the
      # contract, .docs/p78-plan.md §Acquisition), then the full ZipFetch
      # choreography into the dataset's own subdir.
      def fetch(workdir, progress: nil, force: false)
        shas = DATASETS.map do |dataset|
          fetch_dataset(workdir, dataset, progress: progress, force: force)
        end
        Nabu::FetchReport.new(sha: shas.join("+"), fetched_at: Time.now,
                              notes: DATASETS.map { |dataset| "data.go.kr #{dataset[:pk]}" })
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "sillok fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        volume_files(workdir).each do |path|
          id = File.basename(path, ".xml").sub(/\A2nd_/, "")
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:sillok:#{id}",
            path: File.expand_path(path),
            metadata: { "volume" => id }
          )
        end
      end

      # The census: the DTD ships in every zip (recognized); ZipFetch
      # state and attics are mechanics; anything else non-XML is a
      # stray — loud.
      def discovery_skips(workdir)
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "non-corpus file: #{path}" }
        )
      end

      def parse(document_ref)
        volume = parser.parse_file(document_ref.path)
        raise Nabu::DocumentSkipped.new("no text leaves", reason: "volume without text content") if volume.leaves.empty?

        build_document(document_ref, volume)
      end

      private

      def fetch_dataset(workdir, dataset, progress:, force:)
        url = @resolver.call(dataset[:pk])
        dir = File.join(workdir, dataset[:subdir])
        fetch = @zip_fetch_factory.call(url: url, dir: dir,
                                        attic_dir: File.join(dir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          guard_mass_deletion!(dir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        fetch.sha
      end

      # Volume files in the two dataset subdirs — or flat (the fixture
      # dir and any hand-assembled workdir walk the same rule).
      def volume_files(workdir)
        Dir.glob(File.join(workdir, "**", "2nd_*.xml"))
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .sort
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .reject { |path| File.basename(path) =~ /\A2nd_.*\.xml\z/ }
           .reject { |path| File.basename(path) == "history.dtd" }
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      def parser
        @parser ||= NikhXmlParser.new
      end

      def build_document(document_ref, volume)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: volume.title || volume.id,
          metadata: { "volume" => volume.id, "date" => date_envelope(volume) }.compact
        )
        volume.leaves.each_with_index do |leaf, index|
          document << build_passage(document_ref, leaf, index)
        end
        document
      end

      # The MetadataDates :structured shape (P47-r2): the volume's 서기
      # year as a one-year envelope. Undated volumes claim nothing.
      def date_envelope(volume)
        return nil if volume.year.nil?

        { "not_before" => volume.year, "not_after" => volume.year, "raw" => volume.year.to_s }
      end

      def build_passage(document_ref, leaf, index)
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{leaf.id || (index + 1)}",
          language: LANGUAGE,
          text: Nabu::Normalize.nfc(leaf.text),
          sequence: index,
          annotations: {
            "title" => leaf.title, "date" => leaf.date_raw,
            "subject_classes" => (leaf.subject_classes unless leaf.subject_classes.empty?),
            "sources" => (leaf.sources unless leaf.sources.empty?)
          }.compact
        )
      end
    end
  end
end
