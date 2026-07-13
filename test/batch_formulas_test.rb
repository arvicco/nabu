# frozen_string_literal: true

require "test_helper"

# Nabu::BatchFormulas (P16-2): the whole-tradition formula sweep persisting
# kind=formula edges as a STAR per formula — hub = first locus in urn order,
# one edge to every other locus, detail = the gram, score = the count. Only
# the catalog is needed (the miner reads text_normalized directly).
class BatchFormulasTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(
      slug: "aspr", name: "ASPR", adapter_class: "TestAdapter", license_class: "open"
    )
  end

  def teardown
    @journal.disconnect
  end

  def make_passage(urn:, text:, doc_urn: "urn:nabu:aspr:riddle", language: "ang")
    document = Nabu::Store::Document.find(urn: doc_urn) || Nabu::Store::Document.create(
      source_id: @source.id, urn: doc_urn, title: "Riddles", language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: urn,
      sequence: @catalog[:passages].where(document_id: document.id).count,
      language: language, text: text,
      text_normalized: Nabu::Normalize.search_form(text, language: language),
      annotations_json: "{}", content_sha256: "x", revision: 1, withdrawn: false
    )
  end

  # The riddle refrain across three loci, each line padded with unique tails
  # so only the refrain recurs.
  def seed_refrain
    make_passage(urn: "urn:nabu:aspr:riddle:1", text: "saga hwaet ic hatte foo bar")
    make_passage(urn: "urn:nabu:aspr:riddle:2", text: "saga hwaet ic hatte baz qux")
    make_passage(urn: "urn:nabu:aspr:riddle:3", text: "saga hwaet ic hatte alpha beta")
  end

  def producer
    Nabu::BatchFormulas.new(catalog: @catalog, journal: @journal)
  end

  # -- edge shape: the star ----------------------------------------------------

  def test_a_formula_persists_as_a_star_from_its_first_locus
    seed_refrain
    result = producer.run("aspr")
    assert_equal 1, result.formula_count
    assert_equal 2, result.edges_written, "3 loci → 2 star edges (loci − 1)"
    edges = @journal[:links].order(:to_urn).all
    assert_equal %w[urn:nabu:aspr:riddle:1 urn:nabu:aspr:riddle:1], edges.map { |e| e[:from_urn] },
                 "the hub is the first locus in urn order"
    assert_equal(%w[urn:nabu:aspr:riddle:2 urn:nabu:aspr:riddle:3], edges.map { |e| e[:to_urn] })
    assert_equal(%w[formula formula], edges.map { |e| e[:kind] })
  end

  def test_edges_carry_the_gram_as_detail_and_the_count_as_score
    seed_refrain
    producer.run("aspr")
    edge = @journal[:links].first
    assert_equal "saga hwaet ic hatte", edge[:detail], "detail = the folded gram (WHICH refrain)"
    assert_in_delta 3.0, edge[:score], 0.001, "score = the slice count (how strong)"
  end

  def test_a_formula_recurring_within_one_passage_mints_no_edge
    make_passage(urn: "urn:nabu:aspr:riddle:1",
                 text: "eala eala eala min eala eala eala min eala eala eala min")
    result = producer.run("aspr")
    assert_equal 0, result.edges_written, "one locus has nothing to link to"
  end

  # -- pruning, named ------------------------------------------------------------

  def test_max_formulas_caps_by_rank_and_the_result_names_the_cap
    seed_refrain
    # A second, weaker formula (2 loci — below the first's 3 count).
    make_passage(urn: "urn:nabu:aspr:wulf:1", text: "leodum is minum swylce him mon lac gife",
                 doc_urn: "urn:nabu:aspr:wulf")
    make_passage(urn: "urn:nabu:aspr:wulf:2", text: "leodum is minum swylce eft on aer",
                 doc_urn: "urn:nabu:aspr:wulf")
    result = producer.run("aspr", min_count: 2, max_formulas: 1)
    assert_equal 1, result.max_formulas
    assert_operator result.recurring_count, :>, 1, "the tail the cap cut is counted, not hidden"
    assert_equal ["saga hwaet ic hatte"], @journal[:links].select_map(:detail).uniq,
                 "only the top-ranked formula persists"
  end

  def test_overlapping_formulas_coalesce_onto_the_pair_keeping_the_best_ranked_gram
    # A 5-word refrain: its two 4-grams share identical loci, so the second
    # formula's writes fold into the existing pairs.
    make_passage(urn: "urn:nabu:aspr:r:1", text: "saga hwaet ic hatte nu foo bar")
    make_passage(urn: "urn:nabu:aspr:r:2", text: "saga hwaet ic hatte nu baz qux")
    make_passage(urn: "urn:nabu:aspr:r:3", text: "saga hwaet ic hatte nu alpha beta")
    result = producer.run("aspr")
    assert_equal 2, result.formula_count, "both 4-grams of the 5-word refrain recur"
    assert_equal 2, result.edges_written, "one star, not two stacked stars"
    assert_equal 2, result.coalesced, "the folded writes are counted, never silent"
    assert_equal 1, @journal[:links].select_map(:detail).uniq.size,
                 "each pair keeps one gram (the best-ranked)"
  end

  # -- provenance ------------------------------------------------------------------

  def test_run_row_records_the_knobs_in_params_json
    seed_refrain
    result = producer.run("aspr", gram_size: 3, min_count: 2, max_formulas: 50, lang: "ang")
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal "formulas", run[:producer]
    assert_equal "aspr", run[:scope]
    assert_equal({ "kind" => "formula", "gram_size" => 3, "min_count" => 2,
                   "max_formulas" => 50, "lang" => "ang" }, JSON.parse(run[:params_json]))
    assert_match(%r{formulas-batch/1}, run[:code_version])
    assert_equal result.run_id, @journal[:links].first[:run_id]
  end

  # -- rerun idempotency --------------------------------------------------------------

  def test_rerun_supersedes_and_is_idempotent
    seed_refrain
    first = producer.run("aspr")
    second = producer.run("aspr")
    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal 1, @journal[:link_runs].count
    assert_equal first.edges_written, @journal[:links].count
    assert_equal second.run_id, @journal[:links].first[:run_id], "edges cite the current run"
  end

  # -- scoping ---------------------------------------------------------------------------

  def test_lang_scopes_the_slice
    seed_refrain
    make_passage(urn: "urn:nabu:aspr:tr:1", text: "say what i am called foo",
                 doc_urn: "urn:nabu:aspr:tr", language: "eng")
    make_passage(urn: "urn:nabu:aspr:tr:2", text: "say what i am called bar",
                 doc_urn: "urn:nabu:aspr:tr", language: "eng")
    make_passage(urn: "urn:nabu:aspr:tr:3", text: "say what i am called baz",
                 doc_urn: "urn:nabu:aspr:tr", language: "eng")
    result = producer.run("aspr", lang: "ang")
    assert_equal ["saga hwaet ic hatte"], @journal[:links].select_map(:detail).uniq,
                 "the English refrain never mines under --lang ang"
    assert_equal "ang", result.lang
  end

  def test_unknown_scope_mines_nothing_but_still_records_the_run
    seed_refrain
    result = producer.run("urn:no:such")
    assert_equal 0, result.edges_written
    assert_equal 0, result.formula_count
    assert_equal 1, @journal[:link_runs].count
  end
end
