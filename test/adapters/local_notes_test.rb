# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-notes adapter (P24-1): the first NOTES-shaped source. Like
# LocalLanguageTest it cannot include the passage-shaped AdapterConformance
# suite — a notes file mints no Document/Passage — so this test mirrors the
# honest subset for the notes shape: manifest validity + registered id +
# license class, discover→parse round-trip, ref-id ↔ topic identity, topic
# uniqueness and stability across independent passes, NFC output, and the
# LocalFetch pin/vanished/attic discipline (the P19-1 story, verbatim).
class LocalNotesTest < Minitest::Test
  WORKDIR = Nabu::TestSupport.fixtures("local-notes")

  def adapter = Nabu::Adapters::LocalNotes.new

  def test_manifest_is_valid_and_registered_as_local_notes
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "local-notes", manifest.id
    assert_equal Nabu::NoteShelf::SLUG, manifest.id, "gateway and adapter agree on the shelf slug"
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_equal "open", manifest.license_class, "owner-authored annotations"
    assert_equal "urn-notes", manifest.parser_family
  end

  def test_content_kind_is_notes_while_the_base_default_stays_passages
    assert_equal :notes, Nabu::Adapters::LocalNotes.content_kind
    assert_equal :passages, Nabu::Adapter.content_kind
  end

  def test_discover_yields_one_ref_per_topic_in_stable_order
    refs = adapter.discover(WORKDIR).to_a
    assert_equal %w[local-notes:notes local-notes:reading-log], refs.map(&:id)
    refs.each { |ref| assert_equal "local-notes", ref.source_id }
  end

  def test_discovery_skips_count_non_topic_yaml_by_rule
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(WORKDIR, "notes.yml"), dir)
      File.write(File.join(dir, "NOT-a-topic.yml"), "- urn: urn:x:1\n  note: x\n  added: 2026-07-16\n")
      File.write(File.join(dir, "manifest.yml"), "source: x\n")
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule, "a bad name and the reserved manifest furniture both skip"
      assert_predicate skips, :clean?
    end
  end

  def test_parse_yields_note_files_whose_topic_matches_the_ref_id
    adapter.discover(WORKDIR).each do |ref|
      notes = adapter.parse(ref)
      assert_kind_of Nabu::NoteFile, notes
      assert_equal ref.id, "local-notes:#{notes.topic}",
                   "the ref id must be recoverable from the parsed notes file"
      refute_empty notes.records, "#{ref.id} parsed to zero records"
    end
  end

  def test_record_notes_are_nfc_and_non_empty
    adapter.discover(WORKDIR).each do |ref|
      adapter.parse(ref).records.each do |record|
        refute_empty record.note
        assert record.note.unicode_normalized?(:nfc)
        assert record.urn.start_with?("urn:")
      end
    end
  end

  def test_topics_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(WORKDIR).map { |ref| [ref.id, adapter.parse(ref).records] }
    end
    first = snapshot.call
    topics = first.map(&:first)
    assert_equal topics.uniq, topics
    assert_equal first, snapshot.call
  end

  def test_parse_wraps_format_defects_in_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(WORKDIR, "broken.yml.quarantine"), File.join(dir, "broken.yml"))
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/YAML list/, error.message)
    end
  end

  def test_fetch_scans_and_pins_per_file_and_fails_on_a_missing_tree
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-notes")
      FileUtils.cp_r(WORKDIR, tree)
      report = adapter.fetch(tree)
      assert_kind_of Nabu::FetchReport, report
      assert_equal 5, report.repos.size,
                   "one pin per scanned file (2 topics + README + manifest + quarantine rig)"
      assert report.repos.key?("local:notes.yml")
      assert_nil report.notes

      error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(dir, "empty")) }
      assert_match(/no local tree/, error.message)
      assert_match(/nabu note/, error.message, "the hint names the shelf's front door")
    end
  end

  def test_fetch_keeps_a_vanished_files_pin_and_says_so
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-notes")
      FileUtils.cp_r(WORKDIR, tree)
      adapter.fetch(tree)
      FileUtils.rm(File.join(tree, "reading-log.yml"))
      report = adapter.fetch(tree)
      assert report.repos.key?("local:reading-log.yml"), "the vanished file's pin lingers"
      assert_match(/VANISHED/, report.notes)
      assert_match(/reading-log\.yml/, report.notes)
    end
  end

  def test_attic_topics_rediscover_as_retained
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-notes")
      FileUtils.cp_r(WORKDIR, tree)
      adapter.fetch(tree)
      attic = File.join(tree, Nabu::Adapter::ATTIC_DIRNAME)
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(tree, "reading-log.yml"), File.join(attic, "reading-log.yml"))
      report = adapter.fetch(tree)
      assert_match(/1 file\(s\) retired/, report.notes)
      refs = adapter.discover_with_attic(tree).to_a
      retained = refs.find { |ref| ref.id == "local-notes:reading-log" }
      assert retained.metadata[Nabu::Adapter::RETAINED_KEY], "the retired topic is rediscovered retained"
      assert_equal 2, adapter.parse(retained).records.size
    end
  end
end
