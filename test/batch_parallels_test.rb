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
    assert_equal({ "kind" => "parallel", "min_score" => 0.1, "per_anchor" => 3, "lang" => "grc",
                   "gram_size" => 4, "candidate_pool" => 300 }, params,
                 "every EFFECTIVE parameter is recorded — engine defaults included, resolved")
    assert_match(%r{parallels-batch/2 nabu/}, run[:code_version])
    assert_equal result.run_id, @journal[:links].first[:run_id]
    assert_equal "complete", run[:status]
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

  # == P122-2: profiles, chunked resumable runs, provenance ====================

  SCHOLIUM = "ο ποιητης ανδρα μοι εννεπε μουσα πολυτροπον λεγει"

  # grc anchors in urn order: b:misc, h:od, q:hist, r:schol — three pairs
  # share the proem (h–q, h–r, q–r); the bystander shares nothing.
  def seed_chunk_corpus
    make_passage(doc_urn: "urn:r:schol", urn: "urn:r:schol:1", text: SCHOLIUM, title: "Scholia")
    seed_corpus
  end

  def profile(**knobs)
    Nabu::ReuseProfiles::Profile.new(
      name: "demo", lang: "grc", serves: "test", gram_size: nil, min_score: nil, per_anchor: nil,
      candidate_pool: nil, stop_tokens: [], rationale: "test", **knobs
    )
  end

  def edge_set
    @journal[:links].select_map(%i[from_urn to_urn]).sort
  end

  class Killed < StandardError; end

  def test_a_profile_supplies_the_knobs_and_is_recorded_by_name
    seed_chunk_corpus
    result = producer.run("homerics", profile: profile(gram_size: 3, min_score: 0.2, per_anchor: 2,
                                                       candidate_pool: 40, stop_tokens: %w[μοι]))
    params = JSON.parse(@journal[:link_runs].first(id: result.run_id)[:params_json])
    assert_equal({ "kind" => "parallel", "profile" => "demo", "lang" => "grc", "min_score" => 0.2,
                   "per_anchor" => 2, "gram_size" => 3, "candidate_pool" => 40, "stop_tokens" => ["μοι"] },
                 params)
    assert_equal ["demo", 3], [result.profile, result.gram_size]
    assert_equal 4, result.anchor_count, "the profile's lang scopes the anchors (the English passage is out)"
  end

  def test_explicit_arguments_override_the_profile
    seed_chunk_corpus
    result = producer.run("homerics", profile: profile(gram_size: 3, min_score: 0.2, per_anchor: 2),
                                      gram_size: 4, min_score: 0.05, lang: "eng")
    params = JSON.parse(@journal[:link_runs].first(id: result.run_id)[:params_json])
    assert_equal [4, 0.05, 2, "eng"], params.values_at("gram_size", "min_score", "per_anchor", "lang"),
                 "flags win; the profile fills only what was not given"
    assert_equal 300, params["candidate_pool"], "the pool resolves from the EFFECTIVE per_anchor"
  end

  def test_chunked_run_records_each_chunk_and_tags_edges
    seed_chunk_corpus
    result = producer.run("homerics", lang: "grc", chunk_size: 2)
    assert_equal [2, 2], [result.chunks, result.chunks_mined]
    chunks = @journal[:link_run_chunks].where(run_id: result.run_id).order(:chunk).all
    assert_equal([[1, "urn:b:misc:1", "urn:h:od:1.1"], [2, "urn:q:hist:12.1", "urn:r:schol:1"]],
                 chunks.map { |row| row.values_at(:chunk, :first_urn, :last_urn) })
    assert_equal [2, 1], chunks.map { |row| row[:edges_inserted] }, "h→q, h→r in chunk 1; q→r in chunk 2"
    assert_equal 3, @journal[:links].count
    assert_equal [1, 1, 2], @journal[:links].order(:id).select_map(:chunk)
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal ["complete", 2, "urn:r:schol:1", 2, 4],
                 run.values_at(:status, :chunk_size, :cursor_urn, :chunks_done, :anchors_done)
    assert_equal 2, JSON.parse(run[:params_json])["chunk_size"]
  end

  def test_a_killed_run_resumes_at_its_cursor_without_re_mining_or_duplicating
    seed_chunk_corpus
    uninterrupted = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    Nabu::BatchParallels.new(catalog: @catalog, fulltext: @fulltext, journal: uninterrupted)
                        .run("homerics", lang: "grc", chunk_size: 2)
    expected = uninterrupted[:links].select_map(%i[from_urn to_urn]).sort

    assert_raises(Killed) do
      producer.run("homerics", lang: "grc", chunk_size: 2, on_chunk: ->(_report) { raise Killed })
    end
    assert_equal 2, @journal[:links].count, "chunk 1 committed before the kill"
    assert_equal "running", @journal[:link_runs].first[:status]

    mined = []
    result = producer.run("homerics", lang: "grc", chunk_size: 2,
                                      progress: ->(_done, _total, _edges) { mined << :anchor })
    assert result.resumed, "the unfinished run is continued, not superseded"
    assert_equal [2, 1], [result.chunks, result.chunks_mined]
    assert_equal 2, mined.size, "only chunk 2's anchors are probed on resume"
    assert_equal 0, result.superseded_runs
    assert_equal expected, edge_set, "resume yields exactly the uninterrupted run's edges"
    assert_equal 1, @journal[:link_runs].count
    assert_equal "complete", @journal[:link_runs].first[:status]
    assert_equal [1, 2], @journal[:link_run_chunks].order(:chunk).select_map(:chunk)
    uninterrupted.disconnect
  end

  def test_a_kill_mid_chunk_rolls_the_chunk_back_and_resume_re_mines_it
    seed_chunk_corpus
    ticks = 0
    assert_raises(Killed) do
      producer.run("homerics", lang: "grc", chunk_size: 2,
                               progress: lambda { |_d, _t, _e|
                                 ticks += 1
                                 raise Killed if ticks == 3
                               })
    end
    assert_equal 2, @journal[:links].count, "the in-flight chunk's edges never landed"
    assert_equal [1], @journal[:link_run_chunks].select_map(:chunk)

    result = producer.run("homerics", lang: "grc", chunk_size: 2)
    assert_equal 1, result.chunks_mined
    assert_equal 3, @journal[:links].count
  end

  def test_rerunning_a_finished_chunked_run_supersedes_without_duplicates
    seed_chunk_corpus
    first = producer.run("homerics", lang: "grc", chunk_size: 2)
    edges = edge_set
    second = producer.run("homerics", lang: "grc", chunk_size: 2)
    refute second.resumed, "a complete run is never resumed — a rerun supersedes it"
    assert_equal [1, 3], [second.superseded_runs, second.superseded_edges]
    assert_equal edges, edge_set
    assert_equal [second.run_id], @journal[:link_runs].select_map(:id)
    assert_equal 2, @journal[:link_run_chunks].count, "the superseded run's chunk rows went with it"
    refute_equal first.run_id, second.run_id
  end

  def test_resuming_under_different_parameters_is_refused_unless_restarted
    seed_chunk_corpus
    assert_raises(Killed) do
      producer.run("homerics", lang: "grc", chunk_size: 2, on_chunk: ->(_report) { raise Killed })
    end
    error = assert_raises(Nabu::Error) { producer.run("homerics", lang: "grc", chunk_size: 2, min_score: 0.3) }
    assert_match(/run 1 is unfinished/, error.message)
    assert_match(/--restart/, error.message)

    result = producer.run("homerics", lang: "grc", chunk_size: 2, min_score: 0.3, restart: true)
    refute result.resumed
    assert_equal 1, result.superseded_runs, "restart supersedes the unfinished run"
    assert_equal "complete", @journal[:link_runs].first(id: result.run_id)[:status]
  end

  def test_on_chunk_reports_feed_a_log_friendly_progress_line
    seed_chunk_corpus
    reports = []
    producer.run("homerics", lang: "grc", chunk_size: 3, on_chunk: ->(report) { reports << report })
    assert_equal([[1, 2], [2, 2]], reports.map { |r| [r.chunk, r.chunks] })
    line = Nabu::BatchParallels.chunk_line(reports.first)
    shape = %r{\Achunk 1/2 · 3 anchors · \d+ candidates · 3 edges minted · 0 refreshed · \d+\.\ds · run \d+\.\ds\z}
    assert_match shape, line
    refute_includes line, "\n", "one line per chunk — log-friendly"
  end

  def test_unchunked_run_is_one_chunk_and_stays_atomic
    seed_chunk_corpus
    assert_raises(Killed) do
      producer.run("homerics", lang: "grc",
                               progress: ->(done, _t, _e) { raise Killed if done == 3 })
    end
    assert_equal [0, 0], [@journal[:links].count, @journal[:link_runs].count],
                 "without --chunk-size the whole run is one transaction — a kill leaves nothing"
    result = producer.run("homerics", lang: "grc")
    assert_equal [1, 1], [result.chunks, result.chunks_mined]
    assert_nil JSON.parse(@journal[:link_runs].first[:params_json])["chunk_size"]
  end
end
