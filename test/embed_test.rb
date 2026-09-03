# frozen_string_literal: true

require "test_helper"

# Nabu::Embed (P93-4, №R-36) — the semantic-vector build lane, exercised
# against the fake worker (test/fixtures/embed/fake_worker.rb) over the
# real Shell.duplex plumbing: no Python, no venv, no model, no network.
class EmbedTest < Minitest::Test
  include StoreTestDB

  FAKE_WORKER = ["ruby", File.expand_path("fixtures/embed/fake_worker.rb", __dir__)].freeze

  def setup
    @catalog = store_test_db
    @vectors = Sequel.sqlite # in-memory vectors.sqlite3 stand-in
    @source = Nabu::Store::Source.create(
      slug: "lit", name: "Lit", adapter_class: "TestAdapter", license_class: "open"
    )
    @other = Nabu::Store::Source.create(
      slug: "outside", name: "Out", adapter_class: "TestAdapter", license_class: "open"
    )
  end

  def teardown
    @vectors.disconnect
  end

  def make_document(source: @source, urn: "urn:d:1", language: "grc")
    Nabu::Store::Document.create(
      source_id: source.id, urn: urn, title: "t", language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
  end

  def make_passage(document, urn:, text:, sequence:, language: "grc", withdrawn: false)
    Nabu::Store::Passage.create(
      document_id: document.id, urn: urn, sequence: sequence, language: language,
      text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: withdrawn
    )
  end

  def embedder(slugs: %w[lit], **)
    Nabu::Embed.new(catalog: @catalog, vectors: @vectors, slugs: slugs,
                    worker_argv: FAKE_WORKER, **)
  end

  def vector_rows = @vectors[Nabu::Embed::VECTORS_TABLE].order(:urn).all

  # -- the build -----------------------------------------------------------

  def test_run_embeds_the_scope_and_records_meta
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε", sequence: 0)
    make_passage(doc, urn: "urn:d:1:2", text: "οὐλομένην", sequence: 1)
    outside = make_document(source: @other, urn: "urn:o:1")
    make_passage(outside, urn: "urn:o:1:1", text: "not in scope", sequence: 0)

    result = embedder.run!

    assert_equal 2, result.embedded
    assert_equal %w[urn:d:1:1 urn:d:1:2], vector_rows.map { |row| row[:urn] },
                 "exactly the flagged source's passages embed"
    row = vector_rows.first
    assert_equal Nabu::Embed::MODEL, row[:model]
    assert_equal "grc", row[:language]
    assert_equal 4, row[:vec].bytesize, "dim 4 × 1 byte int8"
    assert_equal Nabu::Embed.input_sha("μῆνιν ἄειδε"), row[:text_sha]
    meta = @vectors[Nabu::Embed::META_TABLE].first
    assert_equal 4, meta[:dim]
    assert_equal "i8", meta[:encoding]
  end

  def test_second_run_is_a_no_op_delta
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)
    assert_equal 1, embedder.run!.embedded

    result = embedder.run!
    assert_equal 0, result.embedded, "everything fresh — the incremental contract"
    assert_equal 1, result.skipped_fresh
  end

  def test_revised_text_re_embeds_exactly_that_row
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)
    make_passage(doc, urn: "urn:d:1:2", text: "ἄειδε", sequence: 1)
    embedder.run!
    old = @vectors[Nabu::Embed::VECTORS_TABLE].where(urn: "urn:d:1:2").first

    Nabu::Store::Passage.first(urn: "urn:d:1:1").update(text: "μῆνιν οὐλομένην")
    result = embedder.run!

    assert_equal 1, result.embedded, "only the revised passage re-embeds"
    assert_equal Nabu::Embed.input_sha("μῆνιν οὐλομένην"),
                 @vectors[Nabu::Embed::VECTORS_TABLE].where(urn: "urn:d:1:1").get(:text_sha)
    assert_equal old[:text_sha],
                 @vectors[Nabu::Embed::VECTORS_TABLE].where(urn: "urn:d:1:2").get(:text_sha),
                 "the untouched row is untouched"
  end

  # The owner's constraint made structural: a rebuild re-mints passage
  # ids, and the vectors must not care — keys are (model, urn) + the
  # embedded text's own sha.
  def test_vectors_survive_a_passage_id_renumbering
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)
    embedder.run!

    # Simulate the rebuild: same urn + text, entirely new row ids.
    @catalog[:passages].delete
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)

    assert_equal 0, embedder.run!.embedded,
                 "identical text under a re-minted id owes nothing — never redone from scratch"
  end

  # The P79-5 hard finding: pointed Hebrew embeds marks-stripped; a
  # points-only change therefore owes NO re-embed (the stripped input is
  # identical), while the stored text stays untouched.
  def test_nfc_exempt_language_embeds_marks_stripped
    doc = make_document(urn: "urn:d:hbo", language: "hbo")
    pointed = "בְּרֵאשִׁית"
    make_passage(doc, urn: "urn:d:hbo:1", text: pointed, sequence: 0, language: "hbo")

    embedder.run!
    stripped = pointed.unicode_normalize(:nfd).gsub(/\p{Mn}+/, "")
    assert_equal Nabu::Embed.input_sha(stripped),
                 @vectors[Nabu::Embed::VECTORS_TABLE].first[:text_sha],
                 "the sha is of the marks-stripped embed input"

    Nabu::Store::Passage.first(urn: "urn:d:hbo:1")
                        .update(text: "בּרֵאשִׁית") # repointed, same letters
    repointed_stripped = "בּרֵאשִׁית".unicode_normalize(:nfd).gsub(/\p{Mn}+/, "")
    skip "fixture letters differ" unless repointed_stripped == stripped
    assert_equal 0, embedder.run!.embedded, "a points-only change owes no re-embed"
  end

  def test_empty_text_and_limit
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "   ", sequence: 0)
    make_passage(doc, urn: "urn:d:1:2", text: "α", sequence: 1)
    make_passage(doc, urn: "urn:d:1:3", text: "β", sequence: 2)

    result = embedder(limit: 1).run!
    assert_equal 1, result.embedded, "--limit bounds the campaign"
    assert_equal 1, result.skipped_empty
  end

  def test_worker_error_aborts_resumably
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "fine", sequence: 0)
    make_passage(doc, urn: "urn:d:1:2", text: "BOOM", sequence: 1)

    assert_raises(Nabu::Embed::WorkerError) { embedder(batch_size: 1).run! }
    assert_equal %w[urn:d:1:1], vector_rows.map { |row| row[:urn] },
                 "batches before the failure are committed — re-fire embeds only the rest"
  end

  def test_refuses_an_empty_flag_set
    error = assert_raises(Nabu::Error) { embedder(slugs: []).run! }
    assert_match(/embed_index/, error.message)
  end

  # -- the census ----------------------------------------------------------

  def test_census_counts_fresh_stale_missing
    doc = make_document
    make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)
    make_passage(doc, urn: "urn:d:1:2", text: "ἄειδε", sequence: 1)
    embedder.run!
    Nabu::Store::Passage.first(urn: "urn:d:1:1").update(text: "changed")
    make_passage(doc, urn: "urn:d:1:3", text: "new", sequence: 2)

    census = embedder.census
    assert_equal 3, census.total
    assert_equal 1, census.fresh
    assert_equal 1, census.stale
    assert_equal 1, census.missing
    assert_in_delta 2 / Nabu::Embed::TRIAL_RATE, census.eta_seconds, 0.001
  end
end
