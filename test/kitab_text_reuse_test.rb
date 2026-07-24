# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::KitabTextReuse (P43-4): producer #9 for the links journal — the KITAB
# Text Reuse instrument over the held OpenITI corpus (pilot scope). Reads the
# canonical pairwise TSV tree (passim alignments) and mints ONE kind="reuse"
# edge per alignment row, from book1's passage at milestone seq1 to book2's
# passage at milestone seq2. Exercised against the two REAL staged files
# (retrieved 2026-07-24) laid out as the canonical tree stores them.
#
# The version ids (ALCorpus00001-ara2, Shia004016-ara1, PV20230224-ara1) each
# resolve to a held openiti document — the vid is the version_uri's last
# dotted segment. Milestone→passage resolution reads the openiti passages'
# raw msNN tokens from annotations (padding varies — ms1 vs ms01 — normalized
# on the integer value); a seq with no held passage DOWNGRADES the edge to
# document grain, censused, never dropped.
class KitabTextReuseTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("kitab")

  # The three held openiti documents (urn = author.book.<version-id>; the KITAB
  # vid is the trailing dotted segment). ALCorpus carries a PADDED milestone
  # (ms01) so seq1=1 exercises the ms1-vs-ms01 normalization.
  ALC_URN = "urn:nabu:openiti:0001TestAuthor.Book.ALCorpus00001-ara2"
  ALC_P1  = "#{ALC_URN}:1.1.1".freeze   # milestone ms01 (padded)
  SHIA_URN = "urn:nabu:openiti:0157TestAuthor.Maqtal.Shia004016-ara1"
  SHIA_P7  = "#{SHIA_URN}:1.1.1".freeze # milestone ms7
  PV_URN = "urn:nabu:openiti:0500TestAuthor.Ziyada.PV20230224-ara1"
  PV_P449 = "#{PV_URN}:1.1.1".freeze    # milestone ms449

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::KitabTextReuse.new(catalog: @catalog, journal: @journal)
  end

  # --- minting: one reuse edge per alignment row -----------------------------

  def test_mints_one_reuse_edge_per_row_across_the_pilot_fan
    seed_openiti!
    result = producer.run("kitab", workdir: FIXTURES)

    assert_equal 2, result.files, "both pilot TSVs read"
    assert_equal 84, result.rows_read, "1 (single) + 83 (multi) alignment rows"
    assert_equal 0, result.unheld_book_files, "every vid resolves to a held openiti document"
    assert_equal ["reuse"], @journal[:links].select_map(:kind).uniq,
                 "a NEW kind, distinct from nabu's own kind=parallel intertext detection"
    assert_equal [nil], @journal[:links].select_map(:score).uniq,
                 "an upstream-computed alignment is not a mined similarity score"
    assert_equal 4, @journal[:links].count,
                 "4 distinct passage/document pairs (write_edge! keeps one edge per unordered pair per kind)"
  end

  # --- the fully-resolved passage-grain edge, pinned -------------------------

  def test_pins_the_passage_grain_edge_with_offsets_verbatim
    seed_openiti!
    producer.run("kitab", workdir: FIXTURES)

    edge = edge_between(ALC_P1, SHIA_P7)
    refute_nil edge, "seq1=1 (ms01) and seq2=7 both resolve to held passages"
    assert_equal "reuse", edge[:kind]
    assert_nil edge[:score]
    assert_equal "seq 1→7 · b1:b2 1460:759 · e1:e2 1659:959 · bw1:bw2 261:145 · ew1:ew2 298:182",
                 edge[:detail], "the reader can find the exact span from the verbatim offsets"
  end

  def test_padded_milestone_normalizes_on_integer_value
    seed_openiti!
    producer.run("kitab", workdir: FIXTURES)
    # ALC_P1 carries "ms01" (padded); seq1=1 must still resolve to it.
    refute_nil edge_between(ALC_P1, SHIA_P7),
               "ms01 (padded) resolves seq1=1 — normalization is on the integer, not the token"
  end

  # --- the document-grain downgrade + census ---------------------------------

  def test_seq_outside_our_parse_downgrades_to_document_grain
    seed_openiti!
    result = producer.run("kitab", workdir: FIXTURES)

    # multi file: only (seq1=1,seq2=449) fully resolves; the other 82 rows have
    # seq1>=2 (no held passage) and/or seq2>=450 → document-grain fallback.
    assert_equal 82, result.downgraded_rows,
                 "every row a milestone cannot place falls back to the book's document urn, censused"

    doc_edge = edge_between(ALC_URN, PV_URN)
    refute_nil doc_edge, "the both-sides-unresolved rows collapse to one book↔book reuse edge"
    assert_equal "reuse", doc_edge[:kind]
    assert_includes doc_edge[:detail], "document grain",
                    "the downgraded edge names the fallback and still carries a row's seqs+offsets"

    # the passage-grain PV edge (seq1=1,seq2=449) survives beside the downgrade.
    refute_nil edge_between(ALC_P1, PV_P449), "seq2=449 resolves to a held passage"
    # seq1=1,seq2=450: from resolves, to downgrades → passage↔document mixed grain.
    refute_nil edge_between(ALC_P1, PV_URN), "a one-sided downgrade keeps the resolved side at passage grain"
  end

  # --- an unheld partner book: file skipped, censused ------------------------

  def test_a_file_whose_book_is_not_held_is_skipped_and_censused
    seed_openiti!
    Dir.mktmpdir do |dir|
      fan = File.join(dir, "pairwise", "ALCorpus00001-ara2")
      FileUtils.mkdir_p(fan)
      # book2 = NotHeld999-ara1 has no openiti document row.
      File.write(File.join(fan, "ALCorpus00001-ara2_NotHeld999-ara1.csv"),
                 "b1\tb2\tbw1\tbw2\te1\te2\tew1\tew2\tseq1\tseq2\n1\t2\t3\t4\t5\t6\t7\t8\t1\t1\n")
      result = producer.run("kitab", workdir: dir)

      assert_equal 1, result.files
      assert_equal 1, result.unheld_book_files, "a partner with no held document row skips the whole file"
      assert_equal 0, @journal[:links].count, "no edge can be minted without both endpoints"
    end
  end

  # --- kind=reuse surfaces cleanly in `nabu links` ---------------------------

  def test_reuse_kind_lists_cleanly_in_links
    seed_openiti!
    producer.run("kitab", workdir: FIXTURES)

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(ALC_P1)
    refute_nil result
    counterparts = result.groups.fetch("reuse")
    assert_includes counterparts.map(&:urn), SHIA_P7, "the reuse group lists the aligned passage"
    assert_includes counterparts.map(&:urn), PV_P449
    assert(counterparts.select { |edge| edge.urn == SHIA_P7 }.all?(&:resolved?),
           "the held counterpart resolves against the catalog")
  end

  # --- run mechanics: idempotency + supersede-scoped-to-producer -------------

  def test_rerun_supersedes_and_is_idempotent
    seed_openiti!
    first = producer.run("kitab", workdir: FIXTURES)
    second = producer.run("kitab", workdir: FIXTURES)

    assert_equal first.edges_written, second.edges_written
    assert_equal first.downgraded_rows, second.downgraded_rows
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal 4, @journal[:links].count, "the journal holds exactly the current reuse graph"
    run = @journal[:link_runs].first(id: second.run_id)
    assert_equal "kitab", run[:producer]
    assert_equal "kitab", run[:scope]
  end

  def test_supersede_is_scoped_to_this_producer
    seed_openiti!
    # a foreign producer's edge on the same passage must survive our supersede.
    foreign = Nabu::Store::LinksJournal.record_run!(@journal, producer: "parallels", scope: "openiti",
                                                              params: {}, code_version: "test")
    Nabu::Store::LinksJournal.write_edge!(@journal, from_urn: ALC_P1, to_urn: SHIA_P7,
                                                    kind: "parallel", score: 0.9, run_id: foreign)
    producer.run("kitab", workdir: FIXTURES)
    producer.run("kitab", workdir: FIXTURES)

    assert_equal 1, @journal[:links].where(kind: "parallel").count,
                 "supersede is scoped to (producer=kitab, scope=kitab) — the parallel edge is untouched"
  end

  def test_rebuild_equivalence_after_dropping_the_journal
    seed_openiti!
    producer.run("kitab", workdir: FIXTURES)
    before = reuse_edges

    @journal.disconnect
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    producer.run("kitab", workdir: FIXTURES)

    assert_equal before, reuse_edges, "identical edges re-derived from canonical + catalog"
  end

  def test_a_workdir_without_the_tree_is_a_no_op_that_supersedes_nothing
    seed_openiti!
    producer.run("kitab", workdir: FIXTURES)
    count = @journal[:links].count
    Dir.mktmpdir do |empty|
      result = producer.run("kitab", workdir: empty)
      assert_equal 0, result.edges_written
      assert_equal 0, result.superseded_runs, "a parse-only sync before the fetch must not wipe edges"
      assert_nil result.run_id
    end
    assert_equal count, @journal[:links].count
  end

  private

  def edge_between(one, two)
    @journal[:links].first(from_urn: one, to_urn: two) ||
      @journal[:links].first(from_urn: two, to_urn: one)
  end

  def reuse_edges
    @journal[:links].where(kind: "reuse").select_map(%i[from_urn to_urn]).sort
  end

  # Three held openiti documents, each with one passage carrying a milestone.
  def seed_openiti!
    source = Nabu::Store::Source.create(slug: "openiti", name: "OpenITI",
                                        adapter_class: "Nabu::Adapters::Openiti", license_class: "nc")
    hold_passage!(source, ALC_URN, ALC_P1, "ms01") # padded on purpose
    hold_passage!(source, SHIA_URN, SHIA_P7, "ms7")
    hold_passage!(source, PV_URN, PV_P449, "ms449")
  end

  def hold_passage!(source, doc_urn, passage_urn, milestone)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: doc_urn, title: doc_urn,
                                       language: "ara", metadata_json: "{}", content_sha256: "x",
                                       revision: 1, withdrawn: false)
    Nabu::Store::Passage.create(
      document_id: doc.id, urn: passage_urn, sequence: 0, language: "ara",
      text: "…", text_normalized: "…",
      annotations_json: Nabu::Store::ContentHash.canonical_json("milestones" => [milestone]),
      content_sha256: "x", revision: 1, withdrawn: false
    )
  end
end
