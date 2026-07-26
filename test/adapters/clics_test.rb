# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The CLICS³ adapter (P46-6): the Database of Cross-Linguistic
# Colexifications (Rzymski, Tresoldi et al. 2019) at the AGGREGATE
# NETWORK grain — the released clics3-network.gml artifact (2,919
# Concepticon-linked concept nodes, 4,228 colexification edges with
# family/variety/word weights AND the per-edge family list), scoped
# honestly: the 90 MB distributed sqlite's per-variety statements stay
# upstream; what this shelf serves is the family-aware pair network.
# One dictionary (slug clics, language mul), one entry per edge-bearing
# concept node. Exercised against a real trimmed subgraph — the
# in-law triangle (CHILD-IN-LAW ↔ DAUGHTER/SON-IN-LAW (OF WOMAN)).
class ClicsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("clics")

  def adapter(pin: nil)
    pin ? Nabu::Adapters::Clics.new(pin: pin) : Nabu::Adapters::Clics.new
  end

  # --- manifest ---------------------------------------------------------------------

  def test_manifest_identifies_the_clics_source
    manifest = adapter.manifest
    assert_equal "clics", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/Rzymski/, manifest.license, "the citation rides the license lane")
    assert_equal "attribution", manifest.license_class
    assert_equal "clics-gml", manifest.parser_family
  end

  def test_content_kind_is_dictionary_without_reflexes
    assert_equal :dictionary, Nabu::Adapters::Clics.content_kind
    refute Nabu::Adapters::Clics.reflex_bearing?,
           "the aggregate network carries no word forms — colexification lines ride the body"
  end

  # --- discover → parse -------------------------------------------------------------

  def test_discover_yields_one_ref_for_the_network
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["clics:network"], refs.map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  def entries
    document.entries.to_h { |e| [e.entry_id, e] }
  end

  def test_parse_yields_the_mul_concept_shelf
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "clics", document.slug
    assert_equal "mul", document.language, "cross-linguistic concepts — the ISO 639-2 collective"
    assert_equal %w[2264 2266 1060], document.map(&:entry_id),
                 "entry id = the node's Concepticon id, node file order"
  end

  def test_a_concept_entry_carries_gloss_field_and_attestation_census
    child = entries.fetch("1060")
    assert_equal "CHILD-IN-LAW", child.headword
    assert_equal "child-in-law", child.headword_folded
    assert_equal "Kinship", child.gloss
    assert_includes child.body, "CLICS³ concept 1060 — CHILD-IN-LAW"
    assert_includes child.body, "semantic field: Kinship; category: Person/Thing"
    assert_includes child.body, "attested in 18 varieties / 12 families / 26 words"
  end

  # THE COLEXIFICATION PAIR QUERY (the packet pin): each edge renders as a
  # ↔ line on BOTH endpoints, weights and family list verbatim.
  def test_colexification_pairs_render_symmetrically_with_family_aware_weights
    child = entries.fetch("1060")
    assert_includes child.body,
                    "↔ DAUGHTER-IN-LAW (OF WOMAN) (Concepticon 2264) — 6 families / " \
                    "7 varieties / 8 words",
                    "the per-pair variety counts"
    assert_includes child.body, "families: Atlantic-Congo; Austroasiatic; Indo-European; " \
                                "Saharan; Tai-Kadai; Yeniseian"
    daughter = entries.fetch("2264")
    assert_includes daughter.body, "↔ CHILD-IN-LAW (Concepticon 1060) — 6 families",
                    "the same edge from the other endpoint"
    assert_includes daughter.body, "↔ SON-IN-LAW (OF WOMAN) (Concepticon 2266) — 10 families / " \
                                   "21 varieties / 21 words"
  end

  def test_edges_sort_strongest_family_weight_first
    lines = entries.fetch("2264").body.lines.select { |l| l.start_with?("↔") }
    assert_equal 2, lines.size
    assert_match(/SON-IN-LAW/, lines.first, "10 families outranks 6")
    assert_match(/CHILD-IN-LAW/, lines.last)
  end

  def test_entry_ids_are_stable_across_independent_passes_and_nfc
    ids = adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id)
    assert_equal ids.uniq, ids
    assert_equal ids, adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id)
    document.each { |entry| assert_equal entry.body.unicode_normalize(:nfc), entry.body }
  end

  # --- loader round-trip ------------------------------------------------------------

  def test_loads_through_the_dictionary_loader_idempotently
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "clics", name: "CLICS3", adapter_class: "Nabu::Adapters::Clics",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: "https://github.com/clics/clics3", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)
    report = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 3, report.added
    assert_equal 0, report.errored
    assert_equal "urn:nabu:dict:clics:1060",
                 db[:dictionary_entries].where(entry_id: "1060").get(:urn)
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added + second.updated + second.withdrawn
  end

  # --- fetch (WebMock only, no network) ---------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      graphs = File.join(dir, "graphs")
      FileUtils.mkdir_p(graphs)
      FileUtils.cp(File.join(FIXTURES, "graphs", "network-3-families.gml"), graphs)
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "graphs") }
      File.binread(zip)
    end
  end

  def test_fetch_pins_the_artifact_sha_and_discovers_the_network
    body = zip_body
    stub_request(:get, Nabu::Adapters::Clics::ARTIFACT_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      report = adapter(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      refs = adapter.discover(workdir).to_a
      assert_equal ["clics:network"], refs.map(&:id),
                   "the single-top-dir zip flattens; discover finds the gml either way"
      assert_equal 3, adapter.parse(refs.first).size
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_pin
    stub_request(:get, Nabu::Adapters::Clics::ARTIFACT_URL)
      .to_return(status: 200, body: zip_body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256/, error.message)
      assert_empty Dir.glob(File.join(workdir, "**", "*.gml")), "a refused fetch leaves no tree"
    end
  end

  # --- registry ---------------------------------------------------------------------

  def test_registry_row_is_unwired_manual_on_the_etym_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["clics"]
    refute_nil entry, "config/sources.yml must register clics"
    assert entry.wired, "flipped 2026-07-26 (owner ruling \"flip all wired\"; first sync verified)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "etym"
  end
end
