# frozen_string_literal: true

require "fileutils"
require "json"

module Nabu
  module Adapters
    # Trismegistos — the TexRelations crosswalk, registered as a FEATURE
    # MODULE (kind: module), not a text source. It mints NO catalog rows: its
    # data is a links-journal instrument that makes the library's ~7,185
    # dangling `tm:<id>` reference targets (minted by the isicily/itant/tir/
    # ceipom/vienna-wiki concordance extraction) RESOLVABLE — to their
    # partner-project ids and, where two held sources witness the same stone,
    # to each other. The parse/load work lives entirely in the links producer
    # Nabu::TrismegistosCrosswalk (producer #8), wired via reference_producer
    # below and run by SyncRunner after every trismegistos sync — so, like
    # bridging, discover yields NOTHING and parse is unreachable.
    #
    # == fetch: sweep exactly the library's tm ids (the fetch cone IS the graph)
    #
    # `nabu sync trismegistos` (owner-run) reads the links journal LIVE at
    # fetch time for every distinct `tm:<id>` target present, and GETs
    #
    #   https://www.trismegistos.org/dataservices/texrelations/<id>
    #
    # (documented API, read 2026-07-24) once per id, landing the JSON under
    # canonical/trismegistos/texrelations/<id>.json. The cone is exactly what
    # the library references — no id we do not already point at is fetched.
    # SEQUENTIAL with a ≥1s pause between requests, and RESUMABLE (an id
    # already on disk is skipped), because the sweep is thousands of ids.
    #
    # NB the API's fair-use terms do NOT render to this fetcher and are
    # UNREAD — the 1s pause is a deliberately conservative guess; the owner
    # eyeballs the endpoint's rate policy before the first real sync.
    #
    # This deliberately does NOT use Nabu::FileFetch: that class dooms every
    # live file under its dir except the one target, which would attic/delete
    # the whole accumulating id-keyed tree on each per-id fetch. The
    # texrelations tree ACCUMULATES (one immutable response per id), so the
    # fetch writes each file directly and never touches siblings; a changed
    # response is a plain refresh (overwrite), the git-adapters' stance.
    #
    # == License (verbatim, dataservices page, 2026-07-24)
    #
    # "open access to our data on a CC BY-SA 4.0 license" → class
    # attribution (the house BY-SA posture — every CC BY-SA source in
    # config/sources.yml classes attribution; share-alike is a
    # downstream-relicensing duty, not a serving gate).
    class Trismegistos < Nabu::Adapter
      API_BASE = "https://www.trismegistos.org/dataservices/texrelations"
      # Mirrors Nabu::TrismegistosCrosswalk::DIRNAME (kept literal here so the
      # adapter carries no load-order dependency on the producer).
      DIRNAME = "texrelations"
      TM_TARGET = /\Atm:(\d+)\z/
      REQUEST_PAUSE_SECONDS = 1.0

      MANIFEST = Nabu::SourceManifest.new(
        id: "trismegistos",
        name: "Trismegistos TexRelations — the cross-project concordance crosswalk (links instrument)",
        license: "CC BY-SA 4.0 (dataservices page verbatim: \"open access to our data on a " \
                 "CC BY-SA 4.0 license\") — the house BY-SA class",
        license_class: "attribution",
        upstream_url: "https://www.trismegistos.org/dataservices/",
        parser_family: "trismegistos-crosswalk"
      )

      def self.manifest
        MANIFEST
      end

      # This module's data rides the links journal via TrismegistosCrosswalk
      # (producer #8), refreshed by SyncRunner after every sync.
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        Nabu::TrismegistosCrosswalk.new(catalog: catalog, journal: journal)
      end

      # A feature module mints no documents — its data is links-graph edges,
      # not passages. Empty by design, not by accident (the bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: trismegistos is a links instrument, not a text source — " \
                          "its crosswalk rides the links journal (P43-3, TrismegistosCrosswalk); " \
                          "parse is unreachable"
      end

      # Sweep the library's tm ids and fetch one texrelations response each
      # (class note). +force+ has no destructive surface here (the tree only
      # accumulates), so it is accepted for interface parity and ignored.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        dir = File.join(workdir, DIRNAME)
        FileUtils.mkdir_p(dir)
        ids = swept_tm_ids
        fetched = 0
        skipped = 0
        ids.each do |id|
          path = File.join(dir, "#{id}.json")
          if File.file?(path)
            skipped += 1
            next
          end
          sleep(REQUEST_PAUSE_SECONDS) unless fetched.zero?
          progress&.call("Trismegistos #{id} (#{fetched + 1}/#{ids.size - skipped})…\n")
          File.write(path, fetch_texrelations(id))
          fetched += 1
        end
        Nabu::FetchReport.new(sha: nil, fetched_at: Time.now,
                              notes: "texrelations: #{fetched} fetched, #{skipped} already present " \
                                     "(#{ids.size} tm ids in the links graph)")
      end

      private

      # The distinct tm ids the links journal currently references — a LIVE
      # read at fetch time (class note). No journal file yet (no producer has
      # ever run) means an empty cone, never an error.
      def swept_tm_ids
        path = Nabu::Config.load.links_path
        db = Store::LinksJournal.open_readonly(path)
        return [] unless db

        begin
          targets = db[:links].select_map(:from_urn) + db[:links].select_map(:to_urn)
        ensure
          db.disconnect
        end
        targets.filter_map { |t| t[TM_TARGET, 1] }.uniq.sort_by(&:to_i)
      end

      # GET one texrelations response (redirect-following, cert-hardened
      # connection). RedirectFollow raises Nabu::FetchError on any non-200 or
      # transport failure, so the sweep aborts loudly rather than persisting
      # an error body.
      def fetch_texrelations(id)
        url = "#{API_BASE}/#{id}"
        response, = Nabu::RedirectFollow.get(url, http: Nabu::ZipFetch.default_http,
                                                  error: Nabu::FetchError, accept: [200])
        response.body.to_s
      end
    end
  end
end
