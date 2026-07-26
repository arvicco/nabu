# frozen_string_literal: true

require_relative "edr_epidoc_parser"

module Nabu
  module Adapters
    # The EDR adapter (P46-4): the Epigraphic Database Roma (edr-edr.it;
    # Panciera/Orlandi et al., Sapienza) — the inscriptions of ITALY,
    # the geographic complement of held EDH (whose remit is the Roman
    # provinces; the two projects partition the EAGLE federation's map,
    # and share some inscriptions at the border as provenance-distinct
    # witnesses — standing doctrine, never deduped). A thin composition of
    # the EdrEpidocParser family with the rem Zenodo-zip choreography.
    #
    # == The data release (census 2026-07-26)
    #
    # ONE Zenodo artifact: record 18468635 (version 12, concept DOI
    # 10.5281/zenodo.3931222), EDR.zip, 267,683,094 B, md5
    # d679b73ce95537406b84468cac64753c (Zenodo-published, verified on the
    # census download). Contents measured, not estimated: 115,591 EpiDoc
    # XML files (649.5 MB unpacked; median 5.3 KB) in nine range dirs at
    # the zip ROOT (000001-025000 … 200001-225000 — no single top dir, so
    # ZipFetch unpacks the ranges directly into the workdir), every file
    # <range>/aEDR<nnnnnn>.xml, ids unique, zero non-XML members. Exactly
    # 1 file is malformed XML (aEDR188615.xml, overlapping <supplied>/<l>
    # hierarchy — the honest quarantine). EDR's site holds ~230K records;
    # the zip is the subset the project has auto-converted to EpiDoc.
    #
    # == Layout
    #
    #   <workdir>/<range>/aEDR<nnnnnn>.xml   (nine flat range dirs)
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:edr:edr<nnnnnn> — EDR numbers are the stable id the
    # EAGLE federation, Trismegistos, and the held I.Sicily/EDH
    # concordances key on. discover mints from the filename (aEDR…xml,
    # the upstream "a" prefix shed); parse cross-checks the in-file
    # <idno type="localID"> (zero mismatches censused; drift quarantines).
    #
    # == License (two layers, recorded honestly)
    #
    # - DEPOSIT level: the Zenodo record's license field is CC BY 4.0 —
    #   the redistribution grant this snapshot is ingested under. The
    #   depositors are the EDR project leadership themselves (Panciera,
    #   Camodeca, Cecconi, Orlandi, Fabriani, Evangelisti), so the grant
    #   is authoritative for the dataset.
    # - IN-FILE: every record's <licence> still carries the EAGLE-era
    #   "Reserved Rights - Free access via Epigraphic Database Roma"
    #   (europeana.eu rr-f) — uniform across all 115,590 well-formed
    #   files, recorded verbatim in the manifest and PINNED at parse
    #   (drift quarantines), but superseded for this dataset by the
    #   deposit-level grant. → license_class "attribution".
    #
    # == fetch / sync policy
    #
    # ZipFetch in STREAM mode (267 MB never buffers in memory) with the
    # phases hand-driven so the hard sha256 pin is checked BETWEEN
    # download and any tree mutation (the rem mold). Zenodo files are
    # immutable; EDR re-releases periodically as a NEW version under the
    # concept DOI — the owner re-pins ZIP_URL + RELEASE_SHA256 and fires
    # the re-sync. sync_policy: manual, wired: false until the owner-fired
    # first sync.
    class Edr < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/18468635"
      ZIP_URL = "https://zenodo.org/api/records/18468635/files/EDR.zip/content"

      # sha256 of the 267,683,094-byte EDR.zip, pinned from the 2026-07-26
      # census download (test/fixtures/edr/README.md); its md5 matches the
      # Zenodo-published d679b73ce95537406b84468cac64753c. Zenodo files
      # are immutable: a mismatch is corruption or an unannounced
      # re-release, never a routine update.
      RELEASE_SHA256 = "61be8164b35fbf7409568da095242b247dec420a56df7f5f452bb4736c55917b"

      MANIFEST = Nabu::SourceManifest.new(
        id: "edr",
        name: "EDR — Epigraphic Database Roma (EpiDoc data release)",
        license: "CC BY 4.0 (Zenodo deposit 10.5281/zenodo.18468635, deposited by the EDR project " \
                 "leadership — the redistribution grant this snapshot is ingested under); every " \
                 "file's own <licence> carries the EAGLE-era \"Reserved Rights - Free access via " \
                 "Epigraphic Database Roma\" (europeana.eu rr-f) verbatim — pinned at parse, " \
                 "superseded for this dataset by the deposit-level grant",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "edr-epidoc"
      )

      # A record file as the zip spells it (aEDR000002.xml …); anything
      # else in a range dir is not a record.
      RECORD_FILENAME = /\AaEDR\d+\.xml\z/

      def self.manifest
        MANIFEST
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. metadata_url nil — the license
      # travels on the record page and in-file.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "EDR.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin
      # drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per record file, sorted by urn; a workdir without
      # the range dirs yields nothing (the day-one pre-fetch state). The
      # one-level glob never descends into .attic (dot-dirs unmatched).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        EdrEpidocParser.new.parse(document_ref.path, urn: document_ref.id)
      end

      # Download (streamed) + verify the hard sha pin + unpack, phases
      # hand-driven so the pin check runs BETWEEN download and any tree
      # mutation (prepare → pin → mass-deletion breaker → complete); a 304
      # replays the stored pin and touches nothing. No network in tests:
      # WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, stream: true,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch, workdir))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "edr fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "*", "aEDR*.xml"))
           .select { |path| RECORD_FILENAME.match?(File.basename(path)) }
           .map do |path|
             local = File.basename(path, ".xml").delete_prefix("a").downcase
             Nabu::DocumentRef.new(
               source_id: manifest.id, id: "#{EdrEpidocParser::URN_PREFIX}#{local}",
               path: File.expand_path(path)
             )
           end.sort_by(&:id)
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "edr: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{RECORD_URL} and re-pin ZIP_URL + RELEASE_SHA256 " \
              "only after reading the record"
      end

      def fetch_notes(fetch, workdir)
        base =
          if fetch.not_modified?
            "not modified (304)"
          else
            records = Dir.glob(File.join(workdir, "*", "aEDR*.xml")).size
            "zenodo record 18468635 sha pin verified (#{records} records)"
          end
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
