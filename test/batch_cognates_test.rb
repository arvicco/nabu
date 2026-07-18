# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

# Nabu::BatchCognates (P16-2): the whole-work cognate map persisting
# kind=cognate edges between cross-language witness passages that meet at a
# reconstruction root; the meet (ref · root [shelf]) rides each edge's detail.
# Same rig as Query::CognatesTest: real wiktionary-recon fixtures for the
# shelf, PROIEL-shaped sentences for the hub, plus an in-memory journal.
class BatchCognatesTest < Minitest::Test
  include StoreTestDB

  NT_REGISTRY = <<~YAML
    nt:
      title: "New Testament (test witnesses)"
      witnesses:
        - document: urn:nabu:test:grc-nt
        - document: urn:nabu:test:marianus
        - document: urn:nabu:test:gothic
        - document: urn:nabu:test:oe-mark
  YAML

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    recon = Nabu::Store::Source.create(
      slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
      adapter_class: "Nabu::Adapters::WiktionaryRecon",
      license: "CC-BY-SA + GFDL", license_class: "attribution"
    )
    Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                 .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                            workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
    @texts = Nabu::Store::Source.create(
      slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
    )
    @docs = {}
  end

  def teardown
    @fulltext.disconnect
    @journal.disconnect
  end

  # -- rig (the Query::CognatesTest shape) ------------------------------------

  def registry
    Dir.mktmpdir do |dir|
      path = File.join(dir, "alignments.yml")
      File.write(path, NT_REGISTRY)
      return Nabu::AlignmentRegistry.load(path)
    end
  end

  def witness_doc(tail, language:, title: tail)
    @docs[tail] ||= Nabu::Store::Document.create(
      source_id: @texts.id, urn: "urn:nabu:test:#{tail}", title: title,
      language: language, content_sha256: "x", revision: 1, withdrawn: false
    )
  end

  def make_sentence(doc, ref:, lemmas:, forms: nil)
    seq = @catalog[:passages].where(document_id: doc.id).count
    tokens = lemmas.each_with_index.map do |lemma, i|
      { "citation_part" => ref, "lemma" => lemma, "form" => (forms || lemmas)[i] }
    end
    Nabu::Store::Passage.create(
      document_id: doc.id, urn: "#{doc.urn}:#{seq + 1}", sequence: seq,
      language: doc.language, text: "t", text_normalized: "t",
      annotations_json: JSON.generate({ "citation" => ref, "tokens" => tokens }),
      content_sha256: "x", revision: 1
    )
  end

  def inflate_df(language:, lemma:, count:)
    doc = witness_doc("filler-#{language}", language: language)
    count.times { make_sentence(doc, ref: "X 1.1", lemmas: [lemma]) }
  end

  # grc ἔφᾰγον × chu богъ meet at MARK 1.1 (PIE *bʰeh₂g- in the crosswalk
  # fixtures); ang cāsere × chu цѣсар҄ь at MARK 2.1 (gem-pro *kaisaraz — the
  # loan shelf). Exactly the Query::CognatesTest constellation.
  def seed_gospel_verses
    grc = witness_doc("grc-nt", language: "grc", title: "Greek NT")
    chu = witness_doc("marianus", language: "chu", title: "Codex Marianus")
    ang = witness_doc("oe-mark", language: "ang", title: "OE Mark")
    make_sentence(grc, ref: "MARK 1.1", lemmas: ["ἔφᾰγον"], forms: ["ἔφαγεν"])
    make_sentence(chu, ref: "MARK 1.1", lemmas: ["богъ"], forms: ["ба"])
    make_sentence(ang, ref: "MARK 2.1", lemmas: ["cāsere"])
    make_sentence(chu, ref: "MARK 2.1", lemmas: ["цѣсар҄ь"])
  end

  def rebuild!(reg = registry)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: reg)
    reg
  end

  def producer(reg)
    Nabu::BatchCognates.new(catalog: @catalog, fulltext: @fulltext, registry: reg, journal: @journal)
  end

  def run_batch(**)
    producer(rebuild!).run("nt", **)
  end

  # -- edge shape ---------------------------------------------------------------

  def test_cross_language_witness_passages_link_with_the_meet_as_detail
    seed_gospel_verses
    result = run_batch
    assert_equal 2, result.edges_written, "one edge per cross-language pair per verse meet"
    edges = @journal[:links].order(:from_urn).all
    assert_equal(%w[cognate cognate], edges.map { |e| e[:kind] })

    eat = edges.find { |e| e[:detail].include?("MARK 1.1") }
    assert_equal %w[urn:nabu:test:grc-nt:1 urn:nabu:test:marianus:1],
                 [eat[:from_urn], eat[:to_urn]].sort
    assert_operator eat[:from_urn], :<, eat[:to_urn],
                    "direction is normalized (lexicographically smaller urn first)"
    assert_equal "MARK 1.1 · *bʰeh₂g- [ine-pro]", eat[:detail],
                 "detail = ref · root [shelf]"
    assert_in_delta 1.0, eat[:score], 0.001, "score = distinct roots met"

    caesar = edges.find { |e| e[:detail].include?("MARK 2.1") }
    assert_match(/\*kaisaraz \[gem-pro\]/, caesar[:detail],
                 "the loan shelf rides the edge — the borrowing signal")
    assert_equal %w[urn:nabu:test:marianus:2 urn:nabu:test:oe-mark:1],
                 [caesar[:from_urn], caesar[:to_urn]].sort
  end

  # P18-3: P16-2 pinned multi-ROOT pairs collapsing to one edge; the same
  # holds for duplicate closure rows of ONE root (multi-subtree descent —
  # forced here, the indexer never emits them): the meets Set keeps one
  # meet, the edge count and score are unchanged.
  def test_duplicate_closure_rows_collapse_to_one_edge_with_one_meet
    seed_gospel_verses
    reg = rebuild!
    table = @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE]
    row = table.where(language: "chu", lemma_folded: "bogъ", # P27-2 skeleton key
                      root_urn: "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root").first
    refute_nil row, "the closure must hold the chu богъ → *bʰeh₂g- row"
    table.insert(row)

    result = producer(reg).run("nt")
    assert_equal 2, result.edges_written, "the duplicate closure row mints no extra edge"
    eat = @journal[:links].all.find { |e| e[:detail].include?("MARK 1.1") }
    assert_equal "MARK 1.1 · *bʰeh₂g- [ine-pro]", eat[:detail], "the meet is listed once"
    assert_in_delta 1.0, eat[:score], 0.001, "score counts distinct roots, not closure rows"
  end

  def test_no_edge_within_one_language
    grc = witness_doc("grc-nt", language: "grc", title: "Greek NT")
    chu = witness_doc("marianus", language: "chu", title: "Codex Marianus")
    make_sentence(chu, ref: "MARK 1.1", lemmas: ["богъ"])
    make_sentence(chu, ref: "MARK 1.1", lemmas: ["богъ"]) # a second OCS witness sentence
    make_sentence(grc, ref: "MARK 1.1", lemmas: ["ἔφᾰγον"])
    run_batch
    same_language = @journal[:links].all.select do |edge|
      edge[:from_urn].include?("marianus") && edge[:to_urn].include?("marianus")
    end
    assert_empty same_language, "two codices of one language are transmission, not comparison"
    assert_equal 2, @journal[:links].count, "each OCS sentence pairs with the Greek one"
  end

  def test_langs_restricts_and_rides_params_json
    seed_gospel_verses
    result = run_batch(langs: %w[grc chu])
    assert_equal 1, result.edges_written, "the ang×chu caesar meet is out of --langs"
    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal({ "kind" => "cognate", "langs" => %w[grc chu] }, JSON.parse(run[:params_json]))
    assert_equal "cognates", run[:producer]
    assert_equal "nt", run[:scope]
    assert_match(%r{cognates-batch/1}, run[:code_version])
  end

  # -- suppression stays honest ----------------------------------------------------

  def test_common_word_suppression_applies_and_all_lifts_and_is_recorded
    seed_gospel_verses
    inflate_df(language: "grc", lemma: "ἔφᾰγον", count: 60)
    inflate_df(language: "chu", lemma: "богъ", count: 60)
    reg = rebuild!
    suppressed = producer(reg).run("nt")
    assert_equal 1, suppressed.edges_written, "the now-common god meet fell; caesar survives"
    assert_operator suppressed.suppressed, :>=, 1, "what fell is counted, never silent"

    lifted = producer(reg).run("nt", all: true)
    assert_equal 2, lifted.edges_written, "--all keeps the common-word meet"
    run = @journal[:link_runs].first(id: lifted.run_id)
    assert JSON.parse(run[:params_json]).fetch("all"), "the lifted suppression is recorded"
  end

  # -- rerun idempotency ---------------------------------------------------------------

  def test_rerun_supersedes_and_is_idempotent
    seed_gospel_verses
    reg = rebuild!
    first = producer(reg).run("nt")
    second = producer(reg).run("nt")
    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal 1, @journal[:link_runs].count
    assert_equal first.edges_written, @journal[:links].count
    assert_equal second.run_id, @journal[:links].first[:run_id], "edges cite the current run"
  end

  # -- contract -----------------------------------------------------------------------------

  def test_batch_takes_a_registered_work_id_not_a_ref
    seed_gospel_verses
    reg = rebuild!
    error = assert_raises(Nabu::Query::Cognates::Error) { producer(reg).run("MARK 1.1") }
    assert_match(/registered work id/, error.message)
    assert_match(/interactive/, error.message, "the per-ref path is pointed at")
  end
end
