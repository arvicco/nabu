# frozen_string_literal: true

require_relative "freising_tei_parser"

module Nabu
  module Adapters
    # The Freising Manuscripts adapter (P13-11): Brižinski spomeniki /
    # Monumenta Frisingensia — the oldest Slovene (and oldest Latin-script
    # Slavic) text, ca. 972–1039 CE, from the eZISS electronic critical
    # edition (ed. Matija Ogrin, TEI encoding Tomaž Erjavec; ZRC SAZU / IJS,
    # edition 1.0, 2007). TEI P4, parser family freising-tei.
    #
    # == License — the ND posture (owner ruling 2026-07-11)
    #
    # CC BY-ND 2.5 SI. Verbatim, the edition's own bs.xml <availability>:
    # "Avtorske pravice za besedilo te izdaje ureja licenca Creative Commons
    # Priznanje avtorstva-Brez predelav 2.5 Slovenija"
    # (creativecommons.org/licenses/by-nd/2.5/si/). The English HTML page's
    # "Share Alike" label contradicts this; the machine-readable TEI header
    # governs. ND = private transformation lawful, distributing adaptations
    # not → license_class research_private: default-excluded from the MCP
    # surface (per-call include_restricted opt-in), and a permission-point
    # entry in improvements §4.3 gates any future external-access feature.
    # The audio (© ZRC SAZU/RTVS) and facsimiles (© BSB München) are
    # separately copyrighted and excluded: fetch takes bs-text.zip only.
    #
    # == Identity (FROZEN minting) and the sibling design (owner-approved)
    #
    # Document = (monument × layer). The CRITICAL transcription is the work
    # itself — the readable scholarly layer: urn:nabu:freising:bs<n>
    # (bs1..bs3). Every other layer rides as a line-aligned SIBLING document
    # (the ORACC -en precedent): bs<n>-dt (diplomatic witness), bs<n>-pt
    # (phonetic reconstruction), bs<n>-tr-<slv|eng|ger|ita|lat|pol> (the six
    # translations). Passage = manuscript line, urn suffix :<line n> —
    # upstream keeps @n/@id identical across layers, so suffix-equality
    # alignment (Query::Parallel) works with no stored links. The display
    # citation rides in annotations: "BS I, fol. 78r, l. 1".
    #
    # == Languages
    #
    # Transcription layers + the modern-Slovene translation: "sl" (owner
    # call; anachronistic for ~1000 CE but the lineal code, matching the
    # goo300k/IMP axis and its ſ→s search fold). Other translations use the
    # repo's established codes where they exist (eng, lat — deviating from
    # upstream's id only where the repo precedent demands: users type
    # --parallel eng) and upstream's TEI ids otherwise (ger, ita, pol).
    # Line-level @lang overrides per passage (the Latin tail of BS I:
    # bs1:37-39 carry language lat inside the sl document).
    class Freising < Nabu::Adapter
      ZIP_URL = "https://nl.ijs.si/e-zrc/bs-text.zip"

      MANIFEST = Nabu::SourceManifest.new(
        id: "freising",
        name: "Freising Manuscripts / Brižinski spomeniki (eZISS, ZRC SAZU)",
        license: "CC BY-ND 2.5 SI (verbatim bs.xml <availability>: \"Creative Commons " \
                 "Priznanje avtorstva-Brez predelav 2.5 Slovenija\", " \
                 "creativecommons.org/licenses/by-nd/2.5/si/ — NoDerivs: local research " \
                 "ingest only, never redistributed; see improvements §4.3)",
        license_class: "research_private",
        upstream_url: ZIP_URL,
        parser_family: "freising-tei"
      )

      Layer = Data.define(:file, :suffix, :language, :label)
      private_constant :Layer

      # Ordered: the critical layer (suffix nil) is the primary document.
      LAYERS = [
        Layer.new(file: "bsCT", suffix: nil, language: "sl", label: "critical transcription"),
        Layer.new(file: "bsDT", suffix: "dt", language: "sl", label: "diplomatic transcription"),
        Layer.new(file: "bsPT", suffix: "pt", language: "sl", label: "phonetic transcription"),
        Layer.new(file: "bsTR-slv", suffix: "tr-slv", language: "sl", label: "modern Slovene translation"),
        Layer.new(file: "bsTR-eng", suffix: "tr-eng", language: "eng", label: "English translation"),
        Layer.new(file: "bsTR-ger", suffix: "tr-ger", language: "ger", label: "German translation"),
        Layer.new(file: "bsTR-ita", suffix: "tr-ita", language: "ita", label: "Italian translation"),
        Layer.new(file: "bsTR-lat", suffix: "tr-lat", language: "lat", label: "Latin translation"),
        Layer.new(file: "bsTR-pol", suffix: "tr-pol", language: "pol", label: "Polish translation")
      ].freeze

      ROMAN = { 1 => "I", 2 => "II", 3 => "III" }.freeze
      private_constant :ROMAN

      # Upstream line-level @lang ids (langUsage) → our codes.
      LINE_LANGS = { "slv" => "sl", "lat" => "lat", "eng" => "eng", "ger" => "ger",
                     "ita" => "ita", "pol" => "pol", "ocs" => "sl" }.freeze
      private_constant :LINE_LANGS

      def self.manifest
        MANIFEST
      end

      # The probe HEADs the zip; the license lives in the TEI header inside
      # the bundle (and on the landing page), not at a probe-shaped endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: File.basename(ZIP_URL), zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One ref per (monument × layer file present), sorted by urn. The
      # master bs.xml anchors the tei dir (fixture: tei/bs.xml; canonical:
      # bs/tei/bs.xml from the zip's single top dir). A workdir without it
      # yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        layer = layer_for(document_ref.metadata.fetch("layer"))
        mon = Integer(document_ref.metadata.fetch("mon"), 10)
        monument = parser_for(document_ref.path).monuments(document_ref.path)
                                                .find { |m| m.n == mon }
        raise ParseError, "#{document_ref.path}: monument #{mon} vanished between discover and parse" if monument.nil?

        document = Nabu::Document.new(
          urn: document_ref.id, language: layer.language, title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: document_ref.metadata.slice("mon", "layer")
        )
        monument.lines.each { |line| document << passage(document_ref, layer, mon, line, document.size) }
        raise ParseError, "#{document_ref.path}: monument #{mon} has no non-empty lines" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # ONE text-only zip via ZipFetch (conditional GET, sha256 pin, staging,
      # attic + mass-deletion guard) — bs.zip (audio) and bs-facs.zip
      # (facsimiles) are never fetched: separately copyrighted, out of scope.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "freising fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        master = Dir.glob(File.join(workdir, "**", "tei", "bs.xml")).min
        return [] if master.nil?

        tei_dir = File.dirname(master)
        LAYERS.flat_map { |layer| layer_refs(layer, tei_dir) }.sort_by(&:id)
      end

      def layer_refs(layer, tei_dir)
        path = File.join(tei_dir, "#{layer.file}.xml")
        return [] unless File.file?(path)

        parser_for(path).monuments(path).map do |monument|
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: urn(monument.n, layer),
            path: File.expand_path(path),
            metadata: { "mon" => monument.n.to_s, "layer" => layer.file,
                        "language" => layer.language, "title" => title(monument.n, layer) }
          )
        end
      end

      def urn(mon, layer)
        ["urn:nabu:freising:bs#{mon}", layer.suffix].compact.join("-")
      end

      def title(mon, layer)
        "Brižinski spomeniki #{ROMAN.fetch(mon)} — #{layer.label}"
      end

      def passage(document_ref, layer, mon, line, sequence)
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{line.n}",
          language: LINE_LANGS.fetch(line.lang, layer.language),
          text: line.text, sequence: sequence,
          annotations: {
            "citation" => "BS #{ROMAN.fetch(mon)}, fol. #{line.folio}, l. #{line.n}",
            "folio" => line.folio, "tei_id" => line.tei_id
          }
        )
      end

      def layer_for(file)
        LAYERS.find { |layer| layer.file == file } or
          raise ParseError, "unknown freising layer #{file.inspect}"
      end

      # One parser per tei dir, its ZRCola glyph map read from the sibling
      # master bs.xml once and memoized (discover touches 9 files).
      def parser_for(layer_path)
        master = File.join(File.dirname(layer_path), "bs.xml")
        (@parsers ||= {})[master] ||= FreisingTeiParser.new(
          glyph_map: FreisingTeiParser.glyph_map(master)
        )
      end
    end
  end
end
