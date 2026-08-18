# frozen_string_literal: true

require_relative "nikh_xml_parser"
require_relative "../zip_fetch"
require_relative "../data_go_kr_fetch"

module Nabu
  module Adapters
    # The sjw adapter (P78-2 — the scale test): 승정원일기, the Daily
    # Records of the Royal Secretariat of Joseon — NIKH bulk XML via
    # data.go.kr dataset 15064218. The library's largest single source
    # by characters (242.25M on the web DB; the 2022-11-03 dump censused
    # at 298 members / 2.44 GB unpacked / members 0.5–19 MB, which is
    # why the nikh-xml family runs a streaming Reader — P78-2a).
    # License: 이용허락범위 제한 없음 (the NIKH family's uniform
    # COEX07 grant, verified 2026-08-18), ruled D47-a → attribution.
    # The query-only website (sjw.history.go.kr) is ARR; the dump is
    # the sanctioned channel.
    #
    # Hanmun only, with the DTD's sjw-specific apparatus: each day
    # (level4) opens with the WEATHER record (front/description/weather
    # — 晴/雨/雪…, one of the longest daily weather series in the world)
    # and a 座目 duty roster whose inline 근무현황 glosses ride in the
    # text verbatim; each article (level5) is a leaf passage carrying
    # the weather via the ancestor chain. Punctuation + named-entity
    # markup in early volumes (survey K-B) flattens like sillok's.
    #
    # Document = one reign-year member (2nd_K00.sjw.y.xml →
    # urn:nabu:sjw:k00 — the filename's reign-year key; the root's own
    # id "SJW-K00" corroborates); passage = one leaf article, urn
    # suffix the leaf's upstream id with the redundant "SJW-" prefix
    # shed and lowercased (k00120130-00000). Language lzh (the kanripo
    # precedent); the volume's 서기 year feeds the timeline via the
    # MetadataDates :structured shape.
    class Sjw < Nabu::Adapter
      LANGUAGE = "lzh"
      DATA_PK = "15064218"
      ATTIC_DIRNAME = ".attic"

      MANIFEST = Nabu::SourceManifest.new(
        id: "sjw",
        name: "승정원일기 — Daily Records of the Royal Secretariat (NIKH)",
        license: "이용허락범위 제한 없음 (data.go.kr dataset 15064218, useScopeCode COEX07, " \
                 "verified 2026-08-18; KOGL framework) — owner ruling D47-a: attribution, " \
                 "credit the institute",
        license_class: "attribution",
        upstream_url: "https://www.data.go.kr/data/15064218/fileData.do",
        parser_family: "nikh-xml",
        credit: "국사편찬위원회 (National Institute of Korean History), 승정원일기 " \
                "bulk XML via data.go.kr (dataset 15064218)"
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

      # One dataset, one zip, one flat workdir: resolve the CURRENT
      # download URL (the atchFileId bumps on upstream replacement),
      # then the normal ZipFetch choreography. ~418 MB compressed /
      # 2.44 GB unpacked — the fetch is the phase's biggest single bite.
      def fetch(workdir, progress: nil, force: false)
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
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: ["data.go.kr #{DATA_PK}"])
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "sjw fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        member_files(workdir).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:sjw:#{member_key(path)}",
            path: File.expand_path(path),
            metadata: { "member" => File.basename(path) }
          )
        end
      end

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

      # 2nd_K00.sjw.y.xml → "k00": the reign-letter + year key, the
      # ".sjw.y" channel suffix shed.
      def member_key(path)
        File.basename(path, ".xml").sub(/\A2nd_/, "").sub(/\.sjw\.y\z/i, "").downcase
      end

      def member_files(workdir)
        Dir.glob(File.join(workdir, "**", "2nd_*.sjw.y.xml"))
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
          title: volume.title || volume.root_id || volume.id,
          metadata: { "member" => volume.id, "root_id" => volume.root_id,
                      "date" => date_envelope(volume) }.compact
        )
        volume.leaves.each_with_index do |leaf, index|
          document << build_passage(document_ref, leaf, index)
        end
        document
      end

      def date_envelope(volume)
        return nil if volume.year.nil?

        { "not_before" => volume.year, "not_after" => volume.year, "raw" => volume.year.to_s }
      end

      def build_passage(document_ref, leaf, index)
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{leaf_key(leaf, index)}",
          language: LANGUAGE,
          text: Nabu::Normalize.nfc(leaf.text),
          sequence: index,
          annotations: {
            "title" => leaf.title, "date" => leaf.date_raw, "weather" => leaf.weather,
            "subject_classes" => (leaf.subject_classes unless leaf.subject_classes.empty?),
            "sources" => (leaf.sources unless leaf.sources.empty?)
          }.compact
        )
      end

      # "SJW-K00120130-00000" → "k00120130-00000" (the redundant source
      # prefix shed, lowercased); an id-less leaf falls back to its
      # 1-based position.
      def leaf_key(leaf, index)
        return index + 1 if leaf.id.nil?

        leaf.id.sub(/\ASJW-/, "").downcase
      end
    end
  end
end
