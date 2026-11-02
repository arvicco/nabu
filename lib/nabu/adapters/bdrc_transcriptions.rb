# frozen_string_literal: true

require "json"
require "digest"
require_relative "../hf_rows_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # BDRC Tibetan transcriptions — the three CC0 page-aligned etext
    # releases the Buddhist Digital Resource Center published on Hugging
    # Face in 2026 as part of its Tibetan OCR release, held as TEXT only:
    #
    # - acip-sungbum (BDRC/ALL-BDRC-alignments): 79,572 pages of the Asian
    #   Classics Input Project's *Sungbum* (gsung 'bum, collected works)
    #   transcriptions via the Asian Legacy Library, hand-matched to the
    #   exact BDRC block print / manuscript and aligned page by page —
    #   119 collected-works sets, mostly woodblock dbu can;
    # - palri-parkhang (BDRC/palri-parkhang-transcriptions): 11,133 pages
    #   input by Palri Parkhang (Nepal, 2006–2013), largely Nyingma
    #   collected works and gter ma cycles, almost all dbu med manuscripts,
    #   abbreviations expanded by the input project;
    # - berkeley (BDRC/berkeley-transcriptions): 8,866 pages transcribed by
    #   Geshe Dangsong Namgyal at UC Berkeley (2016–2026, initiated by Prof.
    #   Kurt Keutzer), dbu med manuscripts plus a small woodblock portion;
    #   readability-first, abbreviations expanded, some emendation/insert
    #   markup kept.
    #
    # == License (the three cards, read 2026-11-02, verbatim)
    #
    # "License: CC0-1.0 — use, modify, redistribute freely. Attribution
    # requested (not required)" — BDRC + the Asian Legacy Library / Palri
    # Parkhang / Prof. Kurt Keutzer (UC Berkeley) respectively; "verifying
    # the copyright status of each underlying original book is the user's
    # responsibility". The image-rights disclaimer concerns the scans,
    # which this adapter never fetches. Class `open`. The cards still carry
    # a <!-- DRAFT --> marker; the card text is pinned beside each release
    # (README.md, fetched at the pinned revision) so a later card edit is
    # visible as a canonical change.
    #
    # == Delivery grains (census 2026-11-02 over the rows API)
    #
    # Upstream serves ONE grain — the page row: (image, transcription, id,
    # mw_id, technology, script[, script_4]) in sharded parquet, rows
    # SHUFFLED across volumes. The row id encodes the whole hierarchy:
    #   <release tag>:<collection>:<IE etext instance>:<VE etext volume>:<v>:<scan file>
    # (e.g. 202604:Kurt:IE23550_MA:VE2115_MA:v2:21150297.tif).
    # - TAKEN: the etext VOLUME (VE…) as the document — it is BDRC's own
    #   etext unit, maps to one scanned volume, and orders by scan file;
    #   the page row is the passage, cited by its scan file stem.
    # - REJECTED: the page as document (≈100k one-page documents, no
    #   continuity — it is the passage grain); the etext instance (IE…,
    #   a multi-volume work — kept as metadata so volumes regroup); the
    #   BDRC version (mw_id, the scanned edition — metadata + the
    #   purl.bdrc.io link); the image column (never fetched — see
    #   HfRowsFetch); the dataset card + subset_info.json (license/
    #   provenance metadata, pinned beside the volumes, skipped by rule).
    #
    # == Fetch
    #
    # Nabu::HfRowsFetch per release into its own subdir — sequential,
    # paced, revision-pinned, resumable at the 100-row page grain. ~1,000
    # rows requests in all; the first sync is a long paced crawl (the rows
    # API rate-limits bursts with 429s), re-syncs are one revision probe
    # per release while upstream is unchanged.
    #
    # Reconciliation (full text-column census 2026-11-02, parsed through
    # this adapter): berkeley 8,866 rows = the card → 19 volumes / 14
    # instances; palri-parkhang 11,133 rows = the card → 23 volumes / 6
    # instances; acip-sungbum 79,572 rows = the card → 1,118 volumes = its
    # 1,118 transcription volumes (1:1 with instances; 119 BDRC versions);
    # 0 unkeyed, 0 blank, scan stems unique per volume (1,160
    # documents / 99,571 passages; parse ≈ 2 min serial). Census crawl:
    # ≈ 75 min sequential through the API's 429/5xx back-offs.
    # Upstream defect, kept verbatim (canonical means canonical): 15 Palri
    # pages (12 in VE2491_MA, 3 in VE2119_MA) carry པ where the tsheg
    # belongs.
    class BdrcTranscriptions < Nabu::Adapter
      SLUG = "bdrc-transcriptions"
      PARSER_FAMILY = "hf-rows-jsonl"
      LANGUAGE = "xct"

      # Release subdir => [Hugging Face dataset, display name]. Order is
      # the discover order.
      RELEASES = {
        "acip-sungbum" => ["BDRC/ALL-BDRC-alignments", "ACIP Sungbum (ALL-BDRC alignments)"],
        "palri-parkhang" => ["BDRC/palri-parkhang-transcriptions", "Palri Parkhang transcriptions"],
        "berkeley" => ["BDRC/berkeley-transcriptions", "Berkeley transcriptions"]
      }.freeze

      # The pinned card files of each release — the rejected metadata grain.
      SIDECARS = %w[README.md subset_info.json].freeze

      ROW_ID = /\A(?<tag>[^:]+):(?<collection>[^:]+):(?<ie>IE[^:]+):(?<ve>VE[^:]+):(?<version>[^:]+):(?<image>[^:]+)\z/

      LICENSE = "CC0-1.0 (each release's dataset card, verbatim: \"License: CC0-1.0 — use, modify, " \
                "redistribute freely. Attribution requested (not required)\"; verifying the copyright " \
                "status of each underlying original book is the user's responsibility)"

      CREDIT = "Buddhist Digital Resource Center (BDRC) — transcriptions by the Asian Classics Input " \
               "Project via the Asian Legacy Library (ACIP Sungbum), by Palri Parkhang, and by Geshe " \
               "Dangsong Namgyal at UC Berkeley (Prof. Kurt Keutzer); page alignment by BDRC with " \
               "Dharmaduta (The BDRC Etext Corpus, Khyentse Foundation)."

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "BDRC Tibetan transcriptions (ACIP Sungbum, Palri Parkhang, Berkeley)",
          license: LICENSE,
          license_class: "open",
          upstream_url: "https://huggingface.co/BDRC",
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # Parallel replay (audited): #parse reads one volume file and keeps
      # no state across refs.
      def self.parallel_parse? = true

      # HTTP, not git: the revision probe is the per-release state file.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        RELEASES.map do |subdir, (repo, _name)|
          Nabu::Adapter::HttpProbeTarget.new(
            label: repo, zip_url: "#{Nabu::HfRowsFetch::API_BASE}/#{repo}", metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::HfRowsFetch::STATE_FILE, liveness_only: true
          )
        end
      end

      # The row id's parts, or nil when it does not carry the hierarchy.
      def self.row_parts(id)
        id.to_s.match(ROW_ID)
      end

      def initialize(rows_fetch: Nabu::HfRowsFetch.method(:sync!))
        super()
        @rows_fetch = rows_fetch
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        RELEASES.each_key do |subdir|
          volume_files(workdir, subdir).each do |path|
            volume = File.basename(path, ".jsonl")
            yield Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{subdir}:#{volume}", path: path,
                                        metadata: { "release" => subdir })
          end
        end
      end

      def discovery_skips(workdir)
        notes = []
        skipped = 0
        RELEASES.each do |subdir, (repo, _name)|
          present = SIDECARS.select { |name| File.file?(File.join(workdir, subdir, name)) }
          next if present.empty?

          skipped += present.size
          notes << "#{repo}: #{present.join(' + ')} — the dataset card / subset metadata " \
                   "(license provenance, not text), pinned and skipped by rule"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        subdir = document_ref.metadata.fetch("release")
        rows = read_rows(document_ref.path)
        pages = rows.filter_map do |row|
          text = Nabu::Normalize.nfc(row["transcription"].to_s).strip
          [row, text] unless text.empty?
        end
        raise Nabu::ParseError, "#{document_ref.id}: every page transcription is blank" if pages.empty?

        document = build_document(document_ref, subdir, rows, blank: rows.size - pages.size)
        pages.each_with_index { |(row, text), index| document << page_passage(document_ref.id, row, text, index) }
        document
      end

      def fetch(workdir, progress: nil, force: false)
        results = RELEASES.map do |subdir, (repo, _name)|
          dir = File.join(workdir, subdir)
          @rows_fetch.call(
            repo: repo, dir: dir, attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir),
            document_path: method(:volume_path), sort_key: method(:page_sort_key),
            sidecars: SIDECARS, progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
        end
        Nabu::FetchReport.new(
          sha: Digest::SHA256.hexdigest(results.map(&:sha).join("\n")), fetched_at: Time.now,
          notes: fetch_notes(results)
        )
      rescue Nabu::HfRowsFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def volume_files(workdir, subdir)
        Dir.glob(File.join(workdir, subdir, "*.jsonl"))
      end

      def volume_path(row)
        parts = self.class.row_parts(row["id"]) or return nil
        "#{parts[:ve]}.jsonl"
      end

      def page_sort_key(row)
        parts = self.class.row_parts(row["id"])
        parts ? parts[:image] : row["id"].to_s
      end

      def read_rows(path)
        SourceRead.utf8_file(path, label: SLUG).each_line(chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: not JSON Lines (#{e.message})"
      end

      def build_document(document_ref, subdir, rows, blank:)
        first = self.class.row_parts(rows.first&.fetch("id", nil)) or
          raise Nabu::ParseError, "#{document_ref.id}: no page row carries a BDRC row id"
        repo, name = RELEASES.fetch(subdir)
        mw_id = rows.first["mw_id"]
        Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: "#{name} — etext volume #{first[:ve]}#{" (BDRC #{mw_id})" if mw_id}",
          metadata: {
            "release" => subdir, "hf_dataset" => repo, "collection" => first[:collection],
            "release_tag" => first[:tag], "etext_instance" => first[:ie], "etext_volume" => first[:ve],
            "bdrc_version" => mw_id, "bdrc_url" => ("http://purl.bdrc.io/resource/#{mw_id}" if mw_id),
            "technology" => tally(rows, "technology"), "script" => tally(rows, "script"),
            "script_4" => tally(rows, "script_4"), "pages" => rows.size,
            "blank_pages" => (blank if blank.positive?)
          }.reject { |_key, value| value.nil? || value == {} }
        )
      end

      def tally(rows, key)
        rows.filter_map { |row| row[key] }.tally.sort.to_h
      end

      def page_passage(document_urn, row, text, sequence)
        parts = self.class.row_parts(row["id"]) or
          raise Nabu::ParseError, "#{document_urn}: page row #{row['id'].inspect} carries no scan file"
        Nabu::Passage.new(
          urn: "#{document_urn}:#{File.basename(parts[:image], '.*')}", language: LANGUAGE, text: text,
          sequence: sequence,
          annotations: { "row_id" => row["id"], "image" => parts[:image], "technology" => row["technology"],
                         "script" => row["script"], "script_4" => row["script_4"] }.compact
        )
      end

      def fetch_notes(results)
        counts = results.zip(RELEASES.keys).map do |result, subdir|
          state = result.not_modified ? "unchanged" : "#{result.rows} rows → #{result.documents} volumes"
          "#{subdir} @#{result.revision.to_s[0, 8]} #{state}"
        end
        unkeyed = results.sum(&:unkeyed)
        atticked = results.flat_map(&:atticked)
        ["#{RELEASES.size} releases: #{counts.join('; ')}",
         ("#{unkeyed} row(s) without a BDRC volume id" if unkeyed.positive?),
         attic_notes(atticked)].compact.join("; ")
      end
    end
  end
end
