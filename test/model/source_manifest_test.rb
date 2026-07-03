# frozen_string_literal: true

require "test_helper"

class SourceManifestTest < Minitest::Test
  def build(**overrides)
    defaults = {
      id: "perseus-greek",
      name: "Perseus Digital Library (Greek)",
      license: "CC BY-SA 4.0",
      license_class: "attribution",
      upstream_url: "https://github.com/PerseusDL/canonical-greekLit",
      parser_family: "epidoc"
    }
    Nabu::SourceManifest.new(**defaults, **overrides)
  end

  def test_happy_path_construction
    manifest = build
    assert_equal "perseus-greek", manifest.id
    assert_equal "Perseus Digital Library (Greek)", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PerseusDL/canonical-greekLit", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_value_is_frozen
    assert_predicate build, :frozen?
  end

  def test_every_license_class_in_enum_accepted
    Nabu::SourceManifest::LICENSE_CLASSES.each do |license_class|
      assert_equal license_class, build(license_class: license_class).license_class
    end
  end

  def test_license_class_enum_is_the_architecture_s5_set
    assert_equal %w[open attribution nc research_private restricted],
                 Nabu::SourceManifest::LICENSE_CLASSES
  end

  def test_symbol_license_class_canonicalized_to_string
    assert_equal "open", build(license_class: :open).license_class
  end

  def test_unknown_license_class_rejected
    ["public-domain", "OPEN", "", nil, :proprietary, 1].each do |license_class|
      error = assert_raises(Nabu::ValidationError, "expected #{license_class.inspect} to be rejected") do
        build(license_class: license_class)
      end
      assert_match(/license_class/, error.message)
    end
  end

  def test_invalid_id_shape_rejected
    ["", "Perseus Greek", "UPPER", nil].each do |id|
      assert_raises(Nabu::ValidationError) { build(id: id) }
    end
  end

  def test_blank_name_license_url_rejected
    assert_raises(Nabu::ValidationError) { build(name: "") }
    assert_raises(Nabu::ValidationError) { build(license: "  ") }
    assert_raises(Nabu::ValidationError) { build(upstream_url: nil) }
  end

  def test_invalid_parser_family_shape_rejected
    assert_raises(Nabu::ValidationError) { build(parser_family: "") }
    assert_raises(Nabu::ValidationError) { build(parser_family: "EpiDoc Parser") }
  end
end
