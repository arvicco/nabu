# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::SlLexicaFrancek (P95-2): the Franček portal's historical module
# as the sl-lexica reference producer — Pleteršnik↔JSV entry crosswalk
# edges with 16th-century Protestant first attestations riding the
# detail. The fixture is five REAL FR-Z entries (verbatim from the
# 2026-09-04 deposit): e000252 (Trubar 1550 attestation + KV + Svet
# 000393 + Plet 000471 — the full shape), e001308 (Prot + Plet only —
# no held pair, no edge), e001104/e000305 (single-space entries — no
# edge), e003552 (Plet only).
class SlLexicaFrancekTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("sl-lexica-francek"), "FR-zgodovina.xml")

  def setup
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @workdir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@workdir, "francek"))
    FileUtils.cp(FIXTURE, File.join(@workdir, "francek", "FR-zgodovina.xml"))
  end

  def teardown
    @journal.disconnect
    FileUtils.remove_entry(@workdir)
  end

  def producer
    Nabu::SlLexicaFrancek.new(catalog: nil, journal: @journal)
  end

  def edges
    @journal[:links].all
  end

  def test_mints_one_edge_per_held_space_pair_with_the_first_attestation
    result = producer.run("sl-lexica", workdir: @workdir)
    assert_equal 1, result.edges_written, "only e000252 keys BOTH held spaces"
    edge = edges.first
    assert_equal "urn:nabu:dict:pletersnik:000471", edge[:from_urn]
    assert_equal "urn:nabu:dict:jsv:000393", edge[:to_urn]
    assert_equal "reference", edge[:kind]
    assert_includes edge[:detail], "Franček e000252"
    assert_includes edge[:detail], "first attested: Primož Trubar, Katekizem, 1550",
                    "the crosswalk's philological payoff rides the edge"
  end

  def test_single_space_entries_mint_nothing
    producer.run("sl-lexica", workdir: @workdir)
    assert_equal 1, edges.size,
                 "Prot-only/Plet-only/Svet-only entries have one end — never an invented urn"
  end

  def test_reruns_supersede_and_a_missing_module_supersedes_to_zero
    producer.run("sl-lexica", workdir: @workdir)
    second = producer.run("sl-lexica", workdir: @workdir)
    assert_equal 1, second.superseded_runs
    assert_equal 1, edges.size, "reruns supersede, never accrete"

    bare = Dir.mktmpdir
    begin
      third = producer.run("sl-lexica", workdir: bare)
      assert_equal 0, third.edges_written, "a pre-refetch tree without the module is honest zero"
    ensure
      FileUtils.remove_entry(bare)
    end
  end

  def test_the_adapter_declares_the_producer_seam
    assert Nabu::Adapters::SlLexica.reference_edges?
    assert_instance_of Nabu::SlLexicaFrancek,
                       Nabu::Adapters::SlLexica.reference_producer(catalog: nil, journal: @journal)
  end
end
