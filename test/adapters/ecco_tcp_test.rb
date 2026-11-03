# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::EccoTcp: ECCO-TCP — the Text Creation Partnership's
# keyed selection from Eighteenth Century Collections Online, on the
# eebo-tcp shape (the TcpCollection base over the tcp-xml family;
# TcpBoxFetch over the TCP's own ECCO Box folder, both P4 classes).
#
# Fixtures (test/fixtures/ecco-tcp/, retrieved 2026-11-03 — see its
# README): three REAL P4 texts — Gray's "Ode on a distant prospect of
# Eton College" (K041165.000, released, 1747, ECLL), the physicians'
# report on William III's dissection (K021105.000, released, 1702, ECMS),
# Smollett's "The tears of Scotland" (K049384.000, unedited, "1746?]") —
# plus the Oxford P5 and SGML copies of the Gray ode, the rejected grains,
# pinned beside its P4 file.
class EccoTcpTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  REPORT = "urn:nabu:ecco-tcp:K021105.000"
  GRAY = "urn:nabu:ecco-tcp:K041165.000"
  SMOLLETT = "urn:nabu:ecco-tcp:K049384.000"

  SHARED = "https://app.box.com/s/6jbuf443i145f97c4t56z3garu3u2j09"
  P4_FOLDER_ID = 232_031_670_863
  FILE_BODIES = {
    "1342307248765" => "fetch/ecco_p4_released.zip",
    "1342302030804" => "fetch/ecco_p4_unedited.zip",
    "1342323752640" => "fetch/eebo2prf.xml.dtd"
  }.freeze

  def conformance_adapter = Nabu::Adapters::EccoTcp.new

  def conformance_workdir = Nabu::TestSupport.fixtures("ecco-tcp")

  def conformance_expected_source_id = "ecco-tcp"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_p4_text_with_its_class
    refs = adapter.discover(workdir).to_a
    assert_equal [REPORT, GRAY, SMOLLETT], refs.map(&:id),
                 "urn = the TCP id with its .000 volume suffix (IDG@ID verbatim)"
    assert_equal(%w[released released unedited], refs.map { |ref| ref.metadata["tcp_class"] })
  end

  def test_the_p5_and_sgml_copies_skip_by_rule_and_are_counted
    skips = adapter.discovery_skips(workdir)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal ["Oxford P5 XML copy, not the P4 text: texts/released/ecco_p4_released/K041165.000.p5.xml",
                  "P3 SGML copy, not the P4 text: texts/released/ecco_p4_released/K041165.000.sgm"],
                 skips.notes
  end

  # -- parse --------------------------------------------------------------------

  def test_the_idg_id_equals_the_filename_stem
    adapter.discover(workdir).each do |ref|
      assert_equal ref.id.delete_prefix("urn:nabu:ecco-tcp:"), adapter.parse(ref).metadata["idg_id"]
    end
  end

  def test_grays_ode_reads_verbatim
    document = adapter.parse(ref_for(GRAY))
    assert_equal "en", document.language
    assert_equal 105, document.count
    passages = document.to_a
    assert_equal "#{GRAY}:d2.l1", passages[4].urn
    assert_equal "YE distant Spires, ye antique Towers;", passages[4].text
    assert_equal "#{GRAY}:d2.l100", passages[103].urn
    assert_equal "'Tis Folly to be wise.", passages[103].text
  end

  def test_fixture_passage_counts_pin_the_grain
    assert_equal 21, adapter.parse(ref_for(REPORT)).count
    assert_equal 64, adapter.parse(ref_for(SMOLLETT)).count
  end

  def test_the_gale_module_and_estc_number_ride_metadata
    gray = adapter.parse(ref_for(GRAY)).metadata
    assert_equal "ECLL", gray["content_set"]
    assert_equal "T41948", gray["estc"]
    assert_equal "ECMS", adapter.parse(ref_for(REPORT)).metadata["content_set"]
    assert_equal "unedited", adapter.parse(ref_for(SMOLLETT)).metadata["tcp_class"]
  end

  def test_the_gale_module_folds_onto_the_kind_axis
    kinds = Nabu::Kinds.load(classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
                             map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml"))
    assert_equal ["literary"], kinds.normalize("ecco-tcp", adapter.parse(ref_for(GRAY)).metadata["content_set"])
    assert_equal ["scholarly"], kinds.normalize("ecco-tcp", adapter.parse(ref_for(REPORT)).metadata["content_set"])
    assert_equal ["legal"], kinds.normalize("ecco-tcp", "ECLW")
    assert_empty kinds.normalize("ecco-tcp", "ECRP"), "a multi-class subject shelf is declared, never guessed"
  end

  # -- dating + places ------------------------------------------------------------

  def test_dating_registers_in_the_metadata_dates_lane
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ecco-tcp"]
    assert_equal %w[imprint_place imprint_place_conjecture source_pub_place],
                 Nabu::Store::TimelineBuilder::MetadataDates::PLACE_KEYS["ecco-tcp"]
  end

  def test_the_imprint_year_and_town_ride_metadata
    gray = adapter.parse(ref_for(GRAY)).metadata
    assert_equal({ "not_before" => 1747, "not_after" => 1747, "raw" => "1747." }, gray["date"])
    assert_equal "London", gray["imprint_place"]
    smollett = adapter.parse(ref_for(SMOLLETT)).metadata
    assert_equal({ "raw" => "1746?]" }, smollett["date"], "?-marked years mint no bounds")
    assert_equal "Edinburgh", smollett["imprint_place_conjecture"]
  end

  # -- license + manifest ---------------------------------------------------------

  def test_the_cc0_waiver_maps_every_fixture_open
    adapter.discover(workdir).each do |ref|
      assert_equal "open", adapter.parse(ref).license_override, ref.id
    end
  end

  def test_manifest_records_the_cc0_terms
    manifest = adapter.manifest
    assert_equal "ecco-tcp", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "tcp-xml", manifest.parser_family
    assert_includes manifest.license, "CC0 1.0 Public Domain Dedication"
    assert_equal SHARED, manifest.upstream_url
    assert_equal ".ecco-tcp-fetch.json", Nabu::Adapters::EccoTcp.http_probe_targets.first.state_file
  end

  # -- fetch --------------------------------------------------------------------

  def test_fetch_walks_the_box_folder_and_unpacks_the_flat_zips
    stub_box!
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::EccoTcp.new(delay: 0).fetch(dir)
      assert_match(/2 zips listed, 2 fetched, 0 unchanged; 3 texts on disk/, report.notes)
      assert File.file?(File.join(dir, "texts", "released", "ecco_p4_released", "K041165.000.p4.xml"))
      assert File.file?(File.join(dir, "texts", "unedited", "ecco_p4_unedited", "K049384.000.p4.xml"))
      assert File.file?(File.join(dir, "eebo2prf.xml.dtd"))
      assert_equal [REPORT, GRAY, SMOLLETT], adapter.discover(dir).map(&:id)
      assert_not_requested :get, "#{SHARED}/folder/232032781362" # p5 — never walked
      assert_not_requested :get, "#{SHARED}/folder/232035311562" # p3 — never walked
    end
  end

  # -- store --------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "ecco-tcp", name: "ECCO-TCP",
                                        adapter_class: "Nabu::Adapters::EccoTcp", license_class: "open")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 190, db[:passages].count, "21 + 105 + 64 across the three fixture texts"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, second.skipped
    assert_equal 190, db[:passages].count
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def download_url(file_id)
    "https://app.box.com/index.php?rm=box_v2_download_shared_file&" \
      "shared_name=6jbuf443i145f97c4t56z3garu3u2j09&file_id=f_#{file_id}"
  end

  def stub_box!
    stub_request(:get, SHARED).to_return(status: 200, body: File.read(File.join(workdir, "fetch", "root.html")))
    stub_request(:get, "#{SHARED}/folder/#{P4_FOLDER_ID}")
      .to_return(status: 200, body: File.read(File.join(workdir, "fetch", "p4.html")))
    FILE_BODIES.each do |file_id, relpath|
      stub_request(:get, download_url(file_id))
        .to_return(status: 200, body: File.binread(File.join(workdir, *relpath.split("/"))))
    end
  end
end
