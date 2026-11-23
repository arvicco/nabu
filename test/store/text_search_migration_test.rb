# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "sequel/extensions/migration"

module Store
  # Migration 055 (the text_normalized diet): the text_search read seam widens to serve the
  # lower-sentinel class. Proved on a FILE catalog migrated to 054 and
  # seeded in the P112 storage shape: the served form is bit-identical
  # across the migration, and the drop + re-add of the VIRTUAL column
  # rewrites no passages page (the ALTER is instant at any size).
  class TextSearchMigrationTest < Minitest::Test
    BEFORE = 54
    AFTER = 55

    # [text, true search form] — the classes the seam must serve: equal to
    # text, ASCII lower, a Unicode fold ASCII lower cannot reach, an
    # arbitrary fold, and the documented empty-fold edge (P112: serves text).
    SEEDS = [
      %w[王道蕩蕩 王道蕩蕩],
      ["Arma Virumque CANO", "arma virumque cano"],
      %w[Μῆνιν μῆνιν],
      ["ÉCOLE Abc", "école abc"],
      ["Ἄνδρα μοι", "ανδρα μοι"],
      ["ABC", ""]
    ].freeze

    # Enough rows that the passages b-tree spans many pages, so "no page
    # rewritten" is a claim about a real tree, not one leaf.
    PADDING_ROWS = 1500

    def setup
      @dir = Dir.mktmpdir("nabu-055")
      @path = File.join(@dir, "catalog.sqlite3")
      # A plain rollback-journal connection: the main file IS the state,
      # so its pages can be read back byte for byte (no WAL to checkpoint).
      @db = Sequel.sqlite(@path)
      migrate(BEFORE)
      seed!
    end

    def teardown
      @db.disconnect
      FileUtils.remove_entry(@dir)
    end

    def test_text_search_is_bit_identical_across_the_migration
      before = served
      migrate(AFTER)

      assert_equal before, served, "every row serves the same search form after the seam widens"
      assert_equal "ABC", @db[:passages].where(text: "ABC").get(:text_search),
                   "the P112 empty-fold edge still serves text"
    end

    def test_the_lower_sentinel_serves_sqlite_lower_after_the_migration
      migrate(AFTER)
      id = insert_passage("Gallia Est Omnis", "\u0001", sequence: 10_000)

      assert_equal "gallia est omnis", @db[:passages].where(id: id).get(:text_search)
    end

    def test_drop_and_add_of_the_virtual_column_rewrites_no_page
      pages = passages_pages
      page_count = pragma(:page_count)
      root = @db[:sqlite_master].where(type: "table", name: "passages").get(:rootpage)
      before = page_bytes(pages)

      migrate(AFTER)

      assert_equal page_count, pragma(:page_count), "page_count unchanged: nothing grew or was copied"
      assert_equal root, @db[:sqlite_master].where(type: "table", name: "passages").get(:rootpage),
                   "same b-tree root: the table was not duplicated"
      assert_equal pages, passages_pages, "same page set"
      assert_equal before, page_bytes(pages), "every passages page is byte-identical — no record rewritten"
      assert_includes @db[:sqlite_master].where(name: "passages").get(:sql), "char(1)",
                      "the widened expression is live"
    end

    def test_down_restores_the_p112_seam_and_unfolds_sentinel_rows
      migrate(AFTER)
      id = insert_passage("Gallia Est", "\u0001", sequence: 10_000)
      before = served

      migrate(BEFORE)

      assert_equal before, served, "down keeps the served form (sentinels materialized first)"
      assert_equal "gallia est", @db[:passages].where(id: id).get(:text_normalized)
    end

    private

    def migrate(version)
      Sequel::Migrator.run(@db, Nabu::Store::MIGRATIONS_DIR, target: version,
                                                             allow_missing_migration_files: true)
    end

    def seed!
      source = @db[:sources].insert(slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open")
      @document = @db[:documents].insert(source_id: source, urn: "urn:d", title: "d", language: "lat",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      SEEDS.each_with_index { |(text, fold), index| insert_passage(text, p112(text, fold), sequence: index) }
      PADDING_ROWS.times do |index|
        text = "Linea #{index} Lorem Ipsum dolor sit amet λόγος #{index}"
        insert_passage(text, text.downcase, sequence: SEEDS.size + index)
      end
    end

    # The P112 loader's stored form: "" when equal to text, else the fold.
    def p112(text, fold) = fold == text ? "" : fold

    def insert_passage(text, stored, sequence:)
      @db[:passages].insert(document_id: @document, urn: "urn:d:#{sequence}", sequence: sequence,
                            language: "lat", text: text, text_normalized: stored, content_sha256: "x",
                            revision: 1, withdrawn: false, annotations_json: "{}")
    end

    def served = @db[:passages].order(:id).select_map(%i[id text_search])

    def pragma(name) = @db.fetch("PRAGMA #{name}").single_value

    def passages_pages = @db[:dbstat].where(name: "passages").order(:pageno).select_map(:pageno)

    def page_bytes(pages)
      size = pragma(:page_size)
      File.open(@path, "rb") do |file|
        pages.map do |page|
          file.seek((page - 1) * size)
          file.read(size)
        end
      end
    end
  end
end
