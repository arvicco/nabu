# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Store
  # Store::NoteLoader (P24-1): the NOTES-shaped fourth loader. urn_notes is
  # temperature-1 derived data (db = f(canonical/local-notes)) — each topic
  # file's records REPLACE that topic's rows wholesale, byte-identical
  # replays are honest no-ops, and full loads sweep topics whose files are
  # gone (not atticked). A fresh migrated db loading the same canonical is
  # exactly what `nabu rebuild` does, so the replay test IS the
  # rebuild-survival test.
  class NoteLoaderTest < Minitest::Test
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("local-notes")

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "local-notes", name: "Owner notes", adapter_class: "Nabu::Adapters::LocalNotes",
        license_class: "open", enabled: true
      )
      @adapter = Nabu::Adapters::LocalNotes.new
    end

    def loader(db: @db)
      Nabu::Store::NoteLoader.new(db: db, source: @source)
    end

    def with_tree
      Dir.mktmpdir("nabu-note-loader") do |dir|
        tree = File.join(dir, "local-notes")
        FileUtils.cp_r(FIXTURES, tree)
        FileUtils.rm(File.join(tree, "broken.yml.quarantine"))
        yield tree
      end
    end

    def test_load_indexes_every_record_with_topic_added_tags_and_provenance
      with_tree do |tree|
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 5, report.added
        assert_equal 0, report.errored
        rows = @db[:urn_notes].order(:topic, :id).all
        assert_equal 5, rows.size
        first = rows.find { |row| row[:urn] == "urn:nabu:ccmh:mar:mt" }
        assert_equal "notes", first[:topic]
        assert_equal "2026-07-14", first[:added]
        assert_equal %w[collation ocs], JSON.parse(first[:tags])
        assert_equal "local-notes/notes.yml", first[:provenance], "provenance names the file of record"
        untagged = rows.find { |row| row[:urn] == "urn:nabu:ccmh:mar:mt:1" }
        assert_nil untagged[:tags], "no tags reads as an honest absence"
      end
    end

    def test_double_load_is_idempotent_rows_and_counts_unchanged
      with_tree do |tree|
        loader.load_from(@adapter, workdir: tree)
        before = @db[:urn_notes].order(:id).all
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 0, report.added
        assert_equal 5, report.skipped, "a byte-identical replay skips every record"
        assert_equal 0, report.withdrawn
        assert_equal before, @db[:urn_notes].order(:id).all, "rows (ids included) untouched"
      end
    end

    def test_an_edited_topic_replaces_its_rows_wholesale_leaving_other_topics_alone
      with_tree do |tree|
        loader.load_from(@adapter, workdir: tree)
        untouched = @db[:urn_notes].where(topic: "reading-log").order(:id).all
        File.write(File.join(tree, "notes.yml"),
                   "- urn: urn:nabu:ccmh:mar:mt\n  note: rewritten by hand\n  added: '2026-07-17'\n")
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 1, report.added, "the edited topic re-derives"
        assert_equal 2, report.skipped, "the untouched topic skips"
        assert_equal ["rewritten by hand"], @db[:urn_notes].where(topic: "notes").select_map(:note)
        assert_equal untouched, @db[:urn_notes].where(topic: "reading-log").order(:id).all
      end
    end

    def test_full_load_sweeps_topics_whose_files_are_gone
      with_tree do |tree|
        loader.load_from(@adapter, workdir: tree)
        FileUtils.rm(File.join(tree, "reading-log.yml"))
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 2, report.withdrawn, "derived rows honestly follow canonical"
        assert_equal %w[notes], @db[:urn_notes].distinct.select_map(:topic)
      end
    end

    def test_an_atticked_topic_keeps_loading_retained
      with_tree do |tree|
        attic = File.join(tree, Nabu::Adapter::ATTIC_DIRNAME)
        FileUtils.mkdir_p(attic)
        FileUtils.mv(File.join(tree, "reading-log.yml"), File.join(attic, "reading-log.yml"))
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 5, report.added, "a retired topic's knowledge never vanishes"
        assert_equal 0, report.withdrawn
      end
    end

    def test_a_malformed_topic_quarantines_the_file_and_the_batch_continues
      with_tree do |tree|
        FileUtils.cp(File.join(FIXTURES, "broken.yml.quarantine"), File.join(tree, "broken.yml"))
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 1, report.errored
        assert_equal 5, report.added, "one broken topic never blocks the shelf"
      end
    end

    def test_replay_into_a_fresh_db_re_derives_identical_rows_the_rebuild_invariant
      with_tree do |tree|
        loader.load_from(@adapter, workdir: tree)
        original = @db[:urn_notes].order(:topic, :id)
                                  .select(:urn, :note, :topic, :tags, :added, :provenance).all
        fresh = store_test_db
        Nabu::Store::NoteLoader.new(db: fresh, source: @source).load_from(@adapter, workdir: tree)
        replayed = fresh[:urn_notes].order(:topic, :id)
                                    .select(:urn, :note, :topic, :tags, :added, :provenance).all
        assert_equal original, replayed, "db = f(canonical): a rebuild re-derives the same index"
      end
    end

    def test_a_catalog_predating_migration_015_indexes_nothing_honestly
      with_tree do |tree|
        @db.drop_table(:urn_notes)
        report = loader.load_from(@adapter, workdir: tree)
        assert_equal 0, report.added + report.updated + report.skipped + report.withdrawn + report.errored,
                     "nothing crashes; the guard honestly indexes nothing"
      end
    end
  end
end
