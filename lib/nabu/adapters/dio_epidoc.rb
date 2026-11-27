# frozen_string_literal: true

require_relative "dio_epidoc_parser"
require_relative "../fetch/zip_fetch"

module Nabu
  module Adapters
    # DIO EpiDoc — the structured-data dumps of Die Deutschen Inschriften
    # (DI, the interacademy edition of the Latin and German inscriptions of
    # the Middle Ages and the early modern period up to 1650; Akademie der
    # Wissenschaften und der Literatur Mainz — Digitale Akademie, on its
    # Epigraf platform): the three volumes published as "Original data"
    # EpiDoc — DI 7 (Braunschweig: Kloster Riddagshausen and the
    # incorporated villages), DI 77 (Greifswald) and DI 102 (Stralsund).
    # A thin composition of the DioEpidocParser family with three
    # sha256-pinned ZipFetch downloads.
    #
    # == License (first-hand, 2026-11-27)
    #
    # Every one of the 978 article files: <licence
    # target="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0 for
    # the text</licence> + <p>Please note that linked images may be
    # published under more restricted licenses.</p>. The dumps page: "Where
    # possible, data is published under CC BY 4.0 … Images have their own
    # copyright and are only contained as links." The EpiDoc carries no
    # image links at all, so everything fetched is the CC BY 4.0 text →
    # attribution. Citation (the page's own): "The German Inscriptions
    # (2025). Structured Data Dumps (Version 1.0) [Data set]. Epigraf."
    #
    # == Grains (enumerated 2026-11-27 against the dumps page)
    #
    #   di<N>_epidoc.zip   one per volume (DI 7: 73, DI 77: 448, DI 102:
    #                      457 article files, exactly the page's "Articles"
    #                      column) — ACCEPTED: unpacked flat into
    #                      canonical/dio-epidoc/di<N>/, one article = one
    #                      document (urn:nabu:dio-epidoc:di7-001).
    #   di<N>_ttl.zip, di<N>_rdf_xml.zip, di<N>_jsonld.zip — the SAME
    #                      articles as RDF triples ("All archives contain the
    #                      same set of triples"): title, date, location, object
    #                      type, a flattened transcription string — a lossy
    #                      projection of the EpiDoc. REJECTED, never fetched; a
    #                      .ttl/.rdf/.jsonld file in the workdir is skipped by
    #                      rule (one specimen each pinned in the fixtures).
    #   epigraf-public-cgif-001.zip — the 31,197 legacy DIO-portal articles
    #                      as Culture Graph Interchange Format TTL: title,
    #                      keywords, year span, the volume's AREA as a Wikidata
    #                      entity, image URLs — no transcriptions. REJECTED,
    #                      never fetched (no text; a catalogue, not an edition).
    #
    # == Count reconciliation
    #
    # Upstream's own advertised count: the dumps page's Articles column,
    # 73 + 448 + 457 = 978. The fixture-time census through this adapter
    # (the three real zips, 2026-11-27): 978 article files → 978 documents
    # / 2,699 passages (every textpart of every article: DI 7 73 / 134,
    # DI 77 448 / 1,325, DI 102 457 / 1,240), 0 text-less, 0 errored —
    # accepted + skipped = 978. FIRST-SYNC RECONCILIATION: pending —
    # recorded here once the first real sync lands.
    #
    # == fetch / sync policy
    #
    # Three GETs against the page's own download links (opaque file ids;
    # each response's Content-Disposition names di<N>_epidoc.zip — read
    # 2026-11-27), one ZipFetch dir per volume, each body checked against
    # its sha256 pin BETWEEN download and any tree mutation; the breaker
    # sees the combined doomed set; Last-Modified replays as
    # If-Modified-Since (the server answers 304 — verified). The unpacked
    # zips ARE upstream's tree — a plain (non-git) tree whose every byte the
    # canonical identity hashes — so nothing is materialized BESIDE it and
    # materialized_paths stays empty (the declared-materializations rule
    # acts inside git repos only; DerivationFingerprint.identity_tokens).
    # Version 1.0 of 2025-05-18; a new version or a new volume on the page
    # is an owner re-pin of VOLUMES. sync_policy manual.
    class DioEpidoc < Nabu::Adapter
      PAGE_URL = "https://epigraf.inschriften.net/pages/dumps"
      DOWNLOAD_BASE = "https://epigraf.inschriften.net/files/download/"

      CITATION = "The German Inscriptions (2025). Structured Data Dumps (Version 1.0) [Data set]. " \
                 "Epigraf. https://epigraf.inschriften.net/pages/dumps — Die Deutschen Inschriften " \
                 "(DI 7 Braunschweig, DI 77 Greifswald, DI 102 Stralsund), Akademie der " \
                 "Wissenschaften und der Literatur Mainz — CC BY 4.0"

      LICENSE = "CC BY 4.0 — every article's <licence target=\"https://creativecommons.org/licenses/by/4.0/\">" \
                "CC BY 4.0 for the text</licence>, beside \"Please note that linked images may be " \
                "published under more restricted licenses.\" (the EpiDoc links no images); the dumps " \
                "page: \"Where possible, data is published under CC BY 4.0 … Images have their own " \
                "copyright and are only contained as links.\" (read 2026-11-27)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dio-epidoc",
        name: "DIO EpiDoc — Die Deutschen Inschriften, Epigraf volume dumps (DI 7, 77, 102)",
        license: LICENSE,
        license_class: "attribution",
        upstream_url: PAGE_URL,
        parser_family: "dio-epidoc",
        credit: CITATION
      )

      # volume dir => the page's EpiDoc link, the body's sha256 (the
      # 2026-11-27 downloads) and the page's article count.
      VOLUMES = {
        "di7" => { url: "#{DOWNLOAD_BASE}77651", file: "di7_epidoc.zip", articles: 73,
                   sha256: "d93e775d3d4b28973489d40af8a52ea6ca992b97a2ce5a8cbb981dcbe321e8fc" },
        "di77" => { url: "#{DOWNLOAD_BASE}77647", file: "di77_epidoc.zip", articles: 448,
                    sha256: "8044fa49fe643370b07d4d6276b96c5b2d97b989a9d7d49ec77044455c4625ea" },
        "di102" => { url: "#{DOWNLOAD_BASE}77661", file: "di102_epidoc.zip", articles: 457,
                     sha256: "f06eb98219f4e46c3e507603183042302d711b05c7bf7067bf12df95a9475e61" }
      }.freeze

      # The rejected RDF serializations (class note).
      RDF_EXTENSIONS = %w[.ttl .rdf .jsonld].freeze

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        VOLUMES.map do |name, volume|
          Nabu::Adapter::HttpProbeTarget.new(
            label: volume[:file], zip_url: volume[:url], metadata_url: nil,
            state_subdir: name, state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      # The unpacked zips are upstream's own tree (class note).
      def self.materialized_paths = []

      # +pins+ overrides the volume sha256 pins (tests; a future re-pin).
      def initialize(pins: VOLUMES.transform_values { |volume| volume[:sha256] })
        super()
        @pins = pins
      end

      # One ref per citable article file of a known volume, attic
      # excluded, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        articles(workdir).select { |_volume, path| DioEpidocParser.citable?(path) }.map do |volume, path|
          Nabu::DocumentRef.new(source_id: manifest.id, id: DioEpidocParser.urn_for(path, volume: volume),
                                path: path, metadata: { "volume" => volume })
        end.sort_by(&:id).each(&block)
      end

      # Text-less articles and the RDF serializations are skipped by rule;
      # any other data file (.xml outside the article shape or the volume
      # dirs) is unrecognized (loud). Fetch state and the attic are
      # infrastructure, never census.
      def discovery_skips(workdir)
        textless = articles(workdir).reject { |_volume, path| DioEpidocParser.citable?(path) }
        others = files(workdir) - articles(workdir).map(&:last)
        rdf, unknown = others.partition { |path| RDF_EXTENSIONS.include?(File.extname(path)) }
        notes = []
        notes << "#{textless.size} text-less article(s) (no citable textpart) skipped by rule" if textless.any?
        notes << "#{rdf.size} RDF serialization file(s) (.ttl/.rdf/.jsonld) skipped by rule" if rdf.any?
        root = File.join(File.expand_path(workdir), "")
        notes.concat(unknown.map { |path| "#{path.delete_prefix(root)}: not an article" })
        DiscoverySkips.new(skipped_by_rule: textless.size + rdf.size, unrecognized: unknown.size, notes: notes)
      end

      def parse(document_ref)
        DioEpidocParser.new.parse(document_ref.path, urn: document_ref.id, volume: document_ref.metadata["volume"])
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify each pin + unpack, phases hand-driven so every
      # pin check and the breaker run BETWEEN download and any tree
      # mutation; a 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        zips = VOLUMES.to_h do |name, volume|
          [name, Nabu::ZipFetch.new(url: volume[:url], dir: File.join(workdir, name),
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME, name), progress: progress)]
        end
        begin
          zips.each { |name, zip| prepare_and_verify!(name, zip) }
          guard_mass_deletion!(workdir, zips.values.flat_map(&:doomed_paths), force: force)
          zips.each_value(&:complete!)
        ensure
          zips.each_value(&:cleanup!)
        end
        Nabu::FetchReport.new(sha: zips.values.last.sha, fetched_at: Time.now, notes: fetch_notes(workdir, zips),
                              repos: zips.to_h { |name, zip| [VOLUMES.dig(name, :url), zip.sha] })
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "dio-epidoc fetch failed into #{workdir}: #{e.message}"
      end

      private

      # [[volume, absolute path]] for every article-shaped .xml in a volume dir.
      def articles(workdir)
        VOLUMES.keys.flat_map do |volume|
          Dir.glob(File.join(workdir, volume, "*.xml"))
             .select { |path| DioEpidocParser::FILENAME.match?(File.basename(path)) }
             .map { |path| [volume, File.expand_path(path)] }
        end
      end

      DATA_EXTENSIONS = (%w[.xml] + RDF_EXTENSIONS).freeze
      private_constant :DATA_EXTENSIONS

      # Every data-shaped (.xml/.ttl/.rdf/.jsonld) non-dot file under the
      # workdir outside the attic.
      def files(workdir)
        root = File.expand_path(workdir)
        Dir.glob(File.join(root, "**", "*")).select do |path|
          relative = path.delete_prefix(File.join(root, "")).split(File::SEPARATOR)
          File.file?(path) && DATA_EXTENSIONS.include?(File.extname(path)) &&
            relative.none? { |part| part.start_with?(".") }
        end
      end

      def prepare_and_verify!(name, zip)
        zip.prepare!
        pin = @pins.fetch(name)
        return if zip.not_modified? || zip.sha == pin

        raise Nabu::FetchError,
              "dio-epidoc: #{VOLUMES.dig(name, :file)} misses its sha256 pin (expected #{pin}, got " \
              "#{zip.sha}) — a re-released dump; read #{PAGE_URL} (version, date, article count) and " \
              "re-pin VOLUMES only after reading it"
      end

      # "di7=<sha12> (73 articles) …" — the honest per-volume record;
      # attic activity rides along.
      def fetch_notes(workdir, zips)
        notes = zips.map do |name, zip|
          count = Dir.glob(File.join(workdir, name, "*.xml")).size
          state = zip.not_modified? ? ", not modified" : ""
          "#{name}=#{zip.sha.to_s[0, 12]} (#{count} articles#{state})"
        end
        [notes.join(" "), attic_notes(zips.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
