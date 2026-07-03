# frozen_string_literal: true

require "test_helper"

class AdapterTest < Minitest::Test
  # A subclass that implements nothing: every contract method must refuse
  # loudly, naming the adapter class and the missing method.
  class BareAdapter < Nabu::Adapter; end

  class ManifestOnlyAdapter < Nabu::Adapter
    MANIFEST = Nabu::SourceManifest.new(
      id: "manifest_only",
      name: "Manifest-only Adapter",
      license: "CC0 1.0",
      license_class: "open",
      upstream_url: "https://example.invalid/manifest_only",
      parser_family: "plaintext"
    )

    def self.manifest
      MANIFEST
    end
  end

  def test_class_manifest_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.manifest }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/manifest/, error.message)
  end

  def test_fetch_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.new.fetch("canonical/bare") }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/fetch/, error.message)
  end

  def test_discover_raises_not_implemented_naming_class_and_method
    error = assert_raises(NotImplementedError) { BareAdapter.new.discover("canonical/bare") }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/discover/, error.message)
  end

  def test_parse_raises_not_implemented_naming_class_and_method
    ref = Nabu::DocumentRef.new(source_id: "bare", id: "doc.txt", path: "canonical/bare/doc.txt")
    error = assert_raises(NotImplementedError) { BareAdapter.new.parse(ref) }
    assert_match(/AdapterTest::BareAdapter/, error.message)
    assert_match(/parse/, error.message)
  end

  def test_instance_manifest_delegates_to_class_manifest
    assert_same ManifestOnlyAdapter.manifest, ManifestOnlyAdapter.new.manifest
  end

  def test_instance_manifest_raises_when_class_manifest_is_not_implemented
    error = assert_raises(NotImplementedError) { BareAdapter.new.manifest }
    assert_match(/AdapterTest::BareAdapter/, error.message)
  end
end
