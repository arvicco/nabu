# frozen_string_literal: true

require_relative "cantigas_html_parser"
require_relative "../cantigas_fetch"

module Nabu
  module Adapters
    # Cantigas Medievais Galego-Portuguesas (P55-1): the complete secular
    # Galician-Portuguese lyric — ~1,680 cantigas de amigo, de amor and de
    # escárnio e maldizer (plus lais, tenções, pastorelas…) from the three
    # great cancioneiros (Ajuda, Biblioteca Nacional, Vaticana), in the
    # Littera critical edition (cantigas.fcsh.unl.pt; Projeto Littera,
    # Instituto de Estudos Medievais, FCSH/NOVA Lisbon; coordinators Graça
    # Videira Lopes and Manuel Pedro Ferreira). A thin composition of the
    # CantigasHtmlParser family with the CantigasFetch letter-index crawl.
    #
    # == The corpus (scout census 2026-07-31, 11 bounded probes)
    #
    # HTML scrape only — no TEI/XML/export exists (Classic ASP on IIS).
    # One page per cantiga at cantiga.asp?cdcant=N; cdcant is SPARSE (ids
    # reach 1713 on letter A alone) and an invalid id answers HTTP 500 —
    # enumeration comes ONLY from the 23 alphabetical incipit indexes
    # (letter A: 244 unique ids; whole corpus ≈ 1,680).
    #
    # == Identity
    #
    # urn = urn:nabu:cantigas:<cdcant> — the database's own stable id.
    # discover mints from the filename; parse cross-checks the page's own
    # self-links (drift quarantines).
    #
    # == License (granted by email 2026-07-27)
    #
    # Graça Videira Lopes (Projeto Littera coordinator): "Our site is free
    # for all. So, with full attribution, you can do whatever you like with
    # the data." → class attribution; the project's own citation format
    # rides the manifest license verbatim and the credit line renders the
    # attribution on every serving surface.
    #
    # == fetch / sync policy
    #
    # CantigasFetch: 23 index GETs + per-id page GETs at 1 req/s (~29 min
    # whole corpus), resume at the file grain, 500-on-a-listed-id fatal
    # after retries (the sparse-id ground truth), retention via the attic +
    # the mass-deletion breaker. sync_policy: manual, wired: false until
    # the owner-fired first sync.
    class Cantigas < Nabu::Adapter
      BASE_URL = "https://cantigas.fcsh.unl.pt"

      # The project's own citation format — the grant's one condition,
      # verbatim, both coordinators named, retrieval-date slot kept.
      CITATION = "Lopes, Graça Videira; Ferreira, Manuel Pedro et al. (2011–), " \
                 "Cantigas Medievais Galego Portuguesas [online database]. " \
                 "Lisboa: Instituto de Estudos Medievais, FCSH/NOVA. " \
                 "[Information retrieved on (date)] Available at: cantigas.fcsh.unl.pt."

      MANIFEST = Nabu::SourceManifest.new(
        id: "cantigas",
        name: "Cantigas Medievais Galego-Portuguesas (Projeto Littera)",
        license: "Free with attribution — the coordinator's grant (Graça Videira Lopes, " \
                 "Projeto Littera, IEM/FCSH-NOVA, by email 2026-07-27): \"Our site is free " \
                 "for all. So, with full attribution, you can do whatever you like with " \
                 "the data.\" Cite (the project's own format): #{CITATION}",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "cantigas-html",
        credit: CITATION
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe GETs one stable edition page
      # (reachability only: the live ASP app serves no Last-Modified/ETag,
      # so the ledger pin never drifts from a probe).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "cantiga.asp?cdcant=1",
          zip_url: Nabu::CantigasFetch.record_url(BASE_URL, 1),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::CantigasFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::CantigasFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per crawled page file, in numeric cdcant order (the
      # ids are sparse integers — string order would shuffle them). A
      # workdir without pages yields nothing (the day-one pre-fetch state);
      # the persisted letter indexes never match.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The 23 persisted letter-index sidecars are content-pattern files
      # discover deliberately skips — an explicit, benign rule, censused
      # here so the accounting never hides it.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, "*.html"))
                     .count { |path| !Nabu::CantigasFetch.record?(File.basename(path)) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        CantigasHtmlParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the
      # network): 23 index GETs + per-id page GETs, polite, resumable,
      # non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::CantigasFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::CantigasFetch::Error => e
        raise Nabu::FetchError, "cantigas fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        pages = Dir.glob(File.join(workdir, "*.html")).filter_map do |path|
          match = Nabu::CantigasFetch::RECORD_FILENAME.match(File.basename(path))
          match && [Integer(match[1], 10), path]
        end
        pages.sort_by(&:first).map do |cdcant, path|
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{CantigasHtmlParser::URN_PREFIX}#{cdcant}",
                                path: File.expand_path(path))
        end
      end

      def fetch_notes(result)
        base = "#{Nabu::CantigasFetch::LETTERS.size} letter indexes verified " \
               "(#{result.manifest_count} cantigas; " \
               "#{result.fetched} fetched, #{result.cached} already on disk)"
        [base, missing_notes(result.missing), attic_notes(result.atticked)].compact.join("; ")
      end

      # P47-i1 posture: listed-but-missing upstream pages, censused by the
      # fetch — named (first 3) so the tail is honest.
      def missing_notes(missing)
        return nil if missing.empty?

        named = missing.first(3).join(", ")
        tail = missing.size > 3 ? ", …" : ""
        "#{missing.size} listed page#{'s' if missing.size > 1} 404 upstream (cdcant #{named}#{tail})"
      end
    end
  end
end
