# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ReuseCensus + Store::ReusePostings — the gram-postings census, held
# to FOLD-BOTH-SIDES against the real FTS index: for every gram a scope's
# anchors probe, the postings engine's rows must be EXACTLY the rows the
# FTS engine's own fts_probe returns on the same data (same passages, same
# order), or — for a gram at or over the common-gram cutoff — skipped by the
# same rule. Real fixtures (kanripo through the CJK lane; SBLGNT, whose
# U+02BC elision is a LETTER to unicode61) plus inline witnesses for the
# folds that move matches (U+2019 elision, a common gram over the cutoff).
class ReuseCensusTest < Minitest::Test
  include StoreTestDB

  JOHN_1_1 = "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος."
  # A U+2019 elision witness (First1K/Swete style) quoting John 1:1–2.
  FATHER = "καὶ πάλιν φησίν· ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, ἀλλ’ οὐκ ἐν χρόνῳ."
  COMMON = "αυτη η φρασις κοινοτατη εστιν"

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @root = Dir.mktmpdir("nabu-reuse")
    load_fixture("kanripo", Nabu::Adapters::Kanripo)
    load_fixture("sblgnt", Nabu::Adapters::Sblgnt)
    @inline = Nabu::Store::Source.create(slug: "inline", name: "Inline", adapter_class: "TestAdapter",
                                         license_class: "open")
  end

  def teardown
    @fulltext.disconnect
    FileUtils.rm_rf(@root)
  end

  def load_fixture(slug, klass)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name, license_class: "open")
    Nabu::Store::Loader.new(db: @catalog, source: source)
                       .load_from(klass.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
  end

  def make_passage(doc_urn:, urn:, text:, language: "grc", sequence: 0)
    document = Nabu::Store::Document.find(urn: doc_urn) || Nabu::Store::Document.create(
      source_id: @inline.id, urn: doc_urn, title: doc_urn, language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: urn, sequence: sequence, language: language, text: text,
      text_normalized: Nabu::Normalize.search_form(text, language: language),
      annotations_json: "{}", content_sha_raw: "x", revision: 1, withdrawn: false
    )
  end

  def index!(cjk: true)
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: cjk ? %w[kanripo inline] : [])
  end

  def census(scope, gram_size: 4, lang: nil, workers: 1)
    Nabu::ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root)
                     .run(scope, gram_size: gram_size, lang: lang, shards: 3, workers: workers)
  end

  # The smallest kanripo document with a few passages — a scope whose
  # every gram can be FTS-probed in test time.
  def small_kanripo_doc
    @catalog[:documents].join(:passages, document_id: :id)
                        .where(Sequel[:documents][:urn].like("urn:nabu:kanripo:%"))
                        .group(Sequel[:documents][:urn])
                        .having { count.function.* >= 3 }
                        .order(Sequel.function(:sum, Sequel.function(:length, Sequel[:passages][:text_search])))
                        .get(Sequel[:documents][:urn])
  end

  # Both engines' fts_probe rows for every gram of every anchor in +scope+.
  def assert_fold_both_sides(scope, manifest, gram_size: 4)
    fts = Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)
    fts.send(:snapshot_cutoffs)
    cutoff = fts.instance_variable_get(:@common_gram_df)
    reader = Nabu::Store::ReusePostings::Reader.new(manifest)
    postings = Nabu::Query::ParallelsPostings.new(cutoff: cutoff, lane: !manifest.provenance["lane"].nil?,
                                                  reader: reader)
    anchors = @catalog[:passages].join(:documents, id: :document_id)
                                 .where(Sequel[:documents][:urn].like("#{scope}%"))
                                 .select_map([Sequel[:passages][:urn], Sequel[:passages][:id],
                                              Sequel[:passages][:document_id], Sequel[:passages][:text_search]])
    refute_empty anchors
    postings.prefetch!(anchors, gram_size: gram_size)
    probed = matched = 0
    anchors.each do |anchor|
      postings.send(:shingle, postings.send(:gram_tokens, anchor[3]), gram_size).uniq.each do |gram|
        expected = fts.send(:fts_probe, gram)
        actual = postings.send(:fts_probe, gram)
        probed += 1
        if expected.size >= cutoff
          assert_operator actual.size, :>=, cutoff, "#{gram.join(' ')}: common on both sides"
        else
          matched += 1 unless expected.empty?
          assert_equal expected.map { |row| row[:passage_id] }, actual.map { |row| row[:passage_id] },
                       "#{gram.join(' ')}: postings rows ≡ FTS phrase rows (same order)"
        end
      end
    end
    postings.close
    [probed, matched]
  end

  def test_cjk_postings_reproduce_the_fts_lane_union_on_real_kanripo
    index!
    scope = small_kanripo_doc
    result = census(scope)
    provenance = result.manifest.provenance
    refute_nil provenance["lane"], "the CJK lane is stamped"
    probed, matched = assert_fold_both_sides(scope, result.manifest)
    assert_operator probed, :>, 50
    assert_operator matched, :>, 50, "real grams really match (the anchors themselves, at least)"
    assert_includes provenance.dig("counts", "prefilter"), "\\p{Han}",
                    "a Han vocabulary prefilters to Han-bearing passages"
    refute_includes provenance.dig("counts", "prefilter"), "Greek"
    assert_operator provenance.dig("counts", "passages_prefiltered"), :>, 0, "the Greek never reached a worker"
  end

  def test_with_kanripo_off_the_lane_han_grams_answer_from_the_main_lane_only
    index!(cjk: false)
    scope = small_kanripo_doc
    result = census(scope)
    assert_equal [], result.manifest.provenance["lane"], "the lane exists but indexes no source"
    assert_fold_both_sides(scope, result.manifest)
  end

  def test_greek_elision_and_case_folds_match_like_the_index
    make_passage(doc_urn: "urn:inline:father", urn: "urn:inline:father:1", text: FATHER)
    index!
    result = census("sblgnt")
    probed, matched = assert_fold_both_sides("urn:nabu:sblgnt", result.manifest)
    assert_operator probed, :>, 100
    assert_operator matched, :>, 0
  end

  def test_a_gram_over_the_cutoff_is_held_common_and_skipped_alike
    make_passage(doc_urn: "urn:inline:anchor", urn: "urn:inline:anchor:1", text: "#{COMMON} και αλλα")
    520.times do |i|
      make_passage(doc_urn: "urn:inline:crowd#{i}", urn: "urn:inline:crowd#{i}:1", text: "#{COMMON} #{i}")
    end
    index!
    result = census("urn:inline:anchor")
    assert_fold_both_sides("urn:inline:anchor", result.manifest)
    engine = Nabu::Query::ParallelsPostings.new(cutoff: 500, lane: true)
    key = engine.keys_for(%w[αυτη η φρασις κοινοτατη].map do |token|
      Nabu::Normalize.search_form(token, language: "grc")
    end)
                .first
    engine.close
    reader = Nabu::Store::ReusePostings::Reader.new(result.manifest)
    assert_equal :common, reader.lookup([key])[key], "df ≥ cap keeps the df, drops the postings"
    reader.close
  end

  def test_forked_census_builds_the_same_store
    index!
    scope = small_kanripo_doc
    serial = census(scope).manifest
    serial_rows = dump(serial)
    forked = census(scope, workers: 3).manifest
    assert_equal serial_rows, dump(forked), "worker count never changes a posting"
    assert_equal serial.provenance["counts"].except("raw_rows", "pass_seconds"),
                 forked.provenance["counts"].except("raw_rows", "pass_seconds")
  end

  def test_a_rebuild_replaces_the_store_whole_and_a_failed_one_keeps_it
    index!
    scope = small_kanripo_doc
    first = census(scope).manifest
    census_engine = Nabu::ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root)
    census_engine.define_singleton_method(:finalize) { |*_args, **_kw| raise Nabu::Error, "boom" }
    assert_raises(Nabu::Error) { census_engine.run(scope, gram_size: 4, shards: 3) }
    assert_equal [first.name], Nabu::Store::ReusePostings.builds(@root).map(&:name)
    assert_empty Nabu::Store::ReusePostings.unfinished(@root), "a failed build leaves no staging behind"
    assert_equal first.provenance["built_at"], Nabu::Store::ReusePostings.builds(@root).first.provenance["built_at"]
  end

  def test_staleness_names_every_moved_input
    index!
    scope = small_kanripo_doc
    manifest = census(scope).manifest
    census_engine = Nabu::ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root)
    assert_empty census_engine.staleness(manifest), "fresh build is current"

    make_passage(doc_urn: "urn:inline:late", urn: "urn:inline:late:1", text: "νεον κειμενον")
    reasons = census_engine.staleness(manifest)
    assert(reasons.any? { |reason| reason.include?("source(s) moved: inline") }, reasons.inspect)

    moved = manifest.with(provenance: manifest.provenance.merge("code" => "other", "cap" => 1))
    reasons = census_engine.staleness(moved)
    assert(reasons.any? { |reason| reason.include?("census code changed") }, reasons.inspect)
    assert(reasons.any? { |reason| reason.include?("exceeds the build's cap 1") }, reasons.inspect)
  end

  def test_a_measure_run_times_every_pass_and_installs_nothing
    index!
    scope = small_kanripo_doc
    result = Nabu::ReuseCensus.new(catalog: @catalog, fulltext: @fulltext, root: @root)
                              .run(scope, gram_size: 4, shards: 2, measure: 10)
    assert_nil result.manifest
    m = result.measurement
    assert_operator m["passages_scanned"], :>=, 10
    assert_operator m["passages_scanned"], :<, @catalog[:passages].count, "the corpus pass stopped early"
    assert_equal %w[anchors finalize universe], m["pass_seconds"].keys.sort
    assert_operator m["projected_universe_seconds"], :>=, m.dig("pass_seconds", "universe")
    assert_empty Nabu::Store::ReusePostings.builds(@root)
    assert_empty Nabu::Store::ReusePostings.unfinished(@root)
  end

  def test_a_killed_builds_staging_is_cleared_and_a_live_one_refuses
    index!
    scope = small_kanripo_doc
    name = Nabu::Store::ReusePostings.build_name(scope: scope, gram_size: 4)
    dead = File.join(@root, "#{name}.building-999999999")
    FileUtils.mkdir_p(dead)
    census(scope)
    refute_path_exists dead, "a dead process's staging is swept by the next build"

    live = File.join(@root, "#{name}.building-#{Process.ppid}")
    FileUtils.mkdir_p(live)
    error = assert_raises(Nabu::Store::ReusePostings::Error) { census(scope) }
    assert_match(/another census is building it/, error.message)
  ensure
    FileUtils.rm_rf(live) if live
  end

  def test_build_names_are_filesystem_safe_and_scoped
    assert_equal "urn_nabu_sblgnt_john.grc.g4",
                 Nabu::Store::ReusePostings.build_name(scope: "urn:nabu:sblgnt:john", lang: "grc", gram_size: 4)
    assert_equal "kanripo.g4", Nabu::Store::ReusePostings.build_name(scope: "kanripo", gram_size: 4)
  end

  private

  def dump(manifest)
    (0...manifest.shards).map do |shard|
      db = Nabu::Store.connect(File.join(manifest.dir, format("shard-%02d.sqlite3", shard)), readonly: true)
      [db[:grams].order(:gram).select_map(%i[gram df]),
       db[:postings].order(:gram, :passage_id).select_map(%i[gram passage_id lanes])]
    ensure
      db&.disconnect
    end
  end
end
