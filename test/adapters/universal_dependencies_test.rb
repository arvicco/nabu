# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Universal Dependencies adapter tests (P3-3). The adapter composes ConlluParser
# with UD's git-repo-per-treebank layout: discover walks <slug>/*.conllu (one
# DocumentRef per file), parse delegates to ConlluParser, fetch clones/pulls
# each treebank repo. Includes the shared AdapterConformance suite against the
# checked-in UD fixtures. No network: fetch is exercised against a local git
# repo in a tmpdir plus a Shell-failure path.
class UniversalDependenciesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = File.expand_path("../fixtures/ud", __dir__)

  EXPECTED_URNS = [
    "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50",
    "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50",
    "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt",
    "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50",
    "urn:nabu:ud:old-east-slavic-rnc:orv_rnc-ud-test-head50",
    "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50"
  ].freeze

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::UniversalDependencies.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "ud"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::UniversalDependencies.manifest
    assert_equal "ud", manifest.id
    assert_equal "Universal Dependencies — ancient treebanks", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "https://github.com/UniversalDependencies", manifest.upstream_url
    assert_equal "conllu", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::UniversalDependencies.manifest,
                 Nabu::Adapters::UniversalDependencies.new.manifest
  end

  # --- dedup guard (P10-2) -------------------------------------------------

  # The UD repo ships CONVERSIONS of data Nabu already ingests natively:
  # UD_Church_Slavonic-PROIEL (slug would be chu-proiel) re-exports the PROIEL
  # OCS canon the `proiel` source syncs, and UD_Old_East_Slavic-TOROT
  # (orv-torot) re-exports the `torot` source. Adding either to TREEBANKS would
  # DOUBLE-LOAD the same sentences under a second urn scheme — the survey's
  # named hazard (docs/slavic-survey.md §1). This test freezes their exclusion:
  # the two orv treebanks we DO add (Birchbark, RNC) are RNC-scheme conversions
  # with no PROIEL/TOROT overlap, so they are safe; the two below are not.
  def test_treebanks_excludes_the_chu_proiel_and_orv_torot_conversions
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    repos = treebanks.values.map { |tb| tb[:repo] }

    # The two UD repos that are CONVERSIONS of data Nabu already ingests
    # natively — UD_Church_Slavonic-PROIEL re-exports the PROIEL OCS canon the
    # `proiel` source syncs, UD_Old_East_Slavic-TOROT re-exports the `torot`
    # source. Adding either would attest every OCS sentence twice (once natively,
    # once under urn:nabu:ud:…), inflating the lemma index and corpus counts.
    # The two orv treebanks we DO add (Birchbark, RNC) are RNC-scheme
    # conversions with no PROIEL/TOROT overlap, so they are safe. Guard both by
    # repo name and — because Church Slavonic is served ONLY natively — by the
    # `chu` language tag, so no future chu-PROIEL slips in under a renamed slug.
    [
      "https://github.com/UniversalDependencies/UD_Church_Slavonic-PROIEL",
      "https://github.com/UniversalDependencies/UD_Old_East_Slavic-TOROT"
    ].each do |conversion_repo|
      refute_includes repos, conversion_repo,
                      "TREEBANKS must exclude #{conversion_repo}: it re-loads the native " \
                      "proiel/torot sync (double-load hazard, docs/slavic-survey.md §1)"
    end

    chu = treebanks.select { |_slug, tb| tb[:language] == "chu" }.keys
    assert_empty chu,
                 "no TREEBANKS entry may carry language chu — the OCS canon is served only " \
                 "natively via proiel/torot; a chu UD treebank would double-load it. Found: #{chu.inspect}"
  end

  # --- per-treebank license override (P10-4) ------------------------------
  #
  # UD's SOURCE class is nc (most-restrictive present, correct for the PROIEL-
  # derived treebanks). The two Old East Slavic treebanks (Birchbark, RNC) are
  # CC BY-SA 4.0 → attribution: they carry a per-document license_override so
  # the shareable shelf labels them honestly, while the four legacy treebanks
  # stay bare (source class nc applies, override NULL).
  SLAVIC_SLUGS = %w[old-east-slavic-birchbark old-east-slavic-rnc].freeze
  LEGACY_SLUGS = %w[gothic-proiel greek-proiel latin-ittb sanskrit-vedic].freeze

  def test_treebanks_map_sets_attribution_only_on_the_two_slavic_entries
    treebanks = Nabu::Adapters::UniversalDependencies::TREEBANKS
    SLAVIC_SLUGS.each do |slug|
      assert_equal "attribution", treebanks.fetch(slug)[:license_class], "#{slug} must be attribution"
      assert_equal "CC BY-SA 4.0", treebanks.fetch(slug)[:license]
    end
    LEGACY_SLUGS.each do |slug|
      assert_nil treebanks.fetch(slug)[:license_class], "#{slug} must stay bare (source class applies)"
    end
  end

  def test_parse_surfaces_license_override_for_slavic_and_nil_for_legacy
    adapter = Nabu::Adapters::UniversalDependencies.new
    by_slug = adapter.discover(FIXTURES).to_h { |ref| [ref.metadata["treebank"], adapter.parse(ref)] }

    SLAVIC_SLUGS.each { |slug| assert_equal "attribution", by_slug.fetch(slug).license_override }
    LEGACY_SLUGS.each { |slug| assert_nil by_slug.fetch(slug).license_override }
  end

  # End-to-end: after a fixture load, documents.license_override reads
  # attribution for the two Slavic treebanks and NULL for the four legacy ones,
  # while the source class remains nc.
  def test_fixture_load_writes_attribution_override_only_for_the_slavic_treebanks
    catalog = store_test_db
    source = Nabu::Store::Source.create(
      slug: "ud", name: "Universal Dependencies",
      adapter_class: "Nabu::Adapters::UniversalDependencies", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)

    override_by_slug = Nabu::Store::Document.where(source_id: source.id).all.to_h do |doc|
      [doc.urn.split(":")[3], doc.license_override]
    end
    SLAVIC_SLUGS.each { |slug| assert_equal "attribution", override_by_slug.fetch(slug) }
    LEGACY_SLUGS.each { |slug| assert_nil override_by_slug.fetch(slug) }
    assert_equal "nc", source.license_class, "the source class is unchanged"
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_six_files_sorted_by_urn
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    assert_equal EXPECTED_URNS, refs.map(&:id)
  end

  def test_discover_sets_source_id_language_treebank_and_absolute_path
    refs = Nabu::Adapters::UniversalDependencies.new.discover(FIXTURES).to_a
    by_urn = refs.to_h { |ref| [ref.id, ref] }

    expected_languages = {
      "urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50" => "got",
      "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50" => "grc",
      "urn:nabu:ud:latin-ittb:la_ittb-ud-test-head50+mwt" => "lat",
      "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50" => "orv",
      "urn:nabu:ud:old-east-slavic-rnc:orv_rnc-ud-test-head50" => "orv",
      "urn:nabu:ud:sanskrit-vedic:sa_vedic-ud-test-head50" => "san"
    }
    expected_languages.each do |urn, language|
      ref = by_urn.fetch(urn)
      assert_equal "ud", ref.source_id
      assert_equal language, ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end

    got = by_urn.fetch("urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50")
    assert_equal "gothic-proiel", got.metadata["treebank"]
    assert_equal "UD_Gothic-PROIEL (got_proiel-ud-test-head50)", got.metadata["title"]
  end

  def test_discover_skips_unknown_subdirectories
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "gothic-proiel"))
      FileUtils.cp(
        File.join(FIXTURES, "gothic-proiel", "got_proiel-ud-test-head50.conllu"),
        File.join(root, "gothic-proiel")
      )
      # An unregistered treebank on disk must be ignored, not error.
      FileUtils.mkdir_p(File.join(root, "klingon-tng"))
      unknown = "# sent_id = 1\n# text = x\n1\tx\t_\t_\t_\t_\t0\troot\t_\t_\n\n"
      File.write(File.join(root, "klingon-tng", "tlh-ud-test.conllu"), unknown)

      refs = Nabu::Adapters::UniversalDependencies.new.discover(root).to_a
      assert_equal ["urn:nabu:ud:gothic-proiel:got_proiel-ud-test-head50"], refs.map(&:id)
    end
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_delegates_to_conllu_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::UniversalDependencies.new
    ref = adapter.discover(FIXTURES).find { |r| r.id.include?("gothic") }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 50, document.size
    assert_equal "got", document.language
  end

  # --- lemma plumbing for the orv treebanks (P10-2) -----------------------
  #
  # The acceptance gate: the CoNLL-U LEMMA column of the two new Old East
  # Slavic treebanks must flow through the UNCHANGED annotation→index plumbing
  # (ConlluParser "tokens"/"lemma"/"form" → Store::Indexer → passage_lemmas),
  # exactly as the existing treebanks do — no orv-specific code path.
  def test_fixture_load_produces_orv_lemma_rows_via_existing_plumbing
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(
      slug: "ud", name: "Universal Dependencies",
      adapter_class: "Nabu::Adapters::UniversalDependencies", license_class: "nc"
    )
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    lemmas = fulltext[:passage_lemmas]
    assert_operator lemmas.where(language: "orv").count, :>, 0,
                    "the orv treebanks must contribute passage_lemmas rows"

    # Both new treebanks contribute (Birchbark AND the Middle-Russian RNC).
    assert_operator lemmas.where(Sequel.like(:urn, "%old-east-slavic-birchbark%")).count, :>, 0
    assert_operator lemmas.where(Sequel.like(:urn, "%old-east-slavic-rnc%")).count, :>, 0

    # A specific readable row: the birchbark NOUN lemma росомуха "wolverine"
    # (002-1), attested by the pristine surface form росомꙋха.
    row = lemmas.where(language: "orv", lemma_raw: "росомуха").first
    refute_nil row, "expected a passage_lemmas row for the orv lemma росомуха"
    assert_equal "urn:nabu:ud:old-east-slavic-birchbark:orv_birchbark-ud-test-head50:002-1", row[:urn]
    assert_includes row[:surface_forms], "росомꙋха"
  ensure
    fulltext&.disconnect
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_each_treebank_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstreams = {}
      Nabu::Adapters::UniversalDependencies::TREEBANKS.each_key do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        upstreams[slug] = upstream
      end

      workdir = File.join(root, "work")
      adapter = ud_pointing_at(upstreams)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_instance_of Time, report.fetched_at

      # Every treebank was cloned into its own subdir.
      upstreams.each_key do |slug|
        assert File.directory?(File.join(workdir, slug, ".git")), "#{slug} must be cloned"
        head = git(upstreams[slug], "rev-parse", "HEAD")
        assert_includes report.notes, "#{slug}=#{head}"
      end

      # sha is the LAST treebank's HEAD; notes carries the whole summary.
      last_slug = upstreams.keys.last
      assert_equal git(upstreams[last_slug], "rev-parse", "HEAD"), report.sha

      # Second call → pull path, still succeeds and reports the same shas.
      assert_equal report.notes, adapter.fetch(workdir).notes
    end
  end

  # P6-3: the FetchReport carries per-repo pins { repo_url => head sha } so the
  # sync path can record one ledger pin per treebank. Keyed by the SAME
  # repo_url the remote probe reads (here the local tmpdirs the test points at).
  def test_fetch_reports_per_repo_pins_keyed_by_repo_url
    Dir.mktmpdir do |root|
      upstreams = {}
      Nabu::Adapters::UniversalDependencies::TREEBANKS.each_key do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        upstreams[slug] = upstream
      end
      adapter = ud_pointing_at(upstreams)

      report = adapter.fetch(File.join(root, "work"))

      expected = upstreams.values.to_h { |upstream| [upstream, git(upstream, "rev-parse", "HEAD")] }
      assert_equal expected, report.repos
      assert_equal report.sha, report.repos.values.last, "sha still pins the last treebank"
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = ud_pointing_at(Hash.new(File.join(root, "does-not-exist")))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- retention across N repos (P5-2) -------------------------------------
  #
  # UD is the multi-repo shape: the breaker must see the deletions of ALL
  # treebanks before ANY repo merges (a trip in the last repo may not leave
  # the first repo already mutated), and atticked files land under the
  # source-level attic — <workdir>/.attic/<treebank>/<file> — so the
  # adapter's own discover finds them there.
  def test_fetch_guards_deletions_across_all_repos_before_any_merge_and_force_attics
    Dir.mktmpdir do |root|
      slugs = Nabu::Adapters::UniversalDependencies::TREEBANKS.keys
      upstreams = slugs.to_h do |slug|
        upstream = File.join(root, "upstream-#{slug}")
        make_git_repo(upstream, slug)
        File.write(File.join(upstream, "#{slug}.conllu"), conllu_stub(slug))
        git(upstream, "add", ".")
        git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "conllu")
        [slug, upstream]
      end
      workdir = File.join(root, "work")
      adapter = ud_pointing_at(upstreams)
      adapter.fetch(workdir)

      # First repo gains a file; the LAST TWO repos each lose their only
      # treebank file (2 of #{slugs.size} ingestible files = 33% > 20% → trip;
      # a single deletion is only 1/#{slugs.size} ≈ 17%, below the breaker, now
      # that the set has grown to six treebanks).
      first = slugs.first
      doomed = slugs.last(2)
      File.write(File.join(upstreams[first], "new.txt"), "new\n")
      git(upstreams[first], "add", ".")
      git(upstreams[first], "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "grow")
      doomed.each do |slug|
        git(upstreams[slug], "rm", "-q", "#{slug}.conllu")
        git(upstreams[slug], "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "scrap")
      end

      assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
      doomed.each do |slug|
        assert File.file?(File.join(workdir, slug, "#{slug}.conllu")), "no repo merged on a trip"
      end
      refute File.exist?(File.join(workdir, first, "new.txt")),
             "the trip must precede EVERY repo's merge, not just the deleting one"
      refute Dir.exist?(File.join(workdir, ".attic"))

      report = adapter.fetch(workdir, force: true)
      assert_includes report.notes, "atticked 2"
      doomed.each do |slug|
        assert File.file?(File.join(workdir, ".attic", slug, "#{slug}.conllu")),
               "the attic preserves the <treebank>/<file> shape discover expects"
      end
      assert File.file?(File.join(workdir, first, "new.txt"))

      retained = adapter.discover_with_attic(workdir).select { |ref| ref.metadata["retained"] }
      assert_equal doomed.map { |slug| "urn:nabu:ud:#{slug}:#{slug}" }.sort, retained.map(&:id).sort
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_ud_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ud"]
    refute_nil entry, "ud must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::UniversalDependencies, entry.adapter_class
    assert_equal "ud", entry.manifest.id
    assert_equal Nabu::Adapters::UniversalDependencies.manifest, entry.manifest
  end

  private

  # An adapter whose repo_url resolves to local git tmpdirs (Perseus test
  # pattern), keeping fetch entirely off the network.
  def ud_pointing_at(upstreams)
    adapter = Nabu::Adapters::UniversalDependencies.new
    adapter.define_singleton_method(:repo_url) { |slug| upstreams[slug] }
    adapter
  end

  def make_git_repo(dir, seed)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "#{seed}.txt"), "#{seed}\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", seed)
  end

  # Minimal CoNLL-U body — discover only globs filenames, so shape suffices.
  def conllu_stub(slug)
    "# sent_id = #{slug}-1\n# text = x\n1\tx\tx\tX\t_\t_\t0\troot\t_\t_\n\n"
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
