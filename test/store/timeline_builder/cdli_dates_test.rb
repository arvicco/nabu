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

    def test_period_parenthetical_becomes_the_year_envelope
      make_document("urn:nabu:cdli:p104749") # Ur III (ca. 2100-2000 BC), Umma
      counts = build!
      row = timeline_for("urn:nabu:cdli:p104749")
      assert_equal(-2100, row.fetch(:not_before))
      assert_equal(-2000, row.fetch(:not_after))
      assert_equal "period", row.fetch(:precision)
      assert_equal "Ur III (ca. 2100-2000 BC)", row.fetch(:date_raw)
      assert_equal "Umma (mod. Tell Jokha)", row.fetch(:place_name)
      assert_nil row.fetch(:place_ref)
      assert_equal 1, counts[:documents]
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
        assert_equal({ documents: 0, undated: 0, invalid: 0 }, counts)
      end
    end
  end
end
