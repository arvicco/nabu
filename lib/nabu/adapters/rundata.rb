# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"

require_relative "rundata_sqlite_parser"

module Nabu
  module Adapters
    # The Rundata adapter (P40-6; dual-axis germanic × epigraphy): the
    # Scandinavian Runic-text Database (SRDB / Samnordisk runtextdatabas /
    # Rundata, Uppsala) — ~6,800 runic inscriptions — via Rundata-net
    # (rundata.info), whose single-page app ships THE ENTIRE database to
    # the browser as one hash-versioned SQLite file. That file is the
    # canonical artifact; RundataSqliteParser reads it read-only.
    #
    # == Identity
    #
    # Document = one inscription; the signum IS the identity:
    # urn:nabu:rundata:<canonical_slug> (u-344, og-136, n-kj101 — the
    # Django-slugify form rundata.info's own /inscription/<slug>/ pages
    # use; .slug_for reimplements it and the fixtures pin the agreement).
    #
    # == The five lanes as sibling documents (the ogham stone×layer mold)
    #
    # The TRANSLITERATION (`run` lane) is the PRIMARY document under the
    # bare urn — it is the inscription's text, in the scholarly Latin
    # transliteration upstream stores (ZERO Runic-block codepoints exist in
    # the data, verified; none are invented). The notation IS content,
    # stored verbatim: §A/§B side markers, | shared/bound runes, '/×/:/¶
    # separators as carved, (a) uncertain, - one lost rune, ---- a lost
    # run, [l] editorial restoration, " marks a proper name, R the yr/ʀ
    # rune. The other lanes ride as suffix-equality siblings
    # (--parallel via the registry siblings declaration):
    #
    #   -fvn  normalisation to Old West Norse (fornvästnordiska)
    #   -rsv  normalisation to runic Swedish / Old East Norse (runsvenska)
    #   -eng  English translation   (minted only with translations: true)
    #   -swe  Swedish translation   (minted only with translations: true)
    #
    # Absent lanes are simply absent. An inscription with NO transliteration
    # mints one metadata-only bare-urn document (the ogham precedent):
    # catalogued, zero passages, never quarantined.
    #
    # == Language honesty (censused, never invented)
    #
    # The dating field's period code decides the run/fvn/rsv language:
    # `U` (urnordisk — Proto-Norse, e.g. N KJ101 Eggja "U 650-700
    # (Grønvik)") → `gmq-pro`, the Wiktionary etymology-language code the
    # house already adopts verbatim for reconstruction/proto lanes
    # (wiktionary-recon precedent; ISO 639-3 has NO Proto-Norse code).
    # Everything else (V Viking, M medieval, blank, uncertain "U?") → `non`
    # (Old Norse — the honest attested default; fvn/rsv are BY DEFINITION
    # Old-Norse normalisations). eng/swe lanes are eng/swe.
    #
    # == Metadata
    #
    # BOTH WGS84 pairs (find + present location) ride as document metadata
    # — coordinates are metadata-only, the EDH decision. dating +
    # year_from/year_to feed the timeline lane via
    # Store::TimelineBuilder::RundataDates (the EDH mold), joining on urns
    # minted through .slug_for — one rule, no drift. carver/style/crosses/
    # material/rune_type etc. carry verbatim (Swedish vocabulary and all).
    # references[]: the stable links (kind=link) ride metadata "related"
    # and become kind=reference edges via the house producer mold
    # (reference_edges? + producer "rundata"); bibliography text entries
    # stay metadata.
    #
    # == fetch — hash-versioned artifact, never-delete retention
    #
    # GET the rundata.info page, extract the current artifact URL
    # (/static/runes/runes.<hash>.sqlite3 — the hash IS the version),
    # download into canonical/rundata/ under the hashed filename. A
    # re-sync with a NEW hash lands the new file BESIDE the old one (the
    # house never-delete posture; nothing is ever doomed, so no attic and
    # no breaker), and .rundata-fetch.json repoints "current" — which
    # discover reads. The ledger records sha + date via the FetchReport.
    # ~45 MB, live upstream → sync_policy manual, owner-fired.
    #
    # == License — odbl (D40-c RULED; re-confirm before enabling)
    #
    # The SRDB data grant, verbatim from Uppsala runforum
    # (https://www.runforum.nordiska.uu.se/en/srd/): "The Scandinavian
    # Runic-text Database is copyrighted, but is made available under the
    # Open Database License. Any rights in individual contents of the
    # database are licensed under the Database Contents License." Required
    # attribution: "When quoting or re-using information from the
    # Scandinavian Runic-text Database, you are required to refer to the
    # database by naming it and linking to its web site." CAVEAT: the
    # grant is authoritative from UPPSALA's page; rundata.info itself
    # states only GPLv3 for its own source code and does not restate a
    # data licence — the owner re-confirms the ODbL grant before flipping
    # enabled: true.
    class Rundata < Nabu::Adapter
      PAGE_URL = "https://rundata.info/"
      # The hash-versioned artifact as referenced from the app page/bundle.
      ARTIFACT_PATTERN = %r{static/runes/(runes\.[0-9a-f]+\.sqlite3)}
      ARTIFACT_GLOB = "runes*.sqlite3"
      STATE_FILE = ".rundata-fetch.json"

      URN_PREFIX = "urn:nabu:rundata:"

      OLD_NORSE = "non"
      # Wiktionary etymology-language code for Proto-Norse (urnordisk) —
      # the wiktionary-recon convention (conventions §4); ISO 639-3 offers
      # no code for it.
      PROTO_NORSE = "gmq-pro"

      # lane code => [urn suffix, document kind, fixed language (nil =
      # dating-dependent, the class-note rule)]. LANE order mirrors the
      # parser's canonical order.
      LANES = {
        "run" => [nil, "transliteration", nil],
        "fvn" => ["fvn", "normalization", nil],
        "rsv" => ["rsv", "normalization", nil],
        "eng" => %w[eng translation eng],
        "swe" => %w[swe translation swe]
      }.freeze

      # Human lane labels for sibling titles.
      LANE_LABELS = {
        "fvn" => "Old West Norse normalisation",
        "rsv" => "runic Swedish normalisation",
        "eng" => "English translation",
        "swe" => "Swedish translation"
      }.freeze

      # The meta_information columns carried through to primary-document
      # metadata, grouped: place, typology, and the boolean flags.
      PLACE_COLUMNS = %w[
        found_location parish district municipality current_location
        original_site parish_code
      ].freeze

      TYPOLOGY_COLUMNS = %w[rune_type style carver material objectInfo additional].freeze

      FLAG_COLUMNS = %w[lost new_reading ornamental recent].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "rundata",
        name: "Rundata — Scandinavian Runic-text Database (SRDB, via rundata.info)",
        license: "ODbL 1.0 (database) + DbCL 1.0 (contents). Uppsala runforum, verbatim: \"The " \
                 "Scandinavian Runic-text Database is copyrighted, but is made available under the " \
                 "Open Database License. Any rights in individual contents of the database are " \
                 "licensed under the Database Contents License.\" Required attribution: based on " \
                 "the Scandinavian Runic-text Database (https://www.runforum.nordiska.uu.se/srd/). " \
                 "CAVEAT: grant authoritative from Uppsala's page; rundata.info states only GPLv3 " \
                 "for its own code — re-confirm before enabling (owner)",
        license_class: "odbl",
        upstream_url: PAGE_URL,
        parser_family: "rundata-sqlite"
      )

      def self.manifest
        MANIFEST
      end

      # The stable-link reference edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "rundata")
      end

      # P11-2: HEAD the app page for reachability; the artifact URL is
      # hash-versioned (unknowable statically), so the pin backfill reads
      # the state file's sha256/last_modified and license drift honestly
      # reads unchecked (no machine license endpoint — the grant lives on
      # Uppsala's page, watched via license_watch in sources.yml).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "rundata.info", zip_url: PAGE_URL, metadata_url: nil,
          state_subdir: ".", state_file: STATE_FILE
        )]
      end

      # Django-slugify (allow_unicode=false), reimplemented: rundata.info's
      # canonical_slug is Django's slugify of the signum, and the urn must
      # agree with it ("U 344" -> u-344, "Ög 136" -> og-136, "N KJ101" ->
      # n-kj101 — pinned against the JSON API fixtures).
      def self.slug_for(signum)
        ascii = signum.unicode_normalize(:nfkd)
                      .encode(Encoding::US_ASCII, invalid: :replace, undef: :replace, replace: "")
        slug = ascii.downcase.gsub(/[^\w\s-]/, "").gsub(/[\s-]+/, "-").gsub(/\A[-_]+|[-_]+\z/, "")
        raise ParseError, "signum #{signum.inspect} slugifies to nothing" if slug.empty?

        slug
      end

      def self.urn_for(signum) = "#{URN_PREFIX}#{slug_for(signum)}"

      # The dating-field period code -> lane language (class note; censused
      # over the fixture set + the SRDB period vocabulary). Only an exact
      # leading "U" token (urnordisk) is Proto-Norse; the uncertain "U?"
      # stays non — the conservative attested default, never a guess.
      def self.language_for(dating)
        dating.to_s.split.first == "U" ? PROTO_NORSE : OLD_NORSE
      end

      # The CURRENT artifact under +workdir+: the state file's pointer when
      # it names an existing file, else the only runes*.sqlite3 present,
      # else (state lost, several artifacts retained) the newest by mtime.
      # nil = never fetched. Shared with the timeline extractor.
      def self.current_artifact(workdir)
        state = read_state(workdir)
        current = state["current"]
        if current
          path = File.join(workdir, File.basename(current))
          return path if File.file?(path)
        end
        Dir.glob(File.join(workdir, ARTIFACT_GLOB)).max_by { |path| File.mtime(path) }
      end

      def self.read_state(workdir)
        path = File.join(workdir, STATE_FILE)
        return {} unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        {}
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter
      # (registry translations: true — the -eng/-swe lanes are parallel
      # translations, opt-in like every other source's).
      def initialize(translations: false)
        super()
        @translations = translations
        @parsers = {}
      end

      # One DocumentRef per (inscription × present lane), sorted by urn;
      # a run-less inscription mints one metadata-only bare ref instead.
      # A workdir without an artifact yields nothing (pre-fetch state; the
      # attic overlay is structurally empty — this fetch never deletes).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = self.class.current_artifact(workdir)
        return if path.nil?

        parser = parser_for(path)
        parser.each_inscription
              .flat_map { |inscription| inscription_refs(inscription, path) }
              .sort_by(&:id)
              .each(&block)
      end

      # The discovery census (P11-7): nothing is skipped by rule — a blank
      # lane row is dropped inside the reader as an honest absence (it
      # never was a document), a run-less inscription still mints its
      # metadata-only ref, and translations: false is a registry posture,
      # not a skip. Nothing is ever unrecognized in a schema-fixed
      # database.
      def discovery_skips(_workdir)
        Nabu::Adapter::DiscoverySkips.new
      end

      def parse(document_ref)
        parser = parser_for(document_ref.path)
        record = parser.record(document_ref.metadata.fetch("signature_id"))
        raise ParseError, "#{document_ref.path}: no inscription for #{document_ref.id}" if record.nil?

        return metadata_only_document(record, document_ref) if
          document_ref.metadata["kind"] == "metadata_only"

        lane_document(record, document_ref)
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # GET the page -> extract the hash-versioned artifact URL -> download
      # under the hashed filename. NEVER-DELETE: previous artifacts stay in
      # place (no doomed paths, so no attic and no breaker); the state file
      # repoints "current". A hash already on disk is the honest 304
      # analogue — the hash IS the version.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        name, url = locate_artifact
        target = File.join(workdir, name)
        return unchanged_report(workdir, name, url, target) if File.file?(target)

        sha, last_modified = download!(url, target, progress)
        retained = previous_artifacts(workdir, name)
        write_state!(workdir, name, sha, url, last_modified)
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: fetch_notes(name, sha, target, retained))
      end

      private

      # -- discovery ------------------------------------------------------------

      def inscription_refs(inscription, path)
        base = self.class.urn_for(inscription.signum)
        refs = inscription.lanes.filter_map do |lane|
          next if %w[eng swe].include?(lane) && !@translations

          suffix, = LANES.fetch(lane)
          ref(suffix ? "#{base}-#{suffix}" : base, path, inscription, "lane" => lane)
        end
        # No transliteration lane: the bare urn still exists — as the
        # metadata-only stone document — and any other lanes still ride as
        # siblings (the ogham never-encoded-stone precedent).
        refs.unshift(metadata_only_ref(base, path, inscription)) unless inscription.lanes.include?("run")
        refs
      end

      def metadata_only_ref(base, path, inscription)
        ref(base, path, inscription, "kind" => "metadata_only")
      end

      def ref(id, path, inscription, extra)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: id, path: path,
          metadata: { "signature_id" => inscription.signature_id,
                      "signum" => inscription.signum }.merge(extra)
        )
      end

      # -- parse ----------------------------------------------------------------

      def parser_for(path)
        @parsers[path] ||= RundataSqliteParser.new(path)
      end

      # A never-encoded inscription (no transliteration lane): catalogued
      # with its full stone metadata, zero passages (the ogham
      # metadata-only precedent) — the conformance override is
      # marker-driven on metadata "kind".
      def metadata_only_document(record, document_ref)
        Nabu::Document.new(
          urn: document_ref.id, language: self.class.language_for(record.meta["dating"]),
          title: record.signum, canonical_path: document_ref.path,
          metadata: primary_metadata(record).merge("kind" => "metadata_only")
        )
      end

      def lane_document(record, document_ref)
        lane = document_ref.metadata.fetch("lane")
        _suffix, kind, fixed_language = LANES.fetch(lane)
        language = fixed_language || self.class.language_for(record.meta["dating"])
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: lane_title(record.signum, lane),
          canonical_path: document_ref.path,
          metadata: lane == "run" ? primary_metadata(record) : sibling_metadata(record, lane, kind)
        )
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:1", language: language,
          text: Normalize.nfc(record.lanes.fetch(lane)), sequence: 0
        )
        document
      end

      def lane_title(signum, lane)
        lane == "run" ? signum : "#{signum} — #{LANE_LABELS.fetch(lane)}"
      end

      def sibling_metadata(record, lane, kind)
        { "kind" => kind, "lane" => lane, "signum" => record.signum }
      end

      # The stone-grain metadata, on the primary (bare-urn) document only.
      # Verbatim upstream values (Swedish vocabulary, NBSP style codes and
      # all); blanks/zeroes are honest absences and mint no key.
      def primary_metadata(record)
        metadata = { "signum" => record.signum }
        metadata["aliases"] = record.aliases unless record.aliases.empty?
        metadata.merge!(place_metadata(record.meta), dating_metadata(record.meta),
                        typology_metadata(record), flag_metadata(record.meta),
                        reference_metadata(record))
      end

      def place_metadata(meta)
        placed = PLACE_COLUMNS.each_with_object({}) do |column, out|
          value = meta[column].to_s
          out[column] = value unless value.strip.empty?
        end
        coordinates = coordinate_pair(meta, "latitude", "longitude")
        placed["coordinates"] = coordinates if coordinates
        present = coordinate_pair(meta, "present_latitude", "present_longitude")
        placed["present_coordinates"] = present if present
        placed
      end

      # A WGS84 pair, or nil for upstream's 0/0 "unknown" filler. Values
      # verbatim (the artifact stores REAL columns).
      def coordinate_pair(meta, lat_column, lon_column)
        lat = meta[lat_column].to_f
        lon = meta[lon_column].to_f
        return nil if lat.zero? && lon.zero?

        { "latitude" => lat, "longitude" => lon }
      end

      def dating_metadata(meta)
        dated = {}
        dating = meta["dating"].to_s
        dated["dating"] = dating unless dating.strip.empty?
        dated["year_from"] = meta["year_from"] if meta["year_from"]
        dated["year_to"] = meta["year_to"] if meta["year_to"]
        dated
      end

      def typology_metadata(record)
        typed = TYPOLOGY_COLUMNS.each_with_object({}) do |column, out|
          value = record.meta[column].to_s
          out[column] = value unless value.strip.empty?
        end
        typed["material_type"] = record.material_type if record.material_type
        typed["crosses"] = record.crosses if record.crosses
        typed
      end

      def flag_metadata(meta)
        FLAG_COLUMNS.each_with_object({}) do |column, out|
          out[column] = true if meta[column] == 1
        end
      end

      # Bibliography entries verbatim; the stable links (kind=link) also
      # ride "related" — the edge-worthy targets the LibraryReferences
      # producer (":"-scheme rule) turns into kind=reference edges.
      def reference_metadata(record)
        return {} if record.references.empty?

        metadata = { "references" => record.references }
        related = record.references.select { |entry| entry["kind"] == "link" }
                                   .map { |entry| entry["text"] }
        metadata["related"] = related unless related.empty?
        metadata
      end

      # -- fetch ----------------------------------------------------------------

      def locate_artifact
        response, final_url = RedirectFollow.get(PAGE_URL, http: http, error: FetchError)
        name = response.body.to_s[ARTIFACT_PATTERN, 1]
        if name.nil?
          raise FetchError, "rundata: no runes.<hash>.sqlite3 reference found on #{PAGE_URL} — " \
                            "the app layout changed; re-derive the artifact URL by hand"
        end

        [name, URI.join(final_url, "/static/runes/#{name}").to_s]
      end

      # The hash already on disk: nothing to fetch. The state still
      # repoints (a lost state file self-heals here).
      def unchanged_report(workdir, name, url, target)
        sha = Digest::SHA256.file(target).hexdigest
        write_state!(workdir, name, sha, url, self.class.read_state(workdir)["last_modified"])
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now,
                              notes: "#{name} already current (the hash is the version; nothing fetched)")
      end

      # Download to <name>.part, verify it opens as a SQLite inscription
      # database, then rename into place — a corrupt body never lands
      # under the canonical name.
      def download!(url, target, progress)
        progress&.call("Downloading #{url}…\n")
        response, = RedirectFollow.get(url, http: http, error: FetchError)
        body = response.body.to_s.b
        FileUtils.mkdir_p(File.dirname(target))
        part = "#{target}.part"
        File.binwrite(part, body)
        verify_artifact!(part, url)
        File.rename(part, target)
        [Digest::SHA256.hexdigest(body), response.headers["last-modified"]]
      end

      def verify_artifact!(part, url)
        RundataSqliteParser.new(part).each_inscription.first
      rescue ParseError => e
        FileUtils.rm_f(part)
        raise FetchError, "rundata: downloaded artifact from #{url} is not a readable SRDB " \
                          "database (#{e.message}) — nothing landed"
      end

      def previous_artifacts(workdir, name)
        Dir.glob(File.join(workdir, ARTIFACT_GLOB)).map { |path| File.basename(path) } - [name]
      end

      def write_state!(workdir, name, sha, url, last_modified)
        FileUtils.mkdir_p(workdir)
        state = { "current" => name, "sha256" => sha, "url" => url,
                  "last_modified" => last_modified, "fetched_at" => Time.now.utc.iso8601 }
        File.write(File.join(workdir, STATE_FILE), JSON.pretty_generate(state))
      end

      def fetch_notes(name, sha, target, retained)
        count = parser_for(target).each_inscription.count
        notes = "#{name} sha256=#{sha[0, 12]} (#{count} inscriptions)"
        return notes if retained.empty?

        "#{notes}; retained #{retained.size} previous artifact(s) (never-delete)"
      end

      def http
        @http ||= ZipFetch.default_http
      end
    end
  end
end
