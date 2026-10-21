# frozen_string_literal: true

require_relative "lotsawa_html_parser"
require_relative "../lotsawa_fetch"

module Nabu
  module Adapters
    # Lotsawa House (lotsawahouse.org; Lotsawa House CIC, UK; ISSN
    # 2753-4812) — "a virtual library of translations from Tibetan": the
    # liturgical, terma, instruction, praise and biographical literature of
    # Tibetan Buddhism by 350+ Tibetan and Indian masters plus sūtras and
    # dhāraṇīs ("Words of the Buddha"), each served as a Tibetan source page
    # and translation pages in up to eight languages. The NON-canonical
    # Tibetan literature shelf the Kangyur/Tengyur holdings lack.
    #
    # == Upstream and its delivery grains (census 2026-10-21)
    #
    # No bulk export, no sitemap (/sitemap.xml 404), robots.txt disallowing
    # only search and app paths. Grains:
    #
    #   text page        /<lang>/<collection>/<author>/<slug> (collections
    #                    tibetan-masters, indian-masters) or
    #                    /<lang>/words-of-the-buddha/<slug>; en unprefixed.
    #                    ACCEPTED — one document per (language, text).
    #   listing pages    the per-language explore page, the Words of the
    #                    Buddha page, the per-author listings — the CATALOG
    #                    grain: crawled, persisted under catalog/, skipped by
    #                    rule (discovery_skips).
    #   topic pages      /<lang>/topics/<slug>/ — a second catalog over the
    #                    same texts; NOT crawled (the topics ride every text
    #                    page's own category tags).
    #   EPUB/PDF         POST-generated per page (dl_dynamic) — derivative
    #                    renderings of the same text; NOT fetched.
    #   rss.xml, about/project pages, images — not texts; NOT fetched.
    #
    # Scale (the "about" page: "more than 6000 texts in nine languages — the
    # writings of over 350 authors on more than 300 topics"; the explore
    # pages list 387 en / 386 bo author listings, de 93 · es 112 · fr 149 ·
    # it 48 · pt 65, nl 34 and zh 207 texts listed directly; a 30-author
    # random sample of en/bo listings averaged 3.6 texts each → ~1,380 en
    # and ~1,380 bo texts). The crawl is PACED (1 req/s): bo only ≈ 1,750
    # requests ≈ 30 min; all nine languages ≈ 7,000–7,800 requests ≈ 2–2.2 h
    # for a first sync, resumable at the file grain (re-syncs re-walk the
    # ~1,250 listings ≈ 21 min and fetch only new pages). Reconciliation
    # against the site's own "6000+ texts" figure is a first-sync duty.
    #
    # == Identity and documents
    #
    # urn:nabu:lotsawa-house:<lang>:<path> (lang the site's code; path
    # "tibetan-masters/mipham/acala-sadhana"). The bo page is the ORIGINAL
    # (language xct — the classical literary language from the 8th-century
    # translations to living authors; declared coarse); every other page is
    # a translation document (metadata kind translation + translation_of
    # → the bo urn whenever the page lists a Tibetan version) in eng / deu
    # / spa / fra / ita / nld / por / cmn. NO sibling declaration: the
    # pages' block structures do not align paragraph for paragraph, so a
    # suffix-paired parallel view would mis-pair — the link is metadata.
    # Passages and page metadata: LotsawaHtmlParser (the lotsawa-html
    # family). Restricted-practice texts (the site's "Restricted" tag —
    # served openly with an advisory popup) carry restricted: true.
    #
    # == License (verified verbatim 2026-10-21, /about/terms, updated Feb 2023)
    #
    # "All texts on Lotsawa House are covered by the Creative Commons
    # Attribution-NonCommercial 4.0 International License."; General User
    # Rights license users to "read, download, make copies, print, search,
    # or link to the full text of each Lotsawa House translation, crawl each
    # page for indexing (subject to reasonable network usage constraints)";
    # metadata is CC0. Footer: "This work is licensed under a Creative
    # Commons Attribution-NonCommercial 4.0 International License." → nc.
    #
    # == fetch / sync policy
    #
    # Nabu::LotsawaFetch (the paced resumable crawl). The registry row's
    # translations: posture sets the scope: false → the Tibetan pages only;
    # true → all nine languages. A living site → sync_policy manual.
    class LotsawaHouse < Nabu::Adapter
      URN_PREFIX = "urn:nabu:lotsawa-house:"
      ORIGINAL = "bo"
      PAGE = %r{\A(#{LotsawaFetch::LANGUAGES.join('|')})/((?:tibetan-masters|indian-masters)/[^/]+/[^/]+|words-of-the-buddha/[^/]+)\.html\z}

      MANIFEST = Nabu::SourceManifest.new(
        id: "lotsawa-house",
        name: "Lotsawa House — Tibetan Buddhist texts and translations",
        license: "CC BY-NC 4.0 — /about/terms (last updated February 2023) verbatim: \"All texts on " \
                 "Lotsawa House are covered by the Creative Commons Attribution-NonCommercial 4.0 " \
                 "International License.\"; General User Rights grant users to \"read, download, make " \
                 "copies, print, search, or link to the full text of each Lotsawa House translation, " \
                 "crawl each page for indexing (subject to reasonable network usage constraints)\"; " \
                 "metadata CC0 (verified 2026-10-21)",
        license_class: "nc",
        upstream_url: LotsawaFetch::BASE_URL,
        parser_family: "lotsawa-html",
        credit: "Lotsawa House (lotsawahouse.org, ISSN 2753-4812) and its translators, credited per text"
      )

      def self.manifest = MANIFEST

      # No git: the probe GETs one stable text page (reachability; the site
      # serves no Last-Modified, so the ledger pin never drifts from a probe).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "tibetan-masters/mipham/instruction-on-point-of-mind",
          zip_url: "#{LotsawaFetch::BASE_URL}/tibetan-masters/mipham/instruction-on-point-of-mind",
          metadata_url: nil, state_subdir: "", state_file: LotsawaFetch::STATE_FILE
        )]
      end

      # +translations+ (the registry posture): ingest the translation pages
      # too. +delay+ exists for the WebMock'd tests.
      def initialize(translations: false, delay: LotsawaFetch::DELAY)
        super()
        @translations = translations
        @delay = delay
        @parser = LotsawaHtmlParser.new
      end

      def languages = @translations ? LotsawaFetch::LANGUAGES : [ORIGINAL]

      # One ref per in-scope page file: the Tibetan pages first, then the
      # translation languages in the site's order, paths sorted within.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        root = File.join(workdir, LotsawaFetch::PAGES_DIR)
        languages.each do |lang|
          Dir.glob("**/*.html", base: File.join(root, lang)).sort.each do |rel|
            match = PAGE.match("#{lang}/#{rel}") or next
            yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{lang}:#{match[2]}",
                                        path: File.expand_path(File.join(root, lang, rel)),
                                        metadata: { "lang" => lang, "path" => match[2] })
          end
        end
      end

      # The catalog grain (listing pages under catalog/) by rule; a page
      # file outside the path grammar is unrecognized.
      def discovery_skips(workdir)
        listings = Dir.glob("#{LotsawaFetch::CATALOG_DIR}/**/*.html", base: workdir).sort
        strays = languages.flat_map do |lang|
          Dir.glob("#{LotsawaFetch::PAGES_DIR}/#{lang}/**/*.html", base: workdir)
             .reject { |rel| PAGE.match?(rel.delete_prefix("#{LotsawaFetch::PAGES_DIR}/")) }
        end
        notes = []
        unless listings.empty?
          notes << "#{listings.size} catalog listing page(s) skipped — the explore/author/scripture listing " \
                   "grain, not a text (#{listings.first(3).join(', ')}#{', …' if listings.size > 3})"
        end
        unless strays.empty?
          notes << "#{strays.size} page file(s) outside the path grammar (#{strays.first(3).join(', ')})"
        end
        DiscoverySkips.new(skipped_by_rule: listings.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        lang = document_ref.metadata.fetch("lang")
        path = document_ref.metadata.fetch("path")
        @parser.parse(document_ref.path, urn: document_ref.id, lang: lang, metadata: path_metadata(path),
                                         original_urn: "#{URN_PREFIX}#{ORIGINAL}:#{path}")
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = LotsawaFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), languages: languages,
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue LotsawaFetch::Error => e
        raise Nabu::FetchError, "lotsawa-house fetch failed into #{workdir}: #{e.message}"
      end

      private

      def path_metadata(path)
        segments = path.split("/")
        meta = { "collection" => segments.first, "path" => path }
        meta["author_slug"] = segments[1] if segments.size == 3
        meta
      end

      def fetch_notes(result)
        base = "#{result.languages.join('/')} catalog walked (#{result.listings} listing pages, " \
               "#{result.records} text pages; #{result.fetched} fetched, #{result.cached} already on disk)"
        missing = if result.missing.empty?
                    nil
                  else
                    "#{result.missing.size} listed page(s) 404 upstream " \
                      "(#{result.missing.first(3).join(', ')})"
                  end
        [base, missing, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
