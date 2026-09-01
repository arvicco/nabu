# frozen_string_literal: true

require_relative "obi_txt_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # OBI — A Structured Corpus of Old Burmese Stone Inscriptions (P92-3;
    # Zenodo record 4321314): 1,121 per-face files of Bagan-period
    # epigraphy (from the Archaeological Directorate's Ancient Burmese
    # Inscriptions, Thein Tun's Recently Found Inscriptions, and the Bagan
    # Epigraphic Database — Frasch), Myanmar-script Unicode with paired
    # transliteration. The mainland gap DHARMA doesn't fill: obr — the
    # ancestor of Burmese, from the Myazedi era on.
    #
    # == Identity
    #
    # One file = one FACE: OBI_Vol7_No3a__ob_p6.txt →
    # urn:nabu:obi-burmese:vol7:3a:ob (face-less files — the
    # three-underscore shape — mint vol7:36). Passage :<line n>.
    #
    # == License
    #
    # CC BY 4.0, verified on the Zenodo record (API read 2026-09-01) →
    # class attribution.
    #
    # == fetch
    #
    # Seven DOI-pinned volume zips via ZipFetch, one per vol<n>/ subdir
    # (each keeps its own state/attic; the deposit is versioned and
    # stable, so conditional re-syncs are cheap). The source-material zip
    # (scans) and the introduction PDF are deliberately not fetched; the
    # transliteration-system TSV is documentation, read upstream.
    class ObiBurmese < Nabu::Adapter
      SLUG = "obi-burmese"
      LANGUAGE = "obr"
      RECORD_URL = "https://zenodo.org/records/4321314"

      VOLUMES = (1..7)

      FILENAME_RE = /\AOBI_Vol(\d+)_No(\w+?)__(ob|re)?_p(\d+)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "OBI — Structured Corpus of Old Burmese Stone Inscriptions",
        license: "CC BY 4.0 (Zenodo record 4321314, verified 2026-09-01)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "obi-txt",
        credit: "A Structured Corpus of Old Burmese Stone Inscriptions (Zenodo " \
                "4321314; after the Archaeological Directorate's Ancient Burmese " \
                "Inscriptions, Thein Tun, and the Bagan Epigraphic Database)."
      )

      def self.manifest
        MANIFEST
      end

      # HTTP artifacts, not git: HEAD each volume zip for liveness; each
      # vol subdir's ZipFetch state feeds the URL-identity lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        VOLUMES.map do |volume|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "OBI_Corpus_Vol#{volume}.zip",
            zip_url: "https://zenodo.org/api/records/4321314/files/OBI_Corpus_Vol#{volume}.zip/content",
            metadata_url: nil, state_subdir: "vol#{volume}",
            state_file: Nabu::ZipFetch::STATE_FILE
          )
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        txt_paths(workdir).each do |path|
          urn = urn_for(path) or next
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: urn, path: File.expand_path(path),
            metadata: { "filename" => File.basename(path) }
          )
        end
      end

      def discovery_skips(workdir)
        unrecognized = txt_paths(workdir).reject { |path| urn_for(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: 0, unrecognized: unrecognized.size,
          notes: unrecognized.map { |path| "#{File.basename(path)}: filename outside the OBI shape" }
        )
      end

      def parse(document_ref)
        record = ObiTxtParser.parse(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: record.title || record.ref || document_ref.metadata["filename"],
          metadata: {
            "ref" => record.ref, "title_translit" => record.title_translit,
            "source" => record.source, "date" => record.date,
            "donor" => record.donor, "face" => record.face,
            "sections" => (record.sections.empty? ? nil : record.sections)
          }.compact
        )
        record.lines.each_with_index do |line, index|
          annotations = line.translit ? { "translit" => line.translit } : {}
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line.n}", language: LANGUAGE,
            text: line.text, sequence: index, annotations: annotations
          )
        end
        document
      end

      # Seven volume zips, each into its own subdir (own state + attic).
      def fetch(workdir, progress: nil, force: false)
        shas = VOLUMES.map do |volume|
          dir = File.join(workdir, "vol#{volume}")
          fetch = Nabu::ZipFetch.new(
            url: volume_url(volume), dir: dir,
            attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
          )
          begin
            fetch.prepare!
            guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
            fetch.complete!
          ensure
            fetch.cleanup!
          end
          fetch.sha
        end
        Nabu::FetchReport.new(
          sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
          notes: "#{VOLUMES.count} volume zips"
        )
      rescue Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "obi-burmese fetch failed into #{workdir}: #{e.message}"
      end

      private

      def volume_url(volume)
        "https://zenodo.org/api/records/4321314/files/OBI_Corpus_Vol#{volume}.zip/content"
      end

      def txt_paths(workdir)
        Dir.glob(File.join(workdir, "vol*", "**", "*.txt"))
      end

      def urn_for(path)
        m = File.basename(path, ".txt").match(FILENAME_RE) or return nil
        ["urn:nabu:#{SLUG}:vol#{m[1]}:#{m[2]}", m[3]].compact.join(":")
      end
    end
  end
end
