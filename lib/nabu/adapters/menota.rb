# frozen_string_literal: true

require_relative "menota_tei_parser"
require_relative "../menota_fetch"

module Nabu
  module Adapters
    # Menota — the Medieval Nordic Text Archive (P82-1, queue Q42 / grant
    # №77-1): ~100 medieval Nordic manuscripts in Menota-TEI (multi-level
    # facsimile/diplomatic/normalized transcription), served through the
    # Corpuscle (korpuskel) REST API behind the catalogue SPA at
    # clarino.uib.no/menota/catalogue/menota. Census 2026-08-23: 91
    # documents / ~2.1M words in the main `menota` corpus; languages per
    # catalogue isl 57, nor 27, swe 4, dan 2, non 1.
    #
    # == Identity
    #
    # The catalogue keys every text on a stable documentId (the manuscript
    # shelfmark, filename-safe: AM-1056-IX-4to); the fetch lands one TEI
    # file per text at texts/<documentId>.xml, so:
    #
    #   document urn  urn:nabu:menota:<documentId downcased>
    #   passage urn   <document-urn>:<page><column>.<line>   (…:1rB.1)
    #
    # ref.id == parse(ref).urn (the conformance identity; documentIds are
    # censused unique after downcasing).
    #
    # == Language (the honest per-document claim)
    #
    # Each file names its own language — textLang @mainLang, with langUsage
    # <language @ident> as the header fallback and the archive-level `non`
    # as the last resort. The codes ride VERBATIM (isl/nor/swe/dan/non) and
    # the value also rides as the `language` document facet the future lect
    # rule keys on; the lect posture is pending on that rule
    # (config/postures.yml — nor/dan have no registry nodes yet).
    #
    # == License (the №77-1 record)
    #
    # CC BY-SA 4.0 on the catalogue's license column (the quotable record)
    # — censused 2026-08-23 on ALL 91 documents — and repeated per-file in
    # <availability><licence>. license_class attribution. The per-text
    # gate maps each header's own licence statement; an EXPLICIT statement
    # the map does not recognize goes `restricted`, never silently BY-SA.
    #
    # == fetch / sync policy
    #
    # The polite session crawl (MenotaFetch): get-session → paged
    # catalogue → per-text download, ~95 requests at 1 req/s (minutes),
    # once-per-text cached, deletions attic behind the breaker. The crawl
    # is upstream-blessed (Stegmann 2026-08-20 — robots.txt disallows
    # anonymous crawlers, the grant records the explicit blessing) and
    # RETIRES when Menota's announced bulk endpoint lands. sync_policy
    # manual, wired: false until the owner-fired first sync.
    class Menota < Nabu::Adapter
      BASE_URL = "https://clarino.uib.no/korpuskel-api"
      CATALOGUE_URL = "https://clarino.uib.no/menota/catalogue/menota"
      ENTITIES_URL = "https://www.menota.org/menota-entities.txt"

      # The header-ladder last resort (the archive's own language).
      LANGUAGE_FALLBACK = "non"

      URN_PREFIX = "urn:nabu:menota:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "menota",
        name: "Menota — the Medieval Nordic Text Archive (clarino.uib.no)",
        license: "CC BY-SA 4.0 — the catalogue's license column (the quotable record, " \
                 "#{CATALOGUE_URL}, censused 2026-08-23 on all 91 texts) and every sampled " \
                 "teiHeader <availability><licence target=\"…by-sa/4.0…\">. Cite the editor(s) " \
                 "named in each text's teiHeader and the Medieval Nordic Text Archive, menota.org",
        license_class: "attribution",
        upstream_url: CATALOGUE_URL,
        parser_family: "menota-tei"
      )

      def self.manifest
        MANIFEST
      end

      # A session-based API the probe cannot diff URL-by-URL: liveness of
      # the session endpoint is the honest verdict (the corpus-corporum
      # posture); drift rides the .menota-fetch.json ledger.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "korpuskel-api get-session",
          zip_url: Nabu::MenotaFetch.rest_url(BASE_URL, "get-session"),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::MenotaFetch::STATE_FILE,
          liveness_only: true
        )]
      end

      # The per-text license gate (the sefaria mold, hardened): only a
      # machine-recognizable statement maps, and an EXPLICIT statement the
      # map does not recognize goes restricted — a stranger grant must
      # never silently inherit the BY-SA source class. NC outranks the SA
      # match (BY-NC-SA carries both words).
      def self.license_override_for(licence)
        text = licence.to_s.strip
        return nil if text.empty?

        case text
        when /non.?commercial|\bNC\b/i then "nc"
        when /public\s+domain|\bCC0\b/i then "open"
        when /CC.?BY(.?SA)?|Creative\s+Commons\s+Attribution/i then "attribution"
        else "restricted"
        end
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default (the grant promise).
      def initialize(delay: Nabu::MenotaFetch::DELAY)
        super()
        @delay = delay
        @entities = {}
      end

      # One DocumentRef per texts/<documentId>.xml, sorted by urn. A
      # pre-fetch workdir yields nothing; the entity table and the
      # catalogue ledger never match.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        MenotaTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          entities: entities_for(document_ref.path),
          language_fallback: LANGUAGE_FALLBACK,
          license_mapper: self.class.method(:license_override_for)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired session crawl (never in tests — WebMock blocks the
      # network): polite, resumable, non-destructive (attic + breaker),
      # error envelopes recorded.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::MenotaFetch.sync!(
          base_url: BASE_URL, entities_url: ENTITIES_URL,
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::MenotaFetch::Error => e
        raise Nabu::FetchError, "menota fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The MUFI entity table beside texts/ (the fetch lands it); for attic
      # refs (workdir/.attic/texts/…) the live table one level up serves.
      def entities_for(path)
        table_path = [File.dirname(path, 2), File.dirname(path, 3)]
                     .map { |dir| File.join(dir, Nabu::MenotaFetch::ENTITIES_FILE) }
                     .find { |candidate| File.file?(candidate) }
        if table_path.nil?
          raise ParseError, "#{path}: no #{Nabu::MenotaFetch::ENTITIES_FILE} beside texts/ — " \
                            "the Menota DOCTYPE entity table is part of the canonical asset; " \
                            "run `nabu sync menota` to land it"
        end

        @entities[table_path] ||= MenotaTeiParser.load_entities(table_path)
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, Nabu::MenotaFetch::TEXTS_DIR, "*.xml")).map do |path|
          document_id = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{document_id.downcase}",
            path: File.expand_path(path),
            metadata: { "document_id" => document_id }
          )
        end.sort_by(&:id)
      end

      def fetch_notes(result)
        base = "catalogue listed #{result.documents} documents " \
               "(#{result.fetched} fetched, #{result.cached} already on disk)"
        [base, skip_notes(result), attic_notes(result.atticked)].compact.join("; ")
      end

      def skip_notes(result)
        skipped = result.refused + result.malformed
        return nil if skipped.empty?

        named = skipped.first(3).join(", ")
        tail = skipped.size > 3 ? ", …" : ""
        "#{skipped.size} download#{'s' if skipped.size > 1} skipped (#{named}#{tail} — " \
          "recorded, re-attempted next sync)"
      end
    end
  end
end
