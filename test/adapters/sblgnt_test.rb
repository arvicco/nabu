# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SBLGNT adapter tests (P11-5): Faithlife/SBLGNT's per-book plain-text files
# under data/sblgnt/text/, one document per book. Includes the shared
# AdapterConformance suite against the checked-in fixtures (Mark 1:1-2:12
# trim, John 1:1-18 trim, 3John whole). No network: fetch runs against a
# local git repo.
class SblgntTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("sblgnt")

  BOOK_URNS = %w[urn:nabu:sblgnt:3john urn:nabu:sblgnt:john urn:nabu:sblgnt:mark].freeze

  def conformance_adapter
    Nabu::Adapters::Sblgnt.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "sblgnt"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_sblgnt_source
    manifest = Nabu::Adapters::Sblgnt.manifest
    assert_equal "sblgnt", manifest.id
    assert_equal "CC BY 4.0", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/Faithlife/SBLGNT", manifest.upstream_url
    assert_equal "sblgnt-tsv", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_file_sorted_by_urn
    refs = Nabu::Adapters::Sblgnt.new.discover(FIXTURES).to_a
    assert_equal BOOK_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "sblgnt" && r.metadata["language"] == "grc" })
  end

  def test_discover_peeks_greek_titles_from_the_first_line
    titles = Nabu::Adapters::Sblgnt.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata["title"]] }
    assert_equal "ΚΑΤΑ ΜΑΡΚΟΝ", titles.fetch("urn:nabu:sblgnt:mark")
    assert_equal "ΙΩΑΝΝΟΥ Γ", titles.fetch("urn:nabu:sblgnt:3john")
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Sblgnt.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_mark_at_verse_grain
    adapter = Nabu::Adapters::Sblgnt.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:sblgnt:mark" }
    document = adapter.parse(ref)
    assert_equal "urn:nabu:sblgnt:mark", document.urn
    assert_equal "grc", document.language
    assert_equal 57, document.size
    assert_equal "Ἀρχὴ τοῦ εὐαγγελίου Ἰησοῦ ⸀χριστοῦ.", document.first.text
    refute_nil(document.find { |p| p.urn == "urn:nabu:sblgnt:mark:2.3" })
  end

  # --- fetch (local git only, no network) ---------------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = sblgnt_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = sblgnt_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_sblgnt_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sblgnt"]
    refute_nil entry, "sblgnt must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Sblgnt, entry.adapter_class
    refute entry.enabled, "sblgnt stays enabled: false until the owner-fired first sync is verified"
    assert_equal Nabu::Adapters::Sblgnt.manifest, entry.manifest
  end

  private

  def sblgnt_pointing_at(upstream)
    adapter = Nabu::Adapters::Sblgnt.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    text_dir = File.join(dir, "data", "sblgnt", "text")
    FileUtils.mkdir_p(text_dir)
    git(dir, "init", "-q")
    FileUtils.cp(File.join(FIXTURES, "data", "sblgnt", "text", "3John.txt"), text_dir)
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
