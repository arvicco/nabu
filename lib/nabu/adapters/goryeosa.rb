# frozen_string_literal: true

require_relative "nikh_xml_parser"
require_relative "../zip_fetch"
require_relative "../data_go_kr_fetch"

module Nabu
  module Adapters
    # The goryeosa adapter (P78-3): 고려사 원문 — the History of Goryeo
    # (1451, 정인지 et al.: the official Joseon-compiled history of the
    # Goryeo dynasty, 918–1392) in the original hanmun, NIKH's bulk XML
    # via data.go.kr — dataset 15053637, one zip (5.3 MB / 50 MB
    # unpacked): 138 members kr_000..kr_137 + history.dtd ver 1.4 (NO
    # "2nd_" filename prefix, unlike sillok). License: 이용허락범위
    # 제한 없음 per the dataset page (the NIKH family answer, verified
    # 2026-08-18), ruled D47-a → attribution, credit the institute.
    #
    # HANMUN-ONLY HONESTY: the dump carries the 원문 only — the modern
    # Korean translation layer is NOT in it, never fetched. The editorial
    # section headline (modern Korean, NIKH apparatus, part of the
    # licensed dump) rides as annotation title, never as passage text.
    # Language: lzh (the kanripo/sillok precedent).
    #
    # CENSUS FACTS (2026-08-18): members root at level1 (世家/志/表/列傳
    # divisions, one 卷 per file) except kr_000 — the ONE <item>-rooted
    # front-matter member (four sibling level1 sections, ids kr_$s01..
    # $s04, the upstream $ riding urns verbatim). Leaves sit at level4
    # or level5 depending on the division. NO 서기 calendar line exists
    # anywhere: dated fronts lead with the lunar 음 machine date
    # (양 following) — leaf-grain only, so documents claim no date;
    # the 음/양 attrs ride annotations raw. 列傳 members carry no dates
    # at all.
    class Goryeosa < Nabu::Adapter
      LANGUAGE = "lzh"

      # The one data.go.kr dataset; the atchFileId behind it bumps on
      # every upstream replacement — resolution is the contract.
      DATA_PK = "15053637"

      ATTIC_DIRNAME = ".attic"
      MEMBER_GLOB = "kr_*.xml"
      MEMBER_PATTERN = /\Akr_.*\.xml\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "goryeosa",
        name: "고려사 원문 — History of Goryeo (NIKH)",
        license: "이용허락범위 제한 없음 (data.go.kr dataset 15053637, verified 2026-08-18; " \
                 "KOGL framework) — owner ruling D47-a: attribution, credit the institute",
        license_class: "attribution",
        upstream_url: "https://www.data.go.kr/data/15053637/fileData.do",
        parser_family: "nikh-xml",
        credit: "국사편찬위원회 (National Institute of Korean History), 고려사 원문 " \
                "bulk XML via data.go.kr (dataset 15053637)"
      )

      def self.manifest
        MANIFEST
      end

      # +resolver+/+zip_fetch_factory+ exist for the tests (no network in
      # the suite, ever); no-arg construction stays the registry contract.
      # P79-2: the data.go.kr resolver posture (see Sillok) — resolve the
      # CURRENT url at probe time, drift on URL identity.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "data.go.kr #{DATA_PK}", zip_url: nil, metadata_url: nil,
          state_subdir: "", resolver: -> { Nabu::DataGoKrFetch.resolve(DATA_PK) }
        )]
      end

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
          # No document-level date claim: the census found no dateOccured
          # on any volume front (no 서기 line exists in the zip at all);
          # the leaf-grain 음/양 machine dates ride annotations below.
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
