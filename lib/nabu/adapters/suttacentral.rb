# frozen_string_literal: true

require "json"

require_relative "../file_fetch"
require_relative "../suttacentral_parallels"

module Nabu
  module Adapters
    # The SuttaCentral adapter (P26-1; biblical–Indic survey lane 3): the
    # whole Tipiṭaka in roman-script Pali from `suttacentral/bilara-data`,
    # branch `published` — the segmented ("bilara") edition whose flat JSON
    # segment maps carry SuttaCentral's own citation scheme, plus English
    # translations keyed by THE SAME segment ids, ingested as `-en` sibling
    # documents (the ORACC/Damaskini precedent; `show URN --parallel`).
    #
    # == Scope (censused at the pinned survey commit, 2026-07-18; lzh flip
    #    censused against the synced canonical tree, P32-1, 2026-07-19)
    #
    # Three root trees: root/pli/ms — the Mahāsaṅgīti Tipiṭāka, 7,289 files
    # (one of which is upstream's own xplayground sandbox, skipped by rule) —
    # root/pra/pts — the 22 Patna Dhammapada files, language `pra`
    # (upstream's own tag; in scope because its English translation is THE
    # licensing outlier, see below) — and root/lzh/sct (P32-1) — the 272
    # Literary Chinese Āgama files, "SuttaCentral Taisho" (scpub39, CC0):
    # sutta 205 (ma 15 / sa 49 / ea 1 / lzh-minor 140) + abhidhamma 67
    # (sag 33 / lzh-dk 22 / sg 12), language `lzh`, stems disjoint from
    # pli/pra (censused: zero collisions across 7,583 stems). Out of scope:
    # root/en (site blurbs/UI strings, not canon), root/misc, root/san
    # (Sanskrit fragments — a future scope decision), the 32 non-English
    # translation languages, and — EXCLUDED by honesty — SuttaCentral's
    # LEGACY translations (the `html_text` layer in the separate sc-data
    # repo, largely CC BY-NC-ND; a different repo/layer this adapter fetches
    # exactly ONE file of — the parallels graph, see below).
    #
    # == The parallels graph rider (P32-6)
    #
    # sc-data's relationship/parallels.json (8,221 relation lists, 49,685
    # uid refs; NOT misc/ — the P26-1 journal's path drifted upstream, and
    # the sibling relationship/new_parallels.json, a 24 MB per-uid derived
    # view, is not the source of truth) becomes kind=reference edges via
    # Nabu::SuttacentralParallels (reference_edges? + the producer seam),
    # refreshed by SyncRunner after every sync. #fetch stage 2 lands the
    # file at <workdir>/parallels/parallels.json through FileFetch from the
    # COMMIT-pinned raw URL (PARALLELS_COMMIT), sha256-verified against
    # PARALLELS_SHA256 — a mismatch aborts with the tree untouched (the
    # etcsl pin choreography; the commit-pinned URL is immutable, so a
    # mismatch is corruption). Refreshing the graph = the owner bumps BOTH
    # constants to a newer sc-data commit with the ordinary sync — never
    # a silent drift. License: the graph carries no in-repo grant (sc-data
    # has no LICENSE file); SuttaCentral's licensing page states, verbatim:
    # "In addition, the reference data, including information on parallels,
    # is not an "original creation" and as such does not fall within the
    # scope of copyright." — and all original SuttaCentral material is CC0
    # ("All original material created by SuttaCentral is dedicated to the
    # Public Domain by means of Creative Commons Zero (CC0 1.0 Universal)").
    # Either way inside the source's "open" class — no override. (Measured
    # at P32-1: 237 relations pair a minted pli/pra text with a minted lzh
    # text — 223 parallels + 14 mentions.)
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:suttacentral:<stem>, the filename stem before the first
    # "_" — SuttaCentral's stable text uid (mn1, sn35.24, dhp21-32,
    # pli-tv-bu-vb-as1-7). English siblings are <stem>-en (no upstream stem
    # ends in "-en" — censused, frozen; the Damaskini variant split).
    # Passage citations are upstream's segment ids (see BilaraJsonParser).
    # Minting is frozen once used (standing rule).
    #
    # == License: read per publication from _publication.json, never assumed
    #
    # The repo's own `_publication.json` (140 publications censused at the
    # survey commit) is the machine-readable grant record: 138 publications
    # CC0 ("Creative Commons Zero"), 1 Public Domain (scpub64 — the
    # Mahāsaṅgīti root itself: "This work is an ancient sacred text… free of
    # known restrictions under copyright law"), and ONE outlier, scpub69 —
    # Ānandajoti's English Patna Dhammapada, "Creative Commons
    # Attribution-ShareAlike 3.0 Unported" (CC BY-SA 3.0) — whose `-en`
    # documents carry license_override "attribution" (P10-4) while the
    # source stays "open". Translation trees WITHOUT their own publication
    # record (e.g. suddhaso's MN files) ride the repo LICENSE.md blanket:
    # "All translations created in Bilara and supported by SuttaCentral are
    # dedicated to the Public Domain by means of the [CC0 license]". A
    # publication license that maps to NO known class stops discovery loudly
    # (Nabu::FetchError) — mislabeled documents are worse than an aborted
    # run. The ORACC gate stance verbatim: gate only where the metadata file
    # exists (the base class also discovers .attic, which holds only files
    # upstream dropped — attic texts were gated while they were live).
    #
    # == Translations (registry `translations: true`)
    #
    # File-driven discovery over translation/en/<translator>/…: one `-en`
    # ref per root stem that has an English file, parsed by the SAME parser
    # (same segment-map shape, same ids → exact suffix alignment; a
    # translation may honestly lack segments the root has, or translate a
    # segment the root leaves blank — one-sided rows, never false pairs).
    # 104 stems are double-covered (always sujato + one other, censused);
    # TRANSLATOR_PRIORITY (coverage-ordered at census time, frozen) picks
    # ONE deterministically, the losers are censused rule skips. Orphan
    # English files (125 stems since the P32-1 lzh flip: sujato's name/
    # glossaries plus en files whose roots bilara has not published — the
    # pre-flip census was 179, and patton's 54 Āgama translations of ma/sa
    # roots stopped being orphans the moment their lzh roots minted; no lzh
    # stem is double-covered) are skipped by rule — a translation without
    # its root is unrenderable (the ORACC orphan-fragment rule). The lzh
    # -en publications are patton's scpub20 (sa) / scpub35 (ma), both CC0
    # verbatim ("Creative Commons Zero" / "CC0"); scpub36 (ea19) and
    # scpub37 (da) cover trees the published branch does not yet carry.
    #
    # == fetch (the shared git path, pinned to `published`)
    #
    # One ordinary clone/pull of the bilara-data repo (~353 MB with .git at
    # census time), pinned to the `published` branch via GitFetch's ref pin
    # (P17-1) — the unreviewed working branches never reach canonical/.
    # Attic + mass-deletion breaker as everywhere. No network in tests.
    class Suttacentral < Nabu::Adapter
      BRANCH = "published"

      # Root tree → [language, edition slug]. The published branch's other
      # root trees are out of scope (see class note).
      ROOT_TREES = {
        "root/lzh/sct" => %w[lzh sct],
        "root/pli/ms" => %w[pli ms],
        "root/pra/pts" => %w[pra pts]
      }.freeze

      # Upstream's own sandbox dir under root/pli/ms ("This file is just for
      # playing around… Do not commit this file to the main data repository"
      # — committed upstream anyway). Never a document; censused rule skip.
      SANDBOX_DIRNAME = "xplayground"

      # The frozen translator pick order for double-covered stems,
      # coverage-ordered at census time (sujato 4,292 files … kovilo 2).
      # A translator missing from this list sorts after it, alphabetically —
      # deterministic even against upstream additions.
      TRANSLATOR_PRIORITY = %w[sujato brahmali kelly soma suddhaso kovilo patton anandajoti].freeze

      # Publication license strings → our license_class enum, matched in
      # order against "license_type (abbreviation)". Anything unmatched is a
      # STOP (see class note).
      LICENSE_CLASSES = [
        [/CC0|Creative Commons Zero|Public Domain/i, "open"],
        [/CC BY-SA|Attribution[- ]Share[- ]?Alike/i, "attribution"]
      ].freeze

      PUBLICATION_FILE = "_publication.json"

      URN_PREFIX = "urn:nabu:suttacentral:"

      # The parallels graph pin (class note): the sc-data commit whose
      # relationship/parallels.json is fetched, and that file's sha256
      # (1,509,922 bytes, retrieved 2026-07-19). Bump BOTH to refresh.
      PARALLELS_COMMIT = "8b3bcaf61c3e4d4d80dc131df3d1b7fb8d1d1311"
      PARALLELS_SHA256 = "cba7f314a32aeecc9cba9381b5f6b781567be75c5dc69d5d1d755b2cd6465f1e"
      PARALLELS_URL = "https://raw.githubusercontent.com/suttacentral/sc-data/" \
                      "#{PARALLELS_COMMIT}/relationship/parallels.json".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "suttacentral",
        name: "SuttaCentral — bilara-data segmented canon (Pali Tipiṭaka + Chinese Āgamas + aligned English)",
        license: "Root: Public Domain (scpub64, \"an ancient sacred text… free of known restrictions " \
                 "under copyright law\"); translations CC0 per publication (138/140; LICENSE.md " \
                 "blanket), except scpub69 CC BY-SA 3.0 → per-document override",
        license_class: "open",
        upstream_url: "https://github.com/suttacentral/bilara-data",
        parser_family: "bilara-json"
      )

      def self.manifest
        MANIFEST
      end

      # The parallels-graph edges (class note; P32-6).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        SuttacentralParallels.new(catalog: catalog, journal: journal)
      end

      # +translations+: when true (the registry row's posture), discover also
      # yields one -en sibling ref per root stem with an English file.
      # +graph_pin+ overrides the parallels-graph sha256 (tests; an owner
      # re-pin drill).
      def initialize(translations: false, graph_pin: PARALLELS_SHA256)
        super()
        @translations = translations
        @graph_pin = graph_pin
      end

      # One DocumentRef per root segment file under the in-scope trees (plus
      # -en siblings when opted in), sorted by urn. A workdir without the
      # trees yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # P11-7 discovery census: the sandbox file(s), the losing alternate
      # translations of double-covered stems, and the orphan English files
      # (no live root stem) are all explicit rule skips. A root tree present
      # but yielding NO segment files is unrecognized — loud, a layout error.
      def discovery_skips(workdir)
        skipped = sandbox_files(workdir).size
        notes = ROOT_TREES.keys.filter_map do |tree|
          dir = File.join(workdir, tree)
          next nil unless Dir.exist?(dir) && root_files(workdir, tree).empty?

          "#{tree}: tree present but no *_root-*.json found (unpack/layout error)"
        end
        if @translations
          stems = root_stems(workdir)
          english_files_by_stem(workdir).each do |stem, by_translator|
            skipped += stems.key?(stem) ? by_translator.size - 1 : by_translator.size
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      # Roots and -en siblings both go to the BilaraJsonParser — same shape,
      # same segment ids (the whole alignment story). Facets/edition ride on
      # roots; kind/translator/publication provenance on translations.
      def parse(document_ref)
        metadata = document_ref.metadata
        BilaraJsonParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          stem: metadata.fetch("stem"),
          language: metadata.fetch("language"),
          metadata: document_metadata(metadata),
          license_override: metadata["license_override"]
        )
      end

      # Stage 1: clone or non-destructively pull bilara-data pinned to the
      # published branch (Adapter#git_fetch! → Nabu::GitFetch: attic +
      # pre-merge mass-deletion breaker). Stage 2: the parallels graph via
      # sha-pinned FileFetch (class note). The FetchReport pin stays the
      # bilara-data HEAD; the graph sha and its sc-data commit ride notes.
      # No network in tests: local fixture repo + WebMock'd graph URL.
      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, ref: BRANCH)
        graph = fetch_parallels_graph!(workdir, progress: progress, force: force)
        report.with(notes: [report.notes, graph_note(graph)].compact.join("; "))
      end

      private

      # FileFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the etcsl choreography); a
      # 304 replays the stored pin and touches nothing.
      def fetch_parallels_graph!(workdir, progress:, force:)
        fetch = Nabu::FileFetch.new(
          url: PARALLELS_URL, dir: File.join(workdir, SuttacentralParallels::DIRNAME),
          filename: SuttacentralParallels::FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, SuttacentralParallels::DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_graph_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        fetch
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "suttacentral parallels graph fetch failed into #{workdir}: #{e.message}"
      end

      def verify_graph_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @graph_pin

        raise Nabu::FetchError,
              "suttacentral: parallels graph misses the sha256 pin (expected #{@graph_pin}, got " \
              "#{fetch.sha}) — the sc-data commit-pinned URL is immutable, so this is corruption; " \
              "an upstream refresh is an OWNER re-pin of PARALLELS_COMMIT + PARALLELS_SHA256"
      end

      def graph_note(fetch)
        state = fetch.not_modified? ? "not modified (304)" : "sha pin verified"
        "parallels graph #{state} (sc-data #{PARALLELS_COMMIT[0, 8]})"
      end

      # Split out so tests can point a singleton at a local git tmpdir (the
      # house pattern), keeping fetch off the network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        roots = root_stems(workdir)
        refs = roots.values
        refs += translation_refs(workdir, roots) if @translations
        refs.sort_by(&:id)
      end

      # stem → root DocumentRef for every in-scope root file (sandbox
      # skipped). Stems are unique across the trees (upstream uids).
      def root_stems(workdir)
        ROOT_TREES.each_with_object({}) do |(tree, (language, edition)), map|
          root_files(workdir, tree).each do |path|
            stem = File.basename(path).split("_", 2).first
            map[stem] = root_ref(workdir, tree, path, stem, language, edition)
          end
        end
      end

      def root_ref(workdir, tree, path, stem, language, edition)
        basket, collection = relative_parts(File.join(workdir, tree), path)
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{stem}",
          path: File.expand_path(path),
          metadata: { "stem" => stem, "language" => language, "edition" => edition,
                      "basket" => basket, "collection" => collection }.compact
        )
      end

      def root_files(workdir, tree)
        Dir.glob(File.join(workdir, tree, "**", "*_root-*.json"))
           .reject { |path| sandbox?(path) }
      end

      def sandbox_files(workdir)
        Dir.glob(File.join(workdir, "root", "**", "*_root-*.json")).select { |path| sandbox?(path) }
      end

      def sandbox?(path)
        path.split(File::SEPARATOR).include?(SANDBOX_DIRNAME)
      end

      # The dir parts of +path+ under +base+ minus the filename: basket
      # ("sutta"/"vinaya"/"abhidhamma") and collection ("mn", "kn",
      # "pli-tv-bu-vb", "pdhp"; nil for a file sitting at basket level).
      def relative_parts(base, path)
        parts = File.expand_path(path).delete_prefix("#{File.expand_path(base)}#{File::SEPARATOR}")
                    .split(File::SEPARATOR)[0...-1]
        [parts[0], parts[1]]
      end

      # -- the -en sibling side ----------------------------------------------

      # One -en ref per root stem with an English file: the priority
      # translator's file, license-gated through _publication.json (see the
      # class note). Orphans and losing alternates are censused, not minted.
      def translation_refs(workdir, roots)
        publications = publication_grants(workdir)
        english_files_by_stem(workdir).filter_map do |stem, by_translator|
          root = roots[stem] or next nil

          translator = by_translator.keys.min_by { |name| translator_rank(name) }
          path = by_translator.fetch(translator)
          publication, override = publications.resolve(relative_path(workdir, path))
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{root.id}-en",
            path: File.expand_path(path),
            metadata: { "stem" => stem, "language" => "eng", "kind" => "translation",
                        "translator" => translator, "publication" => publication,
                        "license_override" => override }.compact
          )
        end
      end

      def translator_rank(name)
        [TRANSLATOR_PRIORITY.index(name) || TRANSLATOR_PRIORITY.size, name]
      end

      # stem → { translator => path } over translation/en. The translator is
      # the path segment right under translation/en.
      def english_files_by_stem(workdir)
        base = File.join(workdir, "translation", "en")
        Dir.glob(File.join(base, "*", "**", "*_translation-en-*.json"))
           .each_with_object({}) do |path, map|
          stem = File.basename(path).split("_", 2).first
          translator = File.expand_path(path).delete_prefix("#{File.expand_path(base)}#{File::SEPARATOR}")
                           .split(File::SEPARATOR).first
          (map[stem] ||= {})[translator] = path
        end
      end

      def relative_path(workdir, path)
        File.expand_path(path).delete_prefix("#{File.expand_path(workdir)}#{File::SEPARATOR}")
      end

      # The per-publication grant table, read once per discover from the
      # repo's own _publication.json. Resolves a repo-relative file path to
      # [publication id, license_override] by longest source_url prefix; no
      # record → the LICENSE.md CC0 blanket ([nil, nil]). An unmappable
      # license string raises (see class note).
      class PublicationGrants
        def self.load(path, source_class:)
          return none unless File.file?(path)

          entries = JSON.parse(File.read(path)).filter_map do |key, publication|
            url = publication["source_url"].to_s
            tail = url.split("/tree/#{BRANCH}/", 2)[1]
            next nil if tail.nil? || tail.empty?

            [tail, key, publication.fetch("license", {})]
          end
          new(entries.sort_by { |tail, _key, _license| -tail.length }, source_class: source_class)
        rescue JSON::ParserError => e
          raise Nabu::FetchError, "suttacentral: malformed #{PUBLICATION_FILE}: #{e.message}"
        end

        # The attic/no-file posture: every path rides the blanket grant.
        def self.none
          new([], source_class: MANIFEST.license_class)
        end

        def initialize(entries, source_class:)
          @entries = entries
          @source_class = source_class
        end

        def resolve(relative_path)
          tail, key, license = @entries.find { |prefix, _k, _l| relative_path.start_with?("#{prefix}/") }
          return [nil, nil] if tail.nil?

          mapped = license_class(key, license)
          [key, mapped == @source_class ? nil : mapped]
        end

        private

        def license_class(key, license)
          text = [license["license_type"], license["license_abbreviation"]].grep(String).join(" ")
          mapped = LICENSE_CLASSES.find { |pattern, _class| text.match?(pattern) }&.last
          return mapped if mapped

          raise Nabu::FetchError,
                "suttacentral publication #{key}: unrecognized license #{text.inspect} — " \
                "map it in Suttacentral::LICENSE_CLASSES (owner decision) before syncing"
        end
      end

      def publication_grants(workdir)
        PublicationGrants.load(File.join(workdir, PUBLICATION_FILE), source_class: manifest.license_class)
      end

      # Document-level metadata from the ref's discover-time metadata.
      def document_metadata(metadata)
        if metadata["kind"] == "translation"
          { "kind" => "translation", "translator" => metadata["translator"],
            "publication" => metadata["publication"] }.compact
        else
          facets = { "basket" => facet(metadata["basket"]), "collection" => facet(metadata["collection"]) }.compact
          { "edition" => metadata["edition"], "facets" => facets }.compact
        end
      end

      def facet(value)
        value.nil? ? nil : { "value" => value, "raw" => value }
      end
    end
  end
end
