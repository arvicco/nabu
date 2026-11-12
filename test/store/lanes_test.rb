# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::Lanes — the cjk and trigram lanes live in their OWN
  # database files beside fulltext.sqlite3 (the incrementality review's
  # lane split), ATTACHed onto every fulltext connection so the readers'
  # unqualified table names keep resolving. File-backed throughout: the
  # contract under test is where the bytes land.
  class LanesTest < Minitest::Test
    include StoreTestDB

    Lanes = Nabu::Store::Lanes
    Indexer = Nabu::Store::Indexer

    def setup
      @catalog = store_test_db
      @dir = Dir.mktmpdir("nabu-lanes")
      @path = File.join(@dir, "fulltext.sqlite3")
      @source = Nabu::Store::Source.create(slug: "s", name: "S", adapter_class: "TestAdapter",
                                           license_class: "open")
      doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:d:s", title: "t", language: "lzh",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      @passage = Nabu::Store::Passage.create(
        document_id: doc.id, urn: "urn:d:s:1", sequence: 0, language: "lzh", text: "時乘六龍以御天",
        text_normalized: "時乘六龍以御天", content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: "{}"
      )
    end

    def teardown
      @open&.each(&:disconnect)
      FileUtils.rm_rf(@dir)
    end

    def connect(**)
      (@open ||= []) << Nabu::Store.connect_fulltext(@path, **)
      @open.last
    end

    def build!(fulltext = connect)
      Indexer.rebuild!(catalog: @catalog, fulltext: fulltext, cjk_slugs: ["s"], fuzzy_slugs: ["s"])
      fulltext
    end

    def tables_in(path)
      db = Sequel.sqlite(path, readonly: true)
      db.fetch("SELECT name FROM sqlite_master WHERE type = 'table'").map(:name).map(&:to_sym)
    ensure
      db&.disconnect
    end

    def cjk_hits(fulltext)
      fulltext[Indexer::CJK_TABLE].where(Sequel.lit("passages_cjk MATCH ?", '"六龍"'))
                                  .select_map(Sequel.lit("rowid"))
    end

    def test_lane_paths_sit_beside_the_fulltext_file
      assert_equal File.join(@dir, "fulltext-cjk.sqlite3"), Lanes.path_for(@path, Lanes::CJK)
      assert_equal File.join(@dir, "fulltext-trigram.sqlite3"), Lanes.path_for(@path, Lanes::TRIGRAM)
    end

    def test_rebuild_mints_the_lane_files_and_keeps_lane_tables_out_of_the_main_file
      build!.disconnect
      @open.clear

      main = tables_in(@path)
      cjk = tables_in(Lanes.path_for(@path, Lanes::CJK))
      trigram = tables_in(Lanes.path_for(@path, Lanes::TRIGRAM))

      assert_includes main, :passages_fts, "the search core stays in fulltext.sqlite3"
      assert_includes main, :passage_lemmas
      Lanes::ALL.flat_map(&:tables).each { |table| refute_includes main, table, "#{table} left the main file" }
      assert_includes cjk, :passages_cjk
      assert_includes cjk, :passages_cjk_scope
      assert_includes trigram, :passages_trigram
      assert_includes trigram, :passages_trigram_scope
      refute_includes cjk, :passages_fts
    end

    def test_a_fresh_connection_attaches_the_lanes_and_search_round_trips
      build!.disconnect
      @open.clear

      [connect, connect(readonly: true)].each do |fulltext|
        assert_equal [@passage.id], cjk_hits(fulltext), "the unqualified lane name resolves into the lane file"
        assert_equal %w[s], fulltext[Indexer::TRIGRAM_SCOPE_TABLE].select_map(:slug)
        hits = Nabu::Query::Fuzzy.new(catalog: @catalog, fulltext: fulltext).run("六龍以")
        assert_equal ["urn:d:s:1"], hits.map(&:urn), "fragment search reads the trigram lane file"
      end
    end

    def test_a_missing_lane_file_degrades_like_a_missing_table
      build!.disconnect
      @open.clear
      Nabu::Store.drop_database_files!(Lanes.path_for(@path, Lanes::CJK))

      fulltext = connect(readonly: true)
      refute fulltext.table_exists?(Indexer::CJK_TABLE), "no file = lane not built"
      assert fulltext.table_exists?(Indexer::TRIGRAM_TABLE), "the other lane is untouched"
      refute File.exist?(Lanes.path_for(@path, Lanes::CJK)), "a connect never mints a lane file"
    end

    def test_lane_riders_ride_the_attached_schema
      build!.disconnect
      @open.clear
      fulltext = connect

      assert_equal "wal", fulltext.fetch("PRAGMA lane_cjk.journal_mode").single_value
      assert_equal Nabu::Store::PAGE_SIZE, fulltext.fetch("PRAGMA lane_cjk.page_size").single_value
      assert_equal 1, fulltext.fetch("PRAGMA lane_trigram.synchronous").single_value, "NORMAL"
    end

    # A pre-split fulltext carries the lane tables in its MAIN schema; they
    # keep serving until the lane is rebuilt, and the build drops them so
    # nothing in main shadows the lane file.
    def test_a_legacy_main_file_lane_serves_until_the_lane_builds_then_leaves_main
      legacy = connect
      legacy.run(Indexer.create_cjk_sql("main"))
      legacy.create_table(Indexer::CJK_SCOPE_TABLE) { String :slug, null: false }
      legacy[Indexer::CJK_SCOPE_TABLE].insert(slug: "old")
      assert_equal %w[old], legacy[Indexer::CJK_SCOPE_TABLE].select_map(:slug)

      build!(legacy)
      assert_equal %w[s], legacy[Indexer::CJK_SCOPE_TABLE].select_map(:slug)
      refute_includes tables_in(@path), :passages_cjk_scope
    end

    def test_in_memory_fulltext_gets_per_connection_lanes
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      build!(fulltext)
      assert_equal [@passage.id], cjk_hits(fulltext)
      refute fulltext[:sqlite_master].where(name: "passages_cjk").any?, "never in the main schema"
    ensure
      fulltext&.disconnect
    end

    def test_drop_fulltext_files_takes_the_lanes_with_it
      build!.disconnect
      @open.clear
      Nabu::Store.drop_fulltext_files!(@path)

      refute File.exist?(@path)
      Lanes::ALL.each { |lane| refute File.exist?(Lanes.path_for(@path, lane)), lane.name.to_s }
    end
  end
end
