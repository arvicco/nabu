# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "../tm_geo"

module Nabu
  module Adapters
    # Trismegistos Geo — the papyrological world's places database (finest
    # grain for Greco-Roman Egypt), registered as a FEATURE MODULE (kind:
    # module, the pleiades shape): discover mints NO documents; the canonical
    # asset is the Geo table dump, which since P63-3 derives `tm:` rows into
    # the namespaced place index.
    #
    # == fetch: the Manual Adapter pattern (P63-1, ruling Dp-a)
    #
    # TM's dump service FAILS the automation bar as measured 2026-08-08: the
    # Geo dump is a browser POST form (`dump.php?serve=geo`) that answered a
    # scripted POST with 0 bytes, and the site serves a captcha "Security
    # Check" interstitial. A human acquires the dump in a browser; fetch here
    # is Nabu::ManualDrop — instruction card while incoming/trismegistos-geo/
    # is empty, validated attic-safe ingest + `.manual-fetch.json` provenance
    # once the owner drops the download. First sanctioned drop: the owner's
    # 2026-08-08 session (64,857 rows — exactly the claimed count).
    #
    # The dump carries NO Pleiades/GeoNames ids: the form's `pleiades_id`/
    # `geonames` checkboxes are commented out upstream (verified in page
    # source 2026-08-08). Crosswalks come from CIGS columns + the Wikidata
    # harvest, never from this shelf — re-check the form on each re-acquire.
    #
    # == License (verbatim, trismegistos.org/dataservices/, 2026-08-07)
    #
    # "We offer you open access to our data on a CC BY-SA 4.0 license."
    # → class attribution (share-alike admissible, the EDH/edr precedent).
    class TrismegistosGeo < Nabu::Adapter
      CSV_NAME = "TM_geo.csv"
      JSON_NAME = "TM_geo.json"

      MANIFEST = Nabu::SourceManifest.new(
        id: "trismegistos-geo",
        name: "Trismegistos Geo — places database (gazetteer instrument)",
        license: "CC BY-SA 4.0 (dataservices page verbatim: \"We offer you open access to our " \
                 "data on a CC BY-SA 4.0 license.\")",
        license_class: "attribution",
        upstream_url: "https://www.trismegistos.org/geo/",
        parser_family: "tm-geo-csv"
      )

      def self.manifest
        MANIFEST
      end

      # P63-3: each sync/rebuild derives the "tm" slice of the namespaced
      # place index from the held CSV (the pleiades producer seam shape —
      # per-gazetteer wholesale, never touching other namespaces' rows).
      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        Nabu::TmGeo::Producer.new(catalog: catalog)
      end

      # The acquisition contract the instruction card renders. The steps are
      # the owner-tested 2026-08-08 route; "every offered field" matters —
      # a partial tick silently loses columns for a whole acquisition cycle.
      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: "trismegistos-geo",
          upstream_url: "https://www.trismegistos.org/dataservices/",
          steps: [
            "Open the URL in a browser and solve the captcha (\"Security Check\") if served",
            "Find the Geo table dump form (dump.php?serve=geo) and tick EVERY offered field",
            "Download as CSV, and as JSON too if offered (it carries the nested name variants)",
            "Save the files as #{CSV_NAME} / #{JSON_NAME} and drop them as listed below"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: CSV_NAME, description: "the Geo table dump, CSV — the canonical asset",
              required: true, sniff: ->(path) { csv_complaint(path) }
            ),
            ManualDrop::FileSpec.new(
              name: JSON_NAME, description: "the same dump as GeoJSON",
              required: false, sniff: ->(path) { json_complaint(path) }
            )
          ],
          refresh_hint: "The gazetteer changes slowly — re-acquire on demand; check whether the " \
                        "form's disabled pleiades_id/geonames checkboxes have returned (they " \
                        "would upgrade this shelf to crosswalk-bearing)."
        )
      end

      # The dump's own header starts "id","country" — a saved captcha page or
      # truncated download does not. One sentence, never a stack.
      def self.csv_complaint(path)
        head = File.open(path, "r:UTF-8") { |f| f.read(64) }.to_s
        return nil if head.start_with?(%("id","country"))

        "does not start with the Geo dump's \"id\",\"country\" header (a saved captcha page?)"
      end

      def self.json_complaint(path)
        head = File.open(path, "r:UTF-8") { |f| f.read(256) }.to_s
        return nil if head.lstrip.start_with?("{") && head.include?("FeatureCollection")

        "not the dump's GeoJSON FeatureCollection"
      end

      # incoming/<slug>/ sits beside canonical/ (ruling Dp-a); workdir is
      # canonical/<slug>, so the drop is two levels up.
      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", "trismegistos-geo"), workdir)
      end

      # A feature module mints no documents (the pleiades/bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: trismegistos-geo is a gazetteer instrument, not a " \
                          "text source — its data derives into the place index; parse is unreachable"
      end

      # P79-2: a ManualDrop source has NO unattended upstream to probe —
      # the geo export is account-gated, the owner drops it by hand. Empty
      # repo list routes the remote probe to the vendored/local posture
      # (alive = the canonical tree is present), the sabellic-loans mold.
      def self.upstream_repo_urls = []

      # force: is the Adapter#fetch signature; a manual ingest has no guard
      # to override (replacement always attics), so it is accepted and unused.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition,
          drop_dir: self.class.drop_dir(workdir),
          dir: workdir,
          attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end
    end
  end
end
