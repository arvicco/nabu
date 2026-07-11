# frozen_string_literal: true

require "test_helper"

# ISWOC adapter tests (P12-1). The ISWOC Treebank (Bech & Eide, University of
# Oslo) ships the *identical* PROIEL 2.1 XML shape as proiel/torot, so the
# adapter is another thinnest-subclass — manifest override plus exactly one
# new behavior: the `ang` language filter (the repo carries ten medieval
# Romance texts outside the corpus's scope; they are excluded by the peeked
# <source language>, never by filename). These tests run the full
# AdapterConformance battery over the two OE fixtures (wscp, 150 sentences;
# æls, 20 sentences) with a real Old French file (eustace) present on disk as
# the exclusion probe (owner-approved third fixture), plus ISWOC-specific
# assertions: the shared urn:nabu:proiel: namespace, the non-ASCII æls urn,
# verse-style MARK citation-parts (the P11-3 hub's witness #8), real OE
# snippets, and registry round-trip. No network.
class IswocTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/iswoc", __dir__)

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Iswoc.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "iswoc"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Iswoc.manifest
    assert_equal "iswoc", manifest.id
    assert_equal "ISWOC Treebank — Old English texts", manifest.name
    assert_equal "nc", manifest.license_class
    assert_equal "CC BY-NC-SA 3.0 (per-source headers; repo README, no LICENSE file)", manifest.license
    assert_equal "https://github.com/iswoc/iswoc-treebank", manifest.upstream_url
    assert_equal "proiel", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::Iswoc.manifest, Nabu::Adapters::Iswoc.new.manifest
  end

  # --- discover + the ang filter ------------------------------------------

  # Three source files on disk, but only the two ang ones become refs — the
  # Old French eustace (language="fro") is dropped by the language filter,
  # not by filename. Sorted by id: wscp before æls (byte order; æ > w).
  def test_discover_yields_only_the_old_english_refs_under_the_shared_proiel_namespace
    refs = Nabu::Adapters::Iswoc.new.discover(FIXTURES).to_a
    assert_equal ["urn:nabu:proiel:wscp", "urn:nabu:proiel:æls"], refs.map(&:id)
    refs.each do |ref|
      assert_equal "iswoc", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path)
    end
  end

  def test_the_exclusion_probe_is_real_and_really_excluded
    # Guard the guard: the fro fixture must exist on disk (otherwise the
    # filter test above passes vacuously) and must carry the non-ang header.
    probe = File.join(FIXTURES, "eustace-head.xml")
    assert File.file?(probe), "exclusion probe fixture missing"
    assert_includes File.read(probe, 8_192), '<source id="eustace" language="fro">'
    ids = Nabu::Adapters::Iswoc.new.discover(FIXTURES).map(&:id)
    refute_includes ids, "urn:nabu:proiel:eustace"
  end

  def test_discover_resolves_per_source_language_and_title
    refs = Nabu::Adapters::Iswoc.new.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
    wscp = refs.fetch("urn:nabu:proiel:wscp")
    assert_equal "ang", wscp.metadata["language"]
    assert_equal "West-Saxon Gospels", wscp.metadata["title"]
    aels = refs.fetch("urn:nabu:proiel:æls")
    assert_equal "ang", aels.metadata["language"]
    assert_equal "Ælfric's Lives of Saints", aels.metadata["title"]
  end

  # --- the non-ASCII æls urn (P12-1 URN-mint policy check) ------------------

  # æls is the corpus's first non-ASCII source id. The urn preserves it
  # verbatim in NFC (æ = U+00E6, a single codepoint — nothing to normalize
  # away), and parse round-trips it as the document urn.
  def test_aels_urn_preserves_the_non_ascii_source_id_in_nfc
    urn = "urn:nabu:proiel:æls"
    assert_equal urn, urn.unicode_normalize(:nfc)
    refs = Nabu::Adapters::Iswoc.new.discover(FIXTURES).map(&:id)
    assert_includes refs, urn
  end

  # --- parse round-trip ---------------------------------------------------

  def test_parse_wscp_yields_old_english_mark_with_verse_citations
    adapter = Nabu::Adapters::Iswoc.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:proiel:wscp" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal "ang", document.language
    assert_equal "West-Saxon Gospels", document.title
    assert_equal 150, document.size
    # The div inventory is Matthew 7 (1-sentence boundary fragment) then Mark
    # 1-2. First passage = the MATT fragment; second = Mark 1:1 with the
    # native verse-style citation-part the P11-3 alignment hub keys on.
    matt = document.first
    assert_equal "urn:nabu:proiel:wscp:100491", matt.urn
    assert_equal "MATT 7.27", matt.annotations.fetch("citation")
    mark = document.to_a.fetch(1)
    assert_equal "urn:nabu:proiel:wscp:102271", mark.urn
    assert_equal "MARK 1.1", mark.annotations.fetch("citation")
    assert mark.text.start_with?("Her ys godspellys angyn hælyndes Cristes Godes suna."),
           "unexpected Mark 1:1 text: #{mark.text[0, 60].inspect}"
  end

  def test_parse_aels_yields_old_english_prose_with_a_real_snippet
    adapter = Nabu::Adapters::Iswoc.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:proiel:æls" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal "ang", document.language
    assert_equal "Ælfric's Lives of Saints", document.title
    assert_equal 20, document.size
    # First sentence (upstream id 107806) opens the life of St Eugenia.
    assert document.first.text.start_with?("Mæg gehyran se ðe wyle be þam halgan mædene Eugenian"),
           "unexpected æls first-sentence prefix: #{document.first.text[0, 60].inspect}"
  end

  # --- fetch identity (identity via #manifest, not the constant) ------------

  # The inherited Proiel#fetch resolves its repo through #repo_url, which must
  # follow the subclass manifest — otherwise an ISWOC sync would clone
  # proiel-treebank. (No network exercised; this asserts the URL only.)
  def test_repo_url_targets_the_iswoc_repo_not_the_inherited_proiel_repo
    assert_equal "https://github.com/iswoc/iswoc-treebank",
                 Nabu::Adapters::Iswoc.new.send(:repo_url)
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_iswoc_frozen_and_disabled_until_first_sync
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["iswoc"]
    refute_nil entry, "iswoc must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Iswoc, entry.adapter_class
    assert_equal "iswoc", entry.manifest.id
    assert_equal "frozen", entry.sync_policy
    assert entry.enabled, "iswoc is live (owner sign-off 2026-07-11 after first sync + eyeball)"
    assert_equal Nabu::Adapters::Iswoc.manifest, entry.manifest
  end
end
