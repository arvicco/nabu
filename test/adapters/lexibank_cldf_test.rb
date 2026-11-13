# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexibank-cldf adapter family base: what a dataset declaration buys —
# manifest, dictionary-shaped discovery/parse, the rejected-grain census,
# both fetch arms (the sha-pinned Zenodo release zip; the sparse GitFetch
# of a tagless repository) and the probe wiring. Exercised through two
# test-only declarations over the real acd fixture so the family stands
# apart from any registered dataset (those are pinned in
# lexibank_datasets_test.rb).
class LexibankCldfTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("acd")
  ZIP_URL = "https://zenodo.org/api/records/1/files/lexibank/demo-v1.0.zip/content"

  class ZenodoDemo < Nabu::Adapters::LexibankCldf
    DATASET = Dataset.new(
      slug: "acd", name: "Demo", title: "Demo shelf", label: "DEMO", language: "map",
      license: "CC BY 4.0 (demo)", upstream_url: "https://doi.org/10.5281/zenodo.1",
      release: Nabu::Adapters::LexibankCldf::ZenodoRelease.new(
        tag: "v1.0", record: 1, url: "https://zenodo.org/api/records/1/files/lexibank/demo-v1.0.zip/content",
        sha256: "0" * 64
      ),
      rejected_grains: { "raw" => "upstream's pre-CLDF source dumps", "out" => "a grain this tree lacks" }
    )
  end

  class GitDemo < Nabu::Adapters::LexibankCldf
    DATASET = Dataset.new(
      slug: "gitdemo", name: "Git demo", title: "Git demo shelf", label: "GIT", language: "map",
      license: "CC BY 4.0 (demo)", upstream_url: "https://github.com/lexibank/gitdemo",
      release: Nabu::Adapters::LexibankCldf::GitRepository.new(
        repo_url: "https://github.com/lexibank/gitdemo", commit: "a" * 40
      )
    )
  end

  class Undeclared < Nabu::Adapters::LexibankCldf; end

  def adapter(pin: nil) = ZenodoDemo.new(pin: pin)

  # --- declaration → class contract ---------------------------------------------

  def test_the_manifest_is_built_from_the_declaration
    manifest = ZenodoDemo.manifest
    assert_equal "acd", manifest.id
    assert_equal "Demo", manifest.name
    assert_equal "attribution", manifest.license_class
    assert_equal "lexibank-cldf", manifest.parser_family
    assert_equal "https://doi.org/10.5281/zenodo.1", manifest.upstream_url
  end

  def test_a_subclass_without_a_declaration_is_refused
    assert_raises(NotImplementedError) { Undeclared.manifest }
  end

  def test_dictionary_shaped_and_reflex_bearing
    assert_equal :dictionary, ZenodoDemo.content_kind
    assert ZenodoDemo.reflex_bearing?
  end

  def test_zenodo_arm_probes_the_artifact_and_git_arm_rides_the_git_probe
    assert_equal :http_zip, ZenodoDemo.remote_probe_strategy
    assert_equal [ZIP_URL], ZenodoDemo.http_probe_targets.map(&:zip_url)
    assert_equal :git, GitDemo.remote_probe_strategy
    assert_empty GitDemo.http_probe_targets
  end

  def test_the_zenodo_release_names_its_doi
    assert_equal "10.5281/zenodo.1", ZenodoDemo.dataset.release.doi
  end

  # --- discover / grains / parse ---------------------------------------------------

  def test_discover_yields_one_ref_for_the_cldf_bundle
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["acd:cldf"], refs.map(&:id)
    assert_equal ["acd"], refs.map(&:source_id)
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_discover_finds_the_bundle_under_a_hand_unpacked_release_dir
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexibank-acd-16085f2"))
      FileUtils.cp_r(File.join(FIXTURES, "cldf"), File.join(dir, "lexibank-acd-16085f2"))
      assert_equal [File.join(dir, "lexibank-acd-16085f2", "cldf")],
                   adapter.discover(dir).map(&:path)
    end
  end

  def test_declared_rejected_grains_present_in_the_tree_are_skipped_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule, "raw/ is pinned in the fixture; out/ is absent here"
    assert_equal 0, skips.unrecognized
    assert_equal ["upstream's pre-CLDF source dumps, not ingested: raw/"], skips.notes
  end

  def test_parse_yields_the_declared_dictionary_shelf
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "acd", document.slug
    assert_equal "map", document.language
    assert_equal "Demo shelf", document.title
    assert_equal %w[24748_1 25118_1 30578_1], document.map(&:entry_id)
    assert_includes document.first.body, "DEMO cognate set 24748_1"
  end

  def test_a_missing_spine_column_quarantines_as_a_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "cldf"), dir)
      cognates = File.join(dir, "cldf", "cognates.csv")
      File.write(cognates, File.read(cognates).sub("Cognateset_ID", "Set"))
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/Cognateset_ID/, error.message)
    end
  end

  def test_the_census_reports_the_read
    census = adapter.census(adapter.discover(FIXTURES).first)
    assert_equal 3, census[:sets_minted]
  end

  def test_entry_ids_are_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_loads_through_the_dictionary_loader_idempotently
    Dir.mktmpdir do |canonical_root|
      db = store_test_db
      source = Nabu::Store::Source.create(
        slug: "acd", name: "Demo", adapter_class: ZenodoDemo.name,
        license: "CC BY 4.0", license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.1", enabled: false
      )
      loader = Nabu::Store::DictionaryLoader.new(
        db: db, source: source, ledger: ledger_test_db,
        language_shelf_dir: File.join(canonical_root, Nabu::LanguageShelf::SLUG)
      )
      report = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 3, report.added
      assert_equal 0, report.errored
      row = db[:dictionary_entries].where(entry_id: "25118_1").first
      assert_equal "urn:nabu:dict:acd:25118_1", row[:urn]
      before = [db[:dictionary_entries].count, db[:dictionary_reflexes].count]
      assert_equal 8, before.last, "2 + 4 + 2 members (each set's own reconstruction row is its headword)"
      second = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 0, second.added + second.updated + second.withdrawn
      assert_equal before, [db[:dictionary_entries].count, db[:dictionary_reflexes].count]
    end
  end

  # --- fetch: the Zenodo arm (WebMock only) -------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      tree = File.join(dir, "lexibank-acd-test", "cldf")
      FileUtils.mkdir_p(tree)
      Dir.glob(File.join(FIXTURES, "cldf", "*.csv")).each { |csv| FileUtils.cp(csv, tree) }
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-acd-test") }
      File.binread(zip)
    end
  end

  def stub_zenodo(body)
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body,
                                          headers: { "Last-Modified" => "Tue, 07 Jan 2025 11:15:51 GMT" })
  end

  def test_fetch_pins_the_release_sha_and_unpacks_the_bundle
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      report = adapter(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_match(/zenodo v1\.0 sha pin verified/, report.notes)
      assert File.file?(File.join(workdir, "cldf", "forms.csv")), "the release's single top dir flattens"
      assert_equal ["acd:cldf"], adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_release_pin
    stub_zenodo(zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      refute File.exist?(File.join(workdir, "cldf")), "a refused fetch leaves the tree untouched"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, ZIP_URL).to_return(status: 503)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  # --- fetch: the git arm ------------------------------------------------------------------

  def test_git_arm_is_the_sparse_git_fetch_of_the_repository
    captured = nil
    subject = GitDemo.new
    subject.define_singleton_method(:git_fetch!) { |**kw| captured = kw }
    subject.fetch("/tmp/nowhere")
    assert_equal "https://github.com/lexibank/gitdemo", captured[:repo_url]
    assert_nil captured[:ref], "no tag exists: the default branch"
    assert_equal %w[cldf LICENSE README.md], captured[:sparse]
  end
end
