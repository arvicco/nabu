# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"
require "sequel/extensions/migration"

module Store
  # Migration 056: passages.content_sha256 becomes a VIRTUAL column over
  # the stored content_sha_raw (32 raw bytes for new rows, the old hex text
  # left as it is). Proved on a FILE catalog migrated to 055 and seeded with
  # hex-text rows: every row reads back the same hex, no passages page is
  # rewritten, writes through the old name are refused, and down restores a
  # plain hex column for both row forms.
  class ContentShaRawMigrationTest < Minitest::Test
    BEFORE = 55
    AFTER = 56

    # Enough rows that the passages b-tree spans many pages, so "no page
    # rewritten" is a claim about a real tree, not one leaf.
    ROWS = 1500

    def setup
      @dir = Dir.mktmpdir("nabu-056")
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

    def test_every_row_reads_the_same_hex_across_the_migration
      before = served
      migrate(AFTER)

      assert_equal before, served, "the virtual column serves the stored hex text unchanged"
      assert_equal %w[text], @db[:passages].distinct.select_map(Sequel.function(:typeof, :content_sha_raw)),
                   "the old rows are left as hex text — no data rewrite"
    end

    def test_the_rename_and_virtual_add_rewrite_no_page
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
    end

    def test_blob_rows_serve_lower_case_hex_beside_text_rows
      migrate(AFTER)
      sha = Digest::SHA256.hexdigest("blob row")
      id = insert_passage(raw: Nabu::Store::ContentHash.stored(sha), sequence: 10_000)

      assert_equal sha, @db[:passages].where(id: id).get(:content_sha256)
      assert_equal ["blob", 32], @db[:passages].where(id: id)
                                               .get([Sequel.function(:typeof, :content_sha_raw).as(:type),
                                                     Sequel.function(:length, :content_sha_raw).as(:bytes)])
      assert_equal 1, @db[:passages].where(content_sha256: sha).count,
                   "an equality probe against hex still matches a blob row"
      assert_equal ROWS, @db[:passages].where(Sequel.function(:typeof, :content_sha_raw) => "text").count,
                   "the mixed file keeps its text rows"
    end

    def test_schema_facts_sqlite_and_sequel_agree_on
      migrate(AFTER)
      schema = @db.schema(:passages, reload: true).to_h

      assert schema.fetch(:content_sha256).fetch(:generated), "Sequel parses the column as generated"
      assert schema.fetch(:text_search).fetch(:generated), "the existing generated column survives"
      refute schema.fetch(:content_sha_raw)[:generated]
      refute schema.fetch(:content_sha_raw).fetch(:allow_null), "NOT NULL rides the renamed column"
      @db.indexes(:passages).each_value do |index|
        refute_includes index[:columns], :content_sha_raw
        refute_includes index[:columns], :content_sha256
      end
      assert_raises(Sequel::NotNullConstraintViolation) do
        @db[:passages].insert(document_id: @document, urn: "urn:d:null", sequence: 20_000, language: "lat",
                              text: "t", text_normalized: "", revision: 1, withdrawn: false,
                              annotations_json: "{}")
      end
    end

    def test_writes_through_the_old_name_fail_loudly
      migrate(AFTER)
      sha = Digest::SHA256.hexdigest("old name")

      assert_raises(Sequel::DatabaseError, "an INSERT naming the generated column is refused") do
        @db[:passages].insert(document_id: @document, urn: "urn:d:old", sequence: 20_000, language: "lat",
                              text: "t", text_normalized: "", content_sha256: sha, revision: 1,
                              withdrawn: false, annotations_json: "{}")
      end
      assert_raises(Sequel::DatabaseError, "an UPDATE of the generated column is refused") do
        @db[:passages].where(sequence: 0).update(content_sha256: sha)
      end
    end

    def test_down_restores_a_plain_hex_column_for_both_row_forms
      migrate(AFTER)
      blob_sha = Digest::SHA256.hexdigest("blob row")
      insert_passage(raw: Nabu::Store::ContentHash.stored(blob_sha), sequence: 10_000)
      before = served

      migrate(BEFORE)

      assert_equal before, served, "down keeps every hex (blob rows materialized first)"
      assert_equal %w[text], @db[:passages].distinct.select_map(Sequel.function(:typeof, :content_sha256))
      schema = @db.schema(:passages, reload: true).to_h

      refute schema.key?(:content_sha_raw)
      refute schema.fetch(:content_sha256)[:generated], "a plain stored column again"
      refute schema.fetch(:content_sha256).fetch(:allow_null)
      assert_equal "lingua 0", @db[:passages].where(sequence: 0).get(:text_search)
    end

    private

    def migrate(version)
      Sequel::Migrator.run(@db, Nabu::Store::MIGRATIONS_DIR, target: version,
                                                             allow_missing_migration_files: true)
    end

    def seed!
      source = @db[:sources].insert(slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open")
      @document = @db[:documents].insert(source_id: source, urn: "urn:d", title: "d", language: "lat",
                                         content_sha256: Digest::SHA256.hexdigest("d"), revision: 1,
                                         withdrawn: false)
      ROWS.times do |index|
        @db[:passages].insert(document_id: @document, urn: "urn:d:#{index}", sequence: index, language: "lat",
                              text: "Lingua #{index}", text_normalized: "\u0001",
                              content_sha256: Digest::SHA256.hexdigest("row #{index}"), revision: 1,
                              withdrawn: false, annotations_json: "{}")
      end
    end

    def insert_passage(raw:, sequence:)
      @db[:passages].insert(document_id: @document, urn: "urn:d:#{sequence}", sequence: sequence,
                            language: "lat", text: "t", text_normalized: "", content_sha_raw: raw,
                            revision: 1, withdrawn: false, annotations_json: "{}")
    end

    def served = @db[:passages].order(:id).select_map(%i[id content_sha256])

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
