# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

# `rake stamps:rebless` (P39-1): rewrite every source's derivation stamp
# against CURRENT code without re-deriving anything — the owner-only escape
# hatch after a fingerprint FORMULA change (which would otherwise read every
# stamp dirty and force a full rebuild that would reproduce byte-identical
# rows). DANGEROUS BY NATURE: blessing a stamp that a full rebuild did not
# actually satisfy is silent under-derivation, so the task demands an explicit
# attestation string and refuses everything else.
class StampReblessTest < Minitest::Test
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"

  def setup
    @root = Dir.mktmpdir("nabu-rebless")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
    File.write(@sources_path, <<~YAML)
      alpha:
        adapter: TestAdapter
      gamma:
        adapter: JpnTestAdapter
    YAML
    write_canonical("alpha", "a.txt" => ILIAD)
    write_canonical("gamma", "g.txt" => "草枕\n學問はどこまでも\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_refuses_without_the_attestation_and_touches_nothing
    full_rebuild
    before = stamp_rows

    [nil, "", "yes", "i-verified"].each do |attestation|
      error = assert_raises(Nabu::Error) { rebless.run(attestation: attestation, out: StringIO.new) }
      assert_match(/full rebuild/, error.message)
      assert_match(/under-deriv/, error.message, "the refusal must spell out the blast radius")
    end
    assert_equal before, stamp_rows, "a refused rebless must rewrite nothing"
  end

  def test_rewrites_stale_formula_stamps_without_rederiving
    full_rebuild
    rows_before = passage_rows
    # Simulate a fingerprint FORMULA change: the stored stamps no longer match
    # what current code computes (exactly the P39-1 migration situation).
    with_db(write: true) do |db|
      db[:derivation_stamps].update(fold_digest: "f" * 64, fingerprint: "0" * 64)
    end

    out = StringIO.new
    rebless.run(attestation: Nabu::Ops::StampRebless::ATTESTATION, out: out)

    assert_match(/alpha/, out.string, "every rewrite must be printed")
    assert_match(/gamma/, out.string)
    assert_equal rows_before, passage_rows, "rebless must not re-derive a single row"
    result = incremental.run
    assert_empty result.outcomes, "reblessed stamps must read clean"
    assert_equal %w[alpha gamma], result.cleans.map(&:slug).sort
  end

  def test_refuses_without_a_catalog
    error = assert_raises(Nabu::Error) do
      rebless.run(attestation: Nabu::Ops::StampRebless::ATTESTATION, out: StringIO.new)
    end
    assert_match(/full rebuild/, error.message)
  end

  def test_refuses_on_schema_drift
    full_rebuild
    with_db(write: true) do |db|
      db[:schema_info].update(version: Nabu::DerivationFingerprint.migration_level - 1)
    end

    error = assert_raises(Nabu::Error) do
      rebless.run(attestation: Nabu::Ops::StampRebless::ATTESTATION, out: StringIO.new)
    end
    assert_match(/full rebuild/, error.message)
  end

  private

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: @db_dir,
      sources_path: @sources_path, config_path: "(test)"
    )
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def rebless = Nabu::Ops::StampRebless.new(config: config, registry: registry)

  def incremental = Nabu::IncrementalRebuild.new(config: config, registry: registry)

  def full_rebuild = Nabu::Rebuild.new(config: config, registry: registry).run

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  def with_db(write: false)
    db = Nabu::Store.connect(config.catalog_path, readonly: !write)
    yield db
  ensure
    db&.disconnect
  end

  def stamp_rows = with_db { |db| db[:derivation_stamps].order(:slug).all }

  def passage_rows = with_db { |db| db[:passages].order(:id).all }
end
