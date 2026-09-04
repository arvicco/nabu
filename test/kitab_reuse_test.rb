# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::KitabReuse + Adapters::KitabReuse (P96-5): document-grain
# kind=reuse edges from the KITAB stats TSV over the held openiti
# corpus. The fixture is the REAL release header + its first four rows
# (retrieved 2026-09-04, re-gzipped verbatim); the test catalog holds
# three of the eight referenced versions, so the held∩held join, the
# unheld skip and the instances floor are all exercised on real rows.
class KitabReuseTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("kitab-reuse")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    source = Nabu::Store::Source.create(slug: "openiti", name: "OpenITI",
                                        adapter_class: "X", license_class: "nc")
    {
      "Sham19Y0009763" => "urn:nabu:openiti:1349MuhammadCabdCazizKhawli.AdabNabawi.Sham19Y0009763-ara1",
      "AOCP2023090622" => "urn:nabu:openiti:0694MuhibbDinTabari.SimtThamin.AOCP2023090622-ara1",
      "JK000710" => "urn:nabu:openiti:0702IbnDaqiqCidQushayri.IhkamAhkam.JK000710-ara1"
    }.each_with_index do |(_vid, urn), i|
      Nabu::Store::Document.create(source_id: source.id, urn: urn, language: "ara",
                                   title: "t#{i}", canonical_path: "x",
                                   content_sha256: i.to_s.rjust(64, "0"))
    end
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::KitabReuse.new(catalog: @catalog, journal: @journal)
  end

  def test_held_pairs_join_and_the_floor_and_unheld_skips_are_censused
    result = producer.run(workdir: FIXTURES)
    census = result.census
    assert_equal 4, census.rows
    # Row 1: Sham19Y0009763 × AOCP2023090622, 3 instances → edge.
    # Row 2: JK000710 × AOCP2023090622, 2 instances → edge.
    # Row 3: Shamela0005978 (unheld) × AOCP2023090622 → skipped_unheld.
    # Row 4: both unheld → skipped_unheld.
    assert_equal 2, census.held_pairs
    assert_equal 2, census.skipped_unheld
    assert_equal 0, census.skipped_floor
    assert_equal 2, result.edges_written

    edge = @journal[:links].first(kind: "reuse", score: 3.0)
    assert_includes edge[:from_urn], "Sham19Y0009763"
    assert_includes edge[:to_urn], "AOCP2023090622"
    assert_includes edge[:detail], "3 aligned instances"
    assert_includes edge[:detail], "224–412 chars"
  end

  def test_reruns_supersede_and_a_missing_stats_file_is_an_honest_noop
    producer.run(workdir: FIXTURES)
    second = producer.run(workdir: FIXTURES)
    assert_equal 1, second.superseded_runs
    assert_equal 2, @journal[:links].count

    assert_nil producer.run(workdir: Dir.mktmpdir), "no stats file = nil, never an empty run"
  end

  def test_module_shape_and_producer_seam
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["kitab-reuse"]
    refute_nil entry
    assert entry.feature_module?
    assert Nabu::Adapters::KitabReuse.reference_edges?
    assert_instance_of Nabu::KitabReuse,
                       Nabu::Adapters::KitabReuse.reference_producer(catalog: @catalog,
                                                                     journal: @journal)
    assert_equal "nc", Nabu::Adapters::KitabReuse.manifest.license_class
  end
end
