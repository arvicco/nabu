# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::SuttacentralParallels (P32-6): the sc-data parallels graph as
# kind=reference edges. The fixture is a trimmed REAL slice of
# relationship/parallels.json (sc-data commit 8b3bcaf6, retrieved
# 2026-07-19) covering every censused shape: the three relation kinds
# (parallels / mentions / retells), `~`-prefixed resolved-by-inference
# uids, `#segment` and `#a-#b` range suffixes, the one `uid:segment`
# colon variant (t765.132:10.0, censused twice corpus-wide), a free-text
# print citation ("Manusmṛti 6.77"), a same-document segment pair, a
# duplicate pair asserted from both sides, and one pair carried by TWO
# kinds (thig11.1 ↔ thi-ap19: mentions + retells). Expansion follows
# upstream's own loader (suttacentral/suttacentral
# server/server/data_loader/arangoload.py): parallels = full×full +
# full×partial (never partial×partial); mentions/retells = star from the
# first uid. Edges are document-grain; segment suffixes and `~` flags
# ride the detail verbatim.
class SuttacentralParallelsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("suttacentral")

  AN768 = "urn:nabu:suttacentral:an7.68"
  MA1 = "urn:nabu:suttacentral:ma1"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::SuttacentralParallels.new(catalog: @catalog, journal: @journal)
  end

  # --- expansion: the censused shape vocabulary, end to end ------------------

  def test_mints_document_grain_edges_for_every_censused_shape
    result = producer.run("suttacentral", workdir: FIXTURES)

    assert_equal 58, result.edges_written,
                 "1 mention (mnd9 twice deduped) + 6 (~sag partial) + 0 (reverse dup) + 36 (C(9,2), " \
                 "free-text skipped) + 10 (an7.68 clique) + 1 retell + 1 (ja self-pair skipped) + " \
                 "2 (partial-only fan) + 1 (mentions, merged with the retells re-assertion)"
    assert_equal 0, result.edges_refreshed, "within-run dedup happens before the journal"
    assert_equal 1, result.skipped_citations, "Manusmṛti 6.77 — a print citation, not a SuttaCentral uid"
    assert_equal 1, result.skipped_self, "ja546#256… ↔ ja546#280… — one document, no self-edge"
    assert_equal 58, @journal[:links].count
    assert_equal ["reference"], @journal[:links].select_map(:kind).uniq
    assert_equal [nil], @journal[:links].select_map(:score).uniq,
                 "curated assertions are not mined similarities — no fake number"
    assert(@journal[:links].select_map(%i[from_urn to_urn]).flatten.all? do |urn|
      urn.start_with?("urn:nabu:suttacentral:") && !urn.include?("#") && !urn.include?("~")
    end, "document-grain urns only; segments and inference flags live in detail")
  end

  def test_pins_the_an7_68_ma1_edge_end_to_end
    producer.run("suttacentral", workdir: FIXTURES)

    edge = @journal[:links].first(from_urn: AN768, to_urn: MA1)
    refute_nil edge, "the Kālāma-hop precedent: AN 7.68 ↔ MA 1 (both minted in the live catalog)"
    assert_equal "reference", edge[:kind]
    assert_nil edge[:score]
    assert_equal "parallels an7.68 ↔ ma1#t0421a12-#t0422a16", edge[:detail],
                 "the upstream spelling verbatim — the Taishō line range rides the detail, " \
                 "never a minted passage target"

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(AN768)
    counterparts = result.groups.fetch("reference").map(&:urn)
    assert_includes counterparts, MA1, "`nabu links` serves the hop natively"
    assert_equal 4, result.total, "an7.68's clique: ea39.1, ma1, t27, t1536.8"
  end

  def test_preserves_inference_flags_and_segment_suffixes_in_detail
    producer.run("suttacentral", workdir: FIXTURES)

    partial = @journal[:links].first(from_urn: "urn:nabu:suttacentral:sn1.1",
                                     to_urn: "urn:nabu:suttacentral:sag")
    assert_equal "parallels sn1.1 ↔ ~sag#sag13", partial[:detail],
                 "the ~ resolved-by-inference flag survives verbatim; first-seen spelling wins " \
                 "over the reverse re-assertion"

    colon = @journal[:links].first(from_urn: "urn:nabu:suttacentral:an4.16",
                                   to_urn: "urn:nabu:suttacentral:t765.132")
    refute_nil colon, "t765.132:10.0 — the colon segment variant splits to its document uid"
    assert_equal "parallels an4.16#3.1 ↔ ~t765.132:10.0", colon[:detail]
  end

  def test_parallels_expand_full_by_full_plus_full_by_partial_only
    producer.run("suttacentral", workdir: FIXTURES)

    # Entry 8 of the slice: one full uid, two ~partial — the partials pair
    # with the full uid but never with each other (upstream's own loader).
    assert_equal 2, @journal[:links].where(from_urn: "urn:nabu:suttacentral:an4.16").count
    assert_nil @journal[:links].first(from_urn: "urn:nabu:suttacentral:iti62",
                                      to_urn: "urn:nabu:suttacentral:t765.132")
    assert_nil @journal[:links].first(from_urn: "urn:nabu:suttacentral:t765.132",
                                      to_urn: "urn:nabu:suttacentral:iti62")
  end

  def test_mentions_and_retells_are_stars_from_the_first_uid
    producer.run("suttacentral", workdir: FIXTURES)

    star = @journal[:links].where(from_urn: "urn:nabu:suttacentral:snp4.9").all
    assert_equal ["urn:nabu:suttacentral:mnd9"], star.map { |edge| edge[:to_urn] },
                 "two mnd9 segment refs dedupe to one document-grain edge"
    assert_equal "mentions snp4.9#vns849 ↔ mnd9#57.1", star.first[:detail]

    retell = @journal[:links].first(from_urn: "urn:nabu:suttacentral:dn19")
    assert_equal "urn:nabu:suttacentral:cp5", retell[:to_urn]
    assert_equal "retells dn19 ↔ cp5", retell[:detail]
  end

  def test_a_pair_asserted_under_two_kinds_merges_into_one_edge
    producer.run("suttacentral", workdir: FIXTURES)

    edges = @journal[:links].where(from_urn: "urn:nabu:suttacentral:thig11.1").all
    assert_equal 1, edges.size, "one row per unordered pair — the journal's standing dedup grain"
    assert_equal "mentions thig11.1#vns227 ↔ ~thi-ap19#18.1; retells thig11.1 ↔ thi-ap19",
                 edges.first[:detail], "both relation kinds ride the one detail, file order"
  end

  # --- run mechanics ---------------------------------------------------------

  def test_rerun_supersedes_the_prior_edges
    first = producer.run("suttacentral", workdir: FIXTURES)
    second = producer.run("suttacentral", workdir: FIXTURES)

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal first.edges_written, @journal[:links].count,
                 "the journal holds exactly the current graph"
    run = @journal[:link_runs].first(id: second.run_id)
    assert_equal "suttacentral", run[:producer]
    assert_equal "suttacentral", run[:scope]
  end

  def test_a_workdir_without_the_graph_file_is_a_no_op_that_supersedes_nothing
    producer.run("suttacentral", workdir: FIXTURES)
    Dir.mktmpdir do |empty|
      result = producer.run("suttacentral", workdir: empty)
      assert_equal 0, result.edges_written
      assert_equal 0, result.superseded_runs, "a parse-only sync before the graph fetch must " \
                                              "never wipe the standing edges"
      assert_nil result.run_id
    end
    assert_equal 58, @journal[:links].count
  end

  def test_an_unknown_relation_kind_stops_loudly
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "parallels"))
      File.write(File.join(dir, "parallels", "parallels.json"),
                 JSON.generate([{ "translates" => %w[mn1 ma1] }]))
      error = assert_raises(Nabu::ParseError) { producer.run("suttacentral", workdir: dir) }
      assert_match(/translates/, error.message)
    end
  end

  def test_malformed_graph_json_stops_loudly
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "parallels"))
      File.write(File.join(dir, "parallels", "parallels.json"), "[{")
      assert_raises(Nabu::ParseError) { producer.run("suttacentral", workdir: dir) }
    end
  end
end
