# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::CllgTlgAlignment — the CLLG Sources Chrétiennes corpus's
# own SC↔TLG alignment (sc_tlg.csv) as links-journal edges, riding the
# cllg-sc adapter's reference seam: each held SC edition → the tlg:<id>
# work identity (kind=reference) and → the freed corpus's edition of the
# same work (kind=parallel-witness), the alignment row riding the detail.
# Fixture: 10 verbatim rows, test/fixtures/cllg-sc/README.md.
class CllgTlgAlignmentTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cllg-sc")

  CELSUM = "urn:cts:greekLit:tlg2042.tlg001.sc-cllg-grc1"
  CELSUM_FREED = "urn:cts:greekLit:tlg2042.tlg001.cllg-grc1"
  ANTONII = "urn:cts:greekLit:tlg2035.tlg047.sc-cllg-grc1"
  FESTAL = "urn:cts:greekLit:tlg4090.cllg001.sc-cllg-grc1"
  LITURGY = "urn:cts:greekLit:tlg3224.tlg001.sc-cllg-grc1"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::Adapters::CllgTlgAlignment.new(catalog: @catalog, journal: @journal)
  end

  def edges(kind)
    @journal[:links].where(kind: kind).order(:from_urn, :to_urn).select_map(%i[from_urn to_urn])
  end

  def detail(from, to)
    @journal[:links].where(from_urn: from, to_urn: to).get(:detail)
  end

  def test_mints_identity_and_witness_edges_from_the_aligned_rows
    result = producer.run("cllg-sc", workdir: FIXTURES)

    assert_equal 10, result.rows
    assert_equal 2, result.skipped_unmapped, "the two here-less rows name no held SC document"
    assert_equal 1, result.skipped_clash, "upstream's urn-clash verdict row is skipped by rule"
    assert_equal 6, result.identity_edges
    assert_equal 3, result.witness_edges
    assert_equal 9, result.edges_written

    assert_equal [
      ["urn:cts:greekLit:tlg0555.tlg001.sc-cllg-grc1", "tlg:0555.001"],
      [ANTONII, "tlg:2035.047"], [ANTONII, "tlg:2035.128"],
      [CELSUM, "tlg:2042.001"], [LITURGY, "tlg:3224.001"], [FESTAL, "tlg:4090.179"]
    ], edges("reference")
    assert_equal [
      ["urn:cts:greekLit:tlg0555.tlg001.sc-cllg-grc1", "urn:cts:greekLit:tlg0555.tlg001.cllg-grc1"],
      [ANTONII, "urn:cts:greekLit:tlg2035.tlg047.cllg-grc1"],
      [CELSUM, CELSUM_FREED]
    ], edges("parallel-witness")
  end

  def test_the_alignment_row_rides_the_detail_and_volumes_of_one_work_merge
    producer.run("cllg-sc", workdir: FIXTURES)

    celsum = detail(CELSUM, "tlg:2042.001")
    assert_includes celsum, "SC 132 ↔ TLG 2042.001 Contra Celsum · same-edition (irvine) · " \
                            "Contra Celsum, cited as 132, Borret 1967"
    assert_includes celsum, "SC 136 ↔ TLG 2042.001", "the second SC volume of one work joins the same edge"
    assert_equal celsum, detail(CELSUM, CELSUM_FREED), "the witness edge carries the same rows"

    festal = detail(FESTAL, "tlg:4090.179")
    assert_includes festal, "same-text-other-edition (tlg-online)",
                    "a non-TLG SC work id reaches TLG only through the alignment"
  end

  def test_rerun_is_idempotent
    first = producer.run("cllg-sc", workdir: FIXTURES)
    count = @journal[:links].count
    second = producer.run("cllg-sc", workdir: FIXTURES)

    assert_equal count, @journal[:links].count, "a re-derivation adds no row"
    assert_equal 1, second.superseded_runs, "the prior (producer, scope) run retires"
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, second.edges_written
    assert_equal 1, @journal[:link_runs].where(producer: "cllg-sc-tlg", scope: "cllg-sc").count
  end

  def test_a_workdir_without_the_csv_is_the_honest_no_op
    Dir.mktmpdir do |empty|
      result = producer.run("cllg-sc", workdir: empty)
      assert_nil result.run_id
      assert_equal 0, result.edges_written
    end
    assert_equal 0, @journal[:link_runs].count, "nothing superseded, nothing recorded"
  end

  def test_the_cllg_sc_adapter_declares_the_producer
    assert Nabu::Adapters::CllgSc.reference_edges?
    assert_instance_of Nabu::Adapters::CllgTlgAlignment,
                       Nabu::Adapters::CllgSc.reference_producer(catalog: @catalog, journal: @journal)
  end
end
