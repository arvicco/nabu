# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"

module Store
  # Nabu::Store::TimelineBuilder::CdliDates (P31-2): the CDLI catalog's own
  # period-string year envelopes → the timeline, over the checked-in
  # real fixture rows (test/fixtures/cdli/cdli_cat.csv) plus synthetic rows
  # for the censused variant shapes (AD, cross-era, single point) that the
  # 12-row fixture doesn't carry.
  class CdliDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "cdli", name: "CDLI", adapter_class: "T", license_class: "attribution"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "sux",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!(root = FIXTURES_ROOT)
      Nabu::Store::TimelineBuilder::CdliDates.build(catalog: @db, canonical_dir: root)
    end

    # №R-28 upgraded this very fixture row: the tablet is regnally dated
    # Amar-Suen.01.04.00, so the ruled table's year (2046 BC) replaces the
    # Ur III period band — finer wins, on real upstream data.
    def test_a_regnally_dated_fixture_row_converts_finer_than_its_period_band
      make_document("urn:nabu:cdli:p104749") # Amar-Suen.01.04.00 · Ur III (ca. 2100-2000 BC), Umma
      counts = build!
      row = timeline_for("urn:nabu:cdli:p104749")
      assert_equal(-2046, row.fetch(:not_before))
      assert_equal(-2046, row.fetch(:not_after))
      assert_equal "regnal-year", row.fetch(:precision)
      assert_equal "Amar-Suen.01.04.00", row.fetch(:date_raw)
      assert_equal "Umma (mod. Tell Jokha)", row.fetch(:place_name)
      assert_nil row.fetch(:place_ref)
      assert_equal 1, counts[:documents]
      assert_equal 1, counts[:regnal]
    end

    def test_undated_fake_modern_row_keeps_its_place_and_counts_undated
      make_document("urn:nabu:cdli:p274853") # fake (modern), Elbonia ?
      counts = build!
      row = timeline_for("urn:nabu:cdli:p274853")
      assert_nil row.fetch(:not_before), "\"fake (modern)\" resolves no chronology"
      assert_equal "Elbonia ?", row.fetch(:place_name)
      assert_equal 1, counts[:undated]
    end

    def test_place_policy_over_the_real_rows
      make_document("urn:nabu:cdli:p323717") # "Garšana (mod. uncertain)" — a real place
      make_document("urn:nabu:cdli:p480562") # provenience empty, Ur III-dated
      build!
      # A LEADING uncertain is a don't-know; "(mod. uncertain)" inside a
      # named ancient site is not.
      assert_equal "Garšana (mod. uncertain)", timeline_for("urn:nabu:cdli:p323717").fetch(:place_name)
      dated_only = timeline_for("urn:nabu:cdli:p480562")
      assert_equal(-2100, dated_only.fetch(:not_before))
      assert_nil dated_only.fetch(:place_name)
    end

    def test_variant_period_shapes_parse_from_the_catalog_string
      variants = {
        "urn:nabu:cdli:p900001" => ["Sassanian (224-641 AD)", [224, 641]],
        "urn:nabu:cdli:p900002" => ["Parthian (247 BC-224 AD)", [-247, 224]],
        "urn:nabu:cdli:p900003" => ["Linear Elamite (ca. 2200 BC)", [-2200, -2200]],
        "urn:nabu:cdli:p900004" => ["Achaemenid (547–331 BC)", [-547, -331]],
        "urn:nabu:cdli:p900005" => ["Neo-Babylonian (ca. 626-539 BC) ?", [-626, -539]]
      }
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        CSV.open(File.join(dir, "cdli", "cdli_cat.csv"), "w") do |csv|
          csv << %w[id_text period provenience]
          variants.each do |urn, (period, _bounds)|
            csv << [urn[/p(\d+)\z/, 1].to_i, period, "Nippur (mod. Nuffar)"]
          end
        end
        variants.each_key { |urn| make_document(urn) }
        counts = build!(dir)
        assert_equal 5, counts[:documents]
        assert_equal 0, counts[:invalid]
        variants.each do |urn, (_period, bounds)|
          row = timeline_for(urn)
          assert_equal bounds[0], row.fetch(:not_before), urn
          assert_equal bounds[1], row.fetch(:not_after), urn
        end
      end
    end

    def test_ascending_bc_range_is_invalid_never_stored
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        CSV.open(File.join(dir, "cdli", "cdli_cat.csv"), "w") do |csv|
          csv << %w[id_text period provenience]
          csv << [900_006, "typo (ca. 2000-2100 BC)", ""]
        end
        make_document("urn:nabu:cdli:p900006")
        counts = build!(dir)
        assert_equal 1, counts[:invalid]
        assert_nil timeline_for("urn:nabu:cdli:p900006")
      end
    end

    def test_an_unmaterialized_lfs_pointer_builds_nothing
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        File.write(File.join(dir, "cdli", "cdli_cat.csv"),
                   "version https://git-lfs.github.com/spec/v1\noid sha256:#{'ab' * 32}\nsize 9\n")
        counts = build!(dir)
        assert_equal({ documents: 0, undated: 0, invalid: 0,
                       regnal: 0, regnal_unruled: 0, regnal_out_of_range: 0 }, counts)
      end
    end

    # №R-28 (2026-08-11, the P73-6 scout ratified): a ruled ruler's regnal
    # year converts to its one conventional absolute year — FINER WINS over
    # the period band; unruled rulers and out-of-range years fall back to
    # the period band, censused.
    def test_regnal_years_convert_where_ruled_and_fall_back_where_not
      rows = {
        "urn:nabu:cdli:p910001" => ["Šulgi.44.02.06", "Ur III (ca. 2100-2000 BC)",
                                    [-2051, -2051, "regnal-year", "Šulgi.44.02.06"]],
        "urn:nabu:cdli:p910002" => ["Šulgi.47.06.00 (us2 year)", "Ur III (ca. 2100-2000 BC)",
                                    [-2047, -2047, "regnal-year", "Šulgi.47.06.00 (us2 year)"]],
        "urn:nabu:cdli:p910003" => ["Amar-Suen.00.00.00", "Ur III (ca. 2100-2000 BC)",
                                    [-2046, -2038, "regnal-reign", "Amar-Suen.00.00.00"]],
        "urn:nabu:cdli:p910004" => ["Lugalanda.04.00.00", "ED IIIb (ca. 2500-2340 BC)",
                                    [-2500, -2340, "period", "ED IIIb (ca. 2500-2340 BC)"]],
        "urn:nabu:cdli:p910005" => ["00.00.00.00", "Ur III (ca. 2100-2000 BC)",
                                    [-2100, -2000, "period", "Ur III (ca. 2100-2000 BC)"]],
        "urn:nabu:cdli:p910006" => ["Amar-Suen.12.01.01", "Ur III (ca. 2100-2000 BC)",
                                    [-2100, -2000, "period", "Ur III (ca. 2100-2000 BC)"]]
      }
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        CSV.open(File.join(dir, "cdli", "cdli_cat.csv"), "w") do |csv|
          csv << %w[id_text dates_referenced period provenience]
          rows.each do |urn, (regnal, period, _expected)|
            csv << [urn[/p(\d+)\z/, 1].to_i, regnal, period, ""]
          end
        end
        rows.each_key { |urn| make_document(urn) }
        counts = build!(dir)
        assert_equal 3, counts[:regnal]
        assert_equal 1, counts[:regnal_unruled], "Lugalanda is deliberately unruled"
        assert_equal 1, counts[:regnal_out_of_range], "Amar-Suen has no year 12"
        rows.each do |urn, (_regnal, _period, expected)|
          row = timeline_for(urn)
          assert_equal expected[0], row.fetch(:not_before), urn
          assert_equal expected[1], row.fetch(:not_after), urn
          assert_equal expected[2], row.fetch(:precision), urn
          assert_equal expected[3], row.fetch(:date_raw), urn
        end
      end
    end
  end
end
