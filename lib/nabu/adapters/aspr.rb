# frozen_string_literal: true

module Nabu
  module Adapters
    # The ASPR adapter (P12-2): the Anglo-Saxon Poetic Records — all six
    # Krapp & Dobbie volumes, the complete canonical Old English poetry
    # corpus (Beowulf, Junius MS, Vercelli Book, Exeter Book, Paris Psalter,
    # Minor Poems) — as ONE 2.2 MB TEI-P5 file from the Oxford Text Archive
    # (OTA 3009; machine-readable version Hidley 1993, deposited
    # Macrae-Gibson, revised from OTA 1936). A thin composition of the
    # AsprParser family in the Vulgate single-file-many-documents shape: the
    # parser lists the poem inventory for discover and extracts one poem per
    # parse; the adapter owns identity, metadata and fetch.
    #
    # == Identity (FROZEN minting): the Cameron number
    #
    # One document per poem div. urn = urn:nabu:aspr:<div xml:id> — the
    # xml:id values are the poems' canonical Cameron/DOE record numbers
    # (A1.1 Genesis … A4.1 Beowulf … A32.1/A32.2 the two dialect witnesses
    # of Cædmon's Hymn), kept VERBATIM (case and dots; the literal-upstream-
    # slug rule), all 349 unique. Title-slugs were REJECTED: titles collide
    # (A43.5 and A43.10 are both "For Loss of Cattle"; the multi-dialect
    # witnesses repeat theirs), while the Cameron number is the id scholars
    # actually cite. Passage urns append the 1-based line ordinal —
    # urn:nabu:aspr:A4.1:1 = "Hwæt! We Gardena in geardagum," — which equals
    # the printed ASPR line number (the divs carry rend="linenumber" and
    # Beowulf's holds exactly 3,182 <l>; Phase A verification in
    # docs/backlog.md P12-2). Minting is frozen once used (standing rule).
    #
    # == License
    #
    # CC BY-SA 3.0 Unported, verbatim from the file's own teiHeader:
    # <licence target="http://creativecommons.org/licenses/by-sa/3.0/">
    # "Distributed by the University of Oxford under a Creative Commons
    # Attribution-ShareAlike 3.0 Unported License" — the OTA record page
    # agrees → license_class "attribution" (MCP-surface-safe). The only
    # fully-open structured OE text source the P11-1 survey found.
    #
    # == fetch / sync policy
    #
    # The first single-file HTTP source: Nabu::FileFetch (ZipFetch's argued
    # sibling — same Last-Modified conditional GET, sha256 pin, attic
    # contract) GETs the DSpace bitstream, auth-free. Upstream is
    # effectively frozen (Last-Modified 2019-07-19, header normalised 2010)
    # → sync_policy: manual (config/sources.yml), enabled: false until the
    # owner-fired first real sync. The remote-health probe rides the
    # :http_zip HEAD path (reachability + Last-Modified drift against the
    # .file-fetch.json pin); there is NO metadata endpoint — the license
    # lives inside the fetched file — so the license row honestly reads
    # unchecked (drift-on-refetch is the license watch).
    class Aspr < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "aspr",
        name: "ASPR — The Anglo-Saxon Poetic Records (Krapp & Dobbie; OTA 3009)",
        license: "CC BY-SA 3.0 Unported (verbatim in the TEI header availability; OTA record page agrees)",
        license_class: "attribution",
        upstream_url: "https://ota.bodleian.ox.ac.uk/repository/xmlui/bitstream/handle/20.500.12024/3009/3009.xml",
        parser_family: "aspr"
      )

      FILENAME = "3009.xml"

      def self.manifest
        MANIFEST
      end

      # The probe HEADs the bitstream itself: reachability + Last-Modified
      # drift vs the .file-fetch.json pin (state_subdir "" — the state file
      # sits at the workdir root). metadata_url nil: no license endpoint
      # exists; the in-file license is re-read at every real fetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef per poem div of the 3009.xml file, in file order
      # (which is Cameron/volume order). Returns an Enumerator without a
      # block (the adapter contract's lazy shape). A workdir without the
      # file yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        AsprParser.new.parse(
          document_ref.path,
          div_id: document_ref.metadata.fetch("div_id"),
          urn: document_ref.id,
          language: "ang",
          title: document_ref.metadata["title"]
        )
      end

      # Download the single upstream file via FileFetch (conditional GET,
      # sha pin, attic + guard contract), returning a Nabu::FetchReport
      # pinning the body sha256. No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "aspr fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        path = Dir.glob(File.join(workdir, "**", FILENAME)).min
        return [] unless path

        AsprParser.new.texts(path).map do |text|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:aspr:#{text.id}",
            path: File.expand_path(path),
            metadata: { "div_id" => text.id, "title" => text.title || text.id, "language" => "ang" }
          )
        end
      end
    end
  end
end
