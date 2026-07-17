# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The local-notes file format (P24-1, architecture §16): one YAML list of
# note records per topic file under canonical/local-notes/. The manifest
# precedent applies verbatim — the owner may hand-edit, so the parser
# validates and names every defect file+entry, never trusting shape.
class NoteFileTest < Minitest::Test
  def write_notes(dir, content, name: "notes.yml")
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  def test_load_parses_records_with_topic_from_the_filename
    Dir.mktmpdir do |dir|
      path = write_notes(dir, <<~YAML, name: "reading-log.yml")
        - urn: urn:nabu:ccmh:mar:mt
          note: Collate against Jagić 1883 before citing.
          added: 2026-07-16
          tags: [collation, ocs]

        - urn: urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
          note: μῆνιν — see the LSJ entry on the accent.
          added: '2026-07-15'
      YAML
      notes = Nabu::NoteFile.load(path)
      assert_equal "reading-log", notes.topic
      assert_equal 2, notes.records.size
      first, second = notes.records
      assert_equal "urn:nabu:ccmh:mar:mt", first.urn
      assert_equal "Collate against Jagić 1883 before citing.", first.note
      assert_equal "2026-07-16", first.added, "a bare YAML date normalizes to its ISO string"
      assert_equal %w[collation ocs], first.tags
      assert_equal [], second.tags, "tags default to an empty list"
      assert_equal "2026-07-15", second.added
    end
  end

  def test_note_text_is_normalized_to_nfc
    Dir.mktmpdir do |dir|
      decomposed = "μη\u{0342}νιν" # eta + combining perispomeni, NOT NFC
      path = write_notes(dir, "- urn: urn:x:1\n  note: \"#{decomposed}\"\n  added: 2026-07-16\n")
      note = Nabu::NoteFile.load(path).records.first.note
      assert note.unicode_normalized?(:nfc)
      assert_equal Nabu::Normalize.nfc(decomposed), note
    end
  end

  def test_load_rejects_a_non_list_naming_the_file
    Dir.mktmpdir do |dir|
      path = write_notes(dir, "urn: not-a-list\n")
      error = assert_raises(Nabu::NoteFile::FormatError) { Nabu::NoteFile.load(path) }
      assert_match(/#{Regexp.escape(path)}/, error.message)
      assert_match(/YAML list/, error.message)
    end
  end

  def test_load_rejects_an_empty_list
    Dir.mktmpdir do |dir|
      path = write_notes(dir, "[]\n")
      error = assert_raises(Nabu::NoteFile::FormatError) { Nabu::NoteFile.load(path) }
      assert_match(/lists no notes/, error.message)
    end
  end

  def test_load_rejects_unparseable_yaml
    Dir.mktmpdir do |dir|
      path = write_notes(dir, "- urn: [unclosed\n")
      error = assert_raises(Nabu::NoteFile::FormatError) { Nabu::NoteFile.load(path) }
      assert_match(/unparseable YAML/, error.message)
    end
  end

  def test_defects_name_the_entry_index
    defects = {
      "- just a string\n" => /entry 1 must be a mapping/,
      "- urn: urn:x:1\n  note: ok\n  added: 2026-07-16\n- note: no urn\n  added: 2026-07-16\n" =>
        /entry 2 needs a `urn:`/,
      "- urn: not-a-urn\n  note: ok\n  added: 2026-07-16\n" => /entry 1.*urn:/,
      "- urn: urn:x:1\n  added: 2026-07-16\n" => /entry 1.*note/,
      "- urn: urn:x:1\n  note: ''\n  added: 2026-07-16\n" => /entry 1.*note/,
      "- urn: urn:x:1\n  note: ok\n" => /entry 1.*added/,
      "- urn: urn:x:1\n  note: ok\n  added: last tuesday\n" => /entry 1.*added/,
      "- urn: urn:x:1\n  note: ok\n  added: 2026-07-16\n  tags: [ok, '']\n" => /entry 1.*tags/
    }
    Dir.mktmpdir do |dir|
      defects.each do |content, pattern|
        path = write_notes(dir, content)
        error = assert_raises(Nabu::NoteFile::FormatError, content) { Nabu::NoteFile.load(path) }
        assert_match(pattern, error.message, content)
        assert_match(/#{Regexp.escape(path)}/, error.message, "defects name the file")
      end
    end
  end
end
