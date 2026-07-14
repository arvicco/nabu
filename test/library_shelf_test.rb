# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The library shelf's sanctioned write gateway (P19-5, architecture §16) —
# LanguageShelf's sibling for canonical/local-library: copy-in (never move),
# the sha duplicate index, and the mechanical manifest APPEND that never
# rewrites the owner's existing entries or comments.
class LibraryShelfTest < Minitest::Test
  def with_shelf
    Dir.mktmpdir("nabu-library-shelf") do |root|
      yield Nabu::LibraryShelf.new(dir: File.join(root, "local-library")), root
    end
  end

  def write_source(root, name, content = "pdf bytes")
    path = File.join(root, name)
    File.write(path, content)
    path
  end

  # -- copy_in!: copy, never move ----------------------------------------------

  def test_copy_in_copies_and_never_moves_the_source
    with_shelf do |shelf, root|
      source = write_source(root, "vaillant-1950-manuel.pdf")
      file = shelf.copy_in!(source, collection: "slavistics")
      assert_equal "vaillant-1950-manuel.pdf", file
      assert_path_exists source, "the source must stay where it was (copy, never move)"
      assert_path_exists File.join(shelf.dir, "slavistics", file)
      assert_equal File.read(source), File.read(File.join(shelf.dir, "slavistics", file))
    end
  end

  def test_copy_in_overwrites_an_existing_target_the_revision_story
    with_shelf do |shelf, root|
      shelf.copy_in!(write_source(root, "a.txt", "first"), collection: "notes")
      FileUtils.rm(File.join(root, "a.txt"))
      shelf.copy_in!(write_source(root, "a.txt", "second"), collection: "notes")
      assert_equal "second", File.read(File.join(shelf.dir, "notes", "a.txt"))
    end
  end

  def test_copy_in_refuses_manifest_and_dot_files
    with_shelf do |shelf, root|
      manifest = write_source(root, "manifest.yml", "- file: x\n")
      dotfile = write_source(root, ".local-fetch.json", "{}")
      assert_raises(Nabu::LibraryShelf::Error) { shelf.copy_in!(manifest, collection: "notes") }
      assert_raises(Nabu::LibraryShelf::Error) { shelf.copy_in!(dotfile, collection: "notes") }
    end
  end

  def test_copy_in_refuses_a_path_shaped_collection
    with_shelf do |shelf, root|
      source = write_source(root, "a.txt")
      assert_raises(Nabu::LibraryShelf::Error) { shelf.copy_in!(source, collection: "../escape") }
      assert_raises(Nabu::LibraryShelf::Error) { shelf.copy_in!(source, collection: "a/b") }
      assert_raises(Nabu::LibraryShelf::Error) { shelf.copy_in!(source, collection: ".attic") }
    end
  end

  # -- the sha index -------------------------------------------------------------

  def test_sha_index_maps_live_files_and_excludes_attic_and_state_file
    with_shelf do |shelf, _root|
      FileUtils.mkdir_p(File.join(shelf.dir, "slavistics"))
      FileUtils.mkdir_p(File.join(shelf.dir, ".attic", "slavistics"))
      File.write(File.join(shelf.dir, "slavistics", "a.txt"), "alpha")
      File.write(File.join(shelf.dir, ".attic", "slavistics", "old.txt"), "retired")
      File.write(File.join(shelf.dir, Nabu::LocalFetch::STATE_FILE), "{}")
      index = shelf.sha_index
      assert_equal({ Digest::SHA256.hexdigest("alpha") => "slavistics/a.txt" }, index)
    end
  end

  def test_sha_index_is_kept_current_by_copy_in
    with_shelf do |shelf, root|
      source = write_source(root, "b.txt", "beta")
      shelf.copy_in!(source, collection: "notes")
      assert_equal "notes/b.txt", shelf.sha_index[Digest::SHA256.hexdigest("beta")]
    end
  end

  # -- manifest append: mechanical, append-only ----------------------------------

  def test_append_entry_creates_collection_and_manifest_loadable_by_library_manifest
    with_shelf do |shelf, _root|
      path = shelf.append_entry!(collection: "slavistics",
                                 entry: { "file" => "a.pdf", "title" => "Manuel", "year" => 1950,
                                          "languages" => ["chu"] })
      manifest = Nabu::LibraryManifest.load(path)
      assert_equal 1, manifest.entries.size
      entry = manifest.entries.first
      assert_equal "a.pdf", entry.file
      assert_equal "Manuel", entry.title
      assert_equal 1950, entry.year
      assert_equal ["chu"], entry.languages
      assert_equal "research_private", entry.license_class, "silence means the conservative default"
    end
  end

  def test_append_entry_preserves_existing_bytes_including_owner_comments
    with_shelf do |shelf, _root|
      existing = "# owner comment — must survive any append\n- file: old.pdf\n  title: \"Old\"\n"
      FileUtils.mkdir_p(File.join(shelf.dir, "slavistics"))
      File.write(shelf.manifest_path("slavistics"), existing)
      shelf.append_entry!(collection: "slavistics", entry: { "file" => "new.pdf" })
      content = File.read(shelf.manifest_path("slavistics"))
      assert content.start_with?(existing), "append-only: the existing bytes are never rewritten"
      manifest = Nabu::LibraryManifest.load(shelf.manifest_path("slavistics"))
      assert_equal %w[old.pdf new.pdf], manifest.entries.map(&:file)
    end
  end

  def test_append_entry_refuses_a_duplicate_file_entry
    with_shelf do |shelf, _root|
      shelf.append_entry!(collection: "notes", entry: { "file" => "a.txt" })
      error = assert_raises(Nabu::LibraryShelf::Error) do
        shelf.append_entry!(collection: "notes", entry: { "file" => "a.txt" })
      end
      assert_match(/already manifested/, error.message)
    end
  end

  def test_append_entry_refuses_a_malformed_manifest_rather_than_deepening_the_damage
    with_shelf do |shelf, _root|
      FileUtils.mkdir_p(File.join(shelf.dir, "bad"))
      File.write(shelf.manifest_path("bad"), "file: not-a-list\n")
      error = assert_raises(Nabu::LibraryShelf::Error) do
        shelf.append_entry!(collection: "bad", entry: { "file" => "a.txt" })
      end
      assert_match(/malformed manifest/, error.message)
    end
  end

  # P20-1: the append is re-validated AND rolled back when rejected — the
  # gateway can never leave a manifest entry the loader would refuse (the
  # "chu (body ger)" poisoning incident, closed at the last write gate).
  def test_append_entry_rolls_back_an_entry_the_loader_would_reject
    with_shelf do |shelf, _root|
      error = assert_raises(Nabu::LibraryShelf::Error) do
        shelf.append_entry!(collection: "notes", entry: { "file" => "a.txt", "languages" => ["chu (body ger)"] })
      end
      assert_match(/chu \(body ger\)/, error.message)
      refute_path_exists shelf.manifest_path("notes"), "a first append that fails validation leaves no manifest"
    end
  end

  def test_append_entry_rollback_preserves_the_existing_bytes_exactly
    with_shelf do |shelf, _root|
      shelf.append_entry!(collection: "notes", entry: { "file" => "good.txt" })
      before = File.read(shelf.manifest_path("notes"))
      assert_raises(Nabu::LibraryShelf::Error) do
        shelf.append_entry!(collection: "notes", entry: { "file" => "bad.txt", "languages" => ["chu (body ger)"] })
      end
      assert_equal before, File.read(shelf.manifest_path("notes")), "the poisoned append is truncated away"
      assert Nabu::LibraryManifest.load(shelf.manifest_path("notes")), "the manifest still parses"
    end
  end

  def test_manifested_reads_the_collection_manifest
    with_shelf do |shelf, _root|
      refute shelf.manifested?("notes", "a.txt"), "no manifest yet"
      shelf.append_entry!(collection: "notes", entry: { "file" => "a.txt" })
      assert shelf.manifested?("notes", "a.txt")
      refute shelf.manifested?("notes", "b.txt")
    end
  end
end
