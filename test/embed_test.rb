# frozen_string_literal: true

require "test_helper"

# Nabu::Embed (P93-4) — the semantic-vector build lane, exercised
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
      text: text, text_normalized: text, content_sha_raw: "x", revision: 1, withdrawn: withdrawn
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

  # -- the scope walk ------------------------------------------------------
  #
  # The walk is a keyset over (document, sequence) per scoped source,
  # riding documents_source_id_index + passages_document_id_sequence_index
  # with no sort: the earlier passage-id keyset over the joined scope
  # re-collected and temp-sorted the WHOLE remaining scope on every page
  # (quadratic in scope size; measured hours on the live library).

  # A multi-source fixture with interleaved ids, a document larger than a
  # page, withdrawn passages and documents, and an out-of-scope source.
  def build_walk_fixture
    third = Nabu::Store::Source.create(slug: "lit2", name: "Lit2", adapter_class: "TestAdapter",
                                       license_class: "open")
    docs = [make_document(urn: "urn:d:a"), make_document(source: third, urn: "urn:d:b"),
            make_document(source: @other, urn: "urn:o:a"), make_document(urn: "urn:d:c")]
    gone = make_document(urn: "urn:d:gone")
    gone.update(withdrawn: true)
    7.times do |i|
      docs.each_with_index do |doc, j|
        make_passage(doc, urn: "#{doc.urn}:#{i}", text: "t#{i}#{j}", sequence: i * 2)
      end
      make_passage(gone, urn: "urn:d:gone:#{i}", text: "g", sequence: i)
    end
    make_passage(docs[0], urn: "urn:d:a:w", text: "w", sequence: 99, withdrawn: true)
  end

  # The pre-fix scope definition, as a plain unpaged query: the set the
  # walk must yield exactly.
  def expected_scope_urns(slugs)
    @catalog[:passages]
      .join(:documents, id: Sequel[:passages][:document_id])
      .join(:sources, id: Sequel[:documents][:source_id])
      .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
      .where(Sequel[:sources][:slug] => slugs)
      .select_map(Sequel[:passages][:urn]).sort
  end

  def walked_urns(walker)
    pages = []
    walker.send(:each_scope_page) { |rows| pages << rows.map { |row| row[:urn] } }
    pages
  end

  def test_scope_walk_yields_exactly_the_scope_across_pages
    build_walk_fixture
    slugs = %w[lit lit2]
    pages = walked_urns(embedder(slugs: slugs, page_size: 3))

    assert_equal expected_scope_urns(slugs), pages.flatten.sort
    assert_equal pages.flatten.uniq.size, pages.flatten.size, "no row yielded twice"
    assert(pages.all? { |page| page.size <= 3 }, "pages stay bounded by the page size")
    assert_operator pages.size, :>, 3, "the fixture really spans many pages"
  end

  def test_census_and_run_agree_with_the_scope_under_small_pages
    build_walk_fixture
    slugs = %w[lit lit2]
    expected = expected_scope_urns(slugs)
    assert_equal expected.size, embedder(slugs: slugs, page_size: 2).census.missing
    assert_equal expected.size, embedder(slugs: slugs, page_size: 2).run!.embedded
    assert_equal(expected, vector_rows.map { |row| row[:urn] })
  end

  def test_scope_walk_pages_need_no_sort
    build_walk_fixture
    sqls = []
    logger = Object.new
    logger.define_singleton_method(:info) { |msg| sqls << msg }
    %i[debug warn error].each { |level| logger.define_singleton_method(level) { |_msg| nil } }
    @catalog.loggers << logger
    walked_urns(embedder(slugs: %w[lit lit2], page_size: 3))
    @catalog.loggers.delete(logger)

    pages = sqls.map { |line| line.sub(/\A\([\d.]+s\)\s*/, "") }
                .select { |sql| sql.start_with?("SELECT") && sql.include?("FROM `passages`") }
    refute_empty pages
    pages.each do |sql|
      plan = @catalog.fetch("EXPLAIN QUERY PLAN #{sql}").map { |row| row[:detail] }
      refute(plan.any? { |step| step.include?("TEMP B-TREE") }, "page query sorts: #{plan.inspect}")
      assert(plan.any? { |step| step.include?("passages_document_id_sequence_index") },
             "page query rides the (document, sequence) index: #{plan.inspect}")
    end
  end
end
