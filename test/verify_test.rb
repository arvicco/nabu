# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu verify` core (P4-4): re-parse each canonical document and compare its
# recomputed content hash against the value the catalog recorded at load time
# (architecture §8). Read-only against both canonical/ and the catalog.
#
# The catalog is seeded through Rebuild off a TestAdapter corpus (the reference
# case whose DocumentRef#id IS the document urn); each test then perturbs
# canonical/ and asserts exactly what Verify reports.
class VerifyTest < Minitest::Test
  ILIAD = "Iliad\nμῆνιν\nἄειδε\n"
  ODYSSEY = "Odyssey\nἄνδρα\n"

  ILIAD_URN = "urn:nabu:test_adapter:one"
  ODYSSEY_URN = "urn:nabu:test_adapter:two"

  def setup
    @root = Dir.mktmpdir("nabu-verify")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
    YAML
    write_canonical("corpus", "one.txt" => ILIAD, "two.txt" => ODYSSEY)
    Nabu::Rebuild.new(config: config, registry: registry).run # seed the catalog
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  # -- clean corpus verifies -----------------------------------------------

  def test_clean_corpus_verifies_with_no_issues
    result = verify

    assert result.clean?
    assert_empty result.issues
    outcome = result.outcomes.fetch(0)
    assert_equal "corpus", outcome.slug
    assert_equal 2, outcome.verified
    assert_predicate outcome, :ok?
  end

  # -- a changed word is a mismatch on exactly that document ----------------

  def test_corrupted_bytes_report_a_mismatch_for_that_document_only
    # Same filename (so the urn is unchanged), one word altered.
    write_canonical("corpus", "one.txt" => "Iliad\nμῆνιν\nΧΧΧΧ\n")

    result = verify

    refute result.clean?
    assert_equal 1, result.issues.size
    issue = result.issues.fetch(0)
    assert_equal ILIAD_URN, issue.urn
    assert_equal :mismatch, issue.kind
    refute_equal issue.detail.fetch(:stored), issue.detail.fetch(:recomputed)
    # The untouched document still verifies.
    assert_equal 2, result.outcomes.fetch(0).verified
  end

  # -- a deleted canonical file is missing ----------------------------------

  def test_deleted_canonical_file_is_reported_missing
    FileUtils.rm(File.join(@canonical, "corpus", "two.txt"))

    result = verify

    refute result.clean?
    assert_equal 1, result.issues.size
    issue = result.issues.fetch(0)
    assert_equal ODYSSEY_URN, issue.urn
    assert_equal :missing, issue.kind
  end

  # -- a file that no longer parses is unparseable --------------------------

  def test_unparseable_file_is_reported
    File.write(File.join(@canonical, "corpus", "one.txt"), "") # empty ⇒ ParseError

    result = verify

    refute result.clean?
    assert_equal 1, result.issues.size
    issue = result.issues.fetch(0)
    assert_equal ILIAD_URN, issue.urn
    assert_equal :unparseable, issue.kind
  end

  # -- withdrawn documents are skipped, not verified ------------------------

  def test_withdrawn_documents_are_skipped
    # Withdraw the Odyssey in the catalog AND delete its file: verify must not
    # flag the missing file, because a withdrawn document names no live
    # canonical obligation.
    with_catalog { |db| db[:documents].where(urn: ODYSSEY_URN).update(withdrawn: true) }
    FileUtils.rm(File.join(@canonical, "corpus", "two.txt"))

    result = verify

    assert result.clean?, "withdrawn document's missing file must not be reported"
    assert_equal 1, result.outcomes.fetch(0).verified # only the Iliad remains in scope
  end

  # -- sources with no canonical dir are skipped ----------------------------

  def test_source_without_canonical_dir_is_skipped
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
      ghost:
        adapter: TestAdapter
        enabled: true
    YAML

    result = verify

    assert result.clean?
    assert_equal %w[corpus], result.outcomes.map(&:slug)
    assert_equal %w[ghost], result.skips.map(&:slug)
    assert_equal :no_canonical, result.skips.fetch(0).reason
  end

  # -- helpers -------------------------------------------------------------

  private

  def verify
    with_catalog { |db| Nabu::Verify.new(config: config, registry: registry, db: db).run }
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: @db_dir,
      sources_path: @sources_path, config_path: "(test)"
    )
  end

  def with_catalog
    db = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.setup!(db)
    yield db
  ensure
    db&.disconnect
  end

  def write_sources(yaml) = File.write(@sources_path, yaml)

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end
end
