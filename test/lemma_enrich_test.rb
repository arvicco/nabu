# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LemmaEnrich (P84-1) — the silver-lemma enricher runner: censuses
# the uncovered slice, keeps ONE model worker alive (Shell.duplex against
# the venv's stanza worker; here the protocol-identical fake), and lands
# batches on the local-lemmas shelf through the sanctioned gateway with a
# campaign checkpoint per flush. The model is never run in tests — the
# fake worker speaks the exact protocol (the enricher-stub rule).
class LemmaEnrichTest < Minitest::Test
  include StoreTestDB

  FAKE_WORKER = File.expand_path("fixtures/lemma/fake_worker.rb", __dir__)

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @source = Nabu::Store::Source.create(
      slug: "edr", name: "EDR", adapter_class: "TestAdapter", license_class: "open"
    )
    @doc = Nabu::Store::Document.create(
      source_id: @source.id, urn: "urn:d:1", title: "t", language: "lat",
      content_sha256: "x", revision: 1, withdrawn: false
    )
    @tmpdir = Dir.mktmpdir("nabu-lemma-enrich")
    @shelf = Nabu::LemmaShelf.new(dir: File.join(@tmpdir, "local-lemmas"))
  end

  def teardown
    @fulltext.disconnect
    FileUtils.remove_entry(@tmpdir)
  end

  def make_passage(urn:, text:, sequence:, language: "lat", annotations: nil)
    Nabu::Store::Passage.create(
      document_id: @doc.id, urn: urn, sequence: sequence, language: language,
      text: text, text_normalized: text, content_sha256: "x", revision: 1,
      annotations_json: annotations ? JSON.generate(annotations) : "{}"
    )
  end

  def enricher(**)
    Nabu::LemmaEnrich.new(
      catalog: @catalog, fulltext: @fulltext, shelf: @shelf, language: "lat",
      worker_argv: [RbConfig.ruby, FAKE_WORKER], **
    )
  end

  def shelf_records
    records = []
    @shelf.each_record(language: "lat") { |r| records << r }
    records
  end

  def test_run_shelves_uncovered_passages_with_worker_provenance
    make_passage(urn: "urn:d:1:1", text: "In fronte pedes", sequence: 0)
    make_passage(urn: "urn:d:1:2", text: "", sequence: 1) # empty: nothing to lemmatize
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    result = enricher.run!
    assert_equal 1, result.processed
    assert_equal 1, result.skipped_empty
    records = shelf_records
    assert_equal 1, records.size
    record = records.first
    assert_equal "urn:d:1:1", record.urn
    assert_equal "edr", record.source
    assert_equal "fake", record.model, "provenance comes from the worker's ready line"
    assert_equal "0.0.1", record.model_version
    assert_equal "la:fake_toy", record.package
    assert_equal [%w[In in X], %w[fronte fronte X], %w[pedes peda X]],
                 record.tokens
  end

  def test_run_skips_lemma_covered_and_already_shelved_passages
    make_passage(urn: "urn:d:1:1", text: "covered text", sequence: 0,
                 annotations: { "tokens" => [{ "lemma" => "covered", "form" => "covered" }] })
    make_passage(urn: "urn:d:1:2", text: "shelved text", sequence: 1)
    make_passage(urn: "urn:d:1:3", text: "fresh text", sequence: 2)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    @shelf.append_batch!(language: "lat", records: [
                           Nabu::LemmaShelf::Record.new(
                             urn: "urn:d:1:2", language: "lat", source: "edr", model: "fake",
                             model_version: "0.0.1", package: "la:fake_toy",
                             tokens: [%w[shelved shelved X]], generated_at: "2026-08-27T00:00:00Z"
                           )
                         ])

    result = enricher.run!
    assert_equal 1, result.processed
    assert_equal 1, result.skipped_covered
    assert_equal 1, result.skipped_shelved
    assert_equal %w[urn:d:1:2 urn:d:1:3], shelf_records.map(&:urn).sort
  end

  def test_run_flushes_shards_and_checkpoints_monotonically
    ids = (0..4).map { |i| make_passage(urn: "urn:d:1:#{i + 1}", text: "verba #{i}", sequence: i).id }
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    enricher(shard_size: 2, batch_size: 2).run!
    assert_equal 3, @shelf.shard_paths("lat").size, "5 records at shard_size 2 = 3 shards"
    state = @shelf.state(language: "lat")
    assert_equal ids.max, state["checkpoint_passage_id"],
                 "the checkpoint covers every considered passage"
  end

  def test_resume_starts_after_the_checkpoint
    make_passage(urn: "urn:d:1:1", text: "prima", sequence: 0)
    later = make_passage(urn: "urn:d:1:2", text: "secunda", sequence: 1)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    @shelf.write_state!(language: "lat",
                        payload: { "state_schema" => 1, "checkpoint_passage_id" => later.id - 1 })

    result = enricher.run!
    assert_equal 1, result.processed
    assert_equal %w[urn:d:1:2], shelf_records.map(&:urn),
                 "passages at or before the checkpoint are not re-sent to the model"
  end

  def test_worker_error_aborts_the_campaign_resumably
    make_passage(urn: "urn:d:1:1", text: "salva", sequence: 0)
    make_passage(urn: "urn:d:1:2", text: "BOOM", sequence: 1)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    error = assert_raises(Nabu::Error) { enricher(shard_size: 1, batch_size: 1).run! }
    assert_match(/FakeError/, error.message)
    assert_equal %w[urn:d:1:1], shelf_records.map(&:urn),
                 "work flushed before the abort stays shelved — the crash loses nothing flushed"
  end

  def test_limit_bounds_the_smoke_run
    3.times { |i| make_passage(urn: "urn:d:1:#{i + 1}", text: "verba #{i}", sequence: i) }
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    result = enricher(limit: 2).run!
    assert_equal 2, result.processed
    assert_equal 2, shelf_records.size
  end

  def test_census_counts_the_uncovered_slice
    make_passage(urn: "urn:d:1:1", text: "covered", sequence: 0,
                 annotations: { "tokens" => [{ "lemma" => "covered", "form" => "covered" }] })
    make_passage(urn: "urn:d:1:2", text: "fresh", sequence: 1)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    census = enricher.census
    assert_equal 2, census.total
    assert_equal 1, census.covered
    assert_equal 1, census.uncovered
  end

  def test_language_aliases_resolve
    assert_equal "lat", Nabu::LemmaEnrich.resolve_language("la")
    assert_equal "lat", Nabu::LemmaEnrich.resolve_language("lat")
    error = assert_raises(Nabu::Error) { Nabu::LemmaEnrich.resolve_language("klingon") }
    assert_match(/lat/, error.message, "the refusal names what IS supported")
  end

  # -- the recorded-shape fixture (real stanza 1.14.0 output) ---------------

  # A replay worker: prints the RECORDED ready + response lines (real
  # la:ittb output, see fixtures/lemma/README.md), then drains stdin — so
  # the runner's protocol parsing is exercised against the exact bytes the
  # real worker emits.
  def test_parses_the_recorded_real_worker_shapes
    make_passage(urn: "urn:d:1:1", text: "In fronte pedes VI in agro pedes X", sequence: 0)
    make_passage(urn: "urn:d:1:2", text: "Dis Manibus sacrum", sequence: 1)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    replay = [RbConfig.ruby, "-e",
              "STDOUT.sync = true; ARGV.each { |f| print File.read(f) }; $stdin.each_line { nil }",
              File.expand_path("fixtures/lemma/worker_ready.jsonl", __dir__),
              File.expand_path("fixtures/lemma/worker_response.jsonl", __dir__)]
    enricher = Nabu::LemmaEnrich.new(
      catalog: @catalog, fulltext: @fulltext, shelf: @shelf, language: "lat",
      worker_argv: replay, batch_size: 2
    )
    result = enricher.run!
    assert_equal 2, result.processed
    assert_equal "stanza", result.model
    assert_equal "1.14.0", result.model_version
    assert_equal "la:ittb_nocharlm", result.package
    records = shelf_records
    assert_equal [%w[In in ADP], %w[fronte frons NOUN], %w[pedes pes NOUN],
                  %w[VI vies NOUN], %w[in in ADP], %w[agro ager NOUN],
                  %w[pedes pes NOUN], %w[X x NUM]],
                 records.first.tokens, "real recorded ittb output round-trips into the shelf"
    assert_equal [%w[Dis Dis NOUN], %w[Manibus manus NOUN], %w[sacrum sacer ADJ]],
                 records.last.tokens
  end

  # -- the gold spot-check (the P79-4 trial protocol, wired) ----------------

  def test_spot_check_scores_folded_lemma_accuracy_against_gold_tokens
    # Gold passage the fake worker gets RIGHT (toy rule: "portas" -> "porta").
    make_passage(urn: "urn:d:1:1", text: "portas", sequence: 0,
                 annotations: { "tokens" => [{ "form" => "portas", "lemma" => "porta" }] })
    # Gold passage it gets WRONG ("pedes" -> gold "pes", fake says "peda").
    make_passage(urn: "urn:d:1:2", text: "pedes", sequence: 1,
                 annotations: { "tokens" => [{ "form" => "pedes", "lemma" => "pes" }] })
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)

    report = enricher.spot_check(sample: 10)
    row = report.fetch("edr")
    assert_equal 2, row[:gold_tokens]
    assert_equal 2, row[:aligned]
    assert_equal 1, row[:folded_hits]
    assert_in_delta 50.0, row[:accuracy], 0.01
  end
end
