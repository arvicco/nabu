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
      assert_equal 1, counts[:documents]
    end

    def test_only_the_bare_inscription_urn_joins_never_the_lane_siblings
      make_document("urn:nabu:rundata:n-kj101")
      make_document("urn:nabu:rundata:n-kj101-eng")
      counts = build!
      row = timeline_for("urn:nabu:rundata:n-kj101")
      assert_equal 650, row.fetch(:not_before)
      assert_equal 700, row.fetch(:not_after)
      assert_equal "U 650-700 (Grønvik)", row.fetch(:date_raw)
      assert_nil timeline_for("urn:nabu:rundata:n-kj101-eng"),
                 "sibling documents carry no timeline row of their own"
      assert_equal 1, counts[:documents]
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
        db.execute("UPDATE meta_information SET year_from = NULL, year_to = NULL, " \
                   "dating = '', found_location = '', parish = '' WHERE signature_id = 1997")
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
