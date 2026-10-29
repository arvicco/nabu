# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::DemoBuild — the self-contained demo library the OCI image bakes in.
# The real build syncs over the network (CI, per release); here the command
# runner is injected, so the suite proves the WIRING (layout, the commands
# and the environment they run under, canonical pruning, the seal, the
# census) and the LICENSE GUARD on fixture registries and file-backed
# catalogs — never a live sync.
class DemoBuildTest < Minitest::Test
  # A non-commercial adapter: the class the guard must refuse to bake.
  class NcAdapter < TestAdapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "demo_nc", name: "NC test adapter", license: "CC BY-NC (test)", license_class: "nc",
      upstream_url: "https://example.invalid/nc", parser_family: "plaintext"
    )

    def self.manifest = MANIFEST
  end

  def setup
    @root = Dir.mktmpdir("nabu-demo")
    @project = File.join(@root, "project")
    FileUtils.mkdir_p(File.join(@project, "config"))
    File.write(File.join(@project, "config", "alignments.yml"), "{}\n")
    File.write(File.join(@project, "config", "profile.yml"), "- private-interest\n") # never copied
    @out = File.join(@root, "out")
    @work = File.join(@root, "work")
    @commands = []
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  CLEAN_SOURCES = <<~YAML
    core-mod:
      adapter: TestAdapter
      group: core
      kind: module
      requires: [gazetteer]
    gazetteer:
      adapter: TestAdapter
      kind: module
    texts:
      adapter: TestAdapter
      wired: true
    more-texts:
      adapter: TestAdapter
      wired: true
  YAML

  def registry(yaml = CLEAN_SOURCES)
    path = File.join(@project, "config", "sources.yml")
    File.write(path, yaml)
    Nabu::SourceRegistry.load(path)
  end

  def build(registry, slugs: %w[texts more-texts], max_bytes: 50_000_000, keep: %w[core-mod], &sync)
    sync ||= ->(config) { fake_sync(config) }
    runner = lambda do |env, argv|
      @commands << [env, argv]
      if argv.include?("sync")
        sync.call(Nabu::Config.load(path: env.fetch("NABU_CONFIG"),
                                    root: env.fetch("NABU_ROOT")))
      end
    end
    Nabu::DemoBuild.new(registry: registry, out_dir: @out, work_dir: @work, project_root: @project,
                        slugs: slugs, keep_canonical: keep, max_bytes: max_bytes, runner: runner,
                        log: StringIO.new)
  end

  # What a real `nabu sync` leaves behind, in miniature: a canonical tree
  # per module, a catalog with source rows, a fulltext index.
  def fake_sync(config, license_class: "open", override: nil)
    %w[core-mod gazetteer].each do |slug|
      FileUtils.mkdir_p(File.join(config.canonical_dir, slug, ".git"))
      File.write(File.join(config.canonical_dir, slug, "data.yml"), "x: 1\n")
    end
    FileUtils.mkdir_p(config.db_dir)
    catalog = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(catalog)
    Nabu::Store.setup!(catalog)
    # A re-run re-syncs into the same catalog (the real sync is idempotent).
    return catalog.disconnect if Nabu::Store::Source.first(slug: "texts")

    source = Nabu::Store::Source.create(slug: "texts", name: "Texts", adapter_class: "TestAdapter",
                                        license_class: license_class, enabled: true)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:texts:a", title: "A", language: "grc",
                                       content_sha256: "x", revision: 1, license_override: override)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:texts:a:1", sequence: 0, language: "grc",
                                text: "λόγος", text_normalized: "λογος", content_sha256: "x", revision: 1)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    Nabu::Store::SourceStats.derive!(catalog, note: "test")
    catalog.disconnect
    fulltext.disconnect
  end

  # -- the license guard (before any network) --------------------------------

  def test_plan_is_the_named_slugs_plus_core_and_requires_closure
    demo = build(registry)
    assert_equal %w[core-mod texts more-texts gazetteer], demo.plan # discovery order
    assert_equal demo.plan, demo.guard!
  end

  def test_guard_refuses_a_named_nc_source_before_running_anything
    reg = registry("#{CLEAN_SOURCES}nc-texts:\n  adapter: DemoBuildTest::NcAdapter\n  wired: true\n")
    error = assert_raises(Nabu::DemoBuild::LicenseRefused) { build(reg, slugs: %w[texts nc-texts]).build! }
    assert_match(/nc-texts \(nc\)/, error.message)
    assert_empty @commands, "nothing runs once the guard refuses"
    refute Dir.exist?(@out), "nothing is laid out either"
  end

  def test_guard_refuses_an_nc_source_pulled_in_by_requires
    reg = registry(CLEAN_SOURCES + "nc-dep:\n  adapter: DemoBuildTest::NcAdapter\n  kind: module\n" \
                                   "needy:\n  adapter: TestAdapter\n  wired: true\n  requires: [nc-dep]\n")
    error = assert_raises(Nabu::DemoBuild::LicenseRefused) { build(reg, slugs: %w[needy]).guard! }
    assert_match(/nc-dep \(nc\)/, error.message)
  end

  def test_guard_refuses_access_gated_rows
    reg = registry("#{CLEAN_SOURCES}gated:\n  adapter: TestAdapter\n  wired: true\n  availability: blocked\n")
    error = assert_raises(Nabu::DemoBuild::LicenseRefused) { build(reg, slugs: %w[gated]).guard! }
    assert_match(/gated \(blocked\)/, error.message)
  end

  def test_guard_refuses_an_unknown_slug
    assert_raises(Nabu::DemoBuild::LicenseRefused) { build(registry, slugs: %w[nowhere]).guard! }
  end

  def test_the_shipped_demo_set_passes_the_guard_against_the_real_registry
    real = Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
    demo = Nabu::DemoBuild.new(registry: real, out_dir: @out, work_dir: @work)
    plan = demo.guard!
    Nabu::DemoBuild::DEMO_SOURCES.each { |source| assert_includes plan, source.slug }
    plan.each do |slug|
      assert_includes Nabu::DemoBuild::SERVABLE_LICENSE_CLASSES, real[slug].manifest.license_class, slug
    end
  end

  # -- the build wiring ---------------------------------------------------------

  def test_build_lays_out_syncs_prunes_seals_and_censuses
    census = build(registry).build!

    env, enable = @commands.first
    assert_equal({ "NABU_ROOT" => @out, "NABU_CONFIG" => File.join(@out, "config", "nabu.yml") }, env)
    assert_equal %w[enable texts more-texts], enable.last(3)
    _, sync = @commands.last
    assert_equal %w[sync texts more-texts], sync.last(3)

    # The project config is copied in — never the personal profile.
    assert File.exist?(File.join(@out, "config", "sources.yml"))
    assert File.exist?(File.join(@out, "config", "alignments.yml"))
    refute File.exist?(File.join(@out, "config", "profile.yml"))

    # The shipped nabu.yml is self-relative: the server finds everything
    # under NABU_ROOT, and canonical/ holds only the kept modules (no .git).
    runtime = Nabu::Config.load(path: File.join(@out, "config", "nabu.yml"), root: @out)
    assert_equal File.join(@out, "db", "catalog.sqlite3"), runtime.catalog_path
    assert_equal File.join(@out, "canonical"), runtime.canonical_dir
    assert_equal %w[core-mod], Dir.children(runtime.canonical_dir)
    refute Dir.exist?(File.join(@out, "canonical", "core-mod", ".git"))
    assert Dir.exist?(File.join(@work, "canonical", "gazetteer")), "the work tree keeps the full fetch"

    # Sealed: rollback journal, no sidecars.
    refute Dir.glob(File.join(@out, "**", "*.sqlite3-{wal,shm}")).any?
    db = Nabu::Store.connect(runtime.catalog_path, readonly: true)
    assert_equal "delete", db.fetch("PRAGMA journal_mode").single_value
    db.disconnect

    # The census lands beside the stores and matches the return value.
    written = JSON.parse(File.read(File.join(@out, Nabu::DemoBuild::CENSUS_FILE)))
    assert_equal JSON.parse(JSON.generate(census)), written
    assert_equal [{ "slug" => "texts", "license_class" => "open", "documents" => 1, "passages" => 1 }],
                 written["sources"]
    assert_operator written["total_bytes"], :>, 0
    assert_includes written["files"].keys, "db/catalog.sqlite3"
  end

  def test_build_is_rerunnable_into_its_own_output
    build(registry).build!
    build(registry).build! # the census marker makes the dir recognizably ours
    assert File.exist?(File.join(@out, Nabu::DemoBuild::CENSUS_FILE))
  end

  def test_build_refuses_a_foreign_non_empty_output_dir
    FileUtils.mkdir_p(@out)
    File.write(File.join(@out, "precious.txt"), "keep me")
    assert_raises(Nabu::Error) { build(registry).build! }
    assert_empty @commands
  end

  def test_post_sync_guard_refuses_a_catalog_carrying_an_nc_source_row
    demo = build(registry) { |config| fake_sync(config, license_class: "nc") }
    error = assert_raises(Nabu::DemoBuild::LicenseRefused) { demo.build! }
    assert_match(/texts \(nc\)/, error.message)
    refute File.exist?(File.join(@out, Nabu::DemoBuild::CENSUS_FILE)), "no census = not a finished demo"
  end

  def test_post_sync_guard_refuses_a_document_level_private_override
    demo = build(registry) { |config| fake_sync(config, override: "research_private") }
    error = assert_raises(Nabu::DemoBuild::LicenseRefused) { demo.build! }
    assert_match(/urn:nabu:texts:a \(research_private\)/, error.message)
  end

  def test_size_ceiling_is_enforced
    error = assert_raises(Nabu::Error) { build(registry, max_bytes: 1_000).build! }
    assert_match(/ceiling/, error.message)
  end

  def test_from_env_reads_the_rake_knobs
    demo = Nabu::DemoBuild.from_env({ "DEMO_OUT" => "x/demo", "DEMO_MAX_MB" => "300" },
                                    registry: registry, project_root: @project)
    assert_equal File.join(@project, "x", "demo"), demo.out_dir
    assert_equal File.join(@project, "x", "demo-work"), demo.work_dir
    assert_equal 300 * 1024 * 1024, demo.max_bytes
    default = Nabu::DemoBuild.from_env({}, registry: registry, project_root: @project)
    assert_equal File.join(@project, "tmp", "demo"), default.out_dir
  end
end
