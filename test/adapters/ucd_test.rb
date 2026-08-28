# frozen_string_literal: true

require "test_helper"

# UCD adapter (P85): the Unicode Character Database core (UnicodeData.txt) as a
# feature-module instrument — the universal character-identity backbone of the
# `nabu char` redesign. This is the ADAPTER SKELETON: the fetch channel,
# manifest and registration, tested WITHOUT the data (fixtures are real files;
# the real UnicodeData.txt lands on the owner-fired `nabu sync ucd`, and the
# read seam + per-script cards get their tests against the trimmed fixture then).
class UcdTest < Minitest::Test
  def test_manifest_is_a_valid_open_module_instrument
    manifest = Nabu::Adapters::Ucd.manifest
    assert_equal "ucd", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/UNICODE LICENSE V3/, manifest.license)
    assert_match(%r{unicode\.org/Public/17\.0\.0/ucd/UnicodeData\.txt}, manifest.upstream_url)
    assert_equal "ucd-txt", manifest.parser_family
  end

  def test_registry_resolves_ucd_as_an_unwired_manual_module
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ucd"]
    refute_nil entry, "ucd must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ucd, entry.adapter_class
    assert entry.feature_module?, "ucd is a character-identity instrument (kind: module), no doc rows"
    refute entry.wired, "flips after the owner-fired first sync + eyeball"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_mints_no_documents
    assert_empty Nabu::Adapters::Ucd.new.discover(Dir.pwd).to_a
  end

  def test_parse_is_unreachable
    ref = Nabu::DocumentRef.new(source_id: "ucd", id: "urn:nabu:ucd:x", path: "x")
    assert_raises(Nabu::ParseError) { Nabu::Adapters::Ucd.new.parse(ref) }
  end

  def test_remote_probe_heads_the_versioned_dump
    assert_equal :http_zip, Nabu::Adapters::Ucd.remote_probe_strategy
    targets = Nabu::Adapters::Ucd.http_probe_targets
    assert_equal 1, targets.size
    assert_equal "UnicodeData.txt", targets[0].label
    assert_match(/UnicodeData\.txt\z/, targets[0].zip_url)
    assert_nil targets[0].metadata_url, "the identity file has no separate metadata endpoint"
  end
end
