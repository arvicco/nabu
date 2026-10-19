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

    # The regnal-precision ruling (2026-08-11) upgraded this very fixture row: the tablet is regnally dated
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
                       regnal: 0, regnal_unruled: 0, regnal_out_of_range: 0,
                       regnal_broken_year: 0, regnal_slash: 0,
                       accounting: 0, accounting_unresolved: 0, origin: 0, origin_unresolved: 0 }, counts)
      end
    end

    # The accounting_period column (4,468 catalog rows): an account's own
    # regnal span. Both ends resolving through the ruled reign table band
    # the document as one envelope, precision "accounting-period" — it
    # outranks the FIRST dates_referenced entry, which on an account is
    # only one of the dates the span covers. The real fixture row:
    # Ibbi-Suen.01 (2028 BC) to Ibbi-Suen.02 "(us2 year)" — the mark read
    # as written, year 2 (2027 BC).
    def test_a_resolving_accounting_period_bands_the_whole_account
      make_document("urn:nabu:cdli:p120698")
      counts = build!
      row = timeline_for("urn:nabu:cdli:p120698")
      assert_equal(-2028, row.fetch(:not_before))
      assert_equal(-2027, row.fetch(:not_after))
      assert_equal "accounting-period", row.fetch(:precision)
      assert_equal "Ibbi-Suen.01.02.00 to Ibbi-Suen.02.02.00 (us2 year)  (Reichskalender)", row.fetch(:date_raw)
      assert_nil row.fetch(:date_class), "the account's own date — the artifact class"
      assert_equal "Nippur (mod. Nuffar)", row.fetch(:place_name)
      assert_equal 1, counts[:accounting]
    end

    # Censused shapes: cross-reign spans band across both reigns; the us2
    # marks read as written (the year number IS the year); anything the
    # ruled table cannot answer at BOTH ends (an unruled ruler, a
    # ruler-less filler span, an out-of-range year) is unresolved —
    # counted, and the document falls back to its dates_referenced /
    # period dating, never a half-guessed envelope.
    def test_accounting_periods_resolve_only_where_both_ends_are_ruled
      rows = {
        "urn:nabu:cdli:p920001" => ["Šulgi.48.00.00 to Amar-Suen.01.00.00", "",
                                    [-2047, -2046, "accounting-period"]],
        "urn:nabu:cdli:p920002" => ["Šulgi.32.13.00 (intercalated) to Šulgi.33.01.00 (us2 year)", "",
                                    [-2063, -2062, "accounting-period"]],
        "urn:nabu:cdli:p920003" => ["Lugalanda.03.00.00 to Lugalanda.04.00.00", "",
                                    [-2500, -2340, "period"]],
        "urn:nabu:cdli:p920004" => ["--.--.01.00 to --.--.12.00", "Šulgi.44.02.06",
                                    [-2051, -2051, "regnal-year"]],
        "urn:nabu:cdli:p920005" => ["Šulgi.48.03.00 (us2-us2 year) to Šulgi.48.04.00 (us2-us2 year)",
                                    "Šulgi.48.03.00 (us2-us2 year)", [-2047, -2047, "accounting-period"]],
        "urn:nabu:cdli:p920006" => ["Amar-Suen.12.00.00 to Amar-Suen.13.00.00", "",
                                    [-2100, -2000, "period"]]
      }
      periods = { "urn:nabu:cdli:p920003" => "ED IIIb (ca. 2500-2340 BC)" }
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        CSV.open(File.join(dir, "cdli", "cdli_cat.csv"), "w") do |csv|
          csv << %w[id_text accounting_period dates_referenced period provenience]
          rows.each do |urn, (account, dated, _expected)|
            csv << [urn[/p(\d+)\z/, 1].to_i, account, dated,
                    periods.fetch(urn, "Ur III (ca. 2100-2000 BC)"), ""]
          end
        end
        rows.each_key { |urn| make_document(urn) }
        counts = build!(dir)
        assert_equal 3, counts[:accounting]
        assert_equal 3, counts[:accounting_unresolved]
        refute counts.key?(:regnal_us2_double), "the double mark is no longer a refusal class"
        rows.each do |urn, (_account, _dated, expected)|
          row = timeline_for(urn)
          assert_equal expected, row.values_at(:not_before, :not_after, :precision), urn
        end
      end
    end

    # Owner-ruled 2026-08-11 (the P73-6 scout ratified): a ruled ruler's regnal
    # year converts to its one conventional absolute year — FINER WINS over
    # the period band; unruled rulers and out-of-range years fall back to
    # the period band, censused.
    def test_regnal_years_convert_where_ruled_and_fall_back_where_not
      rows = {
        "urn:nabu:cdli:p910001" => ["Šulgi.44.02.06", "Ur III (ca. 2100-2000 BC)",
                                    [-2051, -2051, "regnal-year", "Šulgi.44.02.06"]],
        "urn:nabu:cdli:p910002" => ["Šulgi.47.06.00 (us2 year)", "Ur III (ca. 2100-2000 BC)",
                                    [-2048, -2048, "regnal-year", "Šulgi.47.06.00 (us2 year)"]],
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

    # Writes +rows+ ({ urn => { column => value } }) as a catalog CSV under
    # a temp canonical root, mints the documents, builds, and yields counts.
    def build_rows(rows, columns)
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "cdli"))
        CSV.open(File.join(dir, "cdli", "cdli_cat.csv"), "w") do |csv|
          csv << (%w[id_text] + columns)
          rows.each do |urn, values|
            csv << ([urn[/p(\d+)\z/, 1].to_i] + columns.map { |c| values.fetch(c, "") })
          end
        end
        rows.each_key { |urn| make_document(urn) }
        yield build!(dir)
      end
    end

    # date_of_origin (147,383 catalog rows, census 2026-10-19) restates the
    # dates_referenced value verbatim on 142,921 rows; on the other 4,462
    # (all accounts) it is the tablet's own date — the LAST entry of the
    # dates_referenced list. It sits BELOW the explicit datings: consulted
    # only when accounting_period and the first dates_referenced entry
    # resolve nothing, ABOVE the period band. Real catalog strings.
    def test_date_of_origin_dates_an_account_whose_explicit_datings_resolve_nothing
      rows = {
        # P227461: the account opens under an ED III dynast the table
        # deliberately leaves unruled; only its closing date resolves.
        "urn:nabu:cdli:p930001" => {
          "date_of_origin" => "Amar-Suen.00.00.00",
          "dates_referenced" => "Lugalkigenedudu.00.00.00, Amar-Suen.00.00.00",
          "accounting_period" => "Lugalkigenedudu.00.00.00 to Amar-Suen.00.00.00",
          "period" => "Ur III (ca. 2100-2000 BC)"
        },
        "urn:nabu:cdli:p930002" => {
          "date_of_origin" => "Šulgi.11.00.00 ?",
          "dates_referenced" => "Ur-Namma.P.00.00, Šulgi.11.00.00 ?",
          "accounting_period" => "Ur-Namma.P.00.00 to Šulgi.11.00.00 ?",
          "period" => "Ur III (ca. 2100-2000 BC)"
        },
        # The common case: date_of_origin == dates_referenced — the explicit
        # dating answers first and date_of_origin is never counted.
        "urn:nabu:cdli:p930003" => {
          "date_of_origin" => "Amar-Suen.01.04.00", "dates_referenced" => "Amar-Suen.01.04.00",
          "period" => "Ur III (ca. 2100-2000 BC)"
        },
        # Placeholder filler resolves nothing anywhere — the period band stays.
        "urn:nabu:cdli:p930004" => {
          "date_of_origin" => "00.00.00.00", "dates_referenced" => "00.00.00.00",
          "period" => "Ur III (ca. 2100-2000 BC)"
        }
      }
      columns = %w[date_of_origin dates_referenced accounting_period period provenience]
      build_rows(rows, columns) do |counts|
        assert_equal 2, counts[:origin]
        assert_equal 1, counts[:regnal], "only the explicit dates_referenced hit counts regnal"
        expected = {
          "urn:nabu:cdli:p930001" => [-2046, -2038, "regnal-reign", "Amar-Suen.00.00.00"],
          "urn:nabu:cdli:p930002" => [-2084, -2084, "regnal-year", "Šulgi.11.00.00 ?"],
          "urn:nabu:cdli:p930003" => [-2046, -2046, "regnal-year", "Amar-Suen.01.04.00"],
          "urn:nabu:cdli:p930004" => [-2100, -2000, "period", "Ur III (ca. 2100-2000 BC)"]
        }
        expected.each do |urn, values|
          assert_equal values, timeline_for(urn).values_at(:not_before, :not_after, :precision, :date_raw), urn
        end
      end
    end

    # CDLI's date scheme (Tinney, "Date Specifications for CDLI/Oracc"):
    # "components which are broken are given with double hyphen ('--')".
    # A ruled ruler with a broken (or "xx") year still dates the tablet to
    # the reign — the YY=00 whole-reign span, precision "regnal-reign". A
    # "?" on the year itself (doubt) converts like the bare year, the doubt
    # riding date_raw. The Achaemenid "Ruler.DD/MONTH/YY" shape (day /
    # roman month / regnal year — "Artaxerxes1.17/VII/41": the 41-year
    # reign fixes the order) converts its year; "acc" (accession year)
    # stays unresolved. Unruled rulers stay period-banded. Real strings.
    def test_broken_doubted_and_slash_year_shapes_convert_where_ruled
      rows = {
        "urn:nabu:cdli:p940001" => ["Šulgi.--.00.07", [-2094, -2047, "regnal-reign"]],
        "urn:nabu:cdli:p940002" => ["Amar-Suen.--.01.01 (us2 year)", [-2046, -2038, "regnal-reign"]],
        "urn:nabu:cdli:p940003" => ["Nabonidus.xx.03.21", [-555, -539, "regnal-reign"]],
        "urn:nabu:cdli:p940004" => ["Sennacherib.15?.00.00", [-690, -690, "regnal-year"]],
        "urn:nabu:cdli:p940005" => ["Darius1.18/XI/6", [-516, -516, "regnal-year"]],
        "urn:nabu:cdli:p940006" => ["Darius1.20/X/acc", [-2100, -2000, "period"]],
        "urn:nabu:cdli:p940007" => ["Ibbi-Sin.--.00.00", [-2100, -2000, "period"]],
        "urn:nabu:cdli:p940008" => ["Cambyses.1/IV/2", [-2100, -2000, "period"]]
      }
      table = rows.transform_values do |(dated, _)|
        { "dates_referenced" => dated, "period" => "Ur III (ca. 2100-2000 BC)" }
      end
      build_rows(table, %w[dates_referenced period provenience]) do |counts|
        assert_equal 5, counts[:regnal]
        assert_equal 3, counts[:regnal_broken_year]
        assert_equal 1, counts[:regnal_slash]
        assert_equal 2, counts[:regnal_unruled], "Ibbi-Sin (a variant spelling) and Cambyses are unruled"
        rows.each do |urn, (dated, expected)|
          row = timeline_for(urn)
          assert_equal expected, row.values_at(:not_before, :not_after, :precision), urn
          assert_equal dated, row.fetch(:date_raw), urn unless expected[2] == "period"
        end
      end
    end

    # The "(us2-us2 year)" mark is read as written (owner-ruled
    # 2026-10-20): CDLI's own year-name tables number the "second year
    # after" names under their canonical year (Šulgi 41 and 48, Šū-Suen 6,
    # Ibbi-Suen 8 — the years the mark concentrates on in the catalog), so
    # the year number IS the year. On the real strings — and a
    # date_of_origin that merely restates dates_referenced is never re-read
    # (no double census); a DISTINCT one is (p950002, whose first entry is
    # an unruled ED III dynast).
    def test_the_double_us2_mark_reads_as_written_and_a_restating_origin_is_not_reread
      rows = {
        "urn:nabu:cdli:p950001" => {
          "date_of_origin" => "Šulgi.41.09.00 (us2-us2 year)",
          "dates_referenced" => "Šulgi.41.09.00 (us2-us2 year)",
          "period" => "Ur III (ca. 2100-2000 BC)"
        },
        "urn:nabu:cdli:p950002" => {
          "date_of_origin" => "Šulgi.48.03.00 (us2-us2 year)",
          "dates_referenced" => "Lugalanda.03.00.00, Šulgi.48.03.00 (us2-us2 year)",
          "period" => "Ur III (ca. 2100-2000 BC)"
        }
      }
      build_rows(rows, %w[date_of_origin dates_referenced period provenience]) do |counts|
        assert_equal 1, counts[:origin], "only the distinct date_of_origin is read"
        assert_equal 0, counts[:origin_unresolved]
        assert_equal 1, counts[:regnal], "the regnal census counts dates_referenced only"
        assert_equal [-2054, -2054, "regnal-year"],
                     timeline_for("urn:nabu:cdli:p950001").values_at(:not_before, :not_after, :precision),
                     "Šulgi 41 = 2054 BC"
        assert_equal [-2047, -2047, "regnal-year"],
                     timeline_for("urn:nabu:cdli:p950002").values_at(:not_before, :not_after, :precision),
                     "Šulgi 48 = 2047 BC, read through date_of_origin"
      end
    end
  end
end
