# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "ig_cyprus_epidoc_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The IG XV 1,1 adapter: Inscriptiones Graecae XV 1,1 — Inscriptiones
    # Cypri syllabicae (Amathus, Kurion, Marion; ed. Karnava/Perna with
    # Egetmeyer, Berlin 2020) from the Berlin-Brandenburg academy's IG
    # digital edition (telota.bbaw.de/ig): 593 records of Greek in the
    # Cypriot syllabary and Eteocypriot, with bilinguals beside alphabetic
    # Greek. A thin composition of IgCyprusEpidocParser with the riig
    # two-stage polite crawl.
    #
    # == License (the in-file grant governs)
    #
    # EVERY record's <availability><licence target=".../by/4.0/legalcode">,
    # verbatim: "Creative Commons Attribution 4.0 International
    # (https://creativecommons.org/licenses/by/4.0/legalcode). All reuse or
    # distribution of this work must contain somewhere a link back to this
    # page." → CC BY 4.0, license_class "attribution". The link-back clause
    # is the attribution form the grantor asks for; every document carries
    # its edition page URL (metadata "uri", the record's idno type=URI) so
    # downstream reuse can honor it.
    #
    # == fetch: the IG listing + polite record crawl (the riig shape)
    #
    # Stage 1 — the listing: api/inscriptions is ONE JSON object for the
    # whole digital edition, keyed "<fascicle> || <title>" → an array of
    # plain id strings. Fetched through Nabu::FileFetch into
    # <workdir>/map/inscriptions.json (sha pin, attic retention, the remote
    # probe's target). corpus_ids reads THE ONE key prefixed "IG XV 1, 1 ||"
    # and enumerates its ids VERBATIM — numbering is sparse with suffixed
    # ids (237(I), 254(1)…), so ranges are never generated. A missing key,
    # an empty id list or an id outside the censused shapes aborts loudly.
    #
    # Stage 2 — the records: api/xml/<id> (spaces percent-encoded; the
    # comma and parentheses are legal path characters and the server
    # answers them as-is) into <workdir>/documents/<stem>.xml, stem per
    # IgCyprusEpidocParser.stem_for ("IG XV 1, 237(I)" → 237-I.xml,
    # reversible via .id_for). Sequential, CRAWL_DELAY between GETs,
    # tmp+rename writes, never deletes (retention by construction); a
    # non-200 aborts the sync (ids absent upstream answer 500).
    #
    # Resumability: upstream sends no Last-Modified or ETag (observed
    # 2026-10-18), so the listing never answers 304 — an UNCHANGED listing
    # body (the same sha256 as the stored pin) stands in for it and the
    # crawl fetches only records missing locally; a changed listing (any
    # volume of the edition) re-crawls the fascicle. Per-record revisions
    # upstream are therefore picked up only with a listing change — the
    # riig limitation, inherited.
    #
    # == Sibling layers
    #
    # Each record's alphabetic-Greek transcription mints a -transcription
    # sibling (always — it is an edition layer, the isicily -translit
    # shape) and its German translation a -de sibling (registry
    # `translations: true`), where the parser's own extraction finds
    # citable numbered lines.
    class IgCyprus < Nabu::Adapter
      BASE_URL = "https://telota.bbaw.de/ig"
      LISTING_URL = "#{BASE_URL}/api/inscriptions".freeze
      RECORD_BASE_URL = "#{BASE_URL}/api/xml/".freeze

      FASCICLE_PREFIX = "IG XV 1, 1 ||"

      MAP_DIRNAME = "map"
      MAP_FILENAME = "inscriptions.json"
      DOCUMENTS_DIRNAME = "documents"

      # Seconds between record GETs — sequential and polite against an
      # academy host; 593 small records, resumable.
      CRAWL_DELAY = 0.25

      TRANSCRIPTION_LAYER = "transcription"
      TRANSLATION_LAYER = "de"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ig-cyprus",
        name: "IG XV 1,1 — Inscriptiones Cypri syllabicae (BBAW Inscriptiones Graecae digital edition)",
        license: "CC BY 4.0 (per-record <licence> in every EpiDoc header, verbatim: \"Creative Commons " \
                 "Attribution 4.0 International (https://creativecommons.org/licenses/by/4.0/legalcode). " \
                 "All reuse or distribution of this work must contain somewhere a link back to this " \
                 "page.\" — the link-back target is each record's edition page, metadata \"uri\")",
        license_class: "attribution",
        upstream_url: "#{BASE_URL}/",
        parser_family: "ig-cyprus-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # No git repo: the probe HEADs the listing (reachability; upstream
      # carries no Last-Modified, so drift reads unknown). The license
      # lives per-record inside the XML — no metadata endpoint.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "inscriptions-listing", zip_url: LISTING_URL, metadata_url: nil,
          state_subdir: MAP_DIRNAME, state_file: FileFetch::STATE_FILE
        )]
      end

      # The record API URL for a listing id.
      def self.record_url(id)
        "#{RECORD_BASE_URL}#{id.gsub(' ', '%20')}"
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter;
      # +crawl_delay+ exists for the WebMock'd tests (0).
      def initialize(translations: false, crawl_delay: CRAWL_DELAY)
        super()
        @translations = translations
        @crawl_delay = crawl_delay
      end

      # One DocumentRef per crawled record plus its citable layers, sorted
      # by urn. A workdir without documents/ yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, DOCUMENTS_DIRNAME, "*.xml"))
           .flat_map { |path| record_refs(File.expand_path(path)) }
           .sort_by(&:id)
           .each(&block)
      end

      def parse(document_ref)
        IgCyprusEpidocParser.new.parse(document_ref.path, urn: document_ref.id,
                                                          layer: document_ref.metadata["layer"])
      end

      # Listing via FileFetch (prepare → breaker → complete), then the
      # polite record crawl (class note). No network in tests: WebMock.
      def fetch(workdir, progress: nil, force: false)
        previous_sha = stored_sha(workdir)
        map = map_fetch(workdir, progress)
        map.prepare!
        guard_mass_deletion!(workdir, map.doomed_paths, force: force)
        map.complete!
        ids = corpus_ids(workdir)
        unchanged = map.not_modified? || (!previous_sha.nil? && map.sha == previous_sha)
        counts = crawl_records!(workdir, ids, map_changed: !unchanged, progress: progress)
        report(map, ids, counts)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ig-cyprus fetch failed into #{workdir}: #{e.message}"
      end

      private

      def map_fetch(workdir, progress)
        FileFetch.new(
          url: LISTING_URL, dir: File.join(workdir, MAP_DIRNAME), filename: MAP_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, MAP_DIRNAME), progress: progress
        )
      end

      def stored_sha(workdir)
        state = File.join(workdir, MAP_DIRNAME, FileFetch::STATE_FILE)
        return nil unless File.file?(state)

        JSON.parse(File.read(state))["sha256"]
      rescue JSON::ParserError
        nil
      end

      # The fascicle's ids, verbatim and in listing order (class note).
      def corpus_ids(workdir)
        path = File.join(workdir, MAP_DIRNAME, MAP_FILENAME)
        raise Nabu::FetchError, "ig-cyprus fetch: listing #{path} is missing after fetch" unless File.file?(path)

        listing = parse_listing(path)
        key = listing.keys.find { |k| k.start_with?(FASCICLE_PREFIX) }
        if key.nil?
          raise Nabu::FetchError, "ig-cyprus fetch: no #{FASCICLE_PREFIX.inspect} fascicle key in #{path} " \
                                  "(upstream listing shape changed?)"
        end

        ids = Array(listing[key]).map(&:to_s).uniq
        raise Nabu::FetchError, "ig-cyprus fetch: no record ids under #{key.inspect} in #{path}" if ids.empty?

        strays = ids.reject { |id| IgCyprusEpidocParser.stem_for(id) }
        unless strays.empty?
          raise Nabu::FetchError, "ig-cyprus fetch: ids outside the censused shape under #{key.inspect}: " \
                                  "#{strays.first(5).join(' · ')} (extend IgCyprusEpidocParser::ID_SHAPE)"
        end

        ids
      end

      def parse_listing(path)
        listing = JSON.parse(File.read(path))
        raise Nabu::FetchError, "ig-cyprus fetch: listing #{path} is not a JSON object" unless listing.is_a?(Hash)

        listing
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "ig-cyprus fetch: listing #{path} is not valid JSON: #{e.message}"
      end

      # Sequential, polite, resumable (class note).
      def crawl_records!(workdir, ids, map_changed:, progress: nil)
        dir = File.join(workdir, DOCUMENTS_DIRNAME)
        FileUtils.mkdir_p(dir)
        progress&.call("Crawling #{ids.size} IG XV 1,1 records…\n")
        counts = { fetched: 0, cached: 0 }
        ids.each do |id|
          target = File.join(dir, "#{IgCyprusEpidocParser.stem_for(id)}.xml")
          next counts[:cached] += 1 if File.file?(target) && !map_changed

          sleep(@crawl_delay) if @crawl_delay.positive? && counts[:fetched].positive?
          File.binwrite("#{target}.tmp", get_record(id))
          File.rename("#{target}.tmp", target)
          counts[:fetched] += 1
        end
        counts
      end

      def get_record(id)
        url = self.class.record_url(id)
        response = FileFetch.default_http.get(url)
        unless response.status == 200
          raise Nabu::FetchError, "ig-cyprus record crawl: HTTP #{response.status} for #{url}"
        end

        response.body.to_s
      rescue Faraday::Error => e
        raise Nabu::FetchError, "ig-cyprus record crawl: transport error for #{url}: #{e.message}"
      end

      def report(map, ids, counts)
        Nabu::FetchReport.new(
          sha: map.sha, fetched_at: Time.now,
          notes: "listing=#{map.sha.to_s[0, 12]} · documents: #{counts[:fetched]} fetched, " \
                 "#{counts[:cached]} cached (#{ids.size} ids)",
          repos: { LISTING_URL => map.sha }
        )
      end

      # -- discovery -------------------------------------------------------------

      def record_refs(path)
        urn = "#{IgCyprusEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: path)]
        record_layers(path).each do |layer|
          next if layer == TRANSLATION_LAYER && !@translations

          refs << Nabu::DocumentRef.new(source_id: manifest.id, id: "#{urn}-#{layer}", path: path,
                                        metadata: { "layer" => layer })
        end
        refs
      end

      # The layer-minting decision is the parser's own extraction; an
      # unreadable record mints no layers — its base ref carries the
      # honest quarantine.
      def record_layers(path)
        IgCyprusEpidocParser.new.layers(path)
      rescue ParseError
        []
      end
    end
  end
end
