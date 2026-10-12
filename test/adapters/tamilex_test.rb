# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Tamilex (P121-3): TAMILEX's critical editions of the
# classical Tamil corpus — one GitHub repo per work under UHH-Tamilex,
# composed by one sparse GitFetch per repo into canonical/tamilex/<repo>/
# (the dharma-tamil / UD pattern). The parse contract is the
# `tamilex-tei` family's own test; this file pins discovery, exclusion,
# identity, the gold-lemma round trip, idempotency and fetch.
#
# Fixtures: four whole real files from four repos plus upstream's empty
# Kuṟuntokai poem template (see test/fixtures/tamilex/README.md).
class TamilexTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("tamilex")

  TVM = "urn:nabu:tamilex:TVM1.8.2"
  KT = "urn:nabu:tamilex:KT1"
  TK = "urn:nabu:tamilex:TK1"
  TOL = "urn:nabu:tamilex:TolC273"

  FETCH_REPOS = %w[Kuruntokai Tirukkural].freeze

  def conformance_adapter = Nabu::Adapters::Tamilex.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "tamilex"

  def adapter = Nabu::Adapters::Tamilex.new

  def ref_for(urn)
    adapter.discover(FIXTURES).find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  # -- manifest + roster --------------------------------------------------------

  def test_manifest_is_nc_with_the_maintainers_grant_and_credit
    manifest = Nabu::Adapters::Tamilex.manifest
    assert_equal "tamilex", manifest.id
    assert_equal "nc", manifest.license_class
    assert_equal "tamilex-tei", manifest.parser_family
    assert_equal "https://github.com/UHH-Tamilex", manifest.upstream_url
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/2026-10-12/, manifest.license)
    %w[TAMILEX Wilden Chevillard Academies].each { |name| assert_includes manifest.credit, name }
  end

  def test_the_roster_is_the_text_edition_repos_only
    repos = Nabu::Adapters::Tamilex::REPOS
    assert_equal 21, repos.size
    %w[Kuruntokai Tirukkural Tolkappiyam NalayiratTivviyapPirapantam perunkatai].each do |repo|
      assert_includes repos, repo
    end
    %w[lexicon lib rawcorpus collocations poemcheck studies testing workshop Cirupanarruppatai].each do |repo|
      refute_includes repos, repo, "#{repo} is tooling, a lexicon or an empty scaffold"
    end
    assert_equal repos.map { |repo| "https://github.com/UHH-Tamilex/#{repo}" },
                 Nabu::Adapters::Tamilex.upstream_repo_urls
  end

  # -- discover -------------------------------------------------------------------

  def test_discover_spans_the_repo_subdirs_by_file_stem
    refs = adapter.discover(FIXTURES).to_a
    assert_equal [KT, TK, TVM, TOL].sort, refs.map(&:id).sort
    assert_equal "Kuruntokai", refs.find { |ref| ref.id == KT }.metadata["repo"]
    assert(refs.all? { |ref| ref.source_id == "tamilex" })
  end

  def test_templates_aggregates_and_the_duplicate_base_edition_are_censused_skips
    Dir.mktmpdir do |dir|
      seed = File.join(FIXTURES, "Kuruntokai", "KT1.xml")
      { "Kuruntokai" => %w[KT2.xml _KTSAMPLE.xml witnesses.xml wordindex.xml],
        "Tirukkural" => %w[TK2.xml poem-template.xml],
        "Patirruppattu" => %w[.xml],
        "TamilneriVilakkam" => %w[TNV1ed.xml Ed.xml] }.each do |repo, names|
        FileUtils.mkdir_p(File.join(dir, repo))
        names.each { |name| FileUtils.cp(seed, File.join(dir, repo, name)) }
      end
      ids = adapter.discover(dir).map(&:id)
      assert_equal %w[urn:nabu:tamilex:KT2 urn:nabu:tamilex:TK2 urn:nabu:tamilex:TNV1ed].sort, ids.sort
      skips = adapter.discovery_skips(dir)
      assert_equal 6, skips.skipped_by_rule
      notes = skips.notes.join("\n")
      assert_match(%r{Kuruntokai/_KTSAMPLE\.xml: upstream template or scratch file}, notes)
      assert_match(%r{Tirukkural/poem-template\.xml: upstream template or scratch file}, notes)
      assert_match(%r{Patirruppattu/\.xml: upstream template or scratch file}, notes)
      assert_match(%r{Kuruntokai/witnesses\.xml: not an edition}, notes)
      assert_match(%r{Kuruntokai/wordindex\.xml: not an edition}, notes)
      assert_match(%r{TamilneriVilakkam/Ed\.xml: .*per-verse}, notes)
    end
  end

  def test_a_stem_held_by_two_repos_is_skipped_loudly_after_the_first
    Dir.mktmpdir do |dir|
      seed = File.join(FIXTURES, "Kuruntokai", "KT1.xml")
      %w[Akananuru Kuruntokai].each do |repo|
        FileUtils.mkdir_p(File.join(dir, repo))
        FileUtils.cp(seed, File.join(dir, repo, "KT1.xml"))
      end
      refs = adapter.discover(dir).to_a
      assert_equal [KT], refs.map(&:id)
      assert_equal "Akananuru", refs.first.metadata["repo"], "roster order decides; the urn never forks"
      assert_match(%r{Kuruntokai/KT1\.xml: stem also held by Akananuru}, adapter.discovery_skips(dir).notes.join)
    end
  end

  # -- parse --------------------------------------------------------------------

  def test_parse_carries_the_repo_and_a_known_verse_verbatim
    document = adapter.parse(ref_for(KT))
    assert_equal "tam-Latn", document.language
    assert_equal "Kuṟuntokai 1. Tipputtōḷār", document.title
    assert_equal "Kuruntokai", document.metadata["repo"]
    assert_equal %W[#{KT}:KT1-kilavi #{KT}:KT1], document.map(&:urn)
    assert_equal "kurutip pūviṉ kulaikkān taṭṭē.", document.passages.last.text.split("\n").last
  end

  def test_fixture_passage_counts
    counts = adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref).size] }
    assert_equal({ KT => 2, TK => 6, TVM => 1, TOL => 19 }, counts)
  end

  def test_the_textless_template_is_never_a_document
    refute(adapter.discover(FIXTURES).any? { |ref| ref.path.end_with?("_KTSAMPLE.xml") })
    assert_equal 1, adapter.discovery_skips(FIXTURES).skipped_by_rule
  end

  # -- the store: gold lemmas + idempotency ---------------------------------

  def test_fixture_load_produces_gold_tamil_lemma_rows
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    load_fixtures(catalog)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    lemmas = fulltext[:passage_lemmas]
    assert_operator lemmas.where(language: "tam-Latn").count, :>, 50
    row = lemmas.where(lemma_folded: Nabu::Normalize.search_form("kāntaṭṭu", language: "tam-Latn")).first
    refute_nil row, "the wordsplit's simple form is the indexed lemma"
    assert_equal "#{KT}:KT1", row[:urn]
    assert_equal "gold", row[:tier]
    assert_equal "kāntaṭṭu-ē", row[:surface_forms]
  end

  def test_double_load_is_idempotent
    catalog = store_test_db
    first = load_fixtures(catalog)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    load_fixtures(catalog)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal [4, 28], counts
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  # -- fetch (local git only, no network) ---------------------------------------

  def test_fetch_sparse_clones_every_repo_into_its_own_subdir
    Dir.mktmpdir("nabu-tamilex-fetch") do |root|
      upstreams = build_upstreams(root)
      work = File.join(root, "canonical")
      tamilex = pointing_at(upstreams)

      report = tamilex.fetch(work)

      assert_instance_of Nabu::FetchReport, report
      expected = upstreams.values.to_h { |up| [up, git(up, "rev-parse", "HEAD")] }
      assert_equal expected, report.repos, "one ledger pin per repo, keyed by repo url"
      upstreams.each_key do |repo|
        assert File.file?(File.join(work, repo, "#{repo[0, 2]}1.xml"))
        refute File.exist?(File.join(work, repo, "wordindex.db")), "derived indexes stay outside the cone"
        refute File.exist?(File.join(work, repo, "mss")), "witness subtrees stay outside the cone"
      end
      assert_equal upstreams.size, tamilex.discover(work).count
      assert_equal report.repos, tamilex.fetch(work).repos, "second call: the pull path"
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      tamilex = pointing_at(Hash.new(File.join(root, "does-not-exist")))
      assert_raises(Nabu::FetchError) { tamilex.fetch(File.join(root, "work")) }
    end
  end

  private

  def load_fixtures(catalog)
    source = Nabu::Store::Source.find(slug: "tamilex") ||
             Nabu::Store::Source.create(slug: "tamilex", name: "TAMILEX",
                                        adapter_class: "Nabu::Adapters::Tamilex", license_class: "nc")
    Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
  end

  def build_upstreams(root)
    source = File.read(File.join(FIXTURES, "Kuruntokai", "KT1.xml"))
    FETCH_REPOS.to_h do |repo|
      upstream = File.join(root, "upstream-#{repo}")
      FileUtils.mkdir_p(File.join(upstream, "mss"))
      Nabu::Shell.run("git", "init", "-q", upstream)
      File.write(File.join(upstream, "#{repo[0, 2]}1.xml"), source)
      File.write(File.join(upstream, "mss", "C1.xml"), source)
      File.write(File.join(upstream, "wordindex.db"), "sqlite")
      File.write(File.join(upstream, "README.md"), "readme")
      git(upstream, "add", ".")
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
      [repo, upstream]
    end
  end

  def pointing_at(upstreams)
    tamilex = Nabu::Adapters::Tamilex.new
    repos = upstreams.is_a?(Hash) && !upstreams.empty? ? upstreams.keys : FETCH_REPOS
    tamilex.define_singleton_method(:repos) { repos }
    tamilex.define_singleton_method(:repo_url_for) { |repo| upstreams[repo] }
    tamilex
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
