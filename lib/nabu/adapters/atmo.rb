# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"
require_relative "../url_download"

module Nabu
  module Adapters
    # ATMO — Annotated Turki Manuscripts from the Jarring Collection
    # Online (P107-4, Q97.1; uyghur.linguistics.indiana.edu — Dwyer,
    # Sperberg-McQueen et al.; Kansas/Indiana + Lund UB, Luce-funded):
    # 18 line-by-line TEI P5 transcripts of 18th–20th c. Eastern Turki
    # manuscripts from Lund's Jarring collection. THE Chagatai-lane
    # opener (the "Turki" of these manuscripts is late chg — the
    # declared honest-coarse posture; a finer late-Turki node is a
    # future registry call).
    #
    # == Shape (fixture-verified 2026-09-28)
    #
    # tei:surface[@n = folio side "1a"] → atmo:page → zones (atmo:main
    # = the text body; atmo:top holds endorsements/folio numbers) →
    # tei:line[@n] carrying atmo:lit (Perso-Arabic, THE text) and
    # atmo:lat (Latin transliteration). Passages serve lit with lat as
    # the translit annotation, cited :s<surface>.l<line>; non-main
    # zones ride WITH a zone annotation (marginalia are philology, not
    # noise). Facsimile-only XMLs (73) stay upstream by design — the
    # fetch cone is transcripts + the index sidecar.
    #
    # == License — CC BY-SA 4.0, site-verbatim
    #
    # atmo-licensing.xhtml: "Everything produced by the project
    # Annotated Turki Manuscripts from the Jarring Collection Online is
    # licensed under a Creative Commons Attribution-ShareAlike 4.0
    # International License."
    class Atmo < Nabu::Adapter
      BASE_URL = "https://uyghur.linguistics.indiana.edu/manuscripts"
      INDEX_FILE = "index.xhtml"
      URN_PREFIX = "urn:nabu:atmo:"
      LANGUAGE = "chg"
      TRANSCRIPT_HREF = /href="(Jarring[^"]*\.transcript\.xml)"/
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0",
                 "atmo" => "http://uyghur.linguistics.indiana.edu/2015/ns/0.1" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "atmo",
        name: "ATMO — Annotated Turki Manuscripts from the Jarring Collection Online",
        license: "CC BY-SA 4.0, stated verbatim on the project's licensing page: \"Everything " \
                 "produced by the project Annotated Turki Manuscripts from the Jarring " \
                 "Collection Online is licensed under a Creative Commons Attribution-ShareAlike " \
                 "4.0 International License.\" Credit ATMO (uyghur.linguistics.indiana.edu) and " \
                 "Lund University Library's Jarring collection",
        license_class: "attribution",
        upstream_url: "https://uyghur.linguistics.indiana.edu/manuscripts/index.xhtml",
        parser_family: "atmo-tei"
      )

      def self.manifest = MANIFEST

      # UrlDownload keeps no state file — the probe HEADs the stable
      # upstream URL for liveness only; drift honestly reads unknown.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "index", zip_url: "#{BASE_URL}/index.xhtml", metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "Jarring_*.transcript.xml")).each do |path|
          slug = File.basename(path, ".transcript.xml").downcase.tr("_", "-")
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{slug}",
                                      path: path, metadata: { "file" => File.basename(path) })
        end
      end

      def parse(document_ref)
        xml = Nokogiri::XML(File.read(document_ref.path, encoding: "UTF-8"))
        raise Nabu::ParseError, "#{document_ref.path}: #{xml.errors.first}" if xml.errors.any?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          canonical_path: document_ref.path,
          title: title_for(xml), metadata: { "file" => document_ref.metadata["file"] }
        )
        xml.xpath("//tei:surface", TEI_NS).each_with_index do |surface, surface_index|
          surface_label = surface_label(surface, surface_index)
          add_surface_lines(document, surface, surface_label)
        end
        document
      end

      # 19 GETs: the index (the manifest, kept as a sidecar) + every
      # transcript it lists. Wholesale, idempotent overwrite — at this
      # size a resume/attic apparatus would outweigh the corpus.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        index = Nabu::UrlDownload.new.fetch("#{BASE_URL}/index.xhtml", dir: workdir)
        target = File.join(workdir, INDEX_FILE)
        FileUtils.mv(index, target) unless index == target
        # Commented-out index entries are UNPUBLISHED manuscripts (the
        # 2026-09-28 first sync met Prov_28 inside an HTML comment) —
        # strip comments before scanning, and census what they hide.
        index_html = File.read(target, encoding: "UTF-8")
        live_html = index_html.gsub(/<!--.*?-->/m, "")
        names = live_html.scan(TRANSCRIPT_HREF).flatten.uniq.sort
        hidden = index_html.scan(TRANSCRIPT_HREF).flatten.uniq.sort - names
        raise Nabu::FetchError, "atmo: the index lists no transcript files — reshaped page?" if names.empty?

        names.each_with_index do |name, i|
          progress&.call("ATMO transcript #{i + 1}/#{names.size} (#{name})…\n")
          downloaded = Nabu::UrlDownload.new.fetch("#{BASE_URL}/#{name}", dir: workdir)
          wanted = File.join(workdir, name)
          FileUtils.mv(downloaded, wanted) unless downloaded == wanted
        end
        sha = Digest::SHA256.hexdigest(
          names.map { |n| Digest::SHA256.file(File.join(workdir, n)).hexdigest }.join("\n")
        )
        notes = ["#{names.size} transcripts + index"]
        notes << "#{hidden.size} commented-out (unpublished) index entries skipped" unless hidden.empty?
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: notes)
      end

      private

      def title_for(xml)
        raw = xml.at_xpath("//tei:titleStmt/tei:title", TEI_NS)&.text.to_s
        raw = raw.gsub(/\s+/, " ").strip
        raw.empty? ? nil : Normalize.nfc(raw)
      end

      # Surface @n is the folio side ("1a"); anything unruly falls back
      # to position.
      def surface_label(surface, index)
        n = surface["n"].to_s.strip
        n.match?(/\A[0-9]+[a-z]?\z/) ? n : (index + 1).to_s
      end

      def add_surface_lines(document, surface, surface_label)
        surface.xpath(".//tei:line", TEI_NS).each_with_index do |line, line_index|
          lit = layer_text(line, "atmo:lit")
          next if lit.empty?

          annotations = {}
          lat = layer_text(line, "atmo:lat")
          annotations["translit"] = lat unless lat.empty?
          zone = line.at_xpath("ancestor::tei:zone", TEI_NS)&.[]("type").to_s
          annotations["zone"] = zone unless zone.empty?
          label = line["n"].to_s.strip
          label = (line_index + 1).to_s unless label.match?(/\A\d+\z/)
          document << Nabu::Passage.new(
            urn: unique_urn(document, "#{document.urn}:s#{surface_label}.l#{label}"),
            language: LANGUAGE, text: Normalize.nfc(lit),
            sequence: document.passages.size + 1, annotations: annotations
          )
        end
      end

      def layer_text(line, xpath)
        line.at_xpath(xpath, TEI_NS)&.text.to_s.gsub(/\s+/, " ").strip
      end

      # Line numbers restart per zone within a surface — collisions take
      # the house b2 suffix.
      def unique_urn(document, candidate)
        return candidate if document.passages.none? { |p| p.urn == candidate }

        suffix = 2
        suffix += 1 while document.passages.any? { |p| p.urn == "#{candidate}b#{suffix}" }
        "#{candidate}b#{suffix}"
      end
    end
  end
end
