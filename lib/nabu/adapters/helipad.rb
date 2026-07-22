# frozen_string_literal: true

require "digest"

module Nabu
  module Adapters
    # The HeliPaD adapter (P40-3): *HeliPaD — the Heliand Parsed Database*
    # (George Walkden), the 9th-century Old Saxon gospel harmony *Heliand*
    # as a syntactically parsed corpus in Penn labeled bracketing — the
    # first PennPsdParser composition (YCOE and native IcePaHC are the
    # planned family siblings). One upstream artifact: heliand.psd
    # (3,524,675 B, 3,549 tree blocks) from the frozen Zenodo v0.9 deposit.
    #
    # == Document grain (decided from the ID structure, fixture census)
    #
    # Every tree block ends in (ID OSHeliandC.<n>.<lines>). The middle
    # component is the TREE ORDINAL, not a fitt: the first two blocks are
    # 1.1-5 and 2.5-9 — continuous line numbering across the ".1"/".2"
    # boundary (fitt 1 runs far past line 5), and 3,549 trees over the
    # corpus's 5,968 lines matches sentence grain. The ID therefore carries
    # NO division structure; fitt boundaries live in (CODE <F_n>) markers
    # INSIDE trees. So: ONE document — the whole poem, minted from the ID
    # prefix, urn:nabu:helipad:OSHeliandC (verbatim upstream slug; C = the
    # Cotton Caligula A. VII manuscript) — with one passage per tree block,
    # urn tail the ID minus the text prefix ("1.1-5"). Lineation, caesurae
    # and fitts stay reconstructible from the retained CODE lane.
    #
    # == License
    #
    # CC BY 4.0 — the Zenodo record 4395040 metadata declares
    # `license: cc-by-4.0`; the .psd itself carries no license header
    # (record-level grant, the ETCSL shape) → license_class attribution.
    # Cite: Walkden, George (2015). HeliPaD: the Heliand Parsed Database,
    # v0.9, Zenodo, doi:10.5281/zenodo.4395040.
    #
    # == fetch / sync policy
    #
    # Nabu::FileFetch of the single Zenodo file URL, sha256-PINNED to the
    # v0.9 artifact (the open-etruscan choreography: prepare, verify pin,
    # breaker, complete — drift aborts with the tree byte-unchanged). The
    # deposit is versioned and immutable; a new HeliPaD version is a NEW
    # Zenodo file whose pin the owner verifies before re-syncing (re-pin =
    # owner decision). sync_policy: manual, enabled: false until the
    # owner-fired first real sync (CLAUDE.md checklist §6).
    class Helipad < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/4395040"
      CORPUS_URL = "https://zenodo.org/api/records/4395040/files/heliand.psd/content"
      FILENAME = "heliand.psd"
      # The frozen v0.9 pin (sha256 of the full 3,524,675 B artifact,
      # recorded at fixture build 2026-07-22 — test/fixtures/helipad/).
      CORPUS_SHA256 = "2f83b2c0bb64b0e4dc8284a0aa56aed937f3a0b26ad9a82440d832bf702bda4d"
      LANGUAGE = "osx"
      TITLE = "Heliand"

      MANIFEST = Nabu::SourceManifest.new(
        id: "helipad",
        name: "HeliPaD — the Heliand Parsed Database (Walkden; Zenodo 4395040, v0.9)",
        license: "CC BY 4.0 (Zenodo record 4395040 license field cc-by-4.0; no in-file license " \
                 "header — record-level grant. Cite: Walkden, George (2015), HeliPaD: the Heliand " \
                 "Parsed Database, v0.9, doi:10.5281/zenodo.4395040)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "penn-psd"
      )

      def self.manifest
        MANIFEST
      end

      # The probe HEADs the file URL itself (reachability + Last-Modified
      # drift vs the .file-fetch.json pin at the workdir root). metadata_url
      # nil: the Zenodo API record body carries volatile stats (the diorisis
      # false-alarm lesson), so the probe's license row honestly reads
      # unchecked — the pinned sha is the real drift guard.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: CORPUS_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +corpus_sha256+ exists for the WebMock'd fetch tests (the
      # open-etruscan pattern) — real syncs keep the frozen pin.
      def initialize(corpus_sha256: CORPUS_SHA256)
        super()
        @corpus_sha256 = corpus_sha256
      end

      # One DocumentRef per .psd file under +workdir+ (sorted) — one for
      # the real corpus, and the same walk serves the fixture trim and the
      # attic. The urn is minted from the file's OWN first (ID …) prefix,
      # not the filename, so an upstream rename cannot fork identity (the
      # proiel doctrine). A workdir without a .psd yields nothing (the
      # day-one pre-fetch state); a .psd without a readable ID is skipped
      # defensively.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        PennPsdParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: LANGUAGE,
          title: document_ref.metadata["title"],
          id_prefix: document_ref.metadata["text_id"]
        )
      end

      # Download the single pinned file via FileFetch, two-phase: prepare
      # (tree untouched), verify the sha256 pin, run the mass-deletion
      # breaker, complete. Returns a Nabu::FetchReport pinning the body
      # sha256. No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::FileFetch.new(
          url: CORPUS_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "helipad fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.sha == @corpus_sha256

        raise Nabu::FetchError,
              "helipad: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{@corpus_sha256}; the deposit is frozen at v0.9 (Zenodo 4395040) — review " \
              "upstream and re-pin (owner decision)"
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "**", "*.psd")).filter_map do |path|
          text_id = peek_text_id(path)
          next unless text_id

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:helipad:#{text_id}",
            path: File.expand_path(path),
            metadata: { "text_id" => text_id, "title" => TITLE, "language" => LANGUAGE }
          )
        end
      end

      # Cheap peek at the file's first (ID …) token — the tail of the first
      # tree block, ~50 lines in — returning its prefix before the first
      # "." (the text id, "OSHeliandC"). nil when no ID is found.
      def peek_text_id(path)
        File.foreach(path) do |line|
          id = line[/\(ID ([^\s()]+)\)/, 1]
          return id.split(".").first if id
        end
        nil
      end
    end
  end
end
