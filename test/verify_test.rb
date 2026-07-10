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

# A TestAdapter whose parse DECLINES one ref by rule (Nabu::DocumentSkipped) —
# the P11-7 fix-3 shape. Verify must skip it, never crash the run (the regression
# below). Resolved by the registry via Object.const_get, so top-level.
class SkippingVerifyAdapter < TestAdapter
  ODYSSEY_URN = "urn:nabu:test_adapter:two"

  def parse(document_ref)
    if document_ref.id == ODYSSEY_URN
      raise Nabu::DocumentSkipped.new("catalog-only skeleton", reason: "catalog-only (no content)")
    end

    super
  end
end

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

  # -- P11-7 fix 3 regression: a DocumentSkipped ref must not crash verify ---

  # The oracc catalog-only skeletons now raise Nabu::DocumentSkipped from parse;
  # Verify#reparse (the passage path) must skip them, not let the signal abort
  # the whole run (the same failure mode fix 2 closed for dictionaries — caught
  # live by the full-catalog verify, not the unit suite, so pinned here).
  def test_document_skipped_ref_is_skipped_not_a_crash
    write_sources(<<~YAML)
      corpus:
        adapter: SkippingVerifyAdapter
        enabled: true
    YAML
    Nabu::Rebuild.new(config: config, registry: registry).run # seeds only Iliad

    result = verify # must COMPLETE (no NoMethodError/DocumentSkipped escaping)

    assert result.clean?
    outcome = result.outcomes.fetch(0)
    assert_equal "corpus", outcome.slug
    assert_equal 1, outcome.verified # Iliad verified; the skipped Odyssey names no row
  end

  # -- P11-7 fix 2: dictionary sources verify instead of crashing the run ----

  # Verify#reparse called document.urn on a Nabu::DictionaryDocument (no such
  # method); the crash aborted the ENTIRE verify run, leaving every source after
  # lexica unchecked. Verify must now route dictionary sources to entry-level
  # verification and complete, reporting BOTH kinds.
  def test_verify_completes_over_both_passage_and_dictionary_sources
    write_sources(<<~YAML)
      corpus:
        adapter: TestAdapter
        enabled: true
      lexica:
        adapter: Nabu::Adapters::Lexica
        enabled: true
    YAML
    FileUtils.cp_r(Nabu::TestSupport.fixtures("lexica"), File.join(@canonical, "lexica"))
    Nabu::Rebuild.new(config: config, registry: registry).run # seed both kinds

    result = verify

    assert result.clean?, "both a passage source and a dictionary source verify clean"
    slugs = result.outcomes.map(&:slug)
    assert_includes slugs, "corpus"
    assert_includes slugs, "lexica"
    lexica = result.outcomes.find { |outcome| outcome.slug == "lexica" }
    assert_operator lexica.verified, :>, 0, "dictionary entries must be verified, not skipped"
    assert_predicate lexica, :ok?
  end

  def test_verify_flags_a_tampered_dictionary_entry
    write_sources(<<~YAML)
      lexica:
        adapter: Nabu::Adapters::Lexica
        enabled: true
    YAML
    lexica_dir = File.join(@canonical, "lexica")
    FileUtils.cp_r(Nabu::TestSupport.fixtures("lexica"), lexica_dir)
    Nabu::Rebuild.new(config: config, registry: registry).run
    # Corrupt the stored hash of one entry: verify must catch the divergence.
    with_catalog do |db|
      db[:dictionary_entries].where(entry_id: "n67485").update(content_sha256: "tampered")
    end

    result = verify

    refute result.clean?
    issue = result.issues.find { |i| i.urn == "urn:nabu:dict:lsj:n67485" }
    refute_nil issue
    assert_equal :mismatch, issue.kind
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
