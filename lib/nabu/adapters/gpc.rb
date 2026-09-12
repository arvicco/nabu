# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "gpc_xlsx_parser"

module Nabu
  module Adapters
    # Geiriadur Prifysgol Cymru — the University of Wales Dictionary of
    # the Welsh Language (P97-3): the historical dictionary of Welsh,
    # as the OPEN-ACCESS SUBSET the GPC editor supplies under CC BY 4.0
    # — headwords + variants + permanent entry URLs + POS + plural
    # forms + English first-sense openings (~89k entries, 2020
    # vintage). The full GPC stays upstream's (UW/UWTSD copyright, a
    # living dictionary); this subset is the granted slice.
    #
    # == License (grant by email, 2026-09-04)
    #
    # CC BY 4.0, granted by the GPC editor (A. Hawke, Centre for
    # Advanced Welsh & Celtic Studies) with two conditions, both held:
    # no scraping/republication of the GPC website's HTML (nothing
    # here touches the site), and users are pointed at GPC Online —
    # every entry body ends with its permanent gpc.html?gpcNNNNNN URL.
    # A public site publication of the same subset was announced as
    # upstream's future channel; until it appears the email-supplied
    # artifact is the acquisition (ManualDrop below).
    #
    # == Acquisition (ManualDrop — docs/manual/gpc.md)
    #
    # The subset arrives by email, not by URL, so `nabu sync gpc`
    # follows the manual-drop contract: the xlsx (and optionally the
    # format-spec PDF that travels with it) is placed under
    # incoming/gpc/, validated, moved into canonical/gpc/ with the
    # sha-stamped provenance sidecar. Refresh = the next emailed (or
    # eventually published) vintage dropped the same way.
    class Gpc < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "gpc",
        name: "GPC — Geiriadur Prifysgol Cymru (open subset)",
        license: "CC BY 4.0 (the open-access subset; grantor's terms by email, 2026-09-04: no " \
                 "website-HTML scraping/republication, link users to GPC Online — every entry " \
                 "carries its permanent URL)",
        license_class: "attribution",
        upstream_url: "https://www.geiriadur.ac.uk/",
        parser_family: "gpc-xlsx"
      )

      # Any .xlsx in the workdir is the workbook (one artifact per
      # drop; the vintage-dated filename changes on refresh). A named
      # *GPC* glob bit CI: macOS matches case-insensitively, Linux not.
      XLSX_GLOB = "*.xlsx"
      DICTIONARY_SLUG = "gpc"
      LANGUAGE = "cy"
      TITLE = "Geiriadur Prifysgol Cymru (open subset)"

      def self.manifest = MANIFEST

      def self.content_kind = :dictionary

      # A ManualDrop source has no fetch URL to drift against; the probe
      # HEADs the GPC site for liveness only (also the watch surface for
      # the announced subset publication).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "geiriadur.ac.uk", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", "gpc"), workdir)
      end

      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: "gpc",
          upstream_url: "supplied by the GPC editors by email (gpc@geiriadur.ac.uk); " \
                        "a site publication of the subset is upstream's announced future channel",
          steps: [
            "Request (or receive) the open-access subset xlsx from the GPC editors",
            "Save the xlsx (and the format-spec PDF if supplied) as downloaded — no re-saving"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: "2020-09-03_GPC_Agored_UTF8.xlsx",
              description: "the open-subset workbook (UTF-8 vintage export)",
              required: true,
              sniff: lambda { |path|
                File.binread(path, 4) == "PK\x03\x04".b ? nil : "not a zip/xlsx (bad magic bytes)"
              }
            ),
            ManualDrop::FileSpec.new(
              name: "Welsh_ELEXIS_GPC_Open_Description.pdf",
              description: "the data-format specification that travels with the subset",
              required: false,
              sniff: ->(path) { File.binread(path, 5) == "%PDF-".b ? nil : "not a PDF" }
            )
          ],
          refresh_hint: "A newer vintage (emailed or site-published) drops the same way; " \
                        "the sha pin makes an identical re-drop a no-op."
        )
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      # One DocumentRef for the one workbook (glob: the filename carries
      # upstream's vintage date and will change on refresh).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, XLSX_GLOB)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{File.basename(path)}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        parser = GpcXlsxParser.new(document_ref.path)
        parser.entries { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "gpc: #{document_ref.id}: #{e.message}"
      end
    end
  end
end
