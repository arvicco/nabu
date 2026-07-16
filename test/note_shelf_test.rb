# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-notes shelf's sanctioned write gateway (P24-1, architecture §16)
# — the FOURTH local-shelf gateway, LanguageShelf/LibraryShelf's sibling:
# atomic append + reparse-validate with rollback, and urn resolution against
# the catalog BEFORE any write (a typo'd urn is an error naming the miss;
# --force records a note on a not-yet-held urn deliberately).
class NoteShelfTest < Minitest::Test
  include StoreTestDB

  KNOWN = ["urn:nabu:ccmh:mar:mt", "urn:nabu:ccmh:mar:mt:1"].freeze

  def with_shelf(resolver: ->(urn) { KNOWN.include?(urn) })
    Dir.mktmpdir("nabu-note-shelf") do |root|
      yield Nabu::NoteShelf.new(dir: File.join(root, "local-notes"), resolver: resolver)
    end
  end

  def test_append_note_creates_the_topic_file_loadable_by_note_file
    with_shelf do |shelf|
      path = shelf.append_note!(urn: "urn:nabu:ccmh:mar:mt", note: "Collate against Jagić 1883.",
                                tags: %w[collation], now: Time.utc(2026, 7, 16))
      assert_equal shelf.path_for("notes"), path, "the default topic is notes"
      notes = Nabu::NoteFile.load(path)
      assert_equal 1, notes.records.size
      record = notes.records.first
      assert_equal "urn:nabu:ccmh:mar:mt", record.urn
      assert_equal "Collate against Jagić 1883.", record.note
      assert_equal "2026-07-16", record.added
      assert_equal %w[collation], record.tags
    end
  end

  def test_append_note_is_append_only_preserving_owner_comments
    with_shelf do |shelf|
      existing = "# owner comment — must survive any append\n- urn: urn:nabu:ccmh:mar:mt\n  " \
                 "note: first thought\n  added: 2026-07-01\n"
      FileUtils.mkdir_p(shelf.dir)
      File.write(shelf.path_for("notes"), existing)
      shelf.append_note!(urn: "urn:nabu:ccmh:mar:mt:1", note: "Second thought.")
      content = File.read(shelf.path_for("notes"))
      assert content.start_with?(existing), "append-only: the existing bytes are never rewritten"
      assert_equal 2, Nabu::NoteFile.load(shelf.path_for("notes")).records.size
    end
  end

  def test_append_note_refuses_an_unresolvable_urn_naming_the_miss
    with_shelf do |shelf|
      error = assert_raises(Nabu::NoteShelf::Error) do
        shelf.append_note!(urn: "urn:nabu:ccmh:mar:tm", note: "typo'd urn")
      end
      assert_match(/urn:nabu:ccmh:mar:tm/, error.message)
      assert_match(/does not resolve/, error.message)
      assert_match(/--force/, error.message, "the deliberate-dangling escape hatch is named")
      refute_path_exists shelf.path_for("notes"), "a refusal writes nothing"
    end
  end

  def test_force_records_a_note_on_a_not_yet_held_urn
    with_shelf do |shelf|
      shelf.append_note!(urn: "urn:nabu:planned:grammar", note: "Order the Leskien reprint.", force: true)
      assert_equal "urn:nabu:planned:grammar", Nabu::NoteFile.load(shelf.path_for("notes")).records.first.urn
    end
  end

  def test_append_note_refuses_an_empty_note_and_a_bad_topic
    with_shelf do |shelf|
      assert_raises(Nabu::NoteShelf::Error) { shelf.append_note!(urn: KNOWN.first, note: "   ") }
      error = assert_raises(Nabu::NoteShelf::Error) do
        shelf.append_note!(urn: KNOWN.first, note: "ok", topic: "../escape")
      end
      assert_match(/topic/, error.message)
      reserved = assert_raises(Nabu::NoteShelf::Error) do
        shelf.append_note!(urn: KNOWN.first, note: "ok", topic: "manifest")
      end
      assert_match(/reserved/, reserved.message)
      refute Dir.exist?(shelf.dir), "refusals precede any write"
    end
  end

  def test_append_note_refuses_a_malformed_existing_topic_file
    with_shelf do |shelf|
      FileUtils.mkdir_p(shelf.dir)
      File.write(shelf.path_for("notes"), "urn: not-a-list\n")
      error = assert_raises(Nabu::NoteShelf::Error) { shelf.append_note!(urn: KNOWN.first, note: "ok") }
      assert_match(/fix it first/, error.message)
      assert_equal "urn: not-a-list\n", File.read(shelf.path_for("notes")), "the broken file is untouched"
    end
  end

  # The reparse-validate backstop (the LibraryShelf P20-1 pattern): a --force
  # append of a non-urn passes the gateway's resolution skip but fails the
  # NoteFile round-trip — rolled back, the prior bytes byte-identical.
  def test_append_note_rolls_back_a_record_the_parser_rejects
    with_shelf do |shelf|
      shelf.append_note!(urn: KNOWN.first, note: "good note")
      before = File.read(shelf.path_for("notes"))
      error = assert_raises(Nabu::NoteShelf::Error) do
        shelf.append_note!(urn: "not-a-urn", note: "dangling typo", force: true)
      end
      assert_match(/needs a `urn:`/, error.message)
      assert_equal before, File.read(shelf.path_for("notes")), "the rejected append is truncated away"
    end
  end

  def test_append_note_without_a_resolver_requires_force
    Dir.mktmpdir("nabu-note-shelf") do |root|
      shelf = Nabu::NoteShelf.new(dir: File.join(root, "local-notes"))
      error = assert_raises(Nabu::NoteShelf::Error) { shelf.append_note!(urn: KNOWN.first, note: "ok") }
      assert_match(/no catalog/, error.message)
      shelf.append_note!(urn: KNOWN.first, note: "ok", force: true)
      assert_path_exists shelf.path_for("notes")
    end
  end

  # -- catalog_resolver: Query::Show's resolution, dictionary urns included ----

  def seed_catalog
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "ccmh", name: "CCMH", adapter_class: "TestAdapter",
                                        license_class: "open", enabled: true)
    document = Nabu::Store::Document.create(source_id: source.id, urn: "urn:nabu:ccmh:mar:mt",
                                            title: "Marianus", language: "chu",
                                            content_sha256: "x", revision: 1)
    Nabu::Store::Passage.create(document_id: document.id, urn: "urn:nabu:ccmh:mar:mt:1", sequence: 1,
                                language: "chu", text: "искони", text_normalized: "искони",
                                annotations_json: "{}", content_sha256: "x", revision: 1)
    dictionary = Nabu::Store::Dictionary.create(source_id: source.id, slug: "lsj", title: "LSJ",
                                                language: "grc")
    Nabu::Store::DictionaryEntry.create(dictionary_id: dictionary.id, urn: "urn:nabu:dict:lsj:n1",
                                        entry_id: "n1", key_raw: "λόγος", headword: "λόγος",
                                        headword_folded: "λογοσ", body: "word", content_sha256: "x")
    db
  end

  def test_catalog_resolver_resolves_documents_passages_and_dictionary_entries
    resolver = Nabu::NoteShelf.catalog_resolver(seed_catalog)
    assert resolver.call("urn:nabu:ccmh:mar:mt"), "document urn resolves"
    assert resolver.call("urn:nabu:ccmh:mar:mt:1"), "passage urn resolves"
    assert resolver.call("urn:nabu:dict:lsj:n1"), "dictionary-entry urn resolves (P22-2)"
    refute resolver.call("urn:nabu:ccmh:mar:tm"), "a typo'd urn is a miss"
    refute resolver.call("urn:nabu:ccmh:mar:mt:1-2"), "a range with a missing endpoint is a miss, not a crash"
  end
end
