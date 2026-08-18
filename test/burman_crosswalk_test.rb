# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::BurmanCrosswalk (P77-r19) + the burman-concordance instrument
# adapter: the concordance CSV → kind=reference edges from open-etruscan
# CIE urns to the tm:<id> identity hub, the full concordance line in the
# detail; rows without the CIE+TM pair unmapped-counted, never guessed.
class BurmanCrosswalkTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("burman-concordance")

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def crosswalk
    Nabu::BurmanCrosswalk.new(catalog: @catalog, journal: @journal)
  end

  def test_mints_cie_to_tm_edges_with_the_concordance_line_as_detail
    result = crosswalk.run("burman-concordance", workdir: FIXTURES)

    assert_equal 7, result.edges_written, "seven fixture rows carry the CIE+TM pair"
    assert_equal 2, result.skipped_unmapped, "the two CIE-less rows are counted, never guessed"

    edges = @journal[:links].where(kind: "reference").all
    first = edges.find { |edge| edge[:to_urn] == "tm:145534" }
    refute_nil first
    assert_equal "urn:nabu:open-etruscan:cie-1", first[:from_urn],
                 "Burman's zero-padded CIE 00001 joins open-etruscan's unpadded cie-1"
    assert_includes first[:detail], "CIE 00001"
    assert_includes first[:detail], "ET1 Fs 1.0001"
    assert_includes first[:detail], "CII 0104"
  end

  def test_rerun_supersedes_the_prior_run_and_rederives_stably
    crosswalk.run("burman-concordance", workdir: FIXTURES)
    second = crosswalk.run("burman-concordance", workdir: FIXTURES)
    assert_equal 1, second.superseded_runs, "the prior (producer, scope) run retires"
    assert_equal 7, second.superseded_edges
    assert_equal 7, second.edges_written, "the re-derivation re-mints the same seven edges"
  end

  def test_a_workdir_without_the_csv_is_the_honest_no_op
    Dir.mktmpdir do |empty|
      result = crosswalk.run("burman-concordance", workdir: empty)
      assert_nil result.run_id
      assert_equal 0, result.edges_written
    end
  end

  # -- the instrument adapter ------------------------------------------------

  def test_registry_resolves_the_instrument_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["burman-concordance"]
    refute_nil entry
    assert entry.wired, "channel verified (the 2026-08-18 wired-semantics ruling)"
    assert_includes entry.axes, "italic"
  end

  def test_discover_mints_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::BurmanConcordance.new
    assert_empty adapter.discover(FIXTURES).to_a, "a links instrument mints no documents"
    ref = Nabu::DocumentRef.new(source_id: "burman-concordance", id: "urn:x", path: "/x")
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  def test_the_producer_rides_the_reference_seam
    producer = Nabu::Adapters::BurmanConcordance.reference_producer(catalog: @catalog, journal: @journal)
    assert_instance_of Nabu::BurmanCrosswalk, producer
  end
end
