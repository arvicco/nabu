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
    # CC BY-SA, Latin-ITTB CC BY-NC-SA, all three Old East Slavic treebanks
    # (Birchbark, RNC, Ruthenian) CC BY-SA 4.0, Old Irish DipSGG CC BY-NC-SA
    # 4.0 and DipWBG CC BY-SA 4.0 (P25-2), both Perseus treebanks CC BY-NC-SA
    # 2.5 Generic (P31-6). The manifest declares the most restrictive class
    # present (nc) so query/export filters never over-share.
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
        },
        # P10-2 (Slavic expansion, survey pick #1): two genuinely-new Old East
        # Slavic treebanks — vernacular birchbark letters (1025–1500) and the
        # Middle-Russian RNC sample (1300–1700). Both CC BY-SA 4.0 (license
        # verified in each repo's README/LICENSE.txt; see the fixture README),
        # language code orv for both (RNC's Middle Russian is filed under orv in
        # UD). Their annotation is a conversion of the native RNC scheme, NOT a
        # re-export of PROIEL/TOROT — so unlike UD_Church_Slavonic-PROIEL and
        # UD_Old_East_Slavic-TOROT (deliberately EXCLUDED here — see the dedup
        # guard in the adapter test) they do not double-load the OCS canon Nabu
        # already ingests natively.
        #
        # P10-4: both are CC BY-SA 4.0 (attribution), unlike the PROIEL-derived
        # treebanks above (nc). They carry a per-treebank license_override so
        # documents.license_override labels them attribution downstream, while
        # the SOURCE class stays nc (the most-restrictive present). The four
        # legacy entries omit :license/:license_class → override NULL → they
        # inherit the source class. Any :license_class set here must be a valid
        # class (Model::Validation::LICENSE_CLASSES) — Document validates it.
        "old-east-slavic-birchbark" => {
          repo: "https://github.com/UniversalDependencies/UD_Old_East_Slavic-Birchbark",
          language: "orv", license: "CC BY-SA 4.0", license_class: "attribution"
        },
        "old-east-slavic-rnc" => {
          repo: "https://github.com/UniversalDependencies/UD_Old_East_Slavic-RNC",
          language: "orv", license: "CC BY-SA 4.0", license_class: "attribution"
        },
        # P13-1b (Survey-II pick #1): the THIRD East Slavic branch — Ruthenian
        # "prosta mova" (Old Belarusian/Old Ukrainian) chancery/legal prose,
        # ca. 1380–1650 (Polotsk letters, Lithuanian Metrica, Lokhvitsa town-hall
        # book). Genuinely new: zero text overlap with Birchbark (Novgorod
        # letters), RNC (Muscovite Middle Russian) or TOROT/PROIEL (OCS canon).
        # UD language code orv (treebank id orv_ruthenian; the per-doc `# lang =
        # orv-be` is a finer BCP-47 regional subtag, not the treebank tag). Same
        # CC BY-SA 4.0 → attribution override as birchbark/rnc (LICENSE.txt +
        # README metadata verbatim, verified 2026-07-11 at fixture time).
        "old-east-slavic-ruthenian" => {
          repo: "https://github.com/UniversalDependencies/UD_Old_East_Slavic-Ruthenian",
          language: "orv", license: "CC BY-SA 4.0", license_class: "attribution"
        },
        # P25-2 (Celtic axis): the two diplomatic Old Irish glosses
        # treebanks (Adrian Doyle's conversions of Bernhard Bauer's St Gall
        # data / the wurzburg.ie Würzburg glosses), both test-set only.
        # Language sga for both — the glosses code-mix Latin inside Irish
        # (the README's own framing: "only those glosses which contain some
        # Irish text"), the same one-tag-per-treebank honesty as RNC's
        # Middle Russian under orv. NOTE the same St Gall glosses arrive at
        # a different grain via CorPH (P25-0, morphology) — two honest
        # witnesses, NO dedup wanted (the MW-beside-kaikki precedent; these
        # are UD dependency conversions, not a re-export of CorPH).
        #
        # DipSGG's license is verbatim "CC BY-NC-SA 4.0" (its LICENSE.txt is
        # exactly that line; README metadata agrees) → it rides the SOURCE's
        # nc class unchanged, no override key. DipWBG is verbatim
        # "CC BY-SA 4.0" (README metadata; LICENSE.txt "Attribution-
        # ShareAlike 4.0 International") → the P10-4 per-document
        # attribution override, the birchbark/RNC mechanics.
        "old-irish-dipsgg" => {
          repo: "https://github.com/UniversalDependencies/UD_Old_Irish-DipSGG",
          language: "sga"
        },
        "old-irish-dipwbg" => {
          repo: "https://github.com/UniversalDependencies/UD_Old_Irish-DipWBG",
          language: "sga", license: "CC BY-SA 4.0", license_class: "attribution"
        },
        # P31-0 (Anatolian axis): the one Hittite treebank in UD — 136
        # sentences / 1,309 words of Hoffner & Melchert's tutorial examples
        # (A Grammar of the Hittite Language, Part 2), each with its real
        # KBo/KUB/Laws source line, spanning Old/Middle/New Hittite.
        # Test-set only (the DipWBG shape); clitic chains (ta=an, nu=za…)
        # arrive as CoNLL-U multiword-token ranges the parser already
        # handles (the Latin-ITTB essetque mechanics). Language hit.
        # LICENSE GATE PASSED at fixture time 2026-07-19: LICENSE.txt is
        # verbatim the BY-SA grant ("The treebank is licensed under the
        # Creative Commons License Attribution-ShareAlike 4.0
        # International") + README metadata `License: CC BY-SA 4.0` → the
        # P10-4 per-document attribution override, the birchbark/RNC
        # mechanics exactly; the SOURCE class stays nc.
        "hittite-hittb" => {
          repo: "https://github.com/UniversalDependencies/UD_Hittite-HitTB",
          language: "hit", license: "CC BY-SA 4.0", license_class: "attribution"
        },
        # P31-6 (02-sources row 17's UD half): the UD conversions of the
        # native Perseus AGDT/LDT v2.1 ("automatic conversion of a selection
        # of passages from the Ancient Greek and Latin Dependency Treebank
        # 2.1", both READMEs). Greek ~202k tokens (Homer, Hesiod, tragedy,
        # Herodotus…), Latin ~29k (Caesar-era canon: Cicero, Vergil, Ovid…).
        # DEDUP HONESTY: nabu has never synced the native AGLDT, so the
        # chu-PROIEL re-export guard does NOT apply — no double-load; no
        # overlap with greek-proiel/latin-ittb (different upstream data); and
        # vs the perseus-greek/latin TEXT sources these are the same works at
        # treebank grain = distinct witnesses, never deduped (the
        # DipSGG-beside-CorPH doctrine).
        #
        # LICENSE GATE PASSED at fixture time 2026-07-19: each repo's
        # LICENSE.txt is verbatim "This work is licensed under the Creative
        # Commons Attribution-NonCommercial-ShareAlike 2.5 Generic License."
        # and each README's metadata reads `License: CC BY-NC-SA 2.5` —
        # consistent, NonCommercial → both ride the SOURCE's nc class bare,
        # no override key (the DipSGG posture, NOT the P10-4 mechanics).
        "ancient-greek-perseus" => {
          repo: "https://github.com/UniversalDependencies/UD_Ancient_Greek-Perseus",
          language: "grc"
        },
        "latin-perseus" => {
          repo: "https://github.com/UniversalDependencies/UD_Latin-Perseus",
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

      # Delegate to the ConlluParser with the urn/language/title/license
      # override discover resolved from the treebank layout. The override is a
      # discover→parse hint carried in the ref metadata (nil for the legacy
      # treebanks, which then inherit the source's nc class).
      def parse(document_ref)
        ConlluParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"],
          license_override: document_ref.metadata["license_class"]
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
        Nabu::FetchReport.new(sha: shas.values.last, fetched_at: Time.now,
                              notes: fetch_notes(shas, pulls), repos: repo_pins(shas))
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

      # { repo_url => head_sha } from the per-slug shas — the FetchReport.repos
      # payload SyncRunner pins into the ledger (P6-3/P7-1). Keyed by the SAME
      # repo_url the remote probe reads from Adapter.upstream_repo_urls, so the
      # pin and the probe line up per repo.
      def repo_pins(shas)
        shas.to_h { |slug, sha| [repo_url(slug), sha] }
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
            metadata = {
              "language" => info[:language],
              "treebank" => slug,
              "title" => "#{repo_name(info[:repo])} (#{stem})"
            }
            # Only the treebanks with a declared override carry the key (P10-4);
            # the legacy ones stay bare so they inherit the source class.
            metadata["license_class"] = info[:license_class] if info[:license_class]
            Nabu::DocumentRef.new(
              source_id: MANIFEST.id, id: "urn:nabu:ud:#{slug}:#{stem}",
              path: File.expand_path(path), metadata: metadata
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
