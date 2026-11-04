# frozen_string_literal: true

require_relative "cantus_source_index"
require_relative "cantus_csv_parser"
require_relative "../cantus_fetch"

module Nabu
  module Adapters
    # Cantus Database (cantusdatabase.org; directed by Debra Lacoste; web
    # development McGill DDMAL; the Digital Analysis of Chant Transmission
    # project, Dalhousie University): the inventories of the chants —
    # chiefly of the Divine Office, increasingly of the Mass — in medieval
    # and early-modern manuscript and printed sources, every record tied
    # to its Cantus ID (the Cantus Index chant identity). A thin
    # composition of the cantus-csv family (CantusCsvParser +
    # CantusSourceIndex) with the CantusFetch source-list crawl.
    #
    # == License (first-hand, 2026-11-04)
    #
    # Every page footer (the home page, /citations/ — read 2026-11-04):
    # "Creative Commons License … This work is licensed under a Creative
    # Commons Attribution-NonCommercial-ShareAlike 4.0 International
    # License." linking https://creativecommons.org/licenses/by-nc-sa/4.0/
    # → license_class nc. The /citations/ page's own citation form rides
    # the credit line.
    #
    # == Grains (enumerated 2026-11-04 against the live site)
    #
    #   /json-sources/             the CSV manifest (305 sources) —
    #                              json-sources.json, a sidecar.
    #   Browse Sources pages       segment 4063, 4 pages — the manuscript
    #                              metadata (siglum, institution, century,
    #                              provenance, chant count); sidecars, read
    #                              by CantusSourceIndex, never documents.
    #   per-source CSV export      /source/<id>/csv/ — ACCEPTED: each row a
    #                              chant record; the record carrying full
    #                              text is the document.
    #   incipit-only chant record  a CSV row with no full text (or a
    #                              standardized field that only repeats the
    #                              incipit) — SKIPPED BY RULE, censused in
    #                              discovery_skips (pinned: Badija V rows).
    #   Sequence Database segment  (4064, 325 sources — Bower's Clavis
    #                              Sequentiarum: incipit-only sequence rows
    #                              keyed to Analecta Hymnica numbers) and
    #                              the ~109 inventory-less "All Sources"
    #                              descriptions — never listed by
    #                              /json-sources/, never fetched.
    #   chant pages, melody search, images, per-source JSON — never fetched
    #                              (the CSV carries every chant field,
    #                              volpiano melody included).
    #
    # == Document grain (chosen deliberately)
    #
    # One document per chant RECORD (urn:nabu:cantus:<node_id>, node_id =
    # upstream's own chant-record id, the /chant/<node_id>/ page), its one
    # passage (…:1) the full text. The record — not the manuscript — is
    # where every axis-shaped field lives (genre, office, feast, mode,
    # Cantus ID), so the per-record document lets the kind/facet lanes and
    # the cantus_id link layer read them directly; and node_id is stable
    # across edits, re-exports and re-orderings of an inventory, where a
    # manuscript-grain passage sequence would shift. The manuscript's own
    # fields (siglum, century, provenance) join every record of it.
    #
    # == Count reconciliation
    #
    # Upstream's own advertised counts (2026-11-04): "Displaying 1-100 of
    # 305 sources." (segment 4063) = the 305 /json-sources/ entries
    # exactly; the listing's Chants column sums to 449,132 records and
    # equals each export's row count (15/15 sources probed). CantusFetch
    # refuses a listing that disagrees with itself or with the manifest.
    # So: accepted records + skipped-by-rule incipit-only records = the
    # export rows = 449,132 (± live edits between the GETs, noted as drift
    # by the fetch). The split is measured at the first sync; a random
    # 12-source sample (20,732 rows) read 58.4% accepted (47.1% with
    # manuscript text, 11.3% standardized-only) — per-source variance is
    # extreme (0–100%), so expect on the order of 260k documents within a
    # wide 150k–300k band.
    #
    # == fetch / sync policy
    #
    # CantusFetch: 1 manifest + 4 listing + 305 export GETs (~310) at 1 s,
    # ~5–10 min, resumable at the file grain; exports re-fetch when their
    # row count drifts from the listing (the old body atticked). wired:
    # false until the first real sync is verified.
    class Cantus < Nabu::Adapter
      BASE_URL = Nabu::CantusFetch::BASE_URL

      CITATION = "Cantus Database. Directed by Debra Lacoste (2011-present), Terence Bailey (1997-2010), " \
                 "and Ruth Steiner (1987-1996); developed for the web by Jan Koláček (2011-2023), McGill " \
                 "University Distributed Digital Music Archives & Libraries Lab - DDMAL (2023-present); and " \
                 "funded through the Digital Analysis of Chant Transmission project at Dalhousie University, " \
                 "Halifax, Nova Scotia, Canada (SSHRC 895-2023-1002), directed by Jennifer Bain, " \
                 "https://cantusdatabase.org — data under CC BY-NC-SA 4.0"

      MANIFEST = Nabu::SourceManifest.new(
        id: "cantus",
        name: "Cantus Database — inventories of chant in medieval manuscripts",
        license: "CC BY-NC-SA 4.0 (every page footer, verbatim: \"This work is licensed under a Creative " \
                 "Commons Attribution-NonCommercial-ShareAlike 4.0 International License.\" → " \
                 "https://creativecommons.org/licenses/by-nc-sa/4.0/). Images are not fetched.",
        license_class: "nc",
        upstream_url: BASE_URL,
        parser_family: "cantus-csv",
        credit: CITATION
      )

      def self.manifest
        MANIFEST
      end

      # No git repo — the probe GETs the source manifest (reachability; the
      # fetch ledger holds the content pin).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "json-sources", zip_url: Nabu::CantusFetch.manifest_url(BASE_URL),
          metadata_url: nil, state_subdir: "", state_file: Nabu::CantusFetch::STATE_FILE
        )]
      end

      # Audited pure per ref: parse reads one export row + the listing
      # sidecars through two memo caches of pure functions (each worker
      # builds its own; a window of CACHE_FILES exports), no handle opened
      # during discovery crosses the fork.
      def self.parallel_parse? = true

      # Exports parsed and held per worker (a parse touches one record; the
      # loader walks records in file order, so a small window means each
      # export is read about once per worker).
      # const: memo window, not a corpus claim
      CACHE_FILES = 4

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::CantusFetch::DELAY)
        super()
        @delay = delay
        @rows = {}
        @indexes = {}
      end

      # One ref per full-text chant record, sources in numeric id order,
      # records in export order. An unfetched workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        walk(workdir) do |path, row, verdict|
          next unless verdict == :accepted

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(row), path: path)
        end
      end

      # The censused skips: incipit-only records (two notes — no full text
      # at all; a standardized field that only repeats the incipit), by
      # rule; a file in sources/ that is not an export, or a record without
      # a node_id / repeating one already seen, is unrecognized. The root
      # sidecars (json-sources.json, the listing pages) are the metadata
      # grain, read by the index — named in a note, not counted (the count
      # reconciles chant records).
      def discovery_skips(workdir)
        tally = Hash.new(0)
        notes = []
        walk(workdir, strays: ->(name) { notes << "#{name}: not a CSV export under sources/" }) do |path, _row, verdict|
          tally[verdict] += 1
          notes << "#{File.basename(path)}: a chant record without a usable node_id" if verdict == :unrecognized
        end
        unrecognized = notes.size
        if tally[:no_text].positive?
          notes << "#{tally[:no_text]} incipit-only chant records (no full text) skipped by rule"
        end
        if tally[:incipit_echo].positive?
          notes << "#{tally[:incipit_echo]} chant records whose standardized text only repeats the incipit " \
                   "skipped by rule"
        end
        sidecars = Dir.glob(File.join(workdir, CantusSourceIndex::PAGE_GLOB)).size
        notes << "#{sidecars} listing pages + the json-sources manifest read as source metadata" if sidecars.positive?
        DiscoverySkips.new(skipped_by_rule: tally[:no_text] + tally[:incipit_echo], unrecognized: unrecognized,
                           notes: notes)
      end

      def parse(document_ref)
        node = document_ref.id.delete_prefix(URN_PREFIX)
        row = rows_of(document_ref.path)[node]
        raise ParseError, "#{document_ref.path}: no chant record #{node}" if row.nil?

        sources = index_for(File.dirname(document_ref.path, 2))
        source = sources[CantusFetch.csv_id(File.basename(document_ref.path))]
        CantusCsvParser.new.document(row, urn: document_ref.id, source: source, canonical_path: document_ref.path)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the network).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::CantusFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::CantusFetch::Error => e
        raise Nabu::FetchError, "cantus fetch failed into #{workdir}: #{e.message}"
      end

      URN_PREFIX = "urn:nabu:cantus:"

      private

      def urn_for(row) = "#{URN_PREFIX}#{row['node_id'].to_s.strip}"

      # Every export under sources/ (numeric source-id order, a superseded
      # attic copy after its live name), each row with its verdict:
      # :accepted / :no_text / :incipit_echo / :unrecognized.
      def walk(workdir, strays: nil)
        seen = Set.new
        export_paths(workdir, strays: strays).each do |path|
          CantusCsvParser.new.each_row(path) do |row|
            node = row["node_id"].to_s.strip
            verdict = if !node.match?(/\A\d+\z/) || !seen.add?(node) then :unrecognized
                      else CantusCsvParser.skip_reason(row) || :accepted
                      end
            yield path, row, verdict
          end
        end
      end

      def export_paths(workdir, strays: nil)
        dir = File.join(workdir, CantusFetch::SOURCES_DIR)
        return [] unless Dir.exist?(dir)

        names = Dir.children(dir).sort
        names.reject { |name| CantusFetch.csv_id(name) || name.end_with?(".tmp") }.each { |name| strays&.call(name) }
        names.select { |name| CantusFetch.csv_id(name) }
             .sort_by { |name| [CantusFetch.csv_id(name), name] }
             .map { |name| File.expand_path(File.join(dir, name)) }
      end

      # node_id → row for one export, memoized over a small window.
      def rows_of(path)
        return @rows[path] if @rows.key?(path)

        @rows.shift while @rows.size >= CACHE_FILES
        @rows[path] = CantusCsvParser.new.each_row(path).to_h { |row| [row["node_id"].to_s.strip, row] }
      end

      def index_for(dir)
        @indexes[dir] ||= CantusSourceIndex.load(dir)
      end

      def fetch_notes(result)
        base = "#{result.sources} sources (#{result.advertised_sources} advertised; " \
               "#{result.advertised_chants} chant records listed; #{result.fetched} exports fetched, " \
               "#{result.cached} already on disk; #{result.pages} listing pages)"
        notes = [base]
        unless result.missing.empty?
          notes << "#{result.missing.size} listed exports 404 (#{result.missing.first(3).join(', ')})"
        end
        unless result.drift.empty?
          notes << "#{result.drift.size} exports differ from the listing count (#{result.drift.first(3).join('; ')})"
        end
        [*notes, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
