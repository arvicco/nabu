# frozen_string_literal: true

require "test_helper"

module Query
  # Query::Notes (P24-1): the derived-notes reader behind the show/define/
  # links footers and `nabu note --list`. Bounded, accretion-ordered, and
  # silent (never crashing) against a catalog predating migration 015.
  class NotesTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
    end

    def seed(urn:, note:, topic: "notes", tags: nil, added: "2026-07-16")
      @db[:urn_notes].insert(urn: urn, note: note, topic: topic, added: added,
                             tags: tags && JSON.generate(tags),
                             provenance: "local-notes/#{topic}.yml")
    end

    def notes = Nabu::Query::Notes.new(catalog: @db)

    def test_for_urn_returns_that_urns_notes_oldest_first_with_tags_decoded
      seed(urn: "urn:d:1", note: "second", added: "2026-07-16")
      seed(urn: "urn:d:1", note: "first", added: "2026-07-14", tags: %w[collation])
      seed(urn: "urn:d:2", note: "other urn")

      rows = notes.for_urn("urn:d:1")
      assert_equal %w[first second], rows.map(&:note)
      assert_equal %w[collation], rows.first.tags
      assert_equal [], rows.last.tags
      assert_equal "notes", rows.first.topic
    end

    def test_for_urn_narrows_by_topic
      seed(urn: "urn:d:1", note: "general")
      seed(urn: "urn:d:1", note: "logged", topic: "reading-log")
      assert_equal %w[logged], notes.for_urn("urn:d:1", topic: "reading-log").map(&:note)
    end

    def test_child_count_counts_suffix_extensions_only
      seed(urn: "urn:d:1", note: "on the document itself")
      seed(urn: "urn:d:1:1.1", note: "on a passage")
      seed(urn: "urn:d:1:1.2", note: "on another passage")
      seed(urn: "urn:d:10:1", note: "a LONGER document urn must not match urn:d:1")

      assert_equal 2, notes.child_count("urn:d:1")
    end

    def test_list_is_bounded_with_an_honest_total_and_topic_filter
      5.times { |i| seed(urn: "urn:d:#{i}", note: "n#{i}", added: "2026-07-1#{i}") }
      seed(urn: "urn:d:9", note: "logged", topic: "reading-log")

      page = notes.list(limit: 3)
      assert_equal 3, page.rows.size
      assert_equal 6, page.total
      assert_equal "n0", page.rows.first.note, "oldest first"

      page = notes.list(topic: "reading-log", limit: 3)
      assert_equal %w[logged], page.rows.map(&:note)
      assert_equal 1, page.total
    end

    def test_a_catalog_predating_migration_015_reads_as_silence
      @db.drop_table(:urn_notes)
      refute_predicate notes, :available?
      assert_equal [], notes.for_urn("urn:d:1")
      assert_equal 0, notes.child_count("urn:d:1")
      assert_equal 0, notes.list.total
    end
  end
end
