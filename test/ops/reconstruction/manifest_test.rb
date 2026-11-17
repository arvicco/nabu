# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "yaml"
require "nabu/ops/reconstruction/manifest"

# `nabu reconstruct manifest` / `reconstruct check`: the portable reference
# manifest — census, per-source counts + transport + canary, and content
# digests of the carried trees — and the arrival check that re-digests the
# trees on the receiving box. In-memory catalog (the verify fixture
# pattern); planted temp trees for the digests.
class ReconstructionManifestTest < Minitest::Test
  include StoreTestDB

  Manifest = Nabu::Ops::Reconstruction::Manifest
  Verify = Nabu::Ops::Reconstruction::Verify

  def entry(slug, wired: true)
    Nabu::SourceRegistry::Entry.new(slug: slug, adapter_class_name: "TestAdapter", wired: wired,
                                    sync_policy: "manual")
  end

  def setup
    @catalog = store_test_db
    @tmp = Dir.mktmpdir("nabu-reconstruct-manifest")
    @canonical = File.join(@tmp, "canonical")
    @registry = Nabu::SourceRegistry.new([entry("greek"), entry("chinese"), entry("dict"),
                                          entry("offline", wired: false)])
    load_source("greek", [["urn:g:1", "grc", ["short", "μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος οὐλομένην, ἣ μυρί᾽"]],
                          ["urn:g:2", "grc", ["ἄνδρα μοι ἔννεπε"]]])
    load_source("chinese", [["urn:c:1", "lzh", ["天地玄黃宇宙洪荒日月盈昃辰宿列張寒來暑往秋收冬藏閏餘成歲律呂調陽"]]])
    dict = Nabu::Store::Source.create(slug: "dict", name: "Dict", adapter_class: "TestAdapter",
                                      license_class: "open")
    @catalog[:dictionaries].insert(source_id: dict.id, slug: "dict-lex", title: "Lex", language: "grc")
  end

  def teardown
    FileUtils.remove_entry(@tmp)
  end

  def load_source(slug, documents)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
    docs = documents.map do |urn, language, texts|
      doc = Nabu::Document.new(urn: urn, title: urn, language: language, canonical_path: "#{urn}.xml")
      texts.each_with_index do |text, i|
        doc << Nabu::Passage.new(urn: "#{urn}:#{i}", sequence: i, language: language, text: text,
                                 text_normalized: Nabu::Normalize.search_form(text, language: language))
      end
      doc
    end
    Nabu::Store::Loader.new(db: @catalog, source: source).load(docs)
  end

  def plant(relpath, content)
    path = File.join(@tmp, relpath)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def build(entry_paths: [], trees: true, absent_layers: [])
    Manifest.new(registry: @registry, catalog: @catalog, entry_paths: entry_paths, root: @tmp,
                 canonical_dir: @canonical, commit: "abc123", as_of: "2026-11-17", trees: trees,
                 absent_layers: absent_layers).build
  end

  # --- digests --------------------------------------------------------------

  def test_a_file_digests_as_the_sha256_of_its_contents
    path = plant("vectors.sqlite3", "vec")

    assert_equal({ "bytes" => 3, "files" => 1, "sha256" => Digest::SHA256.hexdigest("vec") },
                 Manifest.digest(path))
  end

  def test_a_directory_digests_over_sorted_relpath_lines
    plant("local/b.txt", "bee")
    plant("local/a/z.txt", "zed")
    lines = ["a/z.txt\t#{Digest::SHA256.hexdigest('zed')}\n", "b.txt\t#{Digest::SHA256.hexdigest('bee')}\n"]

    assert_equal({ "bytes" => 6, "files" => 2, "sha256" => Digest::SHA256.hexdigest(lines.join) },
                 Manifest.digest(File.join(@tmp, "local")))
  end

  def test_the_directory_digest_is_independent_of_creation_order
    plant("one/b.txt", "bee")
    plant("one/a.txt", "ay")
    plant("two/a.txt", "ay")
    plant("two/b.txt", "bee")

    assert_equal Manifest.digest(File.join(@tmp, "one")), Manifest.digest(File.join(@tmp, "two"))
  end

  def test_symlinks_hash_their_target_string_never_the_target
    plant("tree/real.txt", "real")
    File.symlink("real.txt", File.join(@tmp, "tree", "link"))
    File.symlink("/nowhere/dangling", File.join(@tmp, "tree", "dangling"))
    digest = Manifest.digest(File.join(@tmp, "tree"))
    lines = ["dangling\t#{Digest::SHA256.hexdigest('/nowhere/dangling')}\n",
             "link\t#{Digest::SHA256.hexdigest('real.txt')}\n",
             "real.txt\t#{Digest::SHA256.hexdigest('real')}\n"]

    assert_equal 3, digest["files"]
    assert_equal Digest::SHA256.hexdigest(lines.join), digest["sha256"]
  end

  def test_an_absent_path_digests_as_nil
    assert_nil Manifest.digest(File.join(@tmp, "nope"))
  end

  # --- build ----------------------------------------------------------------

  def test_the_manifest_carries_reference_census_and_per_source_rows
    manifest = build

    assert_equal 1, manifest["schema"]
    assert_equal({ "commit" => "abc123", "as_of" => "2026-11-17" }, manifest["reference"])
    assert_equal({ "documents" => 3, "passages" => 4, "language_codes" => 2, "live_sources" => 3 },
                 manifest["census"])
    assert_equal %w[chinese dict greek], manifest["sources"].keys
    assert_equal 2, manifest["sources"]["greek"]["documents"]
    assert_equal 3, manifest["sources"]["greek"]["passages"]
    assert_equal 0, manifest["sources"]["dict"]["documents"]
    assert_nil manifest["sources"]["dict"]["canary"], "a dictionary shelf has no passage to sample"
  end

  # The reference's own absent capability layers ride the manifest so the
  # receiving box's verify can tell a shared gap (parity) from a fresh one.
  def test_the_manifest_records_the_references_absent_capability_layers
    assert_equal({ "absent" => [] }, build["capability_homes"])
    manifest = build(absent_layers: %w[meter_shelf dates_shelf])

    assert_equal({ "absent" => %w[dates_shelf meter_shelf] }, manifest["capability_homes"])
    text = Manifest.render(manifest)
    assert_match(/^capability_homes: \{absent: \["dates_shelf", "meter_shelf"\]\}$/, text)
    assert_equal manifest, YAML.safe_load(text)
  end

  def test_canaries_are_verifys_own_sample_and_phrase
    manifest = build

    %w[greek chinese].each do |slug|
      source_id = @catalog[:sources].where(slug: slug).get(:id)
      sample = Verify.sample_passage(@catalog, source_id)
      assert_equal({ "urn" => sample[:urn], "phrase" => Verify.phrase(sample[:text_search]) },
                   manifest["sources"][slug]["canary"])
    end
    assert_equal "urn:g:1:1", manifest["sources"]["greek"]["canary"]["urn"],
                 "the first passage over MIN_SAMPLE chars, not the first passage"
  end

  def test_transport_is_carried_only_for_a_whole_canonical_tree_in_the_set
    entries = [File.join(@canonical, "greek"), File.join(@canonical, "chinese", ".attic")]
    sources = build(entry_paths: entries, trees: false)["sources"]

    assert_equal "carried", sources["greek"]["transport"]
    assert_equal "resynced", sources["chinese"]["transport"], "an attic subtree is not the tree"
    assert_equal "resynced", sources["dict"]["transport"]
  end

  def test_trees_are_repo_relative_digests_and_skippable
    plant("local/ledger.txt", "rows")
    plant("canonical/greek/a.xml", "<a/>")
    entries = [File.join(@tmp, "local"), File.join(@canonical, "greek")]

    trees = build(entry_paths: entries)["trees"]
    assert_equal(%w[local canonical/greek], trees.map { |tree| tree["path"] })
    assert_equal Manifest.digest(File.join(@tmp, "local")).merge("path" => "local"), trees.first
    assert_equal [], build(entry_paths: entries, trees: false)["trees"]
  end

  def test_render_round_trips_through_yaml_in_the_frozen_shape
    plant("local/ledger.txt", "rows")
    manifest = build(entry_paths: [File.join(@tmp, "local")])
    text = Manifest.render(manifest)

    assert_equal manifest, YAML.safe_load(text)
    assert_match(/^schema: 1$/, text)
    assert_match(/^reference: \{commit: "abc123", as_of: "2026-11-17"\}$/, text)
    assert_match(/^  - \{path: "local", bytes: 4, files: 1, sha256: "\h{64}"\}$/, text)
    assert_match(/^    canary: \{urn: "urn:g:1:1", phrase: "\\"/, text)
  end

  def test_yaml_ambiguous_slugs_render_quoted
    @registry = Nabu::SourceRegistry.new([entry("yes"), entry("plain-slug")])
    text = Manifest.render(build)

    assert_equal %w[plain-slug yes], YAML.safe_load(text)["sources"].keys
  end

  def test_write_and_load_round_trip
    manifest = build
    path = File.join(@tmp, "out", "manifest.yml")
    Manifest.write(manifest, path)

    assert_equal manifest, Manifest.load(path)
  end

  # --- check ----------------------------------------------------------------

  def test_check_reports_ok_mismatch_and_absent
    plant("local/ledger.txt", "rows")
    plant("canonical/greek/a.xml", "<a/>")
    plant("canonical/chinese/b.xml", "<b/>")
    entries = %w[local canonical/greek canonical/chinese].map { |rel| File.join(@tmp, rel) }
    manifest = build(entry_paths: entries)
    File.write(File.join(@tmp, "canonical", "greek", "a.xml"), "<A/>")
    FileUtils.remove_entry(File.join(@canonical, "chinese"))

    rows = Manifest.check(manifest, root: @tmp)
    assert_equal({ "local" => :ok, "canonical/greek" => :mismatch, "canonical/chinese" => :absent },
                 rows.to_h { |row| [row.path, row.status] })
    text = Manifest.render_check(rows)
    assert_match(/ok\s+local/, text)
    assert_match(%r{MISMATCH\s+canonical/greek}, text)
    assert_match(%r{ABSENT\s+canonical/chinese}, text)
  end

  def test_check_on_another_root_passes_when_the_bytes_arrived_intact
    plant("local/ledger.txt", "rows")
    manifest = build(entry_paths: [File.join(@tmp, "local")])
    other = File.join(@tmp, "other-box")
    FileUtils.mkdir_p(other)
    FileUtils.cp_r(File.join(@tmp, "local"), other)

    assert_equal [:ok], Manifest.check(manifest, root: other).map(&:status)
  end

  def test_the_check_command_exits_nonzero_on_a_mismatch
    plant("local/ledger.txt", "rows")
    path = File.join(@tmp, "manifest.yml")
    Manifest.write(build(entry_paths: [File.join(@tmp, "local")]), path)

    out, = capture_io { Nabu::CLI.start(["reconstruct", "check", path, "--root", @tmp]) }
    assert_match(/ok\s+local/, out)

    File.write(File.join(@tmp, "local", "ledger.txt"), "ROWS")
    error = assert_raises(SystemExit) do
      capture_io { Nabu::CLI.start(["reconstruct", "check", path, "--root", @tmp]) }
    end
    refute_equal 0, error.status
  end
end
