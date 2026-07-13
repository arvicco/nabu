# frozen_string_literal: true

require "test_helper"

# Nabu::BatchParallels (P16-1): the first links-journal producer — the
# interactive Query::Parallels engine looped over a scope's anchors, hits
# persisted as kind=parallel edges. Same in-memory rig as ParallelsTest
# (catalog + fulltext + real Indexer) plus an in-memory links journal.
class BatchParallelsTest < Minitest::Test
  include StoreTestDB

  # Two Greek "works" that share a rare verbatim phrase (grams overlap), plus
  # an English translation riding the same prefix (the --lang case) and an
  # unrelated bystander (no shared grams above noise).
  HOMER = "ανδρα μοι εννεπε μουσα πολυτροπον ος μαλα πολλα"
  QUOTER = "λεγει που ανδρα μοι εννεπε μουσα πολυτροπον ως φησιν"
  ENGLISH = "tell me o muse of that man of many devices"
  BYSTANDER = "αλλο τι παντως ασχετον ουδεν κοινον εχει"

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(
      slug: "homerics", name: "Homerics", adapter_class: "TestAdapter", license_class: "open"
    )
  end

  def teardown
    @fulltext.disconnect
    @journal.disconnect
  end

  def make_passage(doc_urn:, urn:, text:, title: "Doc", language: "grc", sequence: 0)
    document = Nabu::Store::Document.find(urn: doc_urn) || Nabu::Store::Document.create(
      source_id: @source.id, urn: doc_urn, title: title, language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: urn, sequence: sequence, language: language,
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
      annotations_json: "{}", content_sha256: "x", revision: 1, withdrawn: false
    )
  end

  def seed_corpus
    make_passage(doc_urn: "urn:h:od", urn: "urn:h:od:1.1", text: HOMER, title: "Odyssey")
    make_passage(doc_urn: "urn:q:hist", urn: "urn:q:hist:12.1", text: QUOTER, title: "Histories")
    make_passage(doc_urn: "urn:e:od-eng", urn: "urn:e:od-eng:1.1", text: ENGLISH,
                 title: "Odyssey (tr.)", language: "eng")
    make_passage(doc_urn: "urn:b:misc", urn: "urn:b:misc:1", text: BYSTANDER, title: "Misc")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
  end

  def producer
    Nabu::BatchParallels.new(catalog: @catalog, fulltext: @fulltext, journal: @journal)
  end

  # -- mining + dedup ---------------------------------------------------------

  def test_batch_writes_each_pair_once_in_the_direction_the_probe_found
    seed_corpus
    result = producer.run("urn:h:od")
    assert_equal 1, result.anchor_count, "one anchor passage under the work prefix"
    assert_equal 1, result.edges_written
    edge = @journal[:links].first
    assert_equal %w[urn:h:od:1.1 urn:q:hist:12.1], [edge[:from_urn], edge[:to_urn]],
                 "direction = the probe that found it (anchor → hit)"
    assert_equal "parallel", edge[:kind]
    assert_operator edge[:score], :>, 0.0
  end

  def test_batch_over_a_super_scope_dedupes_the_reverse_direction
    seed_corpus
    # Source-slug scope covers BOTH works: urn:h:od:1.1 finds urn:q:hist:12.1,
    # then urn:q:hist:12.1's own probe re-finds the same pair — one edge.
    result = producer.run("homerics", lang: "grc")
    pair_edges = @journal[:links].where(kind: "parallel").all
    assert_equal 1, pair_edges.count { |edge|
      [edge[:from_urn], edge[:to_urn]].sort == %w[urn:h:od:1.1 urn:q:hist:12.1]
    }, "an unordered pair is stored once per run"
    assert_equal result.edges_written, @journal[:links].count
  end

  def test_min_score_threshold_prunes_and_is_reported
    seed_corpus
    result = producer.run("urn:h:od", min_score: 1_000_000.0)
    assert_equal 0, result.edges_written, "an absurd floor prunes everything"
    assert_in_delta 1_000_000.0, result.min_score, 0.1
    assert_equal 0, @journal[:links].count
    assert_equal 1, @journal[:link_runs].count, "the run row still records the (empty) mining"
  end

  def test_lang_scopes_the_anchors
    seed_corpus
    result = producer.run("homerics", lang: "eng")
    assert_equal 1, result.anchor_count, "only the English passage anchors"
    assert_equal 0, result.edges_written, "no English parallel exists"
  end

  # -- provenance --------------------------------------------------------------

  def test_run_row_records_producer_scope_params_and_code_version
    seed_corpus
    result = producer.run("urn:h:od", min_score: 0.1, per_anchor: 3, lang: "grc")
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal "parallels", run[:producer]
    assert_equal "urn:h:od", run[:scope]
    params = JSON.parse(run[:params_json])
    assert_equal({ "kind" => "parallel", "min_score" => 0.1, "per_anchor" => 3, "lang" => "grc" }, params)
    assert_match(%r{parallels-batch/1}, run[:code_version])
    assert_equal result.run_id, @journal[:links].first[:run_id]
  end

  # -- rerun idempotency --------------------------------------------------------

  def test_rerun_supersedes_and_is_idempotent
    seed_corpus
    first = producer.run("urn:h:od")
    second = producer.run("urn:h:od")
    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal 1, @journal[:link_runs].count, "the superseded run row is replaced, not accumulated"
    assert_equal first.edges_written, @journal[:links].count, "edge count unchanged across reruns"
    assert_equal second.run_id, @journal[:links].first[:run_id], "edges cite the current run"
  end

  def test_overlapping_scope_refreshes_the_existing_pair_instead_of_duplicating
    seed_corpus
    producer.run("urn:h:od")
    wider = producer.run("homerics", lang: "grc")
    assert_equal 1, wider.edges_refreshed, "the pair mined by the narrower run is refreshed in place"
    assert_equal 1, @journal[:links].where(kind: "parallel").count
  end

  # -- empty scope ---------------------------------------------------------------

  def test_unknown_scope_mines_nothing_but_still_records_the_run
    seed_corpus
    result = producer.run("urn:no:such")
    assert_equal 0, result.anchor_count
    assert_equal 0, result.edges_written
  end

  def test_progress_callback_ticks_per_anchor
    seed_corpus
    ticks = []
    producer.run("homerics", lang: "grc", progress: ->(done, total, edges) { ticks << [done, total, edges] })
    assert_equal 3, ticks.size, "grc anchors: homer, quoter, bystander"
    assert_equal [3, 3], ticks.last[0, 2]
  end
end
