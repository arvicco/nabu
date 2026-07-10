# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# EngWeb adapter tests (P11-8): the World English Bible from seven1m/open-bibles
# (one whole-bible USFX file, the Vulgate's public-domain English sibling),
# minting one document per book. Includes the shared AdapterConformance suite
# against the checked-in fixture trim (scripture books JON, OBA, PHM plus the
# non-scripture peripheral books FRT + GLO, P11-10). No network: fetch runs
# against a local git repo.
class EngWebTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("eng-web")

  # discover yields every book, in file order — peripheral (FRT/GLO) included;
  # parse declines the peripheral ones by rule (see below).
  ALL_BOOK_URNS = %w[urn:nabu:eng-web:frt urn:nabu:eng-web:jon urn:nabu:eng-web:oba
                     urn:nabu:eng-web:phm urn:nabu:eng-web:glo].freeze
  BOOK_URNS = %w[urn:nabu:eng-web:jon urn:nabu:eng-web:oba urn:nabu:eng-web:phm].freeze

  def conformance_adapter
    Nabu::Adapters::EngWeb.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "eng-web"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_web_source_as_public_domain
    manifest = Nabu::Adapters::EngWeb.manifest
    assert_equal "eng-web", manifest.id
    assert_equal "Public Domain", manifest.license
    assert_equal "open", manifest.license_class
    assert_equal "https://github.com/seven1m/open-bibles", manifest.upstream_url
    assert_equal "usfx", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_in_canon_order
    refs = Nabu::Adapters::EngWeb.new.discover(FIXTURES).to_a
    assert_equal ALL_BOOK_URNS, refs.map(&:id)
    assert_equal(%w[FRT JON OBA PHM GLO], refs.map { |r| r.metadata["book"] })
    assert_equal(%w[Preface Jonah Obadiah Philemon Glossary], refs.map { |r| r.metadata["title"] })
    assert(refs.all? { |r| r.source_id == "eng-web" && r.metadata["language"] == "eng" })
  end

  # P11-10: FRT (front matter) and GLO (glossary) are structural non-scripture
  # books with zero verses. discover still yields them (honest inventory), but
  # parse declines them by rule — Nabu::DocumentSkipped, which the loader counts
  # as skipped-by-rule rather than quarantining as damage.
  def test_parse_skips_non_scripture_books_by_rule
    adapter = Nabu::Adapters::EngWeb.new
    %w[urn:nabu:eng-web:frt urn:nabu:eng-web:glo].each do |urn|
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      error = assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref) }
      assert_match(/non-scripture book/, error.reason)
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::EngWeb.new.discover(dir).to_a
    end
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_round_trips_jonah_at_verse_grain_without_footnotes
    adapter = Nabu::Adapters::EngWeb.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:eng-web:jon" }
    document = adapter.parse(ref)
    assert_equal "urn:nabu:eng-web:jon", document.urn
    assert_equal "eng", document.language
    assert_equal "Jonah", document.title
    assert_equal 48, document.size
    jon11 = document.find { |p| p.urn == "urn:nabu:eng-web:jon:1.1" }
    assert_equal "Now Yahweh’s word came to Jonah the son of Amittai, saying,", jon11.text
    refute_includes jon11.text, "LORD", "footnote apparatus must not bleed into the verse"
  end

  # --- fetch (local git only, no network) ---------------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = eng_web_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = eng_web_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_eng_web_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["eng-web"]
    refute_nil entry, "eng-web must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::EngWeb, entry.adapter_class
    assert entry.enabled, "eng-web is live (owner sign-off 2026-07-10 after first sync + eyeball)"
    assert_equal Nabu::Adapters::EngWeb.manifest, entry.manifest
  end

  private

  def eng_web_pointing_at(upstream)
    adapter = Nabu::Adapters::EngWeb.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    FileUtils.cp(File.join(FIXTURES, "eng-web.usfx.xml"), dir)
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
