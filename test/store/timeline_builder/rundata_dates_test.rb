# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

module Store
  # Nabu::Store::TimelineBuilder::RundataDates (P40-6): SRDB year_from/
  # year_to envelopes + verbatim findspots off the canonical SQLite
  # artifact, joined on urns minted through Adapters::Rundata.urn_for —
  # one rule, no drift. Runs over the checked-in trim
  # (test/fixtures/rundata/runes-trim.sqlite3; the fixtures root IS the
  # canonical layout for the extractor's purposes).
  class RundataDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "rundata", name: "Rundata", adapter_class: "T", license_class: "odbl"
      )
    end

    def make_document(urn)
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, title: urn, language: "non",
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!(canonical_dir: FIXTURES_ROOT)
      Nabu::Store::TimelineBuilder::RundataDates.build(catalog: @db, canonical_dir: canonical_dir)
    end

    def test_year_envelope_and_findspot_verbatim
      make_document("urn:nabu:rundata:u-344")
      counts = build!
      row = timeline_for("urn:nabu:rundata:u-344")
      assert_equal 725, row.fetch(:not_before)
      assert_equal 1100, row.fetch(:not_after)
      assert_equal "range", row.fetch(:precision)
      assert_equal "V", row.fetch(:date_raw), "the scholarly dating string rides verbatim"
      assert_equal "Yttergärde", row.fetch(:place_name)
      assert_nil row.fetch(:place_ref), "verbatim find-spots carry no gazetteer ref"
      assert_equal "rundata", row.fetch(:axis_source)
      # P69-1 (survey P-g): the find-location WGS84 pair rides the axis row
      # — a COORDINATES lane, no gazetteer, straight from the SRDB columns.
      assert_in_delta 59.604644, row.fetch(:place_lat)
      assert_in_delta 18.109098, row.fetch(:place_lon)
      assert_equal 1, counts[:documents]
    end

    # P62-3 REVERSES the P40-6 sibling exclusion (a ruled wave-2 change,
    # the oracc "-en" precedent: the sibling is a rendering of the same
    # artifact, so the date/place are the ARTIFACT's — the English witness
    # inherits the time filter). 23,623 live sibling docs recover their
    # base inscription's band through this join; a lane we don't hold
    # simply doesn't row.
    def test_lane_siblings_inherit_the_base_inscriptions_timeline
      make_document("urn:nabu:rundata:n-kj101")
      make_document("urn:nabu:rundata:n-kj101-eng")
      counts = build!
      row = timeline_for("urn:nabu:rundata:n-kj101")
      assert_equal 650, row.fetch(:not_before)
      assert_equal 700, row.fetch(:not_after)
      assert_equal "U 650-700 (Grønvik)", row.fetch(:date_raw)
      sibling = timeline_for("urn:nabu:rundata:n-kj101-eng")
      refute_nil sibling, "the translation lane is a rendering of the SAME dated stone"
      assert_equal 650, sibling.fetch(:not_before)
      assert_equal "U 650-700 (Grønvik)", sibling.fetch(:date_raw)
      assert_equal 2, counts[:documents], "base + the one held sibling; absent lanes never row"
    end

    def test_documents_we_do_not_hold_contribute_nothing
      counts = build!
      assert_equal 0, counts[:documents]
      assert_equal 0, @db[:document_axes].count
    end

    def test_an_undated_unplaced_inscription_is_counted_never_guessed
      Dir.mktmpdir do |dir|
        workdir = File.join(dir, "rundata")
        FileUtils.mkdir_p(workdir)
        FileUtils.cp(File.join(FIXTURES_ROOT, "rundata", "runes-trim.sqlite3"),
                     File.join(workdir, "runes-trim.sqlite3"))
        db = SQLite3::Database.new(File.join(workdir, "runes-trim.sqlite3"))
        # P69-1: the coordinate columns null too — with them present the
        # inscription would still be PLACED (the coordinates lane), which
        # is the next test's case, not this one's.
        db.execute("UPDATE meta_information SET year_from = NULL, year_to = NULL, " \
                   "dating = '', found_location = '', parish = '', " \
                   "latitude = '', longitude = '' WHERE signature_id = 1997")
        db.close
        make_document("urn:nabu:rundata:u-344")
        make_document("urn:nabu:rundata:og-136")
        counts = build!(canonical_dir: dir)
        assert_nil timeline_for("urn:nabu:rundata:u-344")
        refute_nil timeline_for("urn:nabu:rundata:og-136")
        assert_equal 1, counts[:documents]
        assert_equal 1, counts[:undated]
      end
    end

    # P69-1: coordinates ALONE keep the row — a WGS84 pair is a place
    # assertion even when the name fields are blank.
    def test_a_coordinates_only_inscription_keeps_its_row
      Dir.mktmpdir do |dir|
        workdir = File.join(dir, "rundata")
        FileUtils.mkdir_p(workdir)
        FileUtils.cp(File.join(FIXTURES_ROOT, "rundata", "runes-trim.sqlite3"),
                     File.join(workdir, "runes-trim.sqlite3"))
        db = SQLite3::Database.new(File.join(workdir, "runes-trim.sqlite3"))
        db.execute("UPDATE meta_information SET year_from = NULL, year_to = NULL, " \
                   "dating = '', found_location = '', parish = '' WHERE signature_id = 1997")
        db.close
        make_document("urn:nabu:rundata:u-344")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:rundata:u-344")
        refute_nil row
        assert_nil row.fetch(:place_name)
        assert_in_delta 59.604644, row.fetch(:place_lat)
      end
    end

    def test_a_dateless_but_placed_inscription_keeps_its_place_row
      Dir.mktmpdir do |dir|
        workdir = File.join(dir, "rundata")
        FileUtils.mkdir_p(workdir)
        FileUtils.cp(File.join(FIXTURES_ROOT, "rundata", "runes-trim.sqlite3"),
                     File.join(workdir, "runes-trim.sqlite3"))
        db = SQLite3::Database.new(File.join(workdir, "runes-trim.sqlite3"))
        db.execute("UPDATE meta_information SET year_from = NULL, year_to = NULL, dating = '' " \
                   "WHERE signature_id = 1997")
        db.close
        make_document("urn:nabu:rundata:u-344")
        build!(canonical_dir: dir)
        row = timeline_for("urn:nabu:rundata:u-344")
        assert_nil row.fetch(:not_before)
        assert_nil row.fetch(:not_after)
        assert_equal "Yttergärde", row.fetch(:place_name)
      end
    end

    def test_no_canonical_artifact_yields_the_honest_zero
      Dir.mktmpdir do |dir|
        counts = build!(canonical_dir: dir)
        assert_equal({ documents: 0, undated: 0 }, counts)
      end
    end
  end
end
