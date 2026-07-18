# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # Sefaria — the Targum shelf (P30-3). Sefaria-Export was RESTRUCTURED
    # upstream: the git repo is a lightweight monthly index (books.json,
    # 19,705 version entries / 6,456 titles at the 2026-07-02 generation)
    # and the texts live in a public ~26 GB GCS bucket that is never fetched
    # wholesale. THE ONE-PHASE BITE is the Targum shelf — every version
    # entry whose categories include "Targum" (200 files / 45 titles at the
    # pinned index; 121 NAMED versions ≈ 15.6 MB): Onkelos, Jonathan on the
    # Prophets (and the Pseudo-Jonathan Torah targum), the Writings targums,
    # Neofiti, Jerusalem, Sheni. Verse-aligned to the Tanakh versification →
    # the ot alignment hub's ARAMAIC leg (config/alignments.yml).
    #
    # == fetch (the P30-3 index-driven shape, Nabu::SefariaFetch)
    #
    # GET the index, select the shelf's NAMED versions (.shelf_entry? —
    # merged files and Tafsir Rasag never leave the bucket), GET exactly
    # those files. The index rides in canonical so the scope is reproducible;
    # attic + mass-deletion breaker as everywhere. The fetch pin is the index
    # body's sha256.
    #
    # == Identity (FROZEN minting)
    #
    # Document per title/version: urn = urn:nabu:sefaria:<title-slug>:
    # <versionTitle-slug> (SefariaJsonParser.slug — "Onkelos Genesis" /
    # "Targum Onkelos, vocalized according to the Yemenite Taj " →
    # urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-
    # to-the-yemenite-taj). Passage per verse: <doc-urn>:<chapter>.<verse>
    # (deeper/node-prefixed tails where the file's own structure says so).
    # Discovery is GLOB-DRIVEN over the fetched version files — each file is
    # self-describing (title/versionTitle/license/categories ride beside the
    # text), so the attic rediscovers without an index and no path parsing
    # is ever needed. Minting is frozen once used (standing rule).
    #
    # == THE LICENSE GATE (per-version, machine-readable; censused 2026-07-18)
    #
    # Every named version file carries a "license" field — the census over
    # all 121 named Targum versions: Public Domain ×53 · CC0 ×26 · CC-BY ×9
    # · CC-BY-SA ×5 · CC-BY-NC ×12 · CC-BY-NC-SA ×1 · "unknown" ×14 · field
    # absent ×1. The gate, pinned in tests:
    # - PD/CC0 → the source class (open); CC-BY/CC-BY-SA → license_override
    #   "attribution"; CC-BY-NC/CC-BY-NC-SA → license_override "nc" (the
    #   P10-4 per-document mechanics; nc documents are MCP-excluded
    #   downstream).
    # - "unknown" or an ABSENT field is not a grant → skipped by rule,
    #   censused, never a ref.
    # - merged.json files carry NO license field (they are Sefaria's
    #   maximal-content merges across versions) → NEVER ingested; the fetch
    #   selector also never downloads them.
    # - any OTHER license string stops discovery loudly (Nabu::FetchError) —
    #   mislabeled documents are worse than an aborted run (the ORACC/
    #   SuttaCentral gate stance).
    #
    # == Languages (the shelf ruling)
    #
    # Sefaria's language axis is he/en; on the Targum shelf the "Hebrew"
    # column IS Jewish Literary Aramaic (upstream's own actualLanguage says
    # "he" — a site-axis label, not a linguistic claim) → language `arc`,
    # NFC-EXEMPT byte-verbatim storage (the P26-3 owner ruling). English →
    # `eng`. TAFSIR RASAG IS EXCLUDED BY RULE: it sits in the Targum
    # category but is Saadia Gaon's JUDEO-ARABIC translation — the blanket
    # he→arc ruling would mislabel it, so it stays out of both fetch scope
    # and discovery (censused, documented).
    class Sefaria < Nabu::Adapter
      INDEX_URL = "https://raw.githubusercontent.com/Sefaria/Sefaria-Export/master/books.json"

      SHELF_CATEGORY = "Targum"
      MERGED_VERSION = "merged"

      # In the Targum category, not an Aramaic targum (see class note).
      EXCLUDED_TITLES = ["Tafsir Rasag"].freeze

      # Machine-readable license → our class enum. "unknown"/absent → nil
      # (skip by rule); any other unlisted string is a LOUD STOP.
      LICENSE_CLASSES = {
        "Public Domain" => "open",
        "CC0" => "open",
        "CC-BY" => "attribution",
        "CC-BY-SA" => "attribution",
        "CC-BY-NC" => "nc",
        "CC-BY-NC-SA" => "nc"
      }.freeze
      NON_GRANTS = [nil, "unknown"].freeze

      # Sefaria's site-language axis → the shelf's honest document language.
      LANGUAGES = { "he" => "arc", "en" => "eng" }.freeze

      URN_PREFIX = "urn:nabu:sefaria:"

      # One discovery walk's yield: refs for licensed named versions, the
      # rule-skip count, and unrecognized notes for unreadable files.
      ScanResult = Data.define(:refs, :skipped, :notes)

      MANIFEST = Nabu::SourceManifest.new(
        id: "sefaria",
        name: "Sefaria — the Targum shelf (Onkelos, Jonathan, Writings targums, Neofiti, Jerusalem, Sheni)",
        license: "Per NAMED version, machine-readable \"license\" field (censused 2026-07-18: PD x53, " \
                 "CC0 x26, CC-BY x9, CC-BY-SA x5 -> open/attribution; CC-BY-NC x12, CC-BY-NC-SA x1 -> " \
                 "nc via license_override; \"unknown\" x14 + 1 absent -> never ingested); merged.json " \
                 "carries no license field and is never fetched or ingested",
        license_class: "open",
        upstream_url: "https://github.com/Sefaria/Sefaria-Export",
        parser_family: "sefaria-json"
      )

      def self.manifest
        MANIFEST
      end

      # The fetch selector: NAMED versions of the Targum shelf only. Kept a
      # class method so tests pin the scope rule without a network shape.
      def self.shelf_entry?(entry)
        entry["categories"].is_a?(Array) &&
          entry["categories"].include?(SHELF_CATEGORY) &&
          entry["versionTitle"] != MERGED_VERSION &&
          !EXCLUDED_TITLES.include?(entry["title"]) &&
          entry["json_url"].is_a?(String)
      end

      # One DocumentRef per licensed named version file under json/, sorted
      # by urn. A workdir without the tree yields nothing (the day-one
      # pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.sort_by(&:id).each(&block)
      end

      # P11-7 discovery census: merged files, non-grant licenses ("unknown"/
      # absent) and excluded titles are explicit rule skips; a version file
      # that does not parse as JSON is unrecognized — loud, a fetch defect.
      def discovery_skips(workdir)
        result = scan(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: result.skipped, unrecognized: result.notes.size, notes: result.notes
        )
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        SefariaJsonParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: metadata.fetch("language"),
          metadata: document_metadata(metadata),
          license_override: metadata["license_override"]
        )
      end

      def fetch(workdir, progress: nil, force: false)
        result = SefariaFetch.sync!(
          index_url: index_url, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          select: self.class.method(:shelf_entry?), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue SefariaFetch::Error => e
        raise FetchError, "sefaria fetch failed: #{e.message}"
      end

      private

      # Split out so tests can point a singleton at a stubbed index (the
      # house pattern), keeping fetch off the network.
      def index_url
        INDEX_URL
      end

      def fetch_notes(result)
        notes = ["#{result.downloaded} file(s) downloaded"]
        notes << attic_notes(result.atticked) unless result.atticked.empty?
        notes.join("; ")
      end

      # One walk of json/**/*.json (see ScanResult).
      def scan(workdir)
        refs = []
        skipped = 0
        notes = []
        Dir.glob(File.join(workdir, "json", "**", "*.json")).each do |path|
          data = read_version(path)
          if data.nil?
            notes << "#{relative(workdir, path)}: not a JSON version object (fetch defect?)"
          elsif skip_by_rule?(data)
            skipped += 1
          else
            refs << ref_for(path, data)
          end
        end
        ScanResult.new(refs: refs, skipped: skipped, notes: notes)
      end

      def read_version(path)
        parsed = JSON.parse(File.read(path))
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      # merged files, excluded titles, and versions without a machine-
      # readable grant. An unmapped license STRING is not a skip — it stops
      # discovery loudly (see the class note); the gate only rests where the
      # metadata genuinely carries no grant.
      def skip_by_rule?(data)
        return true if data["versionTitle"] == MERGED_VERSION || data.key?("versions")
        return true if EXCLUDED_TITLES.include?(data["title"])

        NON_GRANTS.include?(data["license"])
      end

      def ref_for(path, data)
        license_class = license_class!(path, data)
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: urn(data),
          path: File.expand_path(path),
          metadata: {
            "language" => language!(path, data),
            "license_override" => license_class == manifest.license_class ? nil : license_class,
            "title" => data["title"],
            "version_title" => data["versionTitle"],
            "license" => data["license"],
            "categories" => data["categories"],
            "he_title" => data["heTitle"],
            "version_source" => data["versionSource"]
          }.compact
        )
      end

      def urn(data)
        "#{URN_PREFIX}#{SefariaJsonParser.slug(data['title'])}:#{SefariaJsonParser.slug(data['versionTitle'])}"
      end

      def license_class!(path, data)
        LICENSE_CLASSES.fetch(data["license"]) do
          raise Nabu::FetchError,
                "sefaria: #{path}: unrecognized license #{data['license'].inspect} — map it in " \
                "Sefaria::LICENSE_CLASSES (owner decision) before syncing"
        end
      end

      def language!(path, data)
        LANGUAGES.fetch(data["language"]) do
          raise Nabu::FetchError,
                "sefaria: #{path}: unknown upstream language #{data['language'].inspect} — the shelf " \
                "ruling maps he->arc and en->eng only (owner decision before syncing anything else)"
        end
      end

      def relative(workdir, path)
        File.expand_path(path).delete_prefix("#{File.expand_path(workdir)}#{File::SEPARATOR}")
      end

      # Document-level metadata: shelf provenance verbatim plus the subshelf/
      # division facets (categories = ["Tanakh", "Targum", <subshelf>,
      # <division?>] on this shelf).
      def document_metadata(metadata)
        categories = metadata["categories"] || []
        facets = { "subshelf" => facet(categories[2]), "division" => facet(categories[3]) }.compact
        {
          "title" => metadata["title"],
          "version_title" => metadata["version_title"],
          "license" => metadata["license"],
          "categories" => categories.empty? ? nil : categories,
          "he_title" => metadata["he_title"],
          "version_source" => metadata["version_source"],
          "facets" => facets.empty? ? nil : facets
        }.compact
      end

      def facet(value)
        value.nil? ? nil : { "value" => SefariaJsonParser.slug(value), "raw" => value }
      end
    end
  end
end
