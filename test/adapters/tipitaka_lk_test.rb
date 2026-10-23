# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::TipitakaLk: tipitaka.lk (Path Nirvana) — the proofread
# Buddha Jayanthi Tripiṭaka in Sinhala-script Pāli with its facing Sinhala
# translation, plus the CST aṭṭhakathā (and the Visuddhimagga) with their
# Sinhala translation, from the static JSON the site is built from
# (github.com/pathnirvana/tipitaka.lk, public/static/text/*.json).
#
# Document = (upstream file × layer): the Pāli root
# urn:nabu:tipitaka-lk:<file> (pli) and its Sinhala sibling
# urn:nabu:tipitaka-lk:<file>-si (si), aligned passage-for-passage by the
# shared <page>.<entry> suffix. The Paṭṭhāna files (ap-pat*) are Pāli-only
# upstream and mint no sibling.
#
# LICENSE: CC BY-ND 4.0 + upstream's sync condition (LICENSE.md, which
# names the Buddha Jayanthi Pāli text); the Sinhala translation and the
# CST aṭṭhakathā with its Sinhala translation are covered on the same
# terms by Path Nirvana's grant (by email, 2026-10-22). No derivatives →
# research_private (the Freising ND precedent).
class TipitakaLkTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  KHP = "urn:nabu:tipitaka-lk:kn-khp"
  KHP_SI = "urn:nabu:tipitaka-lk:kn-khp-si"
  ATTA = "urn:nabu:tipitaka-lk:atta-an-11"
  ATTA_SI = "urn:nabu:tipitaka-lk:atta-an-11-si"
  PAT = "urn:nabu:tipitaka-lk:ap-pat-2-83"

  def conformance_adapter = Nabu::Adapters::TipitakaLk.new

  def conformance_workdir = Nabu::TestSupport.fixtures("tipitaka-lk")

  def conformance_expected_source_id = "tipitaka-lk"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_a_pali_root_and_a_sinhala_sibling_per_file
    refs = adapter.discover(workdir).to_a
    assert_equal [PAT, ATTA, ATTA_SI, KHP, KHP_SI], refs.map(&:id),
                 "sorted by urn; the Pāli-only Paṭṭhāna file mints no -si sibling"
    assert_equal ref_for(KHP).path, ref_for(KHP_SI).path, "both layers read the same upstream file"
    assert_equal(%w[pali sinh], [ref_for(KHP), ref_for(KHP_SI)].map { |ref| ref.metadata["layer"] })
  end

  def test_out_of_cone_grains_are_never_discovered
    # public/static/data/ (navigation tree, file map, footnote-sigla key) is
    # generated or reference data, not text — outside the fetch cone; the
    # pinned specimen proves discovery never reaches it.
    assert File.file?(File.join(workdir, "public/static/data/footnote-abbreviations.json"))
    refute(adapter.discover(workdir).any? { |ref| ref.path.include?("/static/data/") })
    skips = adapter.discovery_skips(workdir)
    assert_equal 0, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
  end

  def test_a_text_file_outside_upstreams_tree_filter_is_unrecognized
    Dir.mktmpdir("nabu-tipitaka-stray") do |root|
      text = File.join(root, "public/static/text")
      FileUtils.mkdir_p(text)
      FileUtils.cp(File.join(workdir, "public/static/text/kn-khp.json"), text)
      File.write(File.join(text, "notes.json"), "{}")
      skips = adapter.discovery_skips(root)
      assert_equal 1, skips.unrecognized, "upstream's own build warns on a file its tree filter drops"
      assert_match(/notes\.json/, skips.notes.first)
      assert_equal [KHP, KHP_SI], adapter.discover(root).map(&:id)
    end
  end

  # -- parse ------------------------------------------------------------------

  def test_root_documents_are_pali_with_canon_facets
    document = adapter.parse(ref_for(KHP))
    assert_equal "pli", document.language
    assert_equal "ඛුද්දකපාඨපාළි", document.title
    facets = document.metadata.fetch("facets")
    assert_equal "mula", facets.dig("collection", "value")
    assert_equal "sutta", facets.dig("pitaka", "value")
    assert_equal "kn", facets.dig("nikaya", "value")
    assert_match(/Buddha Jayanthi/, document.metadata["edition"])
  end

  def test_commentary_documents_carry_the_atta_collection
    document = adapter.parse(ref_for(ATTA))
    facets = document.metadata.fetch("facets")
    assert_equal "atta", facets.dig("collection", "value"), "upstream's own collection field"
    assert_equal "sutta", facets.dig("pitaka", "value")
    assert_equal "an", facets.dig("nikaya", "value")
    assert_match(/aṭṭhakathā/, document.metadata["edition"])
  end

  def test_a_file_without_a_collection_field_falls_back_to_upstreams_filename_rule
    document = adapter.parse(ref_for(PAT))
    facets = document.metadata.fetch("facets")
    assert_equal "mula", facets.dig("collection", "value"),
                 "ap-pat files carry no collection key; upstream's isAttaFile (atta- prefix) decides"
    assert_equal "abhidhamma", facets.dig("pitaka", "value")
    assert_nil facets["nikaya"]
  end

  def test_sinhala_siblings_are_translations_aligned_by_suffix
    root = adapter.parse(ref_for(KHP))
    sibling = adapter.parse(ref_for(KHP_SI))
    assert_equal "si", sibling.language
    assert_equal "translation", sibling.metadata["kind"]
    assert_equal KHP, sibling.metadata["translation_of"]
    assert_nil sibling.metadata["facets"], "a translation sibling folds to no canon kind"
    assert_equal "බුද්ධං සරණං ගච්ඡාමි.", root.find { |p| p.urn == "#{KHP}:2.7" }.text
    assert_equal "බුදුරජුන් සරණයෙමි (පිහිට යැ යි දැන ගණිමි.)",
                 sibling.find { |p| p.urn == "#{KHP_SI}:2.7" }.text
  end

  def test_every_passage_carries_the_attribution
    adapter.discover(workdir).each do |ref|
      assert(adapter.parse(ref).all? { |p| p.annotations["attribution"] == "tipitaka.lk" }, ref.id)
    end
  end

  # -- license ------------------------------------------------------------------

  def test_manifest_is_research_private_with_the_nd_sync_terms_and_the_grant
    manifest = adapter.manifest
    assert_equal "research_private", manifest.license_class
    assert_match(/CC BY-ND 4\.0/, manifest.license)
    assert_match(/sync/i, manifest.license)
    assert_match(/Path Nirvana.*2026-10-22/, manifest.license, "the grant covering the Sinhala and aṭṭhakathā layers")
  end

  # -- store: idempotent load ---------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 5, first.added
    assert_equal 0, first.errored
    assert_equal 227, db[:passages].count,
                 "kn-khp 66 pli + 67 si · atta-an-11 42 pli + 41 si · ap-pat-2-83 11 pli"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 5, second.skipped
    assert_equal 227, db[:passages].count
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) ---------------------------------------

  def test_fetch_sparse_clones_the_text_cone
    Dir.mktmpdir("nabu-tipitaka-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      tipitaka = adapter
      tipitaka.define_singleton_method(:repo_url) { upstream }
      report = tipitaka.fetch(work)

      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "public/static/text/kn-khp.json")), "the text cone materializes"
      refute File.exist?(File.join(work, "public/static/data")), "the generated data dir stays out"
      refute File.exist?(File.join(work, "dev")), "dev/ (alignments, word lists) stays out"
      assert_equal 5, tipitaka.discover(work).count
    end
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "tipitaka-lk", name: "tipitaka.lk",
      adapter_class: "Nabu::Adapters::TipitakaLk", license_class: "research_private"
    )
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "dev", "alignments"))
    FileUtils.cp_r(File.join(workdir, "public"), upstream)
    File.write(File.join(upstream, "dev", "alignments", "README.md"), "stub\n")
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
