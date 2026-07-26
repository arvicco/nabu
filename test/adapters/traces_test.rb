# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Traces (P46-2): the TraCES TEI-Ling export — 15 files /
# 75,440 morphologically analyzed Gǝʿǝz word tokens (Matthew, Kebra nagast
# prologue, royal chronicles, Testamentum Domini, Gadla Libānos excerpts,
# and the Aksumite royal inscriptions RIE 187-232), every token lemma-linked
# into the Dillmann entry files. Fixture: two whole real inscriptions plus
# the stray Alpheios export the adapter must skip — see
# test/fixtures/traces/README.md.
#
# THE D46-b LICENSE (owner-ratified 2026-07-26): the repo carries no license;
# the official archive deposit governs — CC BY-NC-ND 4.0 (fdr.uni-hamburg.de
# record 707, DOI 10.25592/uhhfdm.707) → class nc, MCP default-excluded.
class TracesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  RIE193II = "urn:nabu:traces:rie193ii"
  RIE232 = "urn:nabu:traces:rie232"

  # The Dillmann entry the RIE 232 opening token (ሞተት "she died") lemmatizes
  # to — the cross-shelf crosswalk anchor (test/fixtures/dillmann).
  MOTA = "L2d417be91261494990015aae6b9b5d81"

  def conformance_adapter = Nabu::Adapters::Traces.new

  def conformance_workdir = Nabu::TestSupport.fixtures("traces")

  def conformance_expected_source_id = "traces"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover: the curated census + the Alpheios skip -----------------------

  def test_discover_yields_the_teiling_files_under_curated_ids
    refs = adapter.discover(workdir).to_a
    assert_equal [RIE193II, RIE232], refs.map(&:id),
                 "curated filename census ids, sorted; the stray Alpheios export never becomes a ref"
    assert(refs.all? { |ref| ref.source_id == "traces" })
  end

  def test_discovery_skips_census_counts_the_alpheios_stray
    skips = adapter.discovery_skips(workdir)
    assert_equal 1, skips.skipped_by_rule, "the non-TEILing Alpheios export skips by rule"
    assert_equal 0, skips.unrecognized
  end

  def test_the_upstream_corresp_typo_never_reaches_a_urn
    document = adapter.parse(ref_for(RIE193II))
    assert_equal RIE193II, document.urn, "ids come from the curated census, not the header"
    assert_equal "REI193", document.metadata["corresp"],
                 "the upstream typo (REI for RIE) rides metadata verbatim — canonical means canonical"
  end

  # -- the token grain --------------------------------------------------------

  def test_rie232_parses_one_passage_per_graphunit_in_order
    document = adapter.parse(ref_for(RIE232))
    assert_equal "gez", document.language
    assert_equal 53, document.count, "53 graphunits in the Giḥo inscription"
    first = document.first
    assert_equal "#{RIE232}:w1", first.urn
    assert_equal "ሞተት", first.text, "the passage text is the fidäl form"
    assert_equal "motat", first.annotations["translit"]
    assert_equal (1..53).map { |k| "#{RIE232}:w#{k}" }, document.map(&:urn)
  end

  def test_morphology_rides_the_token_annotations
    first = adapter.parse(ref_for(RIE232)).first
    token = first.annotations["tokens"].first
    assert_equal "motat", token["form"]
    assert_equal "Verb", token["pos"]
    assert_equal "Perfect", token["tam"]
    assert_equal "Third", token["person"]
    assert_equal "Feminine", token["gender"]
    assert_equal "Singular", token["number"]
  end

  def test_proclitic_graphunits_split_into_multiple_tokens
    document = adapter.parse(ref_for(RIE232))
    warha = document.find { |p| p.text == "በወርኀ" } || flunk("no በወርኀ graphunit")
    assert_equal %w[ba warḫa], warha.annotations["tokens"].map { |t| t["form"] },
                 "ba-warḫa: the proclitic preposition and the noun are separate analyzed tokens"
    assert_equal(%w[በ ወርኅ], warha.annotations["tokens"].map { |t| t["lemma"] })
  end

  # -- the Dillmann crosswalk (the lex lemma link) ----------------------------

  def test_lemma_links_carry_the_dillmann_entry_id_and_fidal_lemma
    first = adapter.parse(ref_for(RIE232)).first
    token = first.annotations["tokens"].first
    assert_equal MOTA, token["lex_id"], "the lex value's L-id half IS a Dillmann entry id"
    assert_equal "ሞተ", token["lemma"], "the lex value's fidäl half is the lemma"
  end

  def test_the_crosswalk_anchor_resolves_against_the_dillmann_fixture
    dillmann = Nabu::Adapters::Dillmann.new
    dillmann_dir = Nabu::TestSupport.fixtures("dillmann")
    ref = dillmann.discover(dillmann_dir).find { |r| r.id == "dillmann:#{MOTA}" } ||
          flunk("dillmann fixture must hold the ሞተ entry")
    entry = dillmann.parse(ref).first
    token = adapter.parse(ref_for(RIE232)).first.annotations["tokens"].first
    assert_equal entry.entry_id, token["lex_id"]
    assert_equal entry.headword, token["lemma"],
                 "the TraCES lemma fidäl and the Dillmann headword are the same word — " \
                 "the entry-id crosswalk is real, pinned across both fixtures"
  end

  # -- license ----------------------------------------------------------------

  def test_manifest_class_is_nc_per_the_archive_deposit
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-ND 4\.0/, manifest.license)
    assert_match(%r{10\.25592/uhhfdm\.707}, manifest.license,
                 "the archive deposit DOI is cited as the license basis (no in-repo license exists)")
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 80, db[:passages].count, "53 RIE 232 + 27 RIE 193 II graphunits"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped
    assert_equal 80, db[:passages].count
  ensure
    db&.disconnect
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_clones_the_flat_export
    Dir.mktmpdir("nabu-traces-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      traces = adapter
      traces.define_singleton_method(:repo_url) { upstream }
      report = traces.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "RIE232TEILing.xml"))
      refute_empty traces.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "traces", name: "TraCES TEI-Ling export",
      adapter_class: "Nabu::Adapters::Traces", license_class: "nc"
    )
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    FileUtils.cp(File.join(workdir, "RIE232TEILing.xml"), upstream)
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
