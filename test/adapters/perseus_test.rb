# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Perseus adapter tests (P2-3). The adapter composes EpidocParser with
# PerseusDL repo-layout knowledge: discover walks data/<tg>/<work>/ for
# original-language editions, resolves titles/urns via __cts__.xml; fetch is a
# git clone/pull; parse delegates to EpidocParser.
#
# Includes the shared AdapterConformance suite against the checked-in greekLit
# fixtures. No network: fetch is exercised against a local git repo created in
# a tmpdir (git is a local process, allowed by CLAUDE.md) plus a Shell-failure
# path against a nonexistent upstream.
class PerseusTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/perseus", __dir__)
  GREEK_WORKDIR = File.join(FIXTURES, "greekLit")

  HH13_URN = "urn:cts:greekLit:tlg0013.tlg013.perseus-grc2"
  HH14_URN = "urn:cts:greekLit:tlg0013.tlg014.perseus-grc2"
  JOHN2_URN = "urn:cts:greekLit:tlg0031.tlg024.perseus-grc2"

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Perseus.new
  end

  def conformance_workdir
    GREEK_WORKDIR
  end

  def conformance_expected_source_id
    "perseus-greek"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest_is_the_greeklit_manifest
    manifest = Nabu::Adapters::Perseus.manifest
    assert_equal "perseus-greek", manifest.id
    assert_equal "Perseus Digital Library — canonical Greek literature", manifest.name
    assert_equal "CC BY-SA 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PerseusDL/canonical-greekLit", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
  end

  def test_instance_manifest_agrees_with_class_manifest
    assert_equal Nabu::Adapters::Perseus.manifest, Nabu::Adapters::Perseus.new.manifest
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_exactly_the_three_greeklit_editions_sorted
    refs = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a
    assert_equal [HH13_URN, HH14_URN, JOHN2_URN], refs.map(&:id)
  end

  def test_discover_sets_source_id_language_and_absolute_path
    refs = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a
    refs.each do |ref|
      assert_equal "perseus-greek", ref.source_id
      assert_equal "grc", ref.metadata["language"]
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path), "path must exist: #{ref.path.inspect}"
    end
  end

  def test_discover_resolves_titles_from_cts_metadata_preferring_english
    titles = Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR).to_a.to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "Hymn 13 to Demeter", titles.fetch(HH13_URN)
    assert_equal "Hymn 14 to the Mother of the Gods", titles.fetch(HH14_URN)
    # 2 John has four <ti:title> aliases; the first eng one wins.
    assert_equal "2 John", titles.fetch(JOHN2_URN)
  end

  def test_discover_returns_an_enumerator_without_a_block
    assert_kind_of Enumerator, Nabu::Adapters::Perseus.new.discover(GREEK_WORKDIR)
  end

  def test_discover_prefers_the_highest_edition_version
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc1.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      refs = Nabu::Adapters::Perseus.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc2"], refs.map(&:id)
    end
  end

  def test_discover_skips_translation_files
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-eng2.xml"))
      refs = Nabu::Adapters::Perseus.new.discover(dir).to_a
      assert_equal ["urn:cts:greekLit:tlg9999.tlg001.perseus-grc2"], refs.map(&:id)
    end
  end

  def test_discover_falls_back_to_urn_tail_when_cts_metadata_missing
    Dir.mktmpdir do |dir|
      work = File.join(dir, "data", "tlg9999", "tlg001")
      FileUtils.mkdir_p(work)
      FileUtils.touch(File.join(work, "tlg9999.tlg001.perseus-grc2.xml"))
      ref = Nabu::Adapters::Perseus.new.discover(dir).to_a.fetch(0)
      assert_equal "tlg9999.tlg001.perseus-grc2", ref.metadata["title"]
    end
  end

  # --- parse --------------------------------------------------------------

  def test_parse_round_trips_hh13
    adapter = Nabu::Adapters::Perseus.new
    ref = adapter.discover(GREEK_WORKDIR).find { |r| r.id == HH13_URN }
    document = adapter.parse(ref)
    assert_equal HH13_URN, document.urn
    assert_equal "grc", document.language
    assert_equal "Hymn 13 to Demeter", document.title
    assert_equal 3, document.size
    assert_equal "#{HH13_URN}:1", document.first.urn
    assert_includes document.first.text, "Δημήτηρ"
  end

  # --- fetch (local git only, no network) ---------------------------------

  def test_fetch_clones_when_no_local_repo_then_pulls_and_returns_fetch_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream, "one")
      head = git(upstream, "rev-parse", "HEAD")

      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(upstream)

      # No .git yet → clone path. fetch returns a FetchReport (architecture §3).
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal head, report.sha
      assert_instance_of Time, report.fetched_at
      assert_nil report.notes
      assert File.directory?(File.join(workdir, ".git")), "clone must create a .git dir"

      # Second call with .git present → pull path (ff-only, up to date).
      assert_equal head, adapter.fetch(workdir).sha

      # A new upstream commit is pulled and reflected in the returned sha.
      File.write(File.join(upstream, "two.txt"), "two\n")
      git(upstream, "add", ".")
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "two")
      new_head = git(upstream, "rev-parse", "HEAD")
      refute_equal head, new_head
      assert_equal new_head, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = perseus_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- registry round-trip ------------------------------------------------

  def test_registry_resolves_perseus_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["perseus-greek"]
    refute_nil entry, "perseus-greek must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Perseus, entry.adapter_class
    assert_equal "perseus-greek", entry.manifest.id
    assert_equal Nabu::Adapters::Perseus.manifest, entry.manifest
  end

  private

  def perseus_pointing_at(upstream_url)
    adapter = Nabu::Adapters::Perseus.new
    adapter.define_singleton_method(:manifest) do
      Nabu::SourceManifest.new(
        id: "perseus-greek", name: "test", license: "CC BY-SA 4.0",
        license_class: "attribution", upstream_url: upstream_url, parser_family: "epidoc"
      )
    end
    adapter
  end

  def make_git_repo(dir, seed)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "#{seed}.txt"), "#{seed}\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", seed)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
