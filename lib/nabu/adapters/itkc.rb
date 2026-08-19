# frozen_string_literal: true

require_relative "itkc_xml_parser"
require_relative "../zip_fetch"
require_relative "../data_go_kr_fetch"

module Nabu
  module Adapters
    # The itkc adapter (P78-7): 한국고전번역원 (Institute for the
    # Translation of Korean Classics) classical originals in hanmun —
    # the OPEN-LICENSED slice of the 한국고전종합DB, one complete work
    # per data.go.kr dataset (the P78-7 scout's channel map,
    # 2026-08-18). Every dataset page carries 이용허락범위 제한 없음
    # (the KOGL-framework grant), ruled D47-a → attribution; the ITKC
    # website itself is all-rights-reserved, so ONLY this channel is
    # ingestible, and the ITKC OpenAPI serves search snippets, not text
    # (census use only).
    #
    # HONEST COVERAGE: the GO family counts 257 works upstream; 17 are
    # registered here (~7% of works — but they include anchors like
    # 국조보감 and 신증동국여지승람). The rest need a 공공데이터
    # 제공신청 (the owner letter path — ITKC demonstrably publishes in
    # exactly this format, 2025-01-22 batch). The munjip (문집총간)
    # stays parked per D47-c: its portal presence is a title list plus
    # stragglers, not a corpus.
    #
    # Document = one 권차 fascicle file (urn:nabu:itkc:go-1295a-0010 —
    # the upstream id, ITKC_ prefix shed, lowercased, _ → -); passage =
    # one type="최종정보" article. The work's 서지 sidecar attaches its
    # record to every fascicle document: hanja title, author, and the
    # 원문간행년 ORIGINAL print year feeding the timeline via the
    # MetadataDates :structured shape. Language lzh (upstream's 언어
    # says "coc" — ITKC-internal, not ISO; the text is hanmun).
    class Itkc < Nabu::Adapter
      LANGUAGE = "lzh"
      ATTIC_DIRNAME = ".attic"

      # Fascicle files carry the _NNNN 권차 suffix; the suffix-less
      # sibling is the work's 서지 sidecar (metadata, never a document).
      FASCICLE_RE = /\AITKC_[A-Z]{2}_.+_\d{4}\.xml\z/

      # The 17 scouted datasets (verified 제한 없음 2026-08-18; each
      # subdir is the pk — upstream-stable, unambiguous). New ITKC
      # registrations arrive in waves — re-scan the portal search when
      # the letter path bears fruit, and append here.
      DATASETS = [
        { pk: "15022432", work: "고운당필기" },
        { pk: "15141442", work: "국조보감" },
        { pk: "15141448", work: "임하필기" },
        { pk: "15141450", work: "전율통보" },
        { pk: "15141472", work: "신증동국여지승람" },
        { pk: "15141473", work: "동국여지지" },
        { pk: "15141474", work: "여지도서" },
        { pk: "15141476", work: "여도비지" },
        { pk: "15141477", work: "대동지지" },
        { pk: "15141479", work: "여재촬요" },
        { pk: "15141452", work: "열성지장통기" },
        { pk: "15141458", work: "세자행적" },
        { pk: "15141460", work: "종반행적" },
        { pk: "15141464", work: "국조인물고" },
        { pk: "15141467", work: "인물고" },
        { pk: "15141469", work: "영남인물고" },
        { pk: "15141470", work: "동현주의" }
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "itkc",
        name: "한국고전번역원 고전원문·고전총간 — ITKC classical originals (open datasets)",
        license: "이용허락범위 제한 없음 (data.go.kr, per-dataset pages verified 2026-08-18; " \
                 "KOGL framework) — owner ruling D47-a: attribution, credit the institute. " \
                 "The itkc.or.kr site itself is ARR; only the portal datasets carry the grant",
        license_class: "attribution",
        upstream_url: "https://www.data.go.kr/data/15022432/fileData.do",
        parser_family: "itkc-xml",
        credit: "한국고전번역원 (Institute for the Translation of Korean Classics), " \
                "고전원문/한국고전총간 bulk XML via data.go.kr (17 datasets)"
      )

      def self.manifest
        MANIFEST
      end

      def initialize(resolver: Nabu::DataGoKrFetch.method(:resolve),
                     zip_fetch_factory: Nabu::ZipFetch.method(:new))
        super()
        @resolver = resolver
        @zip_fetch_factory = zip_fetch_factory
      end

      # Seventeen small zips, each into its pk-named subdir with its own
      # ZipFetch state + attic (one zip owns one dir — the sillok rule).
      def fetch(workdir, progress: nil, force: false)
        shas = DATASETS.map do |dataset|
          fetch_dataset(workdir, dataset, progress: progress, force: force)
        end
        Nabu::FetchReport.new(sha: shas.join("+"), fetched_at: Time.now,
                              notes: DATASETS.map { |dataset| "data.go.kr #{dataset[:pk]} #{dataset[:work]}" })
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "itkc fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        fascicle_files(workdir).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:itkc:#{urn_key(fascicle_id(path))}",
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
        fascicle = parser.parse_fascicle(document_ref.path)
        raise Nabu::DocumentSkipped.new("no articles", reason: "fascicle without 최종정보 articles") if
          fascicle.articles.empty?

        build_document(document_ref, fascicle, work_record(document_ref.path))
      end

      private

      def fetch_dataset(workdir, dataset, progress:, force:)
        url = @resolver.call(dataset[:pk])
        dir = File.join(workdir, dataset[:pk])
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

      def fascicle_files(workdir)
        Dir.glob(File.join(workdir, "**", "ITKC_*.xml"))
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .select { |path| File.basename(path).match?(FASCICLE_RE) }
           .sort
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .reject { |path| File.basename(path).start_with?(".") }
           .reject { |path| File.basename(path) =~ /\AITKC_.*\.xml\z/ }
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      def fascicle_id(path)
        File.basename(path, ".xml")
      end

      # "ITKC_GO_1295A_0010" → "go-1295a-0010"
      def urn_key(upstream_id)
        upstream_id.sub(/\AITKC_/, "").downcase.tr("_", "-")
      end

      def parser
        @parser ||= ItkcXmlParser.new
      end

      # The sidecar sits beside the fascicle (same prefix, no 권차
      # suffix). One memoized record per sidecar path; a missing or
      # damaged sidecar attaches nothing — the fascicle still parses.
      def work_record(fascicle_path)
        sidecar = File.join(File.dirname(fascicle_path),
                            "#{fascicle_id(fascicle_path).sub(/_\d{4}\z/, '')}.xml")
        return nil unless File.file?(sidecar)

        @work_records ||= {}
        @work_records[sidecar] ||= parser.parse_work(sidecar)
      rescue Nabu::ParseError
        nil
      end

      def build_document(document_ref, fascicle, work)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: fascicle.title || fascicle.id,
          metadata: {
            "member" => fascicle.id,
            "work_title" => work&.title_hanja, "work_title_hangul" => work&.title_hangul,
            "author" => work&.author_hanja, "author_hangul" => work&.author_hangul,
            "date" => date_envelope(work)
          }.compact
        )
        fascicle.articles.each_with_index do |article, index|
          document << build_passage(document_ref, article, index)
        end
        document
      end

      # The 원문간행년 original print year (never the modern edition's).
      def date_envelope(work)
        year = work&.print_year
        return nil if year.nil?

        { "not_before" => year, "not_after" => year, "raw" => year.to_s }
      end

      def build_passage(document_ref, article, index)
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{article.id ? urn_key(article.id) : index + 1}",
          language: LANGUAGE,
          text: Nabu::Normalize.nfc(article.text),
          sequence: index,
          annotations: {
            "title" => article.title, "dci" => article.dci,
            "author" => article.author_hanja,
            "genre_classes" => (article.genre_classes unless article.genre_classes.empty?),
            "translation_ref" => article.translation_ref
          }.compact
        )
      end
    end
  end
end
