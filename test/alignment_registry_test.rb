# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::AlignmentRegistry (P11-3, architecture §10): the declarative side of
# the alignment hub. Conformance-quality by design brief: every malformed
# registry shape must fail LOUDLY (ValidationError naming the offending
# work/witness), because a silently mis-parsed registry is a silently empty
# alignment index.
class AlignmentRegistryTest < Minitest::Test
  VALID = <<~YAML
    nt:
      title: "New Testament (parallel witnesses)"
      witnesses:
        - document: urn:nabu:proiel:greek-nt
        - document: urn:nabu:proiel:marianus
          label: ocs
          books:
            MK: MARK
  YAML

  def load_registry(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "alignments.yml")
      File.write(path, yaml)
      return Nabu::AlignmentRegistry.load(path)
    end
  end

  # -- loading ---------------------------------------------------------------

  def test_missing_file_is_a_valid_empty_registry
    registry = Nabu::AlignmentRegistry.load("/nonexistent/alignments.yml")
    assert_empty registry.works
  end

  def test_empty_file_is_a_valid_empty_registry
    registry = load_registry("")
    assert_empty registry.works
  end

  def test_loads_works_and_witnesses_in_order
    registry = load_registry(VALID)
    work = registry.work("nt")
    assert_equal "New Testament (parallel witnesses)", work.title
    assert_equal %w[urn:nabu:proiel:greek-nt urn:nabu:proiel:marianus],
                 work.witnesses.map(&:document_urn)
  end

  def test_label_defaults_to_the_urn_tail_and_override_wins
    work = load_registry(VALID).work("nt")
    assert_equal %w[greek-nt ocs], work.witnesses.map(&:label)
  end

  def test_extractor_defaults_to_proiel_citation
    work = load_registry(VALID).work("nt")
    assert(work.witnesses.all? { |witness| witness.extractor == "proiel-citation" })
  end

  def test_unknown_work_returns_nil
    assert_nil load_registry(VALID).work("iliad")
  end

  def test_witness_lookup_by_document_urn
    work = load_registry(VALID).work("nt")
    assert_equal "ocs", work.witness_for("urn:nabu:proiel:marianus").label
    assert_nil work.witness_for("urn:nabu:proiel:latin-nt")
  end

  # -- loud failure on malformed registries -----------------------------------

  def test_non_mapping_registry_fails
    error = assert_raises(Nabu::ValidationError) { load_registry("- nope") }
    assert_match(/mapping/, error.message)
  end

  def test_bad_work_id_fails
    error = assert_raises(Nabu::ValidationError) { load_registry("NT!:\n  witnesses: []\n") }
    assert_match(/NT!/, error.message)
  end

  def test_work_without_witnesses_fails
    error = assert_raises(Nabu::ValidationError) { load_registry("nt:\n  title: x\n") }
    assert_match(/nt/, error.message)
    assert_match(/witnesses/, error.message)
  end

  def test_empty_witness_list_fails
    error = assert_raises(Nabu::ValidationError) { load_registry("nt:\n  witnesses: []\n") }
    assert_match(/witnesses/, error.message)
  end

  def test_witness_without_document_fails
    error = assert_raises(Nabu::ValidationError) do
      load_registry("nt:\n  witnesses:\n    - label: x\n")
    end
    assert_match(/document/, error.message)
  end

  def test_witness_document_must_be_a_urn
    error = assert_raises(Nabu::ValidationError) do
      load_registry("nt:\n  witnesses:\n    - document: greek-nt\n")
    end
    assert_match(/urn/, error.message)
  end

  def test_duplicate_witness_documents_fail
    yaml = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:greek-nt
    YAML
    error = assert_raises(Nabu::ValidationError) { load_registry(yaml) }
    assert_match(/duplicate/, error.message)
  end

  def test_unknown_extractor_fails_naming_the_known_set
    yaml = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
            extractor: telepathy
    YAML
    error = assert_raises(Nabu::ValidationError) { load_registry(yaml) }
    assert_match(/telepathy/, error.message)
    assert_match(/proiel-citation/, error.message)
  end

  def test_books_must_be_a_string_to_string_mapping
    yaml = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
            books: [MK, MARK]
    YAML
    error = assert_raises(Nabu::ValidationError) { load_registry(yaml) }
    assert_match(/books/, error.message)
  end

  # -- the shipped registry -----------------------------------------------------

  def test_shipped_registry_loads_the_five_way_nt
    path = File.join(Nabu::Config::PROJECT_ROOT, "config", "alignments.yml")
    registry = Nabu::AlignmentRegistry.load(path)
    work = registry.work("nt")
    refute_nil work, "config/alignments.yml must register the nt work"
    assert_equal %w[urn:nabu:proiel:greek-nt urn:nabu:proiel:latin-nt urn:nabu:proiel:gothic-nt
                    urn:nabu:proiel:armenian-nt urn:nabu:proiel:marianus],
                 work.witnesses.map(&:document_urn),
                 "the five-way NT flagship (P11-3) is the shipped proof"
  end

  # -- ref normalization (the fold-both-sides contract, §10) -------------------

  def test_normalize_ref_folds_case_whitespace_and_colon
    assert_equal "MARK 2.3", Nabu::AlignmentRegistry.normalize_ref("Mark 2:3")
    assert_equal "MARK 2.3", Nabu::AlignmentRegistry.normalize_ref("  mark   2.3 ")
    assert_equal "1COR 13.4", Nabu::AlignmentRegistry.normalize_ref("1Cor 13:4")
  end

  def test_normalize_ref_passes_non_verse_refs_through_folded
    # Gothic reality: "MARK Incipit.0" — non-numeric refs stay addressable.
    assert_equal "MARK INCIPIT.0", Nabu::AlignmentRegistry.normalize_ref("Mark Incipit.0")
    assert_equal "1.1", Nabu::AlignmentRegistry.normalize_ref("1.1")
  end

  def test_normalize_ref_of_blank_is_nil
    assert_nil Nabu::AlignmentRegistry.normalize_ref("  ")
    assert_nil Nabu::AlignmentRegistry.normalize_ref(nil)
  end

  def test_witness_ref_applies_book_aliases_after_the_fold
    work = load_registry(VALID).work("nt")
    witness = work.witness_for("urn:nabu:proiel:marianus")
    assert_equal "MARK 2.3", witness.normalize_ref("Mk 2:3")
    # Unaliased books pass through the plain fold.
    assert_equal "MATT 1.1", witness.normalize_ref("MATT 1.1")
  end
end
