# frozen_string_literal: true

require_relative "imp_tei_parser"

module Nabu
  module Adapters
    # The goo300k adapter (P13-9): the reference corpus of historical
    # Slovene (Erjavec, Jožef Stefan Institute; CLARIN.SI hdl 11356/1025) —
    # 89 texts / 293,919 words of Early Modern Slovene print, 1584–1899,
    # from Dalmatin's 1584 Biblia on, with GOLD (fully manually validated)
    # modernization + lemma + MSD per word token. The scope ruling (owner
    # 2026-07-11): "there isn't much before Early Modern Slovenian at all,
    # so it's in-scope." The gold flagship of the Slovenian axis; its
    # 17.7M-token silver sibling is the Imp adapter (same imp-tei family,
    # OWNER-APPROVED option B 2026-07-11) — shared documents are
    # ALT-EDITIONS across the two sources (goo300k samples pages, IMP has
    # the full texts), never a dedupe (conventions §3).
    #
    # == Identity (FROZEN minting)
    #
    # One document per upstream root file goo300k-<year>-<SIGIL>.xml: urn =
    # urn:nabu:goo300k:<sigil>-<year> lowercased (urn:nabu:goo300k:
    # zrc_00001-1584) — upstream's own document identity (its xml:ids read
    # <SIGIL>-<year>; the "goo168-" xml:id prefix is corpus-wide noise, not
    # identity). Passage urns append the block citation (upstream
    # document-global ab ids: …:ab.1). Minting is frozen once used
    # (standing rule).
    #
    # == License
    #
    # CC BY 4.0. Verbatim, the CLARIN.SI deposit page: "Creative Commons -
    # Attribution 4.0 International (CC BY 4.0)"; verbatim, the bundle's own
    # 00README.txt: "distributed under the Creative Commons Attribution
    # (CC BY 4.0) licence". license_class "attribution", MCP-safe.
    # Attribution: goo300k, Jožef Stefan Institute / CLARIN.SI. See
    # test/fixtures/goo300k/README.md for the whole chain.
    #
    # == The gold lemma decision (owner 2026-07-11)
    #
    # goo300k parses with tokens: :gold — its manually validated
    # lemma/MSD/modernization rides in annotations["tokens"], so the
    # indexer's passage_lemmas picks the lemmas up and `lemma` search lights
    # up for sl. The Imp sibling parses tokens: :none (automatic annotation,
    # upstream's own "fair amount of errors" caveat).
    #
    # == fetch / sync policy
    #
    # ONE zip bitstream over HTTPS (Nabu::ZipFetch — the ORACC path, here
    # single-shot; DSpace bitstream URL, auth-free, the Bosworth precedent).
    # The deposit is a frozen v1.2 (2015-05-05) → sync_policy: manual,
    # enabled: false until the owner-fired first real sync. The probe HEADs
    # the bitstream; no probe-shaped license endpoint exists (the license
    # lives on the record page + in the bundle README), so the probe's
    # license row honestly reads unchecked.
    class Goo300k < Nabu::Adapter
      ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1025/goo300k-tei.zip"

      MANIFEST = Nabu::SourceManifest.new(
        id: "goo300k",
        name: "goo300k — reference corpus of historical Slovene (CLARIN.SI)",
        license: "CC BY 4.0 (verbatim deposit page hdl 11356/1025: \"Creative Commons - " \
                 "Attribution 4.0 International (CC BY 4.0)\"; bundle 00README.txt: " \
                 "\"distributed under the Creative Commons Attribution (CC BY 4.0) licence\")",
        license_class: "attribution",
        upstream_url: ZIP_URL,
        parser_family: "imp-tei"
      )

      LANGUAGE = "sl"
      ROOT_FILE_PATTERN = /\Agoo300k-(?<year>\d{4})-(?<sigil>[A-Za-z0-9_]+)\.xml\z/

      def self.manifest
        MANIFEST
      end

      # The probe HEADs the zip bitstream: reachability + Last-Modified
      # drift vs the .zip-fetch.json pin. metadata_url nil: see class note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: File.basename(ZIP_URL), zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One DocumentRef per document root file (goo300k-<year>-<SIGIL>.xml),
      # sorted by urn. The corpus root (goo300k.xml), the pages/ and schema/
      # trees and 00README never match the pattern. A workdir without the
      # files yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Re-stream the root for its xi:include page list, then extract every
      # page file's blocks in include order — the tokens live in the page
      # files. Gold tokens + the facsimile page id ride in annotations.
      def parse(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: document_ref.metadata.slice("year", "author", "xml_lang")
        )
        page_paths(document_ref.path).each do |page_path|
          append_blocks(document, page_path, document_ref)
        end
        raise ParseError, "#{document_ref.path}: no passage blocks in any included page" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + unpack the single upstream zip via ZipFetch (conditional
      # GET on Last-Modified, sha256 pin, staging, attic + mass-deletion
      # guard). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "goo300k fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        ImpTeiParser.new(tokens: :gold)
      end

      def document_refs(workdir)
        reader = parser
        Dir.glob(File.join(workdir, "**", "goo300k-*.xml")).filter_map do |path|
          match = ROOT_FILE_PATTERN.match(File.basename(path)) or next
          header = reader.header(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:goo300k:#{match[:sigil].downcase}-#{match[:year]}",
            path: File.expand_path(path),
            metadata: ref_metadata(header, match)
          )
        end.sort_by(&:id)
      end

      def ref_metadata(header, match)
        title = header.title_reg || header.title_orig || "#{match[:sigil]}-#{match[:year]}"
        title = "#{title} — #{[header.author, header.date || match[:year]].compact.join(', ')}"
        { "title" => title, "language" => LANGUAGE, "year" => match[:year],
          "author" => header.author, "xml_lang" => header.xml_lang }.compact
      end

      # The root's xi:include hrefs, resolved against its directory, in
      # document order. A root without includes or with a missing page file
      # is damage, not a rule: ParseError.
      def page_paths(root_path)
        hrefs = []
        each_node(root_path) do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "xi:include"

          hrefs << node.attribute("href")
        end
        raise ParseError, "#{root_path}: no xi:include page references" if hrefs.empty?

        hrefs.map do |href|
          path = File.expand_path(href, File.dirname(root_path))
          raise ParseError, "#{root_path}: included page missing: #{href}" unless File.exist?(path)

          path
        end
      end

      def append_blocks(document, page_path, document_ref)
        parser.blocks(page_path) do |block|
          annotations = { "tokens" => block.tokens }
          annotations["page"] = block.page if block.page
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{block.citation}", language: LANGUAGE,
            text: Normalize.nfc(block.text), annotations: annotations, sequence: document.size
          )
        end
      end

      def each_node(path, &)
        reader = Nokogiri::XML::Reader(File.open(path))
        reader.each(&)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed goo300k root TEI: #{e.message}"
      end
    end
  end
end
