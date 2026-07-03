# frozen_string_literal: true

require "test_helper"

class DocumentTest < Minitest::Test
  def build_document(**overrides)
    defaults = {
      urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2",
      language: "grc",
      title: "Iliad",
      canonical_path: "perseus-greek/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml"
    }
    Nabu::Document.new(**defaults, **overrides)
  end

  def build_passage(sequence:, urn: nil)
    Nabu::Passage.new(
      urn: urn || "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.#{sequence + 1}",
      language: "grc",
      text: "μῆνιν ἄειδε θεὰ",
      text_normalized: "μηνιν αειδε θεα",
      sequence: sequence
    )
  end

  def test_happy_path_construction
    doc = build_document(metadata: { "edition" => "perseus-grc2" })
    assert_equal "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2", doc.urn
    assert_equal "grc", doc.language
    assert_equal "Iliad", doc.title
    assert_equal "perseus-greek/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml", doc.canonical_path
    assert_equal({ "edition" => "perseus-grc2" }, doc.metadata)
  end

  def test_title_is_optional
    assert_nil build_document(title: nil).title
  end

  def test_metadata_defaults_to_empty_hash
    assert_equal({}, build_document.metadata)
  end

  def test_starts_empty
    doc = build_document
    assert_empty doc
    assert_equal 0, doc.size
    assert_equal [], doc.passages
  end

  def test_append_returns_self_for_chaining
    doc = build_document
    result = doc << build_passage(sequence: 0) << build_passage(sequence: 1)
    assert_same doc, result
    assert_equal 2, doc.size
  end

  def test_append_alias
    doc = build_document
    doc.append(build_passage(sequence: 0))
    assert_equal 1, doc.size
  end

  def test_passages_ordered_by_sequence_regardless_of_append_order
    doc = build_document
    doc << build_passage(sequence: 2) << build_passage(sequence: 0) << build_passage(sequence: 1)
    assert_equal [0, 1, 2], doc.passages.map(&:sequence)
  end

  def test_enumerable_access_in_sequence_order
    doc = build_document
    doc << build_passage(sequence: 1) << build_passage(sequence: 0)
    assert_kind_of Enumerable, doc
    assert_equal [0, 1], doc.map(&:sequence)
    assert_equal 0, doc.first.sequence
  end

  def test_each_without_block_returns_enumerator
    doc = build_document << build_passage(sequence: 0)
    enum = doc.each
    assert_kind_of Enumerator, enum
    assert_equal 1, enum.count
  end

  def test_passages_returns_a_defensive_copy
    doc = build_document << build_passage(sequence: 0)
    doc.passages.clear
    assert_equal 1, doc.size
  end

  def test_appending_non_passage_rejected
    error = assert_raises(Nabu::ValidationError) { build_document << "not a passage" }
    assert_match(/Passage/, error.message)
  end

  def test_duplicate_passage_urn_rejected
    doc = build_document << build_passage(sequence: 0, urn: "urn:x:1")
    error = assert_raises(Nabu::ValidationError) { doc << build_passage(sequence: 1, urn: "urn:x:1") }
    assert_match(/urn/i, error.message)
  end

  def test_duplicate_passage_sequence_rejected
    doc = build_document << build_passage(sequence: 0)
    error = assert_raises(Nabu::ValidationError) { doc << build_passage(sequence: 0, urn: "urn:x:other") }
    assert_match(/sequence/i, error.message)
  end

  def test_blank_urn_rejected
    assert_raises(Nabu::ValidationError) { build_document(urn: "") }
    assert_raises(Nabu::ValidationError) { build_document(urn: nil) }
  end

  def test_bad_language_shape_rejected
    assert_raises(Nabu::ValidationError) { build_document(language: "Ancient Greek") }
  end

  def test_blank_title_rejected_when_given
    assert_raises(Nabu::ValidationError) { build_document(title: "   ") }
  end

  def test_blank_canonical_path_rejected
    assert_raises(Nabu::ValidationError) { build_document(canonical_path: "") }
    assert_raises(Nabu::ValidationError) { build_document(canonical_path: nil) }
  end

  def test_non_json_metadata_rejected
    assert_raises(Nabu::ValidationError) { build_document(metadata: { "obj" => Object.new }) }
  end
end
