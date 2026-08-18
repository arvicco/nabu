# frozen_string_literal: true

require_relative "nikh_xml_parser"
require_relative "../zip_fetch"
require_relative "../data_go_kr_fetch"

module Nabu
  module Adapters
    # The bibyeonsa adapter (P78-3): 비변사등록 원문 — the Records of
    # the Border Defense Command (비변사, the de-facto supreme state
    # council of later Joseon; surviving registers 1617–1892) in the
    # original hanmun, NIKH's bulk XML via data.go.kr — dataset
    # 15053636, one zip (31 MB / 180 MB unpacked): 273 members
    # bb_001..bb_273 (no _000) + history.dtd ver 1.4. License:
    # 이용허락범위 제한 없음 per the dataset page (verified 2026-08-18),
    # ruled D47-a → attribution, credit the institute.
    #
    # HANMUN-ONLY HONESTY: the dump carries the 원문 only — the modern
    # Korean translation layer is NOT in it, never fetched. The editorial
    # entry headline (modern Korean, NIKH apparatus, in the licensed
    # dump) rides as annotation title, never as passage text. Language:
    # lzh (the kanripo/sillok precedent).
    #
    # CENSUS FACTS (2026-08-18): one member per 책 (register book),
    # rooted at level1 — except bb_001, the ONE <item>-rooted member
    # (its single level1 carries NIKH's 1959 print-edition front whose
    # modern-Korean 서문 preface rides the front apparatus, never a
    # passage). level2 = year (with value/간지/왕명/재위년도 attrs —
    # years INTERLEAVE non-monotonically in bb_001), level3 = month,
    # level4 = the leaf entries: 좌목 attendance rosters (tables,
    # flattened to text) and the daily memoranda. The single dateOccured
    # per entry carries a machine date attr and NO type at all (the
    # family's 서기 line does not exist here); documents claim no date —
    # the entry dates ride annotations raw.
    class Bibyeonsa < Nabu::Adapter
      LANGUAGE = "lzh"

      # The one data.go.kr dataset; the atchFileId behind it bumps on
      # every upstream replacement — resolution is the contract.
      DATA_PK = "15053636"

      ATTIC_DIRNAME = ".attic"
      MEMBER_GLOB = "bb_*.xml"
      MEMBER_PATTERN = /\Abb_.*\.xml\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "bibyeonsa",
        name: "비변사등록 원문 — Records of the Border Defense Command (NIKH)",
        license: "이용허락범위 제한 없음 (data.go.kr dataset 15053636, verified 2026-08-18; " \
                 "KOGL framework) — owner ruling D47-a: attribution, credit the institute",
        license_class: "attribution",
        upstream_url: "https://www.data.go.kr/data/15053636/fileData.do",
        parser_family: "nikh-xml",
        credit: "국사편찬위원회 (National Institute of Korean History), 비변사등록 원문 " \
                "bulk XML via data.go.kr (dataset 15053636)"
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

      # Resolve the CURRENT download URL, then the full ZipFetch
      # choreography into the FLAT workdir (one zip owns the dir;
      # attic at workdir/.attic).
      def fetch(workdir, progress: nil, force: false)
        sha = fetch_dataset(workdir, progress: progress, force: force)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: ["data.go.kr #{DATA_PK}"])
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{MANIFEST.id} fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        member_files(workdir).each do |path|
          id = File.basename(path, ".xml")
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:#{MANIFEST.id}:#{id}",
            path: File.expand_path(path),
            metadata: { "volume" => id }
          )
        end
      end

      # The census: the DTD ships in the zip (recognized); ZipFetch
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
        raise Nabu::DocumentSkipped.new("no text leaves", reason: "member without text content") if volume.leaves.empty?

        build_document(document_ref, volume)
      end

      private

      def fetch_dataset(workdir, progress:, force:)
        url = @resolver.call(DATA_PK)
        fetch = @zip_fetch_factory.call(url: url, dir: workdir,
                                        attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        fetch.sha
      end

      # The zip is flat — member files sit at the workdir root, the
      # attic (a subdir) is invisible to a root-level glob.
      def member_files(workdir)
        Dir.glob(File.join(workdir, MEMBER_GLOB))
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .reject { |path| File.basename(path).match?(MEMBER_PATTERN) }
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
          # No document-level date claim: book fronts carry publication
          # data (the 1959 NIKH print edition), never a dateOccured; the
          # per-entry machine dates ride annotations below, and the
          # level2 year attrs wait for a future extractor revisit.
          metadata: { "volume" => volume.id }
        )
        volume.leaves.each_with_index do |leaf, index|
          document << build_passage(document_ref, leaf, index)
        end
        document
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
