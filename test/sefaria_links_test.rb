# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::SefariaLinks (P150): Sefaria's connection graph (links/links*.csv,
# the bucket's special files) → kind=reference edges between HELD passages.
# The catalog is the real one the loader builds from the sefaria fixture
# tree (plus the oshb Genesis fixture — the Tanakh base-text leg); the
# link rows are REAL upstream rows (test/fixtures/sefaria/links, cut
# verbatim from the 2026-10 export shards). Three Masoretic book documents
# the oshb fixture does not carry (Obadiah, Jonah, Ruth) are added as
# catalog rows so the targum/commentary/midrash rows have a held base
# verse — the resolver joins on catalog urns, so that is all it needs.
class SefariaLinksTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("sefaria")
  OSHB_FIXTURES = Nabu::TestSupport.fixtures("oshb")

  ZOHAR_CHADASH = "urn:nabu:sefaria:zohar-chadash:he:zohar-chadash"
  MINCHAT_SHAI = "urn:nabu:sefaria:minchat-shai-on-jonah:he:minchat-shai"
  TARGUM_OBADIAH = "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"
  KAUFMANN = "urn:nabu:sefaria:mishnah-tamid:he:mishnah-based-on-the-kaufmann-manuscript-edited-by-dan-be-eri"
  KULP = "urn:nabu:sefaria:mishnah-tamid:en:mishnah-yomit-by-dr-joshua-kulp"
  TAMID_WIKISOURCE = "urn:nabu:sefaria:tamid:he:wikisource-talmud-bavli"
  RUTH_RABBAH = "urn:nabu:sefaria:ruth-rabbah:en:the-sefaria-midrash-rabbah-2022"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    sefaria = Nabu::Store::Source.create(slug: "sefaria", name: "Sefaria",
                                         adapter_class: "Nabu::Adapters::Sefaria", license_class: "open")
    Nabu::Store::Loader.new(db: @catalog, source: sefaria)
                       .load_from(Nabu::Adapters::Sefaria.new, workdir: FIXTURES, full: true)
    oshb = Nabu::Store::Source.create(slug: "oshb", name: "OSHB", adapter_class: "Nabu::Adapters::Oshb",
                                      license_class: "attribution")
    Nabu::Store::Loader.new(db: @catalog, source: oshb)
                       .load_from(Nabu::Adapters::Oshb.new, workdir: OSHB_FIXTURES, full: true)
    { "obad" => %w[1.1 1.10], "jonah" => %w[1.1] }.each do |book, verses|
      add_book(oshb, book, verses)
    end
  end

  def teardown
    @journal.disconnect
  end

  def add_book(source, book, verses)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:oshb:#{book}", language: "hbo",
                                       title: book, canonical_path: "x",
                                       content_sha256: Digest::SHA256.hexdigest(book))
    verses.each_with_index do |verse, i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:oshb:#{book}:#{verse}", language: "hbo",
                                  sequence: i, text: "v", text_normalized: "v", annotations_json: "{}",
                                  content_sha256: Digest::SHA256.hexdigest("#{book}#{verse}"))
    end
  end

  def producer = Nabu::SefariaLinks.new(catalog: @catalog, journal: @journal)

  def edge(from, to)
    @journal[:links].where(kind: "reference", from_urn: from, to_urn: to).first ||
      @journal[:links].where(kind: "reference", from_urn: to, to_urn: from).first
  end

  def test_held_on_both_sides_rows_become_reference_edges_and_the_rest_is_censused
    result = producer.run("sefaria", workdir: FIXTURES)
    assert_equal 8, result.files, "links_by_book.csv is an aggregate grain — never read"
    assert_equal 19, result.rows_read
    assert_equal 8, result.edges_written
    assert_equal 11, result.unknown_ids, "rows with an endpoint the library does not hold"
    assert_equal 0, result.skipped_self
    assert_equal 8, @journal[:links].count
  end

  def test_a_tanakh_ref_resolves_to_the_held_masoretic_verse
    producer.run("sefaria", workdir: FIXTURES)
    found = edge("urn:nabu:oshb:gen:1.3", "#{ZOHAR_CHADASH}:bereshit.1")
    refute_nil found, "Genesis 1:3 ↔ Zohar Chadash, Bereshit 1 (complex title node + section-level ref)"
    assert_equal "urn:nabu:oshb:gen:1.3", found[:from_urn], "the edge keeps upstream's Citation 1 → 2 direction"
    assert_equal "(untyped): Genesis 1:3 ↔ Zohar Chadash, Bereshit 1", found[:detail]
    assert_nil found[:score]
  end

  def test_upstream_link_types_ride_the_detail_verbatim
    producer.run("sefaria", workdir: FIXTURES)
    assert_equal "commentary: Jonah 1:1 ↔ Minchat Shai on Jonah 1:1:1",
                 edge("urn:nabu:oshb:jonah:1.1", "#{MINCHAT_SHAI}:1.1.1")[:detail]
    assert_equal "targum: Obadiah 1:10 ↔ Targum Jonathan on Obadiah 1:10",
                 edge("urn:nabu:oshb:obad:1.10", "#{TARGUM_OBADIAH}:1.10")[:detail]
    assert_equal "mesorat hashas: Mishnah Tamid 1:2 ↔ Tamid 28a:5",
                 edge("#{KAUFMANN}:1.2", "#{TAMID_WIKISOURCE}:28a.5")[:detail],
                 "the original-language version is the hub (Kaufmann before Kulp)"
    assert_nil edge("#{KULP}:1.2", "#{TAMID_WIKISOURCE}:28a.5")
  end

  def test_ranges_anchor_at_their_start_and_named_nodes_cite_their_slug
    producer.run("sefaria", workdir: FIXTURES)
    refute_nil edge("#{KAUFMANN}:1.1", "#{TAMID_WIKISOURCE}:27a.2"), "Tamid 27a:2-3 anchors at 27a.2"
    refute_nil edge("urn:nabu:oshb:ruth:1.1", "#{RUTH_RABBAH}:petichta.1"), "Ruth Rabbah, Petichta 1"
    refute_nil edge("#{TAMID_WIKISOURCE}:25b.3", "#{TAMID_WIKISOURCE}:27b.9"), "intra-document cross-reference"
  end

  def test_the_unresolved_census_rides_the_run_row
    producer.run("sefaria", workdir: FIXTURES)
    run = @journal[:link_runs].first(producer: "sefaria-links")
    assert_equal "sefaria", run[:scope]
    params = JSON.parse(run[:params_json])
    assert_equal 19, params["rows"]
    assert_equal 8, params["resolved_rows"]
    # Unresolved sides: titles not held (Dictionary ×2, Arakhin, Amos, Joel,
    # Leviticus, Kiryat Sefer, Exodus, Proverbs, Siddur Sefard, Tzafnat
    # Pa'neach) and held titles whose cited segment is not held (Tur 241:1
    # and Ruth Rabbah Petichta 3 — trimmed fixture texts; "Tamid 26" — a
    # daf without its amud). Sifrei Zuta 6:8:1 IS held (its row fails on
    # Amos alone).
    assert_equal({ "citation_not_held" => 3, "unheld_title" => 11 }, params["unresolved_sides"])
    assert_equal ["Leviticus", 1], params["top_unheld_titles"].assoc("Leviticus")
  end

  def test_rerun_supersedes_with_identical_edges
    producer.run("sefaria", workdir: FIXTURES)
    before = @journal[:links].select_map(%i[from_urn to_urn kind detail]).sort
    second = producer.run("sefaria", workdir: FIXTURES)
    assert_equal 1, second.superseded_runs
    assert_equal 8, second.superseded_edges
    assert_equal before, @journal[:links].select_map(%i[from_urn to_urn kind detail]).sort
  end

  def test_a_pair_asserted_twice_is_one_edge_with_one_clause
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "links"))
      shard = File.join(FIXTURES, "links", "links14.csv")
      FileUtils.cp(shard, File.join(dir, "links", "links1.csv"))
      FileUtils.cp(shard, File.join(dir, "links", "links2.csv"))
      result = producer.run("sefaria", workdir: dir)
      assert_equal 6, result.rows_read
      assert_equal 2, result.edges_written
      assert_equal "targum: Obadiah 1:1 ↔ Targum Jonathan on Obadiah 1:1",
                   edge("urn:nabu:oshb:obad:1.1", "#{TARGUM_OBADIAH}:1.1")[:detail]
    end
  end

  def test_a_workdir_without_links_is_an_honest_noop_that_supersedes_nothing
    producer.run("sefaria", workdir: FIXTURES)
    result = producer.run("sefaria", workdir: Dir.mktmpdir)
    assert_nil result.run_id
    assert_equal 0, result.superseded_edges
    assert_equal 8, @journal[:links].count, "standing edges survive a parse-only sync before the first fetch"
  end

  def test_the_adapter_declares_the_producer_and_fetches_only_the_link_shards
    assert Nabu::Adapters::Sefaria.reference_edges?
    assert_instance_of Nabu::SefariaLinks,
                       Nabu::Adapters::Sefaria.reference_producer(catalog: @catalog, journal: @journal)
    select = Nabu::Adapters::Sefaria.method(:links_special?)
    assert select.call({ "path" => "links/links0.csv" })
    assert select.call({ "path" => "links/links16.csv" })
    refute select.call({ "path" => "links/links_by_book.csv" }), "aggregate pair counts — not edges"
    refute select.call({ "path" => "links/links_by_book_without_commentary.csv" })
    refute select.call({ "path" => "misc/topic_graph.csv" })
    refute select.call({ "path" => "schemas/Genesis.json" })
  end
end
