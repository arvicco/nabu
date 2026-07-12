# frozen_string_literal: true

require "fileutils"
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
    # documents. All in-scope projects report CC0 (verbatim: "This data is
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
    # == Translations (P13-4; registry `translations: true`, default inert)
    #
    # The JSON carries word glosses (gw) but NO prose translations (P9-5a: 0
    # translation nodes across 265 SAA texts) — and no public bulk artifact
    # does (catf is transliteration-only C-ATF; per-text .atf/.xtf are
    # soft-404s). The running English is acquired from the official per-text
    # fragment `/<project>/<textid>/html` and ingested as sibling documents
    # (`<tablet-urn>-en`, OraccTranslationParser), the P7-4 shape that makes
    # `show <tablet> --parallel` render like the Homers.
    #
    # - CRAWL (fetch, after the zip phases): PROJECT-SCOPED — the served list
    #   is TRANSLATION_PROJECTS (stage 1 = saao, owner 2026-07-11; stage 2 =
    #   the full project list, owner-approved 2026-07-12, P14-4 — the
    #   promised list change, no machinery change). Which texts have English
    #   is machine-read from each project metadata.json's
    #   `formats["tr-en"]`. Fragments land OUTSIDE the zip-managed project
    #   trees (<workdir>/html-en/<slug>/<id>.html) so a zip swap never attics
    #   them; the crawl itself never deletes (retention by construction).
    #   Politeness: sequential, CRAWL_DELAY between GETs, resumable — an
    #   unchanged build (zip 304) re-fetches only files missing locally, a
    #   changed build re-crawls the project (no per-fragment Last-Modified
    #   upstream). A soft-404 body (ORACC answers missing pages with a 200
    #   "404\n") is counted missing and never written.
    # - DISCOVER is file-driven: one -en ref per crawled fragment whose
    #   tablet corpusjson is live (an orphan fragment is skipped by rule and
    #   counted); so stage-2 fragments ingest the sync after they land.
    # - LICENSE: the prose is SAAo/ORACC project *content* ("Content released
    #   under a CC BY-SA 3.0 license" — project footer), NOT the JSON build's
    #   CC0; translation documents carry license_override "attribution"
    #   (P10-4) while the source stays "open".
    class Oracc < Nabu::Adapter
      # In-scope project paths (ORACC project ids; subprojects are
      # slash-paths). Extending scope = adding a path here + owner-fired
      # first sync. Slugs (dir names, urn segments, zip basenames) are the
      # paths hyphen-flattened.
      #
      # Scope history: P10-1 rimanum+etcsri; P11-6 +saao/saa01, rinap/rinap1,
      # dcclt; P13-3 (owner-approved 2026-07-11, "full SAA is the point")
      # +the complete SAA run saa02–saa21 plus saas2 (SAA Studies 2 — the
      # lemmatised Assyrian Eponym/King List editions, a normal saao corpus
      # subproject), riao, ribo (top level only; its babylon* subprojects
      # out of scope), blms, and the four dcclt subprojects — 33 projects,
      # ~159 MB of zips across the 28 new ones. All CC0-expected per the
      # P9-5a family scout; the per-project license gate is the guarantee.
      PROJECTS = %w[
        rimanum etcsri saao/saa01 rinap/rinap1 dcclt
        saao/saa02 saao/saa03 saao/saa04 saao/saa05 saao/saa06 saao/saa07
        saao/saa08 saao/saa09 saao/saa10 saao/saa11 saao/saa12 saao/saa13
        saao/saa14 saao/saa15 saao/saa16 saao/saa17 saao/saa18 saao/saa19
        saao/saa20 saao/saa21 saao/saas2
        riao ribo blms
        dcclt/ebla dcclt/jena dcclt/nineveh dcclt/signlists
      ].freeze

      # Translation-crawl scope. Stage 1 (P13-4, owner 2026-07-11 "Two-stage
      # SAA-first crawl") was the saao projects; stage 2 (P14-4,
      # owner-approved 2026-07-12 "Full crawl") is the FULL project list —
      # the data change the staging design promised, no machinery change.
      # The metadata tr-en gate makes the full list exact: the zero-English
      # catalog hubs (riao, ribo, dcclt/jena — no corpusjson, empty formats)
      # are provably inert, and new upstream tr-en is picked up for free.
      # English only: etcsri's 1441 tr-hun (Hungarian) stays the flagged
      # config-shaped follow-up.
      TRANSLATION_PROJECTS = PROJECTS

      # Crawled fragments live OUTSIDE the zip-managed <slug>/ trees: a zip
      # swap diffs only its own tree, so fragments are never atticked/deleted
      # by the next build.
      TRANSLATIONS_DIRNAME = "html-en"

      # Seconds between crawl GETs — sequential and polite against a
      # university server (~4 texts/s ceiling; the crawl is one-time per
      # build and resumable).
      CRAWL_DELAY = 0.25

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

      # +translations+ (P13-4): when true, fetch also crawls the
      # TRANSLATION_PROJECTS' English fragments and discover yields the -en
      # sibling documents. The default (false) is provably inert — tablets
      # only, exactly the pre-P13-4 behavior. No-arg construction stays the
      # registry contract; the flag arrives via
      # SourceRegistry::Entry#build_adapter for opted-in sources.
      # +crawl_delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(translations: false, crawl_delay: CRAWL_DELAY)
        super()
        @translations = translations
        @crawl_delay = crawl_delay
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
      # stats; the one JSON read (proxy_corpus?) fires only on the rare
      # no-corpusjson branch.
      def discovery_skips(workdir)
        skipped = 0
        notes = []
        PROJECTS.each do |project|
          next unless Dir.exist?(File.join(workdir, slug(project)))

          files = Dir.glob(File.join(project_dir(workdir, project), "corpusjson", "*.json"))
          if files.empty?
            # P14-9 fix 3: riao/ribo/dcclt-jena are PROXY corpora — corpus.json
            # is `type:corpus` with a `proxies` map, their texts hosted in
            # out-of-scope sibling subprojects (PROJECTS note). Owning no
            # corpusjson is BY DESIGN, a benign skip, not the unpack/layout
            # error the loud guard is for.
            if proxy_corpus?(workdir, project)
              skipped += 1
            else
              notes << "#{slug(project)}: project tree present but no corpusjson found (unpack/layout error)"
            end
            next
          end
          skipped += files.count { |path| File.empty?(path) }
          skipped += orphan_fragment_count(workdir, project) if @translations
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      # A proxy/portal corpus owns no corpusjson: its corpus.json is
      # `type:corpus` carrying a non-empty `proxies` map (the texts live in
      # out-of-scope sibling subprojects). Checked at EITHER unpack depth
      # (dcclt/jena nests under <slug>/jena/), so it mirrors project_dir.
      def proxy_corpus?(workdir, project)
        base = File.join(workdir, slug(project))
        [base, File.join(base, project.split("/").last)].any? do |dir|
          path = File.join(dir, "corpus.json")
          next false unless File.exist?(path)

          proxies = JSON.parse(File.read(path))["proxies"]
          proxies.is_a?(Hash) && !proxies.empty?
        rescue JSON::ParserError
          false
        end
      end

      # Tablets go to the OraccJsonParser (title from the catalogue, language
      # derived from the data); -en refs (metadata "kind" => "translation")
      # go to the OraccTranslationParser with their sibling corpusjson.
      def parse(document_ref)
        if document_ref.metadata["kind"] == "translation"
          OraccTranslationParser.new.parse(
            document_ref.path,
            urn: document_ref.id,
            corpusjson_path: document_ref.metadata["corpusjson"],
            title: document_ref.metadata["title"]
          )
        else
          OraccJsonParser.new.parse(
            document_ref.path,
            urn: document_ref.id,
            title: document_ref.metadata["title"]
          )
        end
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
        crawl_notes = crawl_translations!(workdir, fetches, progress: progress)
        report(workdir, fetches, crawl_notes)
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

      def report(workdir, fetches, crawl_notes)
        shas = fetches.transform_values(&:sha)
        Nabu::FetchReport.new(
          sha: shas.values.last, fetched_at: Time.now,
          notes: fetch_notes(workdir, fetches, shas, crawl_notes),
          repos: shas.transform_keys { |project| zip_url(project) }
        )
      end

      # "rimanum=<sha12> (338 texts, 40 catalog-only (empty)) …" — the honest
      # per-project record, including the empty corpusjson files discover
      # will skip. Attic activity and the per-project crawl record ride along.
      def fetch_notes(workdir, fetches, shas, crawl_notes)
        notes = shas.map do |project, sha|
          "#{slug(project)}=#{sha[0, 12]} (#{project_counts(project_dir(workdir, project))})"
        end.join(" ")
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        notes = "#{notes} · atticked #{atticked} upstream-deleted file(s)" if atticked.positive?
        crawl_notes.empty? ? notes : "#{notes} · #{crawl_notes.join(' ')}"
      end

      # -- the stage-scoped translation crawl (P13-4; see class note) --------

      # One pass over TRANSLATION_PROJECTS after the zip phases: GET each
      # tr-en text's fragment into <workdir>/html-en/<slug>/. Returns the
      # human note fragments ("saao-saa01 html-en: 264 fetched, 0 cached,
      # 1 missing"). Silent (empty) when translations are off or nothing is
      # listed.
      def crawl_translations!(workdir, fetches, progress: nil)
        return [] unless @translations

        TRANSLATION_PROJECTS.filter_map do |project|
          ids = translated_ids(project_dir(workdir, project))
          next nil if ids.empty?

          progress&.call("Crawling #{project} translations (#{ids.size} texts)…")
          counts = crawl_project!(workdir, project, ids, zip_changed: !fetches.fetch(project).not_modified?)
          "#{slug(project)} html-en: #{counts[:fetched]} fetched, " \
            "#{counts[:cached]} cached, #{counts[:missing]} missing"
        end
      end

      # The texts with an English translation, machine-read from the project
      # metadata's formats block; [] when the tree or the block is absent
      # (an envelope-only or never-fetched project has nothing to crawl).
      def translated_ids(dir)
        path = File.join(dir, "metadata.json")
        return [] unless File.file?(path)

        Array(JSON.parse(File.read(path)).dig("formats", "tr-en")).map(&:to_s).sort
      rescue JSON::ParserError
        []
      end

      # Sequential, polite, resumable: an unchanged build fetches only what
      # is missing locally; a changed build refreshes every fragment (no
      # per-fragment Last-Modified upstream — the zip's is the build's).
      # Soft-404 bodies are counted missing, never written; a write is
      # tmp+rename so an interrupted crawl never leaves a torn fragment.
      def crawl_project!(workdir, project, ids, zip_changed:)
        dir = File.join(workdir, TRANSLATIONS_DIRNAME, slug(project))
        FileUtils.mkdir_p(dir)
        counts = { fetched: 0, cached: 0, missing: 0 }
        ids.each do |id|
          target = File.join(dir, "#{id}.html")
          next counts[:cached] += 1 if File.file?(target) && !zip_changed

          sleep(@crawl_delay) if @crawl_delay.positive? && (counts[:fetched] + counts[:missing]).positive?
          body = get_fragment(project, id)
          next counts[:missing] += 1 if soft_404?(body)

          File.binwrite("#{target}.tmp", body)
          File.rename("#{target}.tmp", target)
          counts[:fetched] += 1
        end
        counts
      end

      def get_fragment(project, id)
        url = "#{METADATA_BASE_URL}/#{project}/#{id}/html"
        response = ZipFetch.default_http.get(url)
        unless response.status == 200
          raise Nabu::FetchError, "oracc translation crawl: HTTP #{response.status} for #{url}"
        end

        response.body.to_s
      rescue Faraday::Error => e
        raise Nabu::FetchError, "oracc translation crawl: transport error for #{url}: #{e.message}"
      end

      # ORACC answers a missing per-text page with a 200 whose body is a
      # literal "404\n" (verified on .atf/.xtf/fragment endpoints, P13-4
      # Phase A) — a soft-404, honestly a missing text, not damage.
      def soft_404?(body)
        body.strip == "404"
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
        tablets = Dir.glob(File.join(dir, "corpusjson", "*.json")).reject { |path| File.empty?(path) }.map do |path|
          id = File.basename(path, ".json")
          Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:oracc:#{slug(project)}:#{id}",
            path: File.expand_path(path),
            metadata: { "project" => slug(project), "title" => titles[id] || id }
          )
        end
        tablets + translation_refs(workdir, project, dir, titles)
      end

      # One -en ref per crawled fragment whose tablet corpusjson is live
      # (file-driven — see the class Translations note); nothing when the
      # adapter was built without translations. The ref carries the sibling
      # corpusjson path (ref→label alignment) and the catalogue-derived title.
      def translation_refs(workdir, project, dir, titles)
        return [] unless @translations

        Dir.glob(File.join(workdir, TRANSLATIONS_DIRNAME, slug(project), "*.html")).filter_map do |path|
          id = File.basename(path, ".html")
          corpusjson = File.join(dir, "corpusjson", "#{id}.json")
          next nil if !File.file?(corpusjson) || File.empty?(corpusjson)

          Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:oracc:#{slug(project)}:#{id}-en",
            path: File.expand_path(path),
            metadata: { "project" => slug(project), "kind" => "translation",
                        "corpusjson" => File.expand_path(corpusjson),
                        "title" => "#{titles[id] || id} (English translation)" }
          )
        end
      end

      # Crawled fragments whose tablet corpusjson is not live: translation_refs
      # skips them (a translation without its tablet is unrenderable), so the
      # census counts them by rule.
      def orphan_fragment_count(workdir, project)
        dir = project_dir(workdir, project)
        Dir.glob(File.join(workdir, TRANSLATIONS_DIRNAME, slug(project), "*.html")).count do |path|
          corpusjson = File.join(dir, "corpusjson", "#{File.basename(path, '.html')}.json")
          !File.file?(corpusjson) || File.empty?(corpusjson)
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
