# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Nabu::Store::TimelineBuilder::LitopysAnnalDates: the Ipatiev
  # chronicle's per-column annal-year keys (the site's "[6360 (852)]"
  # markers, riding passage annotations as annal_years) become
  # passage-grain timeline rows — one per annal, spanning the columns from
  # its key to the column where the next annal's key sits. The document
  # grain stays the MetadataDates era band (no envelope here).
  class LitopysAnnalDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES = File.expand_path("../../fixtures/litopys", __dir__)
    PREFIX = "urn:nabu:litopys:"

    def lane = Nabu::Store::TimelineBuilder::LitopysAnnalDates

    def load_fixtures
      @db = store_test_db
      source = Nabu::Store::Source.create(slug: "litopys", name: "Izbornyk", adapter_class: "T",
                                          license_class: "open")
      Nabu::Store::Loader.new(db: @db, source: source)
                         .load_from(Nabu::Adapters::Litopys.new, workdir: FIXTURES, full: true)
    end

    def rows_for(page)
      id = @db[:documents].where(urn: "#{PREFIX}#{page}").get(:id)
      @db[:document_axes].where(document_id: id).order(:id).all
    end

    def spans(rows)
      rows.map { |row| row.values_at(:date_raw, :passage_seq_from, :passage_seq_to) }
    end

    # ipat40 (whole page, cols 895–903): four annals, the last one running
    # to the page's end; two keys sharing col 896 split it at the key.
    def test_each_annal_spans_its_key_to_the_next_key
      load_fixtures
      lane.build(catalog: @db)
      rows = rows_for("ipat40")
      assert_equal [["AM 6792 (1284)", 0, 1], ["AM 6793 (1285)", 1, 1], ["AM 6794 (1286)", 1, 2],
                    ["AM 6795 (1287)", 2, 8]], spans(rows)
      first = rows.first
      assert_equal [1283, 1284, "am", "litopys-annals"],
                   first.values_at(:not_before, :not_after, :precision, :axis_source)
      assert_nil first[:date_class], "the annal dates its entry, as the torot annals do"
      assert_nil first[:place_name]
    end

    # ipat01's trimmed head (cols 1, 2, 19) precedes the first key and has
    # no predecessor page: it stays undated and is counted, never guessed.
    def test_leading_columns_without_a_predecessor_are_counted_unkeyed
      load_fixtures
      counts = lane.build(catalog: @db)
      rows = rows_for("ipat01")
      assert_equal 8, rows.size
      assert_equal ["AM 6407 (899)", 3, 3], spans(rows).first
      assert_equal ["AM 6411 (903)", 3, 4], spans(rows)[4]
      assert_equal ["AM 6415 (906)", 4, 4], spans(rows).last
      assert_equal 13, counts[:annals], "ipat01 8 + ipat36 1 + ipat40 4"
      assert_equal 0, counts[:carried], "the fixture pages are not contiguous"
      assert_equal 9, counts[:unkeyed], "ipat01's 3 leading columns + ipat05's 6 (ipat04 not held)"
      assert_empty rows_for("ipat05")
    end

    # The document grain is not this lane's: no passage_seq-NULL rows.
    def test_rows_are_passage_grain_only
      load_fixtures
      lane.build(catalog: @db)
      assert(@db[:document_axes].where(axis_source: "litopys-annals").all.all? { |row| row[:passage_seq_from] })
    end

    # A page opening mid-annal continues its predecessor page's last annal
    # (the chronicle is one text cut into site pages) — carried only
    # across CONTIGUOUS pages.
    def test_leading_columns_carry_the_previous_pages_last_annal
      @db = store_test_db
      source = Nabu::Store::Source.create(slug: "litopys", name: "Izbornyk", adapter_class: "T",
                                          license_class: "open")
      page(source, "ipat04", [nil, [{ "am" => 6583, "ad" => 1075 }]])
      page(source, "ipat05", [nil, nil, [{ "am" => 6584, "ad" => 1076 }], nil])
      page(source, "ipat07", [nil, [{ "am" => 6590, "ad" => 1082 }]])
      counts = lane.build(catalog: @db)
      assert_equal [["AM 6583 (1075)", 0, 2], ["AM 6584 (1076)", 2, 3]], spans(rows_for("ipat05"))
      assert_equal [["AM 6590 (1082)", 1, 1]], spans(rows_for("ipat07")), "ipat06 absent: no carry"
      assert_equal 1, counts[:carried]
      assert_equal 2, counts[:unkeyed], "ipat04's and ipat07's leading column"
    end

    def test_refresh_is_idempotent_and_scoped
      load_fixtures
      2.times { lane.refresh_source!(catalog: @db, slug: "litopys") }
      assert_equal 13, @db[:document_axes].where(axis_source: "litopys-annals").count
      assert_equal 0, lane.refresh_source!(catalog: @db, slug: "torot")
    end

    # Passage-grain rows date no document: the summary carries the lane's
    # counts while the dated-document total stays untouched.
    def test_the_full_timeline_rebuild_runs_the_lane
      load_fixtures
      Dir.mktmpdir do |empty_canonical|
        summary = Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: empty_canonical)
        assert_equal 13, summary.litopys_annals[:annals]
        assert_equal 13, @db[:document_axes].where(axis_source: "litopys-annals").count
      end
    end

    private

    def page(source, stem, columns)
      doc = Nabu::Store::Document.create(
        source_id: source.id, urn: "#{PREFIX}#{stem}", language: "orv", content_sha256: stem,
        revision: 1, withdrawn: false, metadata_json: "{}"
      )
      columns.each_with_index do |years, seq|
        annotations = years ? { "column" => seq + 1, "annal_years" => years } : { "column" => seq + 1 }
        Nabu::Store::Passage.create(
          document_id: doc.id, urn: "#{doc.urn}:#{seq + 1}", sequence: seq, language: "orv",
          text: "лѣто #{seq}", text_normalized: "лето #{seq}", annotations_json: JSON.generate(annotations),
          content_sha256: "#{doc.urn}:#{seq}", revision: 1, withdrawn: false
        )
      end
    end
  end
end
