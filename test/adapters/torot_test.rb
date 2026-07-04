# frozen_string_literal: true

require "test_helper"

# TOROT adapter tests (P3-5). TOROT (Tromsø Old Russian and OCS Treebank) ships
# the *identical* PROIEL 2.1 XML shape as the proiel-treebank, so the adapter is
# the thinnest subclass of the phase: it overrides only the manifest and inherits
# discover/peek/parse/fetch wholesale (the First1kGreek<Perseus pattern). These
# tests run the full AdapterConformance battery over BOTH real fixtures (peter,
# 11 sentences, orv; zogr, 62 sentences, chu) plus TOROT-specific assertions:
# the shared urn:nabu:proiel: namespace, per-source languages, a real Old East
# Slavic snippet (peter) and a real OCS snippet (zogr), empty-token retention,
# and registry round-trip. No network (conformance/registry against fixtures).
class TorotTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/torot", __dir__)

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Torot.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "torot"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Torot.manifest
    assert_equal "torot", manifest.id
    assert_equal "TOROT — Tromsø Old Russian and OCS Treebank", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "CC BY-NC-SA 3.0 (per-source headers; repo README, no LICENSE file)", manifest.license
    assert_equal "https://github.com/torottreebank/treebank-releases", manifest.upstream_url
    assert_equal "proiel", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::Torot.manifest, Nabu::Adapters::Torot.new.manifest
  end

  # --- discover -----------------------------------------------------------

  # Two source files → two refs, sorted by id, minting under the SHARED
  # urn:nabu:proiel: namespace (a deliberate decision documented in the adapter
  # header: TOROT source ids come from the same PROIEL id-space).
  def test_discover_yields_two_sorted_refs_under_the_shared_proiel_namespace
    refs = Nabu::Adapters::Torot.new.discover(FIXTURES).to_a
    assert_equal ["urn:nabu:proiel:peter", "urn:nabu:proiel:zogr"], refs.map(&:id)
    refs.each do |ref|
      assert_equal "torot", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path)
    end
  end

  def test_discover_resolves_per_source_language_and_title
    refs = Nabu::Adapters::Torot.new.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
    peter = refs.fetch("urn:nabu:proiel:peter")
    assert_equal "orv", peter.metadata["language"]
    assert_equal "Correspondence of Peter the Great", peter.metadata["title"]
    zogr = refs.fetch("urn:nabu:proiel:zogr")
    assert_equal "chu", zogr.metadata["language"]
  end

  def test_non_xml_files_in_the_workdir_are_ignored
    # The fixtures dir also holds README.md; the inherited *.xml glob skips it,
    # so discover yields exactly the two treebank documents and never errors.
    ids = Nabu::Adapters::Torot.new.discover(FIXTURES).map(&:id)
    assert_equal ["urn:nabu:proiel:peter", "urn:nabu:proiel:zogr"], ids
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_peter_yields_old_east_slavic_document_with_a_real_snippet
    adapter = Nabu::Adapters::Torot.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:proiel:peter" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal "orv", document.language
    assert_equal "Correspondence of Peter the Great", document.title
    assert_equal 11, document.size
    # First sentence (upstream id 219339) opens the letter to Peter's mother.
    assert document.first.text.start_with?("Вселюбезенейшей"),
           "unexpected peter first-sentence prefix: #{document.first.text[0, 40].inspect}"
  end

  def test_parse_zogr_yields_ocs_document_with_a_real_marianus_family_snippet
    adapter = Nabu::Adapters::Torot.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:proiel:zogr" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal "chu", document.language
    assert_equal 62, document.size
    # Codex Zographensis, first kept sentence (id 75108): "тъ васъ крьститъ …".
    assert_includes document.first.text, "тъ васъ крьститъ"
  end

  # --- empty tokens (heavy in TOROT) --------------------------------------

  def test_empty_tokens_are_retained_in_annotations_but_absent_from_text
    adapter = Nabu::Adapters::Torot.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:proiel:peter" }
    # peter's first sentence (219339) closes with the empty verb token 2340186
    # (empty-token-sort="V", no form) — a null node of the dependency tree.
    first = adapter.parse(ref).first
    tokens = first.annotations.fetch("tokens")
    empty = tokens.find { |token| token["id"] == "2340186" }
    refute_nil empty, "empty token 2340186 must be retained in annotations"
    assert_equal "V", empty["empty_token_sort"]
    refute empty.key?("form"), "empty tokens carry no form"
    refute_includes first.text, "2340186", "empty-token ids never leak into surface text"
  end

  # --- fetch identity (base fix: identity via #manifest, not the constant) --

  # The inherited Proiel#fetch resolves its repo through #repo_url, which must
  # follow the subclass manifest — otherwise a TOROT sync would clone
  # proiel-treebank. (No network exercised; this asserts the URL only.)
  def test_repo_url_targets_the_torot_repo_not_the_inherited_proiel_repo
    assert_equal "https://github.com/torottreebank/treebank-releases",
                 Nabu::Adapters::Torot.new.send(:repo_url)
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_torot_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["torot"]
    refute_nil entry, "torot must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Torot, entry.adapter_class
    assert_equal "torot", entry.manifest.id
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Torot.manifest, entry.manifest
  end
end
