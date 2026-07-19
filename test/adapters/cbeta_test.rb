# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# CBETA adapter tests (P33-2). The adapter composes CbetaTeiParser with the
# xml-p5 canon layout (<canon>/<canon><vol>/<stem>.xml), scoped to T + X;
# THE CANON-LEVEL LICENSE GATE is the packet's signature: the four Category
# B corpora named on cbeta.org/copyright are pinned here and refused by
# canon dir, and the sparse fetch cone never materializes them. Includes
# the shared AdapterConformance suite and the house double-load rule.
class CbetaTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cbeta")

  T01 = "urn:nabu:cbeta:T01n0001-xu"
  T85 = "urn:nabu:cbeta:T85n2884"
  X01 = "urn:nabu:cbeta:X01n0001"
  X55 = "urn:nabu:cbeta:X55n0899"
  ALL_FIXTURES = [T01, T85, X01, X55].freeze # discover order (sorted by urn)

  # --- AdapterConformance hooks ----------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Cbeta.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cbeta"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Cbeta.manifest
    assert_equal "cbeta", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/姓名標示-非商業性-相同方式分享/, manifest.license)
    assert_match(/non-commercial use when distributed with this header intact/, manifest.license)
    assert_equal "https://github.com/cbeta-org/xml-p5", manifest.upstream_url
    assert_equal "cbeta-tei", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_filename_stems_with_canon_vol_work
    refs = Nabu::Adapters::Cbeta.new.discover(FIXTURES).to_a
    assert_equal ALL_FIXTURES, refs.map(&:id)
    refs.each do |ref|
      assert_equal "cbeta", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
    end
    by_id = refs.to_h { |ref| [ref.id, ref] }
    assert_equal %w[T 85 2884], by_id[T85].metadata.values_at("canon", "vol", "work")
    assert_equal %w[X 01 0001], by_id[X01].metadata.values_at("canon", "vol", "work")
  end

  # --- THE CANON-LEVEL LICENSE GATE ------------------------------------------

  # The named Category B list, verbatim from cbeta.org/copyright (類別 B：
  # 不屬於創用 CC 條款授權之文獻, read 2026-07-20). Pinned: a drifted
  # constant is a licensing defect, not a refactor.
  def test_category_b_pins_the_named_exclusion_list_verbatim
    expected = {
      "Y" => "印順法師佛學著作集（印順文教基金會 ©）",
      "LC" => "呂澂佛學著作集（呂應中等 ©）",
      "TX" => "太虛大師全書（印順文教基金會 ©）",
      "YP" => "演培法師全集（演培法師全集出版委員會 ©）"
    }
    assert_equal expected, Nabu::Adapters::Cbeta::CATEGORY_B
  end

  def test_discover_refuses_a_category_b_canon_dir_loudly
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "T"), root)
      FileUtils.mkdir_p(File.join(root, "Y", "Y44"))
      File.write(File.join(root, "Y", "Y44", "Y44n0001.xml"), "")
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Cbeta.new.discover(root).to_a }
      assert_match(/印順法師佛學著作集/, error.message)
      assert_match(/never ingested/, error.message)
    end
  end

  def test_discover_refuses_every_category_b_code
    Nabu::Adapters::Cbeta::CATEGORY_B.each_key do |code|
      Dir.mktmpdir do |root|
        FileUtils.cp_r(File.join(FIXTURES, "T"), root)
        FileUtils.mkdir_p(File.join(root, code))
        assert_raises(Nabu::FetchError, "dir #{code} must refuse") do
          Nabu::Adapters::Cbeta.new.discover(root).to_a
        end
      end
    end
  end

  # The sparse cone is the gate's first line: only T/X + registry + schema
  # are ever asked for. Pinned beside the refusal so the two layers cannot
  # drift apart.
  def test_sparse_cone_covers_scope_and_excludes_every_category_b_dir
    cone = Nabu::Adapters::Cbeta::SPARSE_CONE
    assert_equal ["T/", "X/", "canons.json", "schema/"], cone
    Nabu::Adapters::Cbeta::CATEGORY_B.each_key do |code|
      refute(cone.any? { |path| path.start_with?(code) }, "cone must not include #{code}")
    end
  end

  # --- discovery skips (P11-7) ------------------------------------------------

  def test_non_scope_category_a_canons_skip_by_rule
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "T"), root)
      FileUtils.mkdir_p(File.join(root, "J", "J01"))
      File.write(File.join(root, "J", "J01", "J01nA042.xml"), "")
      adapter = Nabu::Adapters::Cbeta.new
      assert_equal [T01, T85], adapter.discover(root).to_a.map(&:id)
      skips = adapter.discovery_skips(root)
      assert_equal 1, skips.skipped_by_rule
      assert_predicate skips, :clean?
    end
  end

  def test_a_stray_filename_under_a_scope_canon_is_unrecognized
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(FIXTURES, "T"), root)
      File.write(File.join(root, "T", "T01", "not-a-cbeta-stem.xml"), "")
      skips = Nabu::Adapters::Cbeta.new.discovery_skips(root)
      assert_equal 1, skips.unrecognized
      refute_predicate skips, :clean?
      assert_match(/not-a-cbeta-stem/, skips.notes.join)
    end
  end

  # --- parse round-trip -------------------------------------------------------

  def test_parse_carries_the_nc_grant_and_witnesses_on_every_document
    adapter = Nabu::Adapters::Cbeta.new
    adapter.discover(FIXTURES).each do |ref|
      document = adapter.parse(ref)
      assert_equal Nabu::Adapters::CbetaTeiParser::AVAILABILITY_GRANT, document.metadata["license"]
      assert_includes document.metadata["witnesses"], "【CB】"
      assert_equal "lzh", document.language
    end
  end

  # --- load: idempotency (the house double-load rule) -------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = cbeta_source
    loader = Nabu::Store::Loader.new(db: catalog, source: source)
    first = loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored

    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                 "an unchanged corpus must not fake content revisions"
  end

  # --- fetch (local git only, no network) -------------------------------------

  def test_fetch_materializes_only_the_sparse_cone
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_upstream_repo(upstream)
      workdir = File.join(root, "work")
      adapter = cbeta_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      assert File.exist?(File.join(workdir, "T", "T85", "T85n2884.xml")), "T/ is in the cone"
      assert File.exist?(File.join(workdir, "canons.json")), "canons.json is in the cone"
      refute Dir.exist?(File.join(workdir, "Y")), "Category B dir Y must never materialize"
      refute Dir.exist?(File.join(workdir, "J")), "non-scope canon J stays outside the cone"
      # And the materialized tree passes the Category B gate + discovers T.
      assert_includes adapter.discover(workdir).to_a.map(&:id), T85
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = cbeta_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_cbeta_and_stays_disabled_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["cbeta"]
    refute_nil entry, "cbeta must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Cbeta, entry.adapter_class
    assert_equal "manual", entry.sync_policy
    refute entry.enabled, "enabled: false until the owner-fired first sync is verified"
  end

  private

  def cbeta_source
    Nabu::Store::Source.create(
      slug: "cbeta", name: "CBETA", adapter_class: "Nabu::Adapters::Cbeta",
      license_class: "nc"
    )
  end

  def cbeta_pointing_at(upstream)
    adapter = Nabu::Adapters::Cbeta.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  # A miniature upstream with the real layout: scope canons, a non-scope
  # canon, a Category B canon, canons.json — the cone must take exactly
  # T/ + X/ + canons.json + schema/.
  def make_upstream_repo(dir)
    FileUtils.mkdir_p(dir)
    %w[T/T85 X/X01 J/J01 Y/Y44 schema].each { |sub| FileUtils.mkdir_p(File.join(dir, sub)) }
    FileUtils.cp(File.join(FIXTURES, "T", "T85", "T85n2884.xml"), File.join(dir, "T", "T85"))
    FileUtils.cp(File.join(FIXTURES, "X", "X01", "X01n0001.xml"), File.join(dir, "X", "X01"))
    File.write(File.join(dir, "J", "J01", "J01nA042.xml"), "<TEI/>\n")
    File.write(File.join(dir, "Y", "Y44", "Y44n0001.xml"), "<TEI/>\n")
    File.write(File.join(dir, "schema", "cbeta-p5.rnc"), "# schema stub\n")
    FileUtils.cp(File.join(FIXTURES, "canons.json"), dir)
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
