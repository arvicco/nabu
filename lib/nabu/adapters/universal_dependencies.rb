# frozen_string_literal: true

module Nabu
  module Adapters
    # The Universal Dependencies adapter (architecture §3, packet P3-3): a thin
    # composition of the ConlluParser family with UD's git-repo-per-treebank
    # layout. Scope is the ancient-language treebanks Nabu cares about; each is a
    # separate UD GitHub repo cloned under <workdir>/<treebank-slug>/.
    #
    # == One DocumentRef per .conllu file
    #
    # A UD repo ships train/dev/test splits as separate *.conllu files. Each file
    # is its own document (urn:nabu:ud:<treebank>:<file-stem>) — the splits are
    # editorially meaningful and a sentence's stable identity is its sent_id
    # within its file, so collapsing splits would risk sent_id collisions. This
    # urn minting is FROZEN once merged (packet contract).
    #
    # == fetch across several repos
    #
    # Unlike Perseus (one repo), UD is N repos. fetch clones/pulls each treebank
    # into its own subdir (reusing the Perseus git pattern) and returns a single
    # Nabu::FetchReport. The report's +sha+ is the LAST treebank's HEAD (an
    # arbitrary-but-deterministic pin — the treebanks version independently, so
    # no single sha describes the whole set); +notes+ carries the full per-repo
    # "<slug>=<sha>" summary, which is the honest record of what is on disk.
    #
    # == License
    #
    # Varies per treebank (the fixture README records the verbatim, sometimes
    # self-contradictory, LICENSE files): PROIEL is CC BY-NC-SA, Sanskrit-Vedic
    # CC BY-SA, Latin-ITTB CC BY-NC-SA. The manifest declares the most
    # restrictive class present (nc) so query/export filters never over-share.
    class UniversalDependencies < Nabu::Adapter
      # The ancient-language treebanks in scope. key = subdir slug used on disk
      # and in the urn; value = its upstream repo and ISO 639-3 language tag.
      TREEBANKS = {
        "gothic-proiel" => {
          repo: "https://github.com/UniversalDependencies/UD_Gothic-PROIEL",
          language: "got"
        },
        "greek-proiel" => {
          repo: "https://github.com/UniversalDependencies/UD_Ancient_Greek-PROIEL",
          language: "grc"
        },
        "sanskrit-vedic" => {
          repo: "https://github.com/UniversalDependencies/UD_Sanskrit-Vedic",
          language: "san"
        },
        "latin-ittb" => {
          repo: "https://github.com/UniversalDependencies/UD_Latin-ITTB",
          language: "lat"
        }
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ud",
        name: "Universal Dependencies — ancient treebanks",
        license: "CC BY-NC-SA (varies per treebank — see per-repo LICENSE)",
        license_class: "nc",
        upstream_url: "https://github.com/UniversalDependencies",
        parser_family: "conllu"
      )

      def self.manifest
        MANIFEST
      end

      # P5-3: UD is one git repo per treebank, so the remote health probe must
      # ls-remote each (the manifest URL is the GitHub org, not a repo). Ordered
      # by TREEBANKS so the probe output is stable.
      def self.upstream_repo_urls
        TREEBANKS.values.map { |treebank| treebank[:repo] }
      end

      # Walk <workdir>/<treebank-slug>/*.conllu (sorted), one DocumentRef per
      # file. Subdirectories not in TREEBANKS are skipped silently (forward
      # compatibility — a new treebank on disk without a code entry is ignored,
      # not an error). Returns an Enumerator when called without a block.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the ConlluParser with the urn/language/title discover
      # resolved from the treebank layout.
      def parse(document_ref)
        ConlluParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Clone or non-destructively pull each in-scope treebank into
      # <workdir>/<slug> via the shared Nabu::GitFetch phases (P5-2), then
      # return a single Nabu::FetchReport pinning the last treebank's HEAD,
      # with the full per-repo sha summary (and any attic activity) in notes.
      #
      # The two-phase choreography matters here: ALL repos are prepared
      # (objects fetched, tree untouched) and the mass-deletion breaker sees
      # the deletions of the whole SET before ANY repo merges — so a trip
      # caused by the last treebank leaves the first one byte-unchanged too.
      # Upstream-deleted files are atticked under the source-level attic,
      # <workdir>/.attic/<slug>/<file>, preserving the exact relative shape
      # discover walks. No network in tests: exercised against local fixture
      # git repos. Any Shell failure aborts the sync as Nabu::FetchError; a
      # tripped breaker as Nabu::SyncAborted (+force+ overrides).
      def fetch(workdir, progress: nil, force: false)
        pulls = git_pulls(workdir, progress)
        pulls.each_value(&:prepare!)
        guard_mass_deletion!(workdir, pulls.values.flat_map(&:doomed_paths), force: force)
        pulls.each_value(&:complete!)
        shas = pulls.transform_values(&:head_sha)
        Nabu::FetchReport.new(sha: shas.values.last, fetched_at: Time.now, notes: fetch_notes(shas, pulls))
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "ud fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The repo URL for a treebank slug. Split out so fetch tests can point a
      # subclass/singleton at a local git tmpdir (as the Perseus tests do).
      def repo_url(slug)
        TREEBANKS.fetch(slug)[:repo]
      end

      def git_pulls(workdir, progress)
        TREEBANKS.keys.to_h do |slug|
          [slug, Nabu::GitFetch.new(
            repo_url: repo_url(slug), dir: File.join(workdir, slug),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug), progress: progress
          )]
        end
      end

      def fetch_notes(shas, pulls)
        notes = shas.map { |slug, sha| "#{slug}=#{sha}" }.join(" ")
        atticked = pulls.values.sum { |pull| pull.atticked.size }
        atticked.positive? ? "#{notes} · atticked #{atticked} upstream-deleted file(s)" : notes
      end

      def document_refs(workdir)
        TREEBANKS.flat_map do |slug, info|
          Dir.glob(File.join(workdir, slug, "*.conllu")).map do |path|
            stem = File.basename(path, ".conllu")
            Nabu::DocumentRef.new(
              source_id: MANIFEST.id,
              id: "urn:nabu:ud:#{slug}:#{stem}",
              path: File.expand_path(path),
              metadata: {
                "language" => info[:language],
                "treebank" => slug,
                "title" => "#{repo_name(info[:repo])} (#{stem})"
              }
            )
          end
        end.sort_by(&:id)
      end

      def repo_name(repo)
        repo.split("/").last
      end
    end
  end
end
