# frozen_string_literal: true

require "test_helper"

class DocumentRefTest < Minitest::Test
  def build(**overrides)
    defaults = {
      source_id: "perseus-greek",
      id: "tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml",
      path: "/canonical/perseus-greek/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml"
    }
    Nabu::DocumentRef.new(**defaults, **overrides)
  end

  def test_happy_path_construction
    ref = build(metadata: { "language_hint" => "grc" })
    assert_equal "perseus-greek", ref.source_id
    assert_equal "tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml", ref.id
    assert_equal "/canonical/perseus-greek/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml", ref.path
    assert_equal({ "language_hint" => "grc" }, ref.metadata)
  end

  def test_metadata_defaults_to_empty_hash
    assert_equal({}, build.metadata)
  end

  def test_value_is_frozen
    ref = build
    assert_predicate ref, :frozen?
    assert_predicate ref.id, :frozen?
    assert_predicate ref.metadata, :frozen?
  end

  def test_value_equality_supports_stable_discovery
    # Two discover runs over the same canonical tree must yield equal refs.
    assert_equal build, build
  end

  def test_invalid_source_id_shape_rejected
    ["", "Perseus Greek", "perseus/greek", "-leading", nil, 7].each do |source_id|
      assert_raises(Nabu::ValidationError, "expected #{source_id.inspect} to be rejected") do
        build(source_id: source_id)
      end
    end
  end

  def test_blank_id_rejected
    assert_raises(Nabu::ValidationError) { build(id: "") }
    assert_raises(Nabu::ValidationError) { build(id: "   ") }
    assert_raises(Nabu::ValidationError) { build(id: nil) }
  end

  def test_blank_path_rejected
    assert_raises(Nabu::ValidationError) { build(path: "") }
    assert_raises(Nabu::ValidationError) { build(path: nil) }
  end

  def test_non_json_metadata_rejected
    assert_raises(Nabu::ValidationError) { build(metadata: { "io" => $stdin }) }
    assert_raises(Nabu::ValidationError) { build(metadata: "not a hash") }
  end
end
