# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LectRulings (P70-2, the derivability contract): per-document owner
# lect rulings live in config/lect_rulings.yml — the SOURCE OF TRUTH; the
# journal row is the derived mirror, and LectJournal.rederive! re-mints the
# whole journal from this file + the compiled rules + infer-dates, making
# db/lects.sqlite3 formally derived (backup = canonical + config only).
class LectRulingsTest < Minitest::Test
  def with_path
    Dir.mktmpdir { |dir| yield File.join(dir, "lect_rulings.yml") }
  end

  def test_append_creates_the_file_with_doctrine_and_replaces_same_key
    with_path do |path|
      Nabu::LectRulings.append!(path, urn: "urn:d:1", code: "sux", lect_id: "sux:post",
                                      note: "why", at: Time.new(2026, 8, 10))
      assert_match(/source of truth/, File.read(path))
      rulings = Nabu::LectRulings.load(path)
      assert_equal [{ "urn" => "urn:d:1", "code" => "sux", "lect" => "sux:post",
                      "note" => "why", "at" => "2026-08-10" }], rulings

      Nabu::LectRulings.append!(path, urn: "urn:d:1", code: "sux", lect_id: "sux:arch")
      rulings = Nabu::LectRulings.load(path)
      assert_equal 1, rulings.size, "same (urn, code) replaces — one CURRENT ruling per key"
      assert_equal "sux:arch", rulings.first["lect"]
    end
  end

  def test_remove_mirrors_withdrawal
    with_path do |path|
      Nabu::LectRulings.append!(path, urn: "urn:d:1", code: "sux", lect_id: "sux:post")
      Nabu::LectRulings.append!(path, urn: "urn:d:1", code: "akk", lect_id: "akk:ob")
      assert_equal 1, Nabu::LectRulings.remove!(path, urn: "urn:d:1", code: "akk")
      assert_equal 1, Nabu::LectRulings.load(path).size
      assert_equal 1, Nabu::LectRulings.remove!(path, urn: "urn:d:1")
      assert_empty Nabu::LectRulings.load(path)
    end
  end

  def test_absent_file_is_the_empty_state
    with_path { |path| assert_empty Nabu::LectRulings.load(path) }
  end

  def test_apply_replays_config_rulings_into_the_journal_as_owner_rows
    with_path do |path|
      Nabu::LectRulings.append!(path, urn: "urn:d:1", code: "sux", lect_id: "sux:post", note: "n")
      Dir.mktmpdir do |dir|
        journal = Nabu::Store::LectJournal.open!(File.join(dir, "lects.sqlite3"))
        assert_equal 1, Nabu::LectRulings.apply!(path, journal: journal)
        row = journal[:lect_assignments].first
        assert_equal "owner", row[:basis]
        assert_equal "sux:post", row[:lect_id]
        journal.disconnect
      end
    end
  end
end
