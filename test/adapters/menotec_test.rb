# frozen_string_literal: true

require "test_helper"

# Menotec adapter tests (P40-2). Menotec (Old Norwegian treebanks + the Poetic
# Edda / Codex Regius) is served only through the CLARINO INESS session API;
# its get-sentences export is a BLANK-LINE-SEPARATED stream of per-sentence
# PROIEL-XML fragments, so the adapter reuses the PROIEL token/morph shape via
# the sibling MenotecStreamParser (see its header for the compose-vs-sibling
# choice). One treebank = one nabu Document; passages key on sentence/@id;
# Menota / island-id back-references ride each token's `foreign_ids`. These
# tests run the full AdapterConformance battery over the two fixture treebanks
# (Pamphilus + Alvíssmál, 5 sentence blocks each) plus Menotec-specific
# assertions. No network.
class MenotecTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/menotec", __dir__)

  PAMPHILUS = "urn:nabu:menotec:non-pamphilus-dep"
  EDDA = "urn:nabu:menotec:non-edda-regius-dep"

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Menotec.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "menotec"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Menotec.manifest
    assert_equal "menotec", manifest.id
    assert_equal "nc", manifest.license_class
    assert_equal "menotec", manifest.parser_family
    assert_equal "https://clarino.uib.no/iness", manifest.upstream_url
    assert_includes manifest.license, "CC-BY-NC-SA", "the CC BY-NC-SA grant is recorded verbatim"
  end

  def test_no_git_remote_probe_target
    # No ls-remote-able upstream: the INESS session API takes the no-network
    # probe treatment (the vendored-no-git precedent).
    assert_empty Nabu::Adapters::Menotec.upstream_repo_urls
  end

  # --- discover -----------------------------------------------------------

  def test_discover_yields_one_ref_per_treebank_subdirectory_sorted
    refs = Nabu::Adapters::Menotec.new.discover(FIXTURES).to_a
    assert_equal [EDDA, PAMPHILUS], refs.map(&:id), "sorted by urn (edda < pamphilus)"
    refs.each do |ref|
      assert_equal "menotec", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.directory?(ref.path), "a ref points at its treebank subdir"
    end
    assert_equal "non-pamphilus-dep",
                 refs.find { |r| r.id == PAMPHILUS }.metadata.fetch("treebank")
  end

  def test_discover_skips_dotdirs_so_the_attic_is_not_a_treebank
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "non-pamphilus-dep"))
      FileUtils.cp(File.join(FIXTURES, "non-pamphilus-dep", "ch1-head5.xml"),
                   File.join(dir, "non-pamphilus-dep", "ch1-head5.xml"))
      FileUtils.mkdir_p(File.join(dir, ".attic", "non-strengleikar-dep"))
      ids = Nabu::Adapters::Menotec.new.discover(dir).map(&:id)
      assert_equal ["urn:nabu:menotec:non-pamphilus-dep"], ids
    end
  end

  # --- parse: Pamphilus ---------------------------------------------------

  def test_parse_pamphilus_yields_five_sentences_with_the_proiel_token_shape
    adapter = Nabu::Adapters::Menotec.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == PAMPHILUS }
    document = adapter.parse(ref)
    assert_equal PAMPHILUS, document.urn
    assert_equal "non", document.language
    assert_equal "Pamphilus", document.title
    assert_equal 5, document.size

    first = document.first
    assert_equal "urn:nabu:menotec:non-pamphilus-dep:198377", first.urn,
                 "passages key on the sentence/@id (the PROIEL convention)"
    assert_equal "EC EM SÆRÐR.", first.text,
                 "surface reconstructed from the tokens' presentation attributes"
    assert_equal "reviewed", first.annotations.fetch("status")
    tokens = first.annotations.fetch("tokens")
    assert_equal 3, tokens.size
    assert_equal(%w[EC EM SÆRÐR], tokens.map { |t| t.fetch("form") })
    assert_equal "ek", tokens.first.fetch("lemma")
    assert_equal "Pp", tokens.first.fetch("part_of_speech")
    assert_equal "menota-id=w00001", tokens.first.fetch("foreign_ids"),
                 "Menota ids are kept verbatim on the token annotations"
    refute first.annotations.key?("citation"), "Pamphilus tokens carry no citation-part"
  end

  # --- parse: Poetic Edda / Alvíssmál -------------------------------------

  def test_parse_edda_yields_old_icelandic_under_non_with_citation_and_island_ids
    adapter = Nabu::Adapters::Menotec.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == EDDA }
    document = adapter.parse(ref)
    assert_equal EDDA, document.urn
    assert_equal "non", document.language, "the Edda rides the treebank's own non tag"
    assert_equal "Poetic Edda (Codex Regius)", document.title
    assert_equal 5, document.size

    first = document.first
    assert_equal "urn:nabu:menotec:non-edda-regius-dep:144889", first.urn
    assert_equal "Bekki breiða,", first.text
    assert_equal "Alvíssmál 1", first.annotations.fetch("citation"),
                 "the citation-part is surfaced as the passage citation"
    assert_equal "island-id=19992", first.annotations.fetch("tokens").first.fetch("foreign_ids")
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_menotec_disabled_manual_until_first_sync
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["menotec"]
    refute_nil entry, "menotec must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Menotec, entry.adapter_class
    assert_equal "menotec", entry.manifest.id
    refute entry.enabled, "menotec is enabled: false until the owner-fired first sync"
    assert_equal "manual", entry.sync_policy
    assert entry.source?, "menotec is a plain source row"
    assert_includes entry.axes, "germanic"
  end
end
