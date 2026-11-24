# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::BatchParallelsPostings — the postings engine. PARITY IS THE
# CONTRACT: over the same corpus and the same effective parameters, it must
# mint exactly the FTS-probe BatchParallels's edges (pair, direction,
# score, chunk) and chunk rows, per anchor exactly Query::Parallels's hits,
# and keep the base producer's journal contract (supersede, resume, refuse).
class BatchParallelsPostingsTest < Minitest::Test
  include StoreTestDB

  HOMER = "ανδρα μοι εννεπε μουσα πολυτροπον ος μαλα πολλα"
  QUOTER = "λεγει που ανδρα μοι εννεπε μουσα πολυτροπον ως φησιν"
  SCHOLIUM = "ο ποιητης ανδρα μοι εννεπε μουσα πολυτροπον λεγει"
  ECHO = "μουσα πολυτροπον ος μαλα πολλα πλαγχθη"
  ENGLISH = "tell me o muse of that man of many devices"
  BYSTANDER = "αλλο τι παντως ασχετον ουδεν κοινον εχει"
  FATHER = "καὶ πάλιν φησίν· ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, ἀλλ’ οὐκ ἐν χρόνῳ."

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @root = Dir.mktmpdir("nabu-reuse")
    @journals = []
    @homerics = Nabu::Store::Source.create(slug: "homerics", name: "Homerics", adapter_class: "TestAdapter",
                                           license_class: "open")
    @closed = Nabu::Store::Source.create(slug: "closed", name: "Closed", adapter_class: "TestAdapter",
                                         license_class: "nc")
    seed!
  end

  def teardown
    @fulltext.disconnect
    @journals.each(&:disconnect)
    FileUtils.rm_rf(@root)
  end

  # -- corpus --------------------------------------------------------------

  def make_passage(doc_urn:, urn:, text:, source: @homerics, language: "grc", sequence: 0, withdrawn: false)
    document = Nabu::Store::Document.find(urn: doc_urn) || Nabu::Store::Document.create(
      source_id: source.id, urn: doc_urn, title: doc_urn, language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: urn, sequence: sequence, language: language, text: text,
      text_normalized: Nabu::Normalize.search_form(text, language: language),
      annotations_json: "{}", content_sha_raw: "x", revision: 1, withdrawn: withdrawn
    )
  end

  def load_fixture(slug, klass)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name, license_class: "open")
    Nabu::Store::Loader.new(db: @catalog, source: source)
                       .load_from(klass.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
  end

  # Greek quotation networks (two passages of one document tie a pool),
  # an nc witness (the --license filter), a withdrawn twin (visibility),
  # real SBLGNT + a U+2019 Father, real kanripo + a commentary quoting it.
  def seed!
    load_fixture("kanripo", Nabu::Adapters::Kanripo)
    load_fixture("sblgnt", Nabu::Adapters::Sblgnt)
    make_passage(doc_urn: "urn:h:od", urn: "urn:h:od:1.1", text: HOMER)
    make_passage(doc_urn: "urn:h:od", urn: "urn:h:od:1.2", text: ECHO, sequence: 1)
    make_passage(doc_urn: "urn:q:hist", urn: "urn:q:hist:12.1", text: QUOTER)
    make_passage(doc_urn: "urn:q:hist", urn: "urn:q:hist:12.2", text: QUOTER, sequence: 1)
    make_passage(doc_urn: "urn:r:schol", urn: "urn:r:schol:1", text: SCHOLIUM)
    make_passage(doc_urn: "urn:e:od-eng", urn: "urn:e:od-eng:1.1", text: ENGLISH, language: "eng")
    make_passage(doc_urn: "urn:b:misc", urn: "urn:b:misc:1", text: BYSTANDER)
    make_passage(doc_urn: "urn:c:nc", urn: "urn:c:nc:1", text: SCHOLIUM, source: @closed)
    make_passage(doc_urn: "urn:w:gone", urn: "urn:w:gone:1", text: QUOTER, withdrawn: true)
    make_passage(doc_urn: "urn:f:father", urn: "urn:f:father:1", text: FATHER)
    # The passage's LONGEST Han run, not its head (kanripo lines open on the
    # ubiquitous 欽定四庫全書 header — a common gram, rightly scored low).
    line = @catalog[:passages].where(urn: kanripo_anchor_urns.first).get(:text_search)
                              .scan(/\p{Han}+/).max_by(&:size)
    make_passage(doc_urn: "urn:z:shu", urn: "urn:z:shu:1", text: "注曰#{line[0, 9]}者也", language: "lzh",
                 source: @homerics)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: %w[kanripo homerics])
  end

  def kanripo_doc
    @kanripo_doc ||= @catalog[:documents].join(:passages, document_id: :id)
                                         .where(Sequel[:documents][:urn].like("urn:nabu:kanripo:%"))
                                         .group(Sequel[:documents][:urn])
                                         .having { count.function.* >= 3 }
                                         .order(Sequel.function(:sum,
                                                                Sequel.function(:length,
                                                                                Sequel[:passages][:text_search])))
                                         .get(Sequel[:documents][:urn])
  end

  def kanripo_anchor_urns
    @catalog[:passages].join(:documents, id: :document_id)
                       .where(Sequel[:documents][:urn] => kanripo_doc)
                       .order(Sequel[:passages][:urn]).select_map(Sequel[:passages][:urn])
  end

  # -- rigs ----------------------------------------------------------------

  def journal
    Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:")).tap { |db| @journals << db }
  end

  def census!(scope, gram_size: 4, lang: nil)
    Nabu::ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root)
                     .run(scope, gram_size: gram_size, lang: lang, shards: 3)
  end

  def fts(into)
    Nabu::BatchParallels.new(catalog: @catalog, fulltext: @fulltext, journal: into)
  end

  def postings(into, workers: 1, slice: Nabu::BatchParallelsPostings::SLICE)
    Nabu::BatchParallelsPostings.new(catalog: @catalog, fulltext: @fulltext, journal: into, root: @root,
                                     workers: workers, slice: slice)
  end

  def edges(db)
    db[:links].order(:id).select_map(%i[from_urn to_urn kind score chunk])
  end

  def chunk_rows(db)
    db[:link_run_chunks].order(:chunk)
                        .select_map(%i[chunk first_urn last_urn anchors candidates edges_inserted edges_refreshed])
  end

  def profile(**knobs)
    Nabu::ReuseProfiles::Profile.new(name: "demo", lang: "grc", serves: "test", gram_size: nil, min_score: nil,
                                     per_anchor: nil, candidate_pool: nil, stop_tokens: [], rationale: "test",
                                     **knobs)
  end

  def assert_parity(scope, gram_size: 4, census_lang: nil, workers: 1, slice: Nabu::BatchParallelsPostings::SLICE,
                    **options)
    census!(scope, gram_size: gram_size, lang: census_lang)
    a = journal
    b = journal
    expected = fts(a).run(scope, **options)
    actual = postings(b, workers: workers, slice: slice).run(scope, **options)
    assert_equal edges(a), edges(b), "#{scope} #{options}: identical edges (pair, direction, score, chunk)"
    assert_equal chunk_rows(a), chunk_rows(b), "#{scope} #{options}: identical chunk rows"
    assert_equal expected.to_h.except(:run_id, :elapsed), actual.to_h.except(:run_id, :elapsed)
    [a, b, actual]
  end

  # -- parity ----------------------------------------------------------------

  def test_parity_greek_defaults_and_every_knob
    _a, b, = assert_parity("homerics", lang: "grc")
    refute_empty edges(b), "the network is really mined"
    assert_parity("homerics", lang: "grc", chunk_size: 2)
    assert_parity("homerics", lang: "grc", per_anchor: 1, min_score: 0.2)
    assert_parity("homerics", lang: "grc", candidate_pool: 1)
    assert_parity("homerics", lang: "grc", license: "open")
    assert_parity("homerics", gram_size: 3, census_lang: "grc",
                              profile: profile(gram_size: 3, stop_tokens: %w[μοι μουσα]), chunk_size: 3)
  end

  def test_parity_on_real_sblgnt_and_kanripo_through_the_cjk_lane
    _a, b, = assert_parity("sblgnt", chunk_size: 7)
    refute_empty edges(b), "the Father's U+2019 quotation of John 1:1 is found"
    _a, b, = assert_parity(kanripo_doc, lang: "lzh")
    assert(edges(b).any? { |edge| edge[1] == "urn:z:shu:1" }, "the commentary quoting the line, via the lane")
  end

  def test_forked_workers_mint_the_serial_journal
    census!("sblgnt")
    serial = journal
    forked = journal
    postings(serial).run("sblgnt", chunk_size: 5)
    postings(forked, workers: 3, slice: 2).run("sblgnt", chunk_size: 5)
    assert_equal edges(serial), edges(forked)
    assert_equal chunk_rows(serial), chunk_rows(forked)
  end

  # A chunk cut into many worker tasks (and an unchunked run cut the same
  # way) commits exactly the one-task chunk's rows.
  def test_multi_slice_chunks_keep_parity
    assert_parity("sblgnt", slice: 3, chunk_size: 8)
    assert_parity("sblgnt", slice: 3, workers: 2)
    assert_parity("homerics", lang: "grc", slice: 1, chunk_size: 3, workers: 2)
  end

  def test_per_anchor_hits_equal_the_interactive_engine
    census!("sblgnt")
    manifest = Nabu::Store::ReusePostings.builds(@root).first
    cutoff = Nabu::Query::ParallelsPostings.cutoff(@catalog)
    worker = Nabu::Query::ParallelsPostings.new(cutoff: cutoff, lane: true,
                                                reader: Nabu::Store::ReusePostings::Reader.new(manifest))
    committer = Nabu::Query::ParallelsPostings.new(catalog: @catalog, cutoff: cutoff, lane: true)
    interactive = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)
    anchors = @catalog[:passages].join(:documents, id: :document_id)
                                 .where(Sequel[:documents][:urn].like("urn:nabu:sblgnt%"))
                                 .select_map([Sequel[:passages][:urn], Sequel[:passages][:id],
                                              Sequel[:passages][:document_id], Sequel[:passages][:text_search]])
    worker.prefetch!(anchors, gram_size: 4)
    pools = anchors.map { |anchor| worker.pool_for(anchor, gram_size: 4, stop_tokens: nil, limit: 15, pool: 300) }
    resolved = committer.resolve(pools.flat_map(&:first), lang: nil, license: nil)
    compared = 0
    anchors.zip(pools).each do |anchor, pool_entry|
      expected = interactive.run(anchor[0], limit: 15, echoes: false).hits
      actual = committer.hits(anchor, pool_entry, resolved: resolved, limit: 15, gram_size: 4, pool: 300)
      assert_equal expected, actual, "#{anchor[0]}: every hit field (urn, score, grams, loci, evidence)"
      compared += expected.size
    end
    assert_operator compared, :>, 0
    worker.close
  end

  # -- the journal contract --------------------------------------------------

  def test_run_row_records_the_engine_and_the_store
    census!("homerics", lang: "grc")
    db = journal
    result = postings(db).run("homerics", lang: "grc", min_score: 0.1)
    run = db[:link_runs].first(id: result.run_id)
    params = JSON.parse(run[:params_json])
    assert_equal "postings", params["engine"]
    assert_match(/\Ahomerics\.grc\.g4#\h{12}\z/, params["postings"])
    assert_equal [0.1, 5, "grc", 4, 300], params.values_at("min_score", "per_anchor", "lang", "gram_size",
                                                           "candidate_pool")
    assert_match(%r{\Aparallels-batch/2\+postings/1 nabu/}, run[:code_version])
    assert_equal "complete", run[:status]
  end

  def test_rerun_supersedes_across_engines
    census!("homerics", lang: "grc")
    db = journal
    fts(db).run("homerics", lang: "grc")
    before = edges(db).map { |edge| edge.first(4) }
    second = postings(db).run("homerics", lang: "grc")
    assert_equal 1, second.superseded_runs, "one producer, one scope: the postings run replaces the FTS run"
    assert_equal(before, edges(db).map { |edge| edge.first(4) })
    assert_equal 1, db[:link_runs].count
  end

  class Killed < StandardError; end

  def test_a_killed_run_resumes_at_its_cursor
    census!("homerics", lang: "grc")
    whole = journal
    postings(whole).run("homerics", lang: "grc", chunk_size: 2)
    db = journal
    assert_raises(Killed) do
      postings(db).run("homerics", lang: "grc", chunk_size: 2, on_chunk: ->(_report) { raise Killed })
    end
    assert_equal "running", db[:link_runs].first[:status]
    result = postings(db).run("homerics", lang: "grc", chunk_size: 2)
    assert result.resumed
    assert_equal(edges(whole).map { |edge| edge.first(5) }, edges(db).map { |edge| edge.first(5) })
    assert_equal "complete", db[:link_runs].first[:status]

    db2 = journal
    assert_raises(Killed) do
      fts(db2).run("homerics", lang: "grc", chunk_size: 2, on_chunk: ->(_report) { raise Killed })
    end
    error = assert_raises(Nabu::Error) { postings(db2).run("homerics", lang: "grc", chunk_size: 2) }
    assert_match(/unfinished/, error.message, "an FTS run is never resumed by the postings engine")
  end

  def test_refuses_without_a_store_and_with_a_stale_one
    error = assert_raises(Nabu::Error) { postings(journal).run("homerics", lang: "grc") }
    assert_match(/nabu reuse build homerics --gram-size 4 --lang grc/, error.message)

    census!("homerics", lang: "grc")
    make_passage(doc_urn: "urn:late:doc", urn: "urn:late:doc:1", text: "νεον τι")
    error = assert_raises(Nabu::Error) { postings(journal).run("homerics", lang: "grc") }
    assert_match(/is stale .*source\(s\) moved: homerics/, error.message)
  end

  def test_a_lang_agnostic_store_serves_a_lang_scoped_run
    census!("homerics")
    a = journal
    b = journal
    fts(a).run("homerics", lang: "grc")
    postings(b).run("homerics", lang: "grc")
    assert_equal edges(a), edges(b)
  end
end
