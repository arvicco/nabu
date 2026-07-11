# frozen_string_literal: true

require_relative "imp_tei_parser"

module Nabu
  module Adapters
    # The IMP adapter (P13-9): the digital library and corpus of historical
    # Slovene (Erjavec, Jožef Stefan Institute; CLARIN.SI hdl 11356/1031) —
    # 658 texts / 17,723,566 tokens / >45,000 pages, 1584–1919, the
    # full-text SILVER sibling of goo300k (same imp-tei parser family,
    # OWNER-APPROVED option B 2026-07-11). Shared documents (e.g. Dalmatin's
    # 1584 Biblia, upstream sigil ZRC_00001-1584 in both) are ALT-EDITIONS
    # across the two sources — goo300k samples pages with gold annotation,
    # IMP carries the whole text with automatic annotation — never a dedupe
    # (conventions §3).
    #
    # == The silver decision (owner default, 2026-07-11)
    #
    # Upstream's own caveat, verbatim from the deposit page: "Note that the
    # annotations are automatic, so they contain a fair amount of errors."
    # So IMP parses tokens: :none — TEXT ONLY. The automatic reg/lemma/MSD
    # layer is NOT carried into passage annotations and IMP feeds no
    # passage_lemmas rows: the lemma index stays gold-only (goo300k), IMP
    # text is fully FTS-searchable (historical orig surface + the sl ſ→s
    # fold), and the catalog is spared ~17.7M tokens of error-bearing JSON.
    # If silver lemmas ever earn their way in, the parser's :gold mode is a
    # one-line adapter change away — that reload is an owner decision.
    #
    # == Identity (FROZEN minting)
    #
    # One document per self-contained <SIGIL>-<year>-ana.xml file: urn =
    # urn:nabu:imp:<sigil>-<year> lowercased (urn:nabu:imp:wiki00290-1855).
    # Passage urns append the block citation — IMP's <p>/<head> carry no
    # xml:ids, so the imp-tei family mints per-tag document-order counters
    # (…:p.1, …:head.1); stable because the deposit is frozen (1.1,
    # 2015-05-22) and any upstream re-mint is owner-witnessed (manual).
    #
    # == License
    #
    # CC BY-SA 4.0. Verbatim, the CLARIN.SI deposit page: "Creative Commons
    # - Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)"; verbatim,
    # every corpus file's own teiHeader availability: "This work is licensed
    # under the Creative Commons Attribution-ShareAlike 4.0 International
    # License." license_class "attribution" (ShareAlike — same class as the
    # Perseus corpora). Attribution: IMP, Jožef Stefan Institute /
    # CLARIN.SI. See test/fixtures/imp/README.md for the whole chain.
    #
    # == fetch / sync policy
    #
    # ONE 150.31 MB zip bitstream over HTTPS (Nabu::ZipFetch, single-shot;
    # DSpace bitstream URL, auth-free). Frozen deposit → sync_policy:
    # manual, enabled: false until the owner-fired first real sync (a 150 MB
    # GET is an owner decision). Probe: HEAD on the bitstream, license row
    # honestly unchecked (no probe-shaped license endpoint).
    class Imp < Nabu::Adapter
      ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1031/IMP-corpus-tei.zip"

      MANIFEST = Nabu::SourceManifest.new(
        id: "imp",
        name: "IMP — digital library and corpus of historical Slovene (CLARIN.SI)",
        license: "CC BY-SA 4.0 (verbatim deposit page hdl 11356/1031: \"Creative Commons - " \
                 "Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\"; per-file teiHeader: " \
                 "\"This work is licensed under the Creative Commons Attribution-ShareAlike 4.0 " \
                 "International License.\")",
        license_class: "attribution",
        upstream_url: ZIP_URL,
        parser_family: "imp-tei"
      )

      LANGUAGE = "sl"
      FILE_PATTERN = /\A(?<sigil>[A-Za-z0-9_]+)-(?<year>\d{4})-ana\.xml\z/

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: File.basename(ZIP_URL), zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One DocumentRef per <SIGIL>-<year>-ana.xml, sorted by urn. The
      # schema/ tree and 00README never match. A workdir without the files
      # yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Text-only extraction (see the silver decision): the historical orig
      # surface per block, the facsimile page id in annotations, no tokens.
      def parse(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: document_ref.metadata.slice("year", "author", "xml_lang")
        )
        parser.blocks(document_ref.path) do |block|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{block.citation}", language: LANGUAGE,
            text: Normalize.nfc(block.text), sequence: document.size,
            annotations: block.page ? { "page" => block.page } : {}
          )
        end
        raise ParseError, "#{document_ref.path}: no passage blocks" if document.empty?

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
        raise Nabu::FetchError, "imp fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        ImpTeiParser.new(tokens: :none)
      end

      def document_refs(workdir)
        reader = parser
        Dir.glob(File.join(workdir, "**", "*-ana.xml")).filter_map do |path|
          match = FILE_PATTERN.match(File.basename(path)) or next
          header = reader.header(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:imp:#{match[:sigil].downcase}-#{match[:year]}",
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
    end
  end
end
