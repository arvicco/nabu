# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Store
  # The lect-assignment journal (P58-1): db/lects.sqlite3, the per-document
  # overlay's persistence — owner-ratified (or rule-compiled) code → lect-id
  # assignments that survive `nabu rebuild`. LinksJournal mechanics: own
  # migration track (db/lects_migrate + its own schema_info), urn keying
  # (rebuilds re-mint catalog ids), absent-file = empty state. One CURRENT
  # assignment per (urn, code); a rule re-run supersedes its own basis.
  class LectJournalTest < Minitest::Test
    def setup
      @db = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(@db)
    end

    def teardown
      @db.disconnect
    end

    def assign(urn: "urn:nabu:perseus-latin:phi0119.phi001", code: "lat",
               lect_id: "lat:arch", basis: "owner", note: nil)
      Nabu::Store::LectJournal.assign!(
        @db, urn: urn, code: code, lect_id: lect_id, basis: basis, note: note
      )
    end

    # -- schema ---------------------------------------------------------------

    def test_migrations_create_the_assignments_table
      assert @db.table_exists?(:lect_assignments)
    end

    # -- assign! --------------------------------------------------------------

    def test_assign_inserts_a_full_row_and_reports_inserted
      verdict = assign(note: "Plautus — the D57-f per-doc refinement")
      assert_equal :inserted, verdict
      row = @db[:lect_assignments].first
      assert_equal "urn:nabu:perseus-latin:phi0119.phi001", row[:urn]
      assert_equal "lat", row[:code]
      assert_equal "lat:arch", row[:lect_id]
      assert_equal "owner", row[:basis]
      assert_equal "Plautus — the D57-f per-doc refinement", row[:note]
      refute_nil row[:created_at]
    end

    def test_reassigning_the_same_urn_and_code_updates_in_place
      assign
      verdict = assign(lect_id: "lat:cla", basis: "owner", note: "revised")
      assert_equal :updated, verdict
      rows = @db[:lect_assignments].all
      assert_equal 1, rows.size, "one CURRENT assignment per (urn, code)"
      assert_equal "lat:cla", rows.first[:lect_id]
      assert_equal "revised", rows.first[:note]
    end

    def test_distinct_codes_on_one_document_coexist
      assign(code: "lat", lect_id: "lat:arch")
      assign(code: "grc", lect_id: "grc:cla")
      assert_equal 2, @db[:lect_assignments].count
    end

    def test_an_ungrammatical_lect_id_is_rejected_loudly
      error = assert_raises(ArgumentError) { assign(lect_id: "LAT MED!") }
      assert_match(/lect id/i, error.message)
      assert_equal 0, @db[:lect_assignments].count
    end

    def test_a_blank_code_or_urn_is_rejected_loudly
      assert_raises(ArgumentError) { assign(code: "") }
      assert_raises(ArgumentError) { assign(urn: " ") }
    end

    # -- withdraw! / supersede_basis! ----------------------------------------

    def test_withdraw_by_urn_removes_every_code_row
      assign(code: "lat", lect_id: "lat:arch")
      assign(code: "grc", lect_id: "grc:cla")
      deleted = Nabu::Store::LectJournal.withdraw!(@db, urn: "urn:nabu:perseus-latin:phi0119.phi001")
      assert_equal 2, deleted
      assert_equal 0, @db[:lect_assignments].count
    end

    def test_withdraw_scoped_to_one_code_leaves_the_other
      assign(code: "lat", lect_id: "lat:arch")
      assign(code: "grc", lect_id: "grc:cla")
      deleted = Nabu::Store::LectJournal.withdraw!(
        @db, urn: "urn:nabu:perseus-latin:phi0119.phi001", code: "lat"
      )
      assert_equal 1, deleted
      assert_equal "grc", @db[:lect_assignments].first[:code]
    end

    def test_a_rule_rerun_supersedes_exactly_its_own_basis
      assign(urn: "urn:a", basis: "rule:akk-period")
      assign(urn: "urn:b", basis: "rule:akk-period")
      assign(urn: "urn:c", basis: "owner")
      deleted = Nabu::Store::LectJournal.supersede_basis!(@db, basis: "rule:akk-period")
      assert_equal 2, deleted
      remaining = @db[:lect_assignments].all
      assert_equal 1, remaining.size
      assert_equal "owner", remaining.first[:basis], "hand rulings never superseded by a rule re-run"
    end

    # -- the read side --------------------------------------------------------

    def test_overlay_for_returns_the_code_to_lect_map
      assign(code: "lat", lect_id: "lat:arch")
      assign(code: "grc", lect_id: "grc:cla")
      map = Nabu::Store::LectJournal.overlay_for(@db, "urn:nabu:perseus-latin:phi0119.phi001")
      assert_equal({ "lat" => "lat:arch", "grc" => "grc:cla" }, map)
    end

    def test_overlay_for_an_unassigned_urn_is_empty
      assert_empty Nabu::Store::LectJournal.overlay_for(@db, "urn:none")
    end

    def test_the_lazy_overlay_slots_into_the_lects_seam
      assign
      overlay = Nabu::Store::LectJournal::Overlay.new(@db)
      assert_equal({ "lat" => "lat:arch" }, overlay["urn:nabu:perseus-latin:phi0119.phi001"])
      assert_nil overlay["urn:none"], "a miss is nil — Lects#resolve's overlay contract"
    end

    # P81 U-5: the overlay reports each assignment's journal basis — the
    # provenance Lects#resolution hands to the facet materializer — from
    # the same memoized per-urn query the [] lookup rides.
    def test_the_lazy_overlay_reports_the_journal_basis
      assign(code: "lat", lect_id: "lat:arch", basis: "owner")
      assign(code: "akk", lect_id: "akk:ob", basis: "rule:akk-period")
      overlay = Nabu::Store::LectJournal::Overlay.new(@db)
      urn = "urn:nabu:perseus-latin:phi0119.phi001"
      assert_equal "owner", overlay.basis(urn, "lat")
      assert_equal "rule:akk-period", overlay.basis(urn, "akk")
      assert_nil overlay.basis(urn, "grc"), "an unassigned code has no basis"
      assert_nil overlay.basis("urn:none", "lat"), "a missing urn has no basis"
      assert_equal({ "lat" => "lat:arch", "akk" => "akk:ob" }, overlay[urn],
                   "the [] contract is unchanged beside the basis read")
    end

    def test_the_lazy_overlay_reads_through_after_new_writes_to_a_fresh_instance
      overlay = Nabu::Store::LectJournal::Overlay.new(@db)
      assert_nil overlay["urn:x"]
      Nabu::Store::LectJournal.assign!(@db, urn: "urn:x", code: "akk", lect_id: "akk:ob",
                                            basis: "rule:akk-period")
      fresh = Nabu::Store::LectJournal::Overlay.new(@db)
      assert_equal({ "akk" => "akk:ob" }, fresh["urn:x"])
    end

    def test_counts_by_basis
      assign(urn: "urn:a", basis: "rule:akk-period")
      assign(urn: "urn:b", basis: "rule:akk-period")
      assign(urn: "urn:c", basis: "owner")
      counts = Nabu::Store::LectJournal.counts_by_basis(@db)
      assert_equal({ "owner" => 1, "rule:akk-period" => 2 }, counts)
    end

    # -- file lifecycle -------------------------------------------------------

    def test_open_readonly_is_nil_for_an_absent_file_never_an_error
      Dir.mktmpdir do |dir|
        assert_nil Nabu::Store::LectJournal.open_readonly(File.join(dir, "lects.sqlite3"))
      end
    end

    def test_open_bang_creates_migrates_and_round_trips
      Dir.mktmpdir do |dir|
        path = File.join(dir, "db", "lects.sqlite3")
        db = Nabu::Store::LectJournal.open!(path)
        Nabu::Store::LectJournal.assign!(db, urn: "urn:x", code: "sux", lect_id: "sux:ur3",
                                             basis: "owner")
        db.disconnect
        reread = Nabu::Store::LectJournal.open_readonly(path)
        assert_equal({ "sux" => "sux:ur3" }, Nabu::Store::LectJournal.overlay_for(reread, "urn:x"))
        reread.disconnect
      end
    end
  end
end
