# frozen_string_literal: true

require "fileutils"

require_relative "riig_epidoc_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The RIIG adapter (P25-1; the Celtic survey's star pick): Recueil
    # informatisé des inscriptions gauloises — 428 Gaulish inscriptions
    # (Gallo-Greek xtg-Grek, Gallo-Latin xtg-Latn), ANR project at
    # Ausonius/Bordeaux, riig.huma-num.fr. A thin composition of the
    # RiigEpidocParser family with a two-stage polite crawl.
    #
    # == License (two layers, both verbatim; the in-file grant GOVERNS)
    #
    # - EVERY record's EpiDoc <availability>: "Cette œuvre est mise à
    #   disposition selon les termes de la Licence Creative Commons
    #   Attribution 4.0 International" (licence target
    #   creativecommons.org/licenses/by/4.0/).
    # - The project page (fr) adds, over the site documentation: "L'ensemble
    #   de cette documentation est fournie en Open Access, sous la licence
    #   CC BY-NC-ND 4.0".
    # House doctrine (the Freising ruling): the machine-readable per-record
    # header governs the records we ingest → license_class "attribution".
    # The page-level BY-NC-ND covers the site documentation, which is never
    # fetched. Facsimile <graphic> images carry separate per-image rights
    # (CC BY-NC-ND, museum copyrights) and are never fetched either.
    #
    # == fetch: corpus map + polite record crawl (the ORACC html-en shape)
    #
    # Stage 1 — the corpus map: corpus.html?collection=RIIG embeds a GeoJSON
    # FeatureCollection ("placesgeo") carrying every record's riig id (plus
    # findspot name, WGS84 point, RIG concordance, language tag). It is
    # fetched through Nabu::FileFetch into <workdir>/map/corpus.html —
    # conditional GET, sha pin, attic retention, and the remote probe's
    # Last-Modified drift target for free.
    #
    # Stage 2 — the records: each id's EpiDoc XML from the verified stable
    # pattern documents/data/documents/RIIG/<ID>.xml into
    # <workdir>/documents/<ID>.xml. Sequential, CRAWL_DELAY between GETs,
    # resumable: an unchanged map (304) fetches only files missing locally,
    # a changed map re-crawls everything (no per-record Last-Modified
    # relied on). Writes are tmp+rename; the crawl never deletes (retention
    # by construction). ~6 MB total — the owner fires the first full crawl;
    # tests run WebMock-stubbed.
    #
    # == Translations (registry `translations: true`)
    #
    # Records carry French translation divs (per reading, prose). When the
    # registry opts in, discover yields one -fr sibling ref per record whose
    # file carries non-empty translation prose (a cheap byte peek), parsed
    # into <urn>-fr documents cited by reading id — the damaskini/ORACC -en
    # sibling pattern. Same CC BY 4.0 grant (same files) — no license
    # override. Coverage is partial upstream (AHP-01-01's translation div is
    # empty), so the peek, not a blanket flag, decides.
    #
    # == Reference edges (P25-1 deep extraction)
    #
    # Every record's RIG concordance (metadata "related": ["rig:G593", …])
    # becomes a kind=reference edge in the links journal after each sync
    # (reference_edges? + reference_producer "riig") — `nabu links` shows
    # the print-corpus concordance beside the passages; the compact "rig:"
    # key space is the stable citation form (hyphen variants deduped).
    class Riig < Nabu::Adapter
      BASE_URL = "https://riig.huma-num.fr"
      CORPUS_URL = "#{BASE_URL}/corpus.html?collection=RIIG".freeze
      DOCUMENT_BASE_URL = "#{BASE_URL}/documents/data/documents/RIIG/".freeze

      MAP_DIRNAME = "map"
      MAP_FILENAME = "corpus.html"
      DOCUMENTS_DIRNAME = "documents"

      # Seconds between record GETs — sequential and polite against a
      # huma-num host (the ORACC precedent); the crawl is small (~6 MB) and
      # resumable.
      CRAWL_DELAY = 0.25

      # A record id as the corpus map spells it (AHP-01-01, VAU-15-02…).
      RECORD_ID = /\A[A-Z0-9]{2,4}(?:-\d{2,3})+\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "riig",
        name: "RIIG — Recueil informatisé des inscriptions gauloises (Ausonius/ANR)",
        license: "CC BY 4.0 (per-record <licence> in every EpiDoc header: \"Cette œuvre est mise à " \
                 "disposition selon les termes de la Licence Creative Commons Attribution 4.0 " \
                 "International\" — the in-file grant governs; the project page's CC BY-NC-ND 4.0 " \
                 "covers the site documentation only, never fetched)",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "riig-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe HEADs the corpus map (reachability +
      # Last-Modified drift vs map/.file-fetch.json). No metadata endpoint
      # serves the license (it lives per-record inside the XML), so the
      # probe's license row honestly reads unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "corpus-map", zip_url: CORPUS_URL, metadata_url: nil,
          state_subdir: MAP_DIRNAME, state_file: FileFetch::STATE_FILE
        )]
      end

      # The RIG concordance edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "riig")
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter for
      # the opted-in registry row; +crawl_delay+ exists for the WebMock'd
      # tests (0) — real syncs keep the polite default.
      def initialize(translations: false, crawl_delay: CRAWL_DELAY)
        super()
        @translations = translations
        @crawl_delay = crawl_delay
      end

      # One DocumentRef per crawled record (plus the -fr sibling for
      # translated records when opted in), sorted by urn. A workdir without
      # documents/ yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        if document_ref.metadata["kind"] == "translation"
          parse_translation(document_ref)
        else
          RiigEpidocParser.new.parse(document_ref.path, urn: document_ref.id)
        end
      end

      # Map via FileFetch (prepare → breaker → complete), then the polite
      # record crawl (see class note). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        map = map_fetch(workdir, progress)
        map.prepare!
        guard_mass_deletion!(workdir, map.doomed_paths, force: force)
        map.complete!
        ids = corpus_ids(workdir)
        counts = crawl_records!(workdir, ids, map_changed: !map.not_modified?, progress: progress)
        report(map, ids, counts)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "riig fetch failed into #{workdir}: #{e.message}"
      end

      private

      def map_fetch(workdir, progress)
        FileFetch.new(
          url: CORPUS_URL, dir: File.join(workdir, MAP_DIRNAME), filename: MAP_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, MAP_DIRNAME), progress: progress
        )
      end

      # The unique record ids out of the fetched corpus map's embedded
      # GeoJSON ("riig" properties). Zero ids = the page shape changed
      # upstream — loud, never a silent empty sync.
      def corpus_ids(workdir)
        path = File.join(workdir, MAP_DIRNAME, MAP_FILENAME)
        raise Nabu::FetchError, "riig fetch: corpus map #{path} is missing after fetch" unless File.file?(path)

        ids = File.read(path).scan(/"riig":"([^"]+)"/).flatten.map(&:strip).grep(RECORD_ID).uniq.sort
        if ids.empty?
          raise Nabu::FetchError,
                "riig fetch: no record ids found in #{path} (upstream page shape changed?)"
        end

        ids
      end

      # Sequential, polite, resumable (class note). tmp+rename writes; a
      # non-200 aborts the sync loudly.
      def crawl_records!(workdir, ids, map_changed:, progress: nil)
        dir = File.join(workdir, DOCUMENTS_DIRNAME)
        FileUtils.mkdir_p(dir)
        progress&.call("Crawling #{ids.size} RIIG records…")
        counts = { fetched: 0, cached: 0 }
        ids.each do |id|
          target = File.join(dir, "#{id}.xml")
          next counts[:cached] += 1 if File.file?(target) && !map_changed

          sleep(@crawl_delay) if @crawl_delay.positive? && counts[:fetched].positive?
          File.binwrite("#{target}.tmp", get_record(id))
          File.rename("#{target}.tmp", target)
          counts[:fetched] += 1
        end
        counts
      end

      def get_record(id)
        url = "#{DOCUMENT_BASE_URL}#{id}.xml"
        response = FileFetch.default_http.get(url)
        raise Nabu::FetchError, "riig record crawl: HTTP #{response.status} for #{url}" unless response.status == 200

        response.body.to_s
      rescue Faraday::Error => e
        raise Nabu::FetchError, "riig record crawl: transport error for #{url}: #{e.message}"
      end

      def report(map, ids, counts)
        Nabu::FetchReport.new(
          sha: map.sha, fetched_at: Time.now,
          notes: "map=#{map.sha.to_s[0, 12]} · documents: #{counts[:fetched]} fetched, " \
                 "#{counts[:cached]} cached (#{ids.size} ids)",
          repos: { CORPUS_URL => map.sha }
        )
      end

      # -- discovery -------------------------------------------------------------

      def document_refs(workdir)
        Dir.glob(File.join(workdir, DOCUMENTS_DIRNAME, "*.xml")).flat_map do |path|
          record_refs(File.expand_path(path))
        end.sort_by(&:id)
      end

      def record_refs(path)
        urn = "#{RiigEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: path)]
        if @translations && translated?(path)
          refs << Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{urn}-fr", path: path,
            metadata: { "kind" => "translation" }
          )
        end
        refs
      end

      # Cheap byte peek: does the file carry a translation div with real
      # prose? (Empty <div type="translation"/> — AHP-01-01 — must not mint
      # a sibling.)
      def translated?(path)
        File.read(path).scan(%r{<div type="translation"[^>]*>(.*?)</div>}m).any? do |(body)|
          body.match?(/<p[ >][^<]*\S|<p>\s*\S/m) && body.gsub(/<[^>]+>/, "").match?(/\S/)
        end
      end

      # The -fr sibling: one French passage per translation paragraph,
      # cited by reading id (RiigEpidocParser#translations).
      def parse_translation(document_ref)
        original_urn = document_ref.id.delete_suffix("-fr")
        parser = RiigEpidocParser.new
        original = parser.parse(document_ref.path, urn: original_urn)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "fra",
          title: original.title ? "#{original.title} — French translation" : nil,
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        parser.translations(document_ref.path).each_with_index do |(cite, text), sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{cite}", language: "fra", text: text, sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: no translation prose found for #{document_ref.id}" if document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end
    end
  end
end
