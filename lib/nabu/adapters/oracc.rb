# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # The ORACC adapter (P10-1) — the founding dream (the system is named
    # for Nabu): a thin composition of the OraccJsonParser family with
    # ORACC's per-project open-data layout, and the first adapter on the
    # NON-git fetch path (Nabu::ZipFetch — per-project zip over HTTP; no git
    # repo holds the data).
    #
    # == Layout and discovery
    #
    # Each in-scope project unpacks to <workdir>/<project-slug>/ carrying
    # metadata.json (license + config), catalogue.json (per-text designations
    # → document titles) and corpusjson/<P/Q-number>.json (the cdl trees).
    # discover walks corpusjson/*.json per project, SKIPPING the EMPTY files:
    # ~12% of rimanum's corpusjson files are 0-byte catalog-only artifacts
    # (catalogued, never transliterated) — an upstream norm, not damage, so
    # they are not documents and not quarantines; fetch counts them in its
    # notes so the sync record stays honest.
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:oracc:<project>:<P/Q-number>, subproject slash-paths
    # flattened with hyphens (saao/saa01 → saao-saa01). The parser mints from
    # the file's own project/textid fields and cross-checks, so
    # ref.id == parse(ref).urn (the conformance identity the sync breaker
    # relies on).
    #
    # == License: READ per project, never hardcoded
    #
    # Every project's metadata.json carries a machine-readable "license"
    # field. discover reads it per project and maps it through LICENSE_CLASSES
    # (CC0 → open, CC BY-SA → attribution); a license that maps to a class
    # OTHER than the manifest's declared class — or that does not map at all —
    # STOPS the sync loudly (Nabu::FetchError) instead of mislabeling
    # documents. Both in-scope projects report CC0 (verbatim: "This data is
    # released under the CC0 license") → license_class "open". NB the ORACC
    # website footer still shows the 2014 blanket CC BY-SA 3.0; the JSON
    # build's per-project field supersedes it and is what we read.
    #
    # == fetch (HTTP zip; retention contract intact)
    #
    # One zip per project from https://oracc.museum.upenn.edu/json/<slug>.zip,
    # served with Last-Modified (replayed as If-Modified-Since — change
    # detection without a re-download). The UD two-phase choreography: ALL
    # projects are downloaded and staged (live trees untouched), the
    # mass-deletion breaker sees the deletions of the whole set, then each
    # staged tree swaps in — upstream-dropped files land in
    # <workdir>/.attic/<slug>/ with a sha manifest first (ZipFetch mirrors
    # GitFetch's attic semantics, so the base class's attic rediscovery works
    # unchanged). FetchReport.sha pins the LAST project's zip sha256
    # (arbitrary-but-deterministic, the UD stance); notes carry the honest
    # per-project record: sha prefix, text count, catalog-only empty count.
    #
    # `nabu health --remote` probes ORACC over HTTP, not git (P11-2): the
    # probe HEADs each project zip (reachability + Last-Modified drift vs the
    # stored .zip-fetch.json pin) and GETs each project metadata.json for
    # license drift, declared via .remote_probe_strategy / .http_probe_targets
    # below. Both go through ZipFetch.default_http (the vendored-cert path),
    # since oracc.museum.upenn.edu serves an incomplete TLS chain.
    #
    # == Translations
    #
    # None ingested — the JSON carries word glosses (gw) but NO prose
    # translations (P9-5a: 0 translation nodes across 265 SAA texts; running
    # English lives only in the ATF #tr.en source layer). Aligned English is
    # a future separate acquisition; the registry records translations: false.
    class Oracc < Nabu::Adapter
      # In-scope project paths (ORACC project ids; subprojects would be
      # slash-paths). Extending scope = adding a path here + owner-fired
      # first sync. Slugs (dir names, urn segments, zip basenames) are the
      # paths hyphen-flattened.
      PROJECTS = %w[rimanum etcsri saao/saa01 rinap/rinap1 dcclt].freeze

      ZIP_BASE_URL = "https://oracc.museum.upenn.edu/json"

      # The standalone per-project metadata.json lives at the project root,
      # NOT under /json/ (verified live 2026-07-09:
      # https://oracc.museum.upenn.edu/<project>/metadata.json → 200
      # application/json; the /json/<project>/metadata.json path 500s).
      METADATA_BASE_URL = "https://oracc.museum.upenn.edu"

      # Upstream license strings → our license_class enum, matched in order.
      # Anything unmatched is a STOP (see class note).
      LICENSE_CLASSES = [
        [/CC0/i, "open"],
        [/CC BY-SA|Attribution[- ]Share[- ]?Alike/i, "attribution"]
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "oracc",
        name: "ORACC — Open Richly Annotated Cuneiform Corpus",
        license: "CC0 (read per-project from metadata.json)",
        license_class: "open",
        upstream_url: "https://oracc.museum.upenn.edu",
        parser_family: "oracc-json"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: ORACC is the HTTP-zip fetch path, so the remote-health probe
      # HEADs each project zip and GETs each metadata.json instead of
      # ls-remote (there is no git repo).
      def self.remote_probe_strategy = :http_zip

      # One probe target per in-scope project. The zip URL doubles as the
      # ledger-pin key (sync pins each project by its zip URL — see
      # #report's FetchReport.repos), so per-project drift/license baselines
      # attach to the same pins the git sources use.
      def self.http_probe_targets
        PROJECTS.map do |project|
          project_slug = project.tr("/", "-")
          Nabu::Adapter::HttpProbeTarget.new(
            label: project_slug,
            zip_url: "#{ZIP_BASE_URL}/#{project_slug}.zip",
            metadata_url: "#{METADATA_BASE_URL}/#{project}/metadata.json",
            state_subdir: project_slug
          )
        end
      end

      # Walk <workdir>/<slug>/corpusjson/*.json for every in-scope project,
      # one DocumentRef per NON-EMPTY file (empty = catalog-only, skipped —
      # see class note), sorted by urn. Reads each project's license gate
      # and catalogue titles once per call.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # P11-7 discovery census: per in-scope project whose tree is present,
      # count the 0-byte catalog-only skeletons discover skips (skipped-by-rule)
      # and flag any project whose tree exists but yields NO corpusjson at all
      # (unrecognized — the nested-root/unpack signature fix 1 resolves, kept as
      # a loud guard against its recurrence). The no-content skeletons that DO
      # parse-skip are counted by the loader, not here. Cheap: Dir globs + 0-byte
      # stats, no JSON read.
      def discovery_skips(workdir)
        skipped = 0
        notes = []
        PROJECTS.each do |project|
          next unless Dir.exist?(File.join(workdir, slug(project)))

          files = Dir.glob(File.join(project_dir(workdir, project), "corpusjson", "*.json"))
          if files.empty?
            notes << "#{slug(project)}: project tree present but no corpusjson found (unpack/layout error)"
            next
          end
          skipped += files.count { |path| File.empty?(path) }
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      # Delegate to the OraccJsonParser with the title discover resolved from
      # the catalogue. No language: the parser derives the per-text primary
      # language from the data itself.
      def parse(document_ref)
        OraccJsonParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          title: document_ref.metadata["title"]
        )
      end

      # Download/unpack each project zip into <workdir>/<slug> via the shared
      # ZipFetch phases: all projects prepared (staged, trees untouched), the
      # mass-deletion breaker guards the whole set, then each tree swaps in.
      # No network in tests: exercised against WebMock-stubbed zips. An HTTP
      # or unzip failure aborts the sync as Nabu::FetchError; a tripped
      # breaker as Nabu::SyncAborted (+force+ overrides).
      def fetch(workdir, progress: nil, force: false)
        fetches = zip_fetches(workdir, progress)
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          fetches.each_value(&:cleanup!)
        end
        report(workdir, fetches)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "oracc fetch failed into #{workdir}: #{e.message}"
      end

      private

      def slug(project) = project.tr("/", "-")

      # The directory that actually holds this project's corpusjson/ (and its
      # metadata.json/catalogue.json), at EITHER depth (P11-7 the headline):
      # top-level projects unpack to <workdir>/<slug>/, but SUBPROJECT zips
      # (saao/saa01, rinap/rinap1) unpack with a NESTED ROOT —
      # <workdir>/saao-saa01/saa01/corpusjson — so discover looking only at
      # <slug>/corpusjson silently ingested 0 of their 361 texts. Prefer the
      # top level; fall back to the subproject's last path segment (the nested
      # root the zip carries). Returns the base dir unchanged when neither holds
      # corpusjson (never fetched, or damaged) — the caller yields no refs and
      # the discovery accounting renders that loudly.
      def project_dir(workdir, project)
        base = File.join(workdir, slug(project))
        return base if Dir.exist?(File.join(base, "corpusjson"))

        nested = File.join(base, project.split("/").last)
        Dir.exist?(File.join(nested, "corpusjson")) ? nested : base
      end

      # The zip URL for a project — split out so tests could repoint a
      # singleton, though the house pattern here is WebMock stubs.
      def zip_url(project) = "#{ZIP_BASE_URL}/#{slug(project)}.zip"

      def zip_fetches(workdir, progress)
        PROJECTS.to_h do |project|
          [project, Nabu::ZipFetch.new(
            url: zip_url(project), dir: File.join(workdir, slug(project)),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug(project)), progress: progress
          )]
        end
      end

      def report(workdir, fetches)
        shas = fetches.transform_values(&:sha)
        Nabu::FetchReport.new(
          sha: shas.values.last, fetched_at: Time.now,
          notes: fetch_notes(workdir, fetches, shas),
          repos: shas.transform_keys { |project| zip_url(project) }
        )
      end

      # "rimanum=<sha12> (338 texts, 40 catalog-only (empty)) …" — the honest
      # per-project record, including the empty corpusjson files discover
      # will skip. Attic activity rides along as in the git adapters.
      def fetch_notes(workdir, fetches, shas)
        notes = shas.map do |project, sha|
          "#{slug(project)}=#{sha[0, 12]} (#{project_counts(project_dir(workdir, project))})"
        end.join(" ")
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        atticked.positive? ? "#{notes} · atticked #{atticked} upstream-deleted file(s)" : notes
      end

      def project_counts(dir)
        files = Dir.glob(File.join(dir, "corpusjson", "*.json"))
        empty = files.count { |file| File.empty?(file) }
        counts = "#{files.size - empty} texts"
        empty.positive? ? "#{counts}, #{empty} catalog-only (empty)" : counts
      end

      def document_refs(workdir)
        PROJECTS.flat_map { |project| project_refs(workdir, project) }.sort_by(&:id)
      end

      def project_refs(workdir, project)
        dir = project_dir(workdir, project)
        return [] unless Dir.exist?(dir)

        check_license!(dir, project)
        titles = catalogue_titles(dir)
        Dir.glob(File.join(dir, "corpusjson", "*.json")).reject { |path| File.empty?(path) }.map do |path|
          id = File.basename(path, ".json")
          Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:oracc:#{slug(project)}:#{id}",
            path: File.expand_path(path),
            metadata: { "project" => slug(project), "title" => titles[id] || id }
          )
        end
      end

      # The per-project license gate (see class note): metadata.json's
      # license field must map to the manifest's declared class. An unknown
      # or diverging license STOPS the sync — mislabeled documents are worse
      # than an aborted run. Gate only where metadata.json exists: every
      # LIVE project tree carries it (the zip ships it), but the base class
      # also runs discover against <workdir>/.attic, which holds only the
      # files upstream DROPPED — usually no metadata.json. Attic texts were
      # gated while they were live.
      def check_license!(dir, project)
        path = File.join(dir, "metadata.json")
        return unless File.file?(path)

        license = project_metadata(dir, project)["license"].to_s
        mapped = LICENSE_CLASSES.find { |pattern, _class| license.match?(pattern) }&.last
        if mapped.nil?
          raise Nabu::FetchError,
                "oracc project #{project}: unrecognized license #{license.inspect} — " \
                "map it in Oracc::LICENSE_CLASSES (owner decision) before syncing"
        end
        return if mapped == MANIFEST.license_class

        raise Nabu::FetchError,
              "oracc project #{project}: license #{license.inspect} maps to class #{mapped.inspect}, " \
              "but the source is registered #{MANIFEST.license_class.inspect} — " \
              "split the project into its own source rather than mislabel it"
      end

      def project_metadata(dir, project)
        path = File.join(dir, "metadata.json")
        raise Nabu::FetchError, "oracc project #{project}: missing metadata.json in #{dir}" unless File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "oracc project #{project}: malformed metadata.json: #{e.message}"
      end

      # id → designation from the project catalogue; missing/malformed
      # catalogues only cost titles (the id stands in), never discovery.
      def catalogue_titles(dir)
        path = File.join(dir, "catalogue.json")
        return {} unless File.file?(path)

        members = JSON.parse(File.read(path))["members"]
        return {} unless members.is_a?(Hash)

        members.transform_values { |member| member.is_a?(Hash) ? member["designation"] : nil }.compact
      rescue JSON::ParserError
        {}
      end
    end
  end
end
