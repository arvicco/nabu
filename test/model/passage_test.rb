# frozen_string_literal: true

require "test_helper"

class PassageTest < Minitest::Test
  # NFD-decomposed polytonic Greek "andra", built from explicit codepoints so
  # the fixture stays decomposed regardless of editor/filesystem normalization:
  # alpha U+03B1 + psili U+0313 + oxia U+0301 + nu + delta + rho + alpha.
  NFD_ANDRA = "ἄνδρα"
  # Precomposed NFC form: U+1F04 + nu + delta + rho + alpha.
  NFC_ANDRA = "ἄνδρα"

  def build(**overrides)
    defaults = {
      urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1",
      language: "grc",
      text: NFC_ANDRA,
      text_normalized: "ανδρα",
      sequence: 0
    }
    Nabu::Passage.new(**defaults, **overrides)
  end

  def test_happy_path_construction_with_keywords
    passage = build(annotations: { "lemma" => "ἀνήρ" }, sequence: 3)
    assert_equal "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1", passage.urn
    assert_equal "grc", passage.language
    assert_equal NFC_ANDRA, passage.text
    assert_equal "ανδρα", passage.text_normalized
    assert_equal({ "lemma" => "ἀνήρ" }, passage.annotations)
    assert_equal 3, passage.sequence
  end

  def test_annotations_default_to_empty_hash
    assert_equal({}, build.annotations)
  end

  def test_value_is_frozen
    assert_predicate build, :frozen?
  end

  def test_string_members_are_frozen
    passage = build
    assert_predicate passage.urn, :frozen?
    assert_predicate passage.text, :frozen?
    assert_predicate passage.text_normalized, :frozen?
    assert_raises(FrozenError) { passage.text << "x" }
  end

  def test_annotations_are_deeply_frozen_and_detached_from_input
    input = { "morph" => { "case" => "acc" }, "tags" => ["noun"] }
    passage = build(annotations: input)
    assert_predicate passage.annotations, :frozen?
    assert_predicate passage.annotations["morph"], :frozen?
    assert_predicate passage.annotations["tags"], :frozen?
    input["morph"]["case"] = "nom"
    assert_equal "acc", passage.annotations["morph"]["case"]
  end

  def test_with_produces_validated_copy
    passage = build
    copy = passage.with(sequence: 9)
    assert_equal 9, copy.sequence
    assert_equal passage.urn, copy.urn
    assert_raises(Nabu::ValidationError) { passage.with(sequence: -1) }
  end

  def test_value_equality
    assert_equal build, build
  end

  # --- URN ---

  def test_empty_urn_rejected
    error = assert_raises(Nabu::ValidationError) { build(urn: "") }
    assert_match(/urn/i, error.message)
  end

  def test_whitespace_only_urn_rejected
    assert_raises(Nabu::ValidationError) { build(urn: "  \t") }
  end

  def test_non_string_urn_rejected
    assert_raises(Nabu::ValidationError) { build(urn: 42) }
    assert_raises(Nabu::ValidationError) { build(urn: nil) }
  end

  # --- language ---

  def test_valid_language_shapes_accepted
    %w[grc chu hit la en-US grc-Grek sa-Deva-IN].each do |lang|
      assert_equal lang, build(language: lang).language
    end
  end

  def test_invalid_language_shapes_rejected
    ["", "e", "GRC", "Greek", "grc-", "grc_Grek", "ancient greek", "abcd", nil, :grc].each do |lang|
      error = assert_raises(Nabu::ValidationError, "expected #{lang.inspect} to be rejected") do
        build(language: lang)
      end
      assert_match(/language/i, error.message)
    end
  end

  # --- text ---

  def test_non_nfc_text_rejected_not_normalized
    error = assert_raises(Nabu::ValidationError) { build(text: NFD_ANDRA) }
    assert_match(/NFC/, error.message)
  end

  def test_non_nfc_text_normalized_rejected
    assert_raises(Nabu::ValidationError) { build(text_normalized: NFD_ANDRA) }
  end

  def test_invalid_utf8_text_rejected
    invalid = "abc\xFF".dup.force_encoding(Encoding::UTF_8)
    error = assert_raises(Nabu::ValidationError) { build(text: invalid) }
    assert_match(/UTF-8/, error.message)
  end

  def test_non_utf8_encoded_text_rejected
    latin1 = "caf\xE9".dup.force_encoding(Encoding::ISO_8859_1)
    assert_raises(Nabu::ValidationError) { build(text: latin1) }
  end

  def test_empty_text_rejected
    assert_raises(Nabu::ValidationError) { build(text: "") }
    assert_raises(Nabu::ValidationError) { build(text_normalized: "") }
  end

  def test_non_string_text_rejected
    assert_raises(Nabu::ValidationError) { build(text: nil) }
  end

  # --- annotations ---

  def test_non_hash_annotations_rejected
    assert_raises(Nabu::ValidationError) { build(annotations: [%w[lemma x]]) }
    assert_raises(Nabu::ValidationError) { build(annotations: nil) }
  end

  def test_non_json_serializable_annotation_value_rejected
    assert_raises(Nabu::ValidationError) { build(annotations: { "obj" => Object.new }) }
    assert_raises(Nabu::ValidationError) { build(annotations: { "when" => Time.now }) }
  end

  def test_symbol_annotation_values_rejected
    # A Symbol would silently become a String on JSON round-trip; reject the drift.
    assert_raises(Nabu::ValidationError) { build(annotations: { "pos" => :noun }) }
  end

  def test_symbol_annotation_keys_accepted
    assert_equal({ lemma: "ἀνήρ" }, build(annotations: { lemma: "ἀνήρ" }).annotations)
  end

  def test_nested_json_annotations_accepted
    annotations = { "tokens" => [{ "form" => "ἄνδρα", "n" => 1, "stop" => false, "gloss" => nil }] }
    assert_equal annotations, build(annotations: annotations).annotations
  end

  def test_non_finite_float_annotation_rejected
    assert_raises(Nabu::ValidationError) { build(annotations: { "score" => Float::NAN }) }
  end

  # --- sequence ---

  def test_zero_sequence_accepted
    assert_equal 0, build(sequence: 0).sequence
  end

  def test_negative_sequence_rejected
    error = assert_raises(Nabu::ValidationError) { build(sequence: -1) }
    assert_match(/sequence/i, error.message)
  end

  def test_non_integer_sequence_rejected
    assert_raises(Nabu::ValidationError) { build(sequence: "1") }
    assert_raises(Nabu::ValidationError) { build(sequence: 1.0) }
    assert_raises(Nabu::ValidationError) { build(sequence: nil) }
  end
end
