# frozen_string_literal: true

require "cgi"

require_relative "source_read"
require_relative "statutes_realm_dating"
require_relative "statutes_realm_toc"
require_relative "statutes_realm_page_parser"
require_relative "../statutes_realm_fetch"

module Nabu
  module Adapters
    # Statutes of the Realm, vols 5–7 (P160-7): the Acts of the Parliament
    # of England 1625–1701 — Charles I (the Petition of Right, the Long
    # Parliament's acts of 1640–42), Charles II's Restoration statute book,
    # James II, William and Mary (the Bill of Rights, the Toleration and
    # Triennial Acts), William III (the Act of Settlement) — in John
    # Raithby's Record Commission edition (vols 5–6 1819, vol 7 1820), as
    # British History Online (IHR, University of London) serves them,
    # double-rekeyed. A thin composition of StatutesRealmToc +
    # StatutesRealmPageParser with the StatutesRealmFetch crawl.
    #
    # == License (first-hand, 2026-11-05) — the per-page statement governs
    #
    # Every act page, and each volume TOC, reads verbatim: "This free content
    # was digitised by double rekeying. Public Domain." (read on vol5/p1a,
    # vol5/p179, vol6/p1, vol7/pp1-4, vol7/p750 and the vol5–7 TOCs,
    # 2026-11-05; first recorded on the vol5 TOC 2026-11-03). The SITE-WIDE
    # Terms of use (/terms, read 2026-11-05) say otherwise for the site at
    # large — "1. Licence: Unless otherwise stated, the copyright and other
    # intellectual property rights in all material on this site … are owned
    # or controlled by the University of London or the History of
    # Parliament Trust … for non-commercial or your own personal use only
    # … No part of this site may be reproduced or stored in any other web
    # site or included in any public or private electronic retrieval system
    # or service without … prior written permission." THE CONFLICT, recorded:
    # the terms' own "Unless otherwise stated" yields to the per-page
    # statement, and this series is so stated, page by page — the texts are
    # Public Domain (Raithby's edition is 1819–20; the statutes themselves
    # are Crown legislation of 1625–1701) → license_class open, FOR THIS
    # SERIES ONLY; other BHO series stay under the site terms. The parser
    # refuses any page that lacks the statement (a ParseError — quarantined,
    # never admitted under the series' class). Images (the engraving
    # plates) are never fetched.
    #
    # == Grains (enumerated 2026-11-05 against all three live volume TOCs)
    #
    #   TOC page       /statutes-realm/vol<V>?page=<p> — the manifest;
    #                  persisted as toc/vol<V>-page-<p>.html sidecars,
    #                  SKIPPED BY RULE at discover (9 pages: 4 + 2 + 3).
    #   act page       "<Reign>, <session>: <title>" — the DOCUMENT (656).
    #   private-acts   "<Reign>, <session>: The Private Acts" — vol 7's five
    #   schedule       schedules of private-act titles under the roll's
    #                  Latin formula — roll text, ACCEPTED as documents.
    #   index letter   "Index: A" … — Raithby's subject index; rejected (53).
    #   preface,       Raithby's editorial front matter; the chronological
    #   chron. table   table restates the TOC's act titles; rejected (5).
    #   engraving      a plate page (image + caption); rejected (4).
    #   vols 1–4       NOT on BHO: /statutes-realm/vol1 … vol4 answer 404
    #                  (probed 2026-11-05) — the series starts at 1625 here.
    #
    # == Count reconciliation (the live TOCs, 2026-11-05)
    #
    # The first count of the series, "723 act pages (vol5 311 · vol6 192 ·
    # vol7 220)" (2026-11-03), counts TOC ROWS, not acts. Per volume: vol5 311 = 291 acts + 16 index
    # + 2 front + 2 engravings; vol6 192 = 172 acts + 19 index + 1 front;
    # vol7 220 = 193 acts + 5 private-acts schedules + 18 index + 2 front +
    # 2 engravings. Accepted 661 (656 acts + 5 schedules) + rejected by rule
    # 62 = 723 = upstream's own rows; residue 0. Expected first sync: 661
    # documents, 9 TOC sidecars + 62 rejected rows skipped by rule.
    #
    # == Overlap (recorded, not deduplicated)
    #
    # eebo-tcp carries contemporary PRINTED statute collections (Manby's
    # 1667 Collection of the Statutes, the sessional prints, Keble's and
    # Wingate's abridgements) — different editions of the same acts, from
    # the King's Printer's prints, not Raithby's roll-collated text. Both are
    # ingested with their own provenance; nothing here links or suppresses.
    #
    # == Discover
    #
    # The TOC sidecars are the manifest when the workdir carries them: an
    # accepted row whose page is on disk mints a ref (TOC order); a page no
    # row names is censused unrecognized and not minted. A tree WITHOUT toc/
    # (the attic replay — retained pages keep no sidecar) classes each page
    # by its own title, so an upstream-deleted act stays discoverable.
    #
    # == fetch / sync policy
    #
    # StatutesRealmFetch: 9 TOC GETs + 661 page GETs at 1 s → ~12–15 min
    # first crawl, resumable at the file grain. sync_policy manual, wired:
    # false until the first real sync is verified.
    class StatutesRealm < Nabu::Adapter
      BASE_URL = Nabu::StatutesRealmFetch::BASE_URL

      CITATION = "Statutes of the Realm, vols 5–7, ed. John Raithby (Great Britain Record Commission, 1819–1820), " \
                 "via British History Online (Institute of Historical Research, University of London), " \
                 "https://www.british-history.ac.uk/series/statutes-realm — digitised by double rekeying, Public Domain"

      MANIFEST = Nabu::SourceManifest.new(
        id: "statutes-realm",
        name: "Statutes of the Realm, vols 5–7 (1625–1701; Raithby, via British History Online)",
        license: "Public Domain — every page of the series states \"This free content was digitised by double " \
                 "rekeying. Public Domain.\" (read 2026-11-05). This overrides, for this series only, the " \
                 "BHO site-wide Terms of use, whose licence clause opens \"Unless otherwise stated\" " \
                 "(non-commercial, no reproduction in a retrieval system) — the series is otherwise stated. " \
                 "Images are not fetched.",
        license_class: "open",
        upstream_url: "#{BASE_URL}/series/statutes-realm",
        parser_family: "statutes-realm-html",
        credit: CITATION
      )

      PAGE_TITLE = %r{<h2 class="page-title"><span>(.*?)</span>}m

      def self.manifest
        MANIFEST
      end

      # No git repo — the probe GETs the first TOC page (reachability; the
      # fetch ledger holds the content pin).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "statutes-realm vol5 TOC",
          zip_url: Nabu::StatutesRealmFetch.toc_url(BASE_URL, 5, 0),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::StatutesRealmFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::StatutesRealmFetch::DELAY)
        super()
        @delay = delay
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir)[:refs].each(&block)
      end

      def discovery_skips(workdir)
        census = census(workdir)
        DiscoverySkips.new(skipped_by_rule: census[:by_rule], unrecognized: census[:unrecognized].size,
                           notes: census[:unrecognized] + census[:rule_notes])
      end

      def parse(document_ref)
        meta = document_ref.metadata
        row = StatutesRealmToc::Row.new(volume: meta["volume"], slug: File.basename(document_ref.path, ".html"),
                                        title: meta["toc_title"].to_s, pages: meta["pages"].to_s,
                                        grain: meta["grain"]&.to_sym)
        StatutesRealmPageParser.new.parse(document_ref.path, urn: document_ref.id, row: row)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the network).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::StatutesRealmFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::StatutesRealmFetch::Error => e
        raise Nabu::FetchError, "statutes-realm fetch failed into #{workdir}: #{e.message}"
      end

      private

      def urn_for(volume, slug) = "urn:nabu:statutes-realm:vol#{volume}:#{slug}"

      # One pass over the workdir: the refs discover yields and the skip
      # census discovery_skips reports — the same classification for both.
      def census(workdir)
        sidecars = toc_sidecars(workdir)
        pages = page_files(workdir)
        return title_census(pages) if sidecars.empty?

        rows = toc_rows(sidecars)
        named = rows.to_set { |row| [row.volume, row.slug] }
        refs = []
        unrecognized = []
        rows.each do |row|
          next unless row.accepted?

          path = pages[[row.volume, row.slug]]
          if path.nil?
            unrecognized << "vol#{row.volume}/#{row.slug}: listed #{grain_label(row.grain)} page missing " \
                            "on disk — a fetch hole"
          else
            refs << ref(row.volume, row.slug, path, row)
          end
        end
        rows.select { |row| row.grain == :unknown }.each do |row|
          unrecognized << "vol#{row.volume}/#{row.slug}: TOC row of no known grain (#{row.title.inspect})"
        end
        pages.each_key do |volume, slug|
          next if named.include?([volume, slug])

          unrecognized << "vol#{volume}/#{slug}.html: on disk but named by no TOC row"
        end
        rejected = rows.reject { |row| row.accepted? || row.grain == :unknown }
        { refs: refs, unrecognized: unrecognized, by_rule: sidecars.size + rejected.size,
          rule_notes: rule_notes(sidecars.size, rejected) }
      end

      # The TOC-less tree (the attic): each page classed by its own title.
      def title_census(pages)
        refs = []
        unrecognized = []
        rejected = 0
        pages.sort.each do |(volume, slug), path|
          title = page_title(path)
          grain = StatutesRealmToc.grain(title)
          if StatutesRealmToc::ACCEPTED.include?(grain)
            refs << ref(volume, slug, path, nil, grain: grain)
          elsif grain == :unknown
            unrecognized << "vol#{volume}/#{slug}.html: page title of no known grain (#{title.inspect})"
          else
            rejected += 1
          end
        end
        notes = rejected.positive? ? ["#{rejected} rejected-grain pages skipped by rule"] : []
        { refs: refs, unrecognized: unrecognized, by_rule: rejected, rule_notes: notes }
      end

      def ref(volume, slug, path, row, grain: row&.grain)
        metadata = { "volume" => volume, "grain" => grain.to_s }
        if row
          metadata["pages"] = row.pages unless row.pages.empty?
          metadata["toc_title"] = row.title
        end
        Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(volume, slug), path: path, metadata: metadata)
      end

      def rule_notes(sidecar_count, rejected)
        notes = []
        notes << "#{sidecar_count} TOC pages (the manifest grain) skipped by rule" if sidecar_count.positive?
        rejected.group_by(&:grain).sort_by { |grain, _| grain.to_s }.each do |grain, rows|
          notes << "#{rows.size} #{grain_label(grain)} rows skipped by rule"
        end
        notes
      end

      def grain_label(grain)
        { act: "act", private_acts: "private-acts", index: "index", front_matter: "front-matter",
          engraving: "engraving" }.fetch(grain, grain.to_s)
      end

      # [[volume, page, path]] sorted by volume then page number.
      def toc_sidecars(workdir)
        sidecars = Dir.glob(File.join(workdir, Nabu::StatutesRealmFetch::TOC_DIR, "*.html")).filter_map do |path|
          match = Nabu::StatutesRealmFetch::TOC_FILENAME.match(File.basename(path)) or next
          [Integer(match[1], 10), Integer(match[2], 10), File.expand_path(path)]
        end
        sidecars.sort_by { |volume, page, _| [volume, page] }
      end

      # Every TOC row the sidecars carry, in volume/page order, each once.
      def toc_rows(sidecars)
        rows = sidecars.flat_map do |volume, _page, path|
          StatutesRealmToc.rows(SourceRead.utf8_file(path, label: "statutes-realm TOC"), volume: volume)
        end
        rows.uniq { |row| [row.volume, row.slug] }
      end

      # {[volume, slug] => path} for every page file on disk.
      def page_files(workdir)
        Dir.glob(File.join(workdir, "vol*", "*.html")).each_with_object({}) do |path, pages|
          rel = path.delete_prefix("#{workdir.chomp('/')}/")
          match = Nabu::StatutesRealmFetch::PAGE_RELPATH.match(rel) or next
          pages[[Integer(match[1], 10), match[2]]] = File.expand_path(path)
        end
      end

      def page_title(path)
        raw = SourceRead.utf8_file(path, label: "statutes-realm page")[PAGE_TITLE, 1].to_s
        CGI.unescapeHTML(raw).gsub(/[[:space:]]+/, " ").strip
      end

      def fetch_notes(result)
        base = "#{result.toc_pages} TOC pages (#{result.rows} rows, #{result.accepted} accepted; " \
               "#{result.fetched} pages fetched, #{result.cached} already on disk)"
        named = result.missing.first(3).join(", ")
        missing = result.missing.empty? ? nil : "#{result.missing.size} listed pages 404 (#{named})"
        [base, missing, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
