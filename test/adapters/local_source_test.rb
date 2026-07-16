# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-source dossier adapter (P24-0): the first SOURCE-shaped source.
# Like LocalLanguageTest it cannot include the shared AdapterConformance
# suite — that suite is passage-shaped — so this test mirrors the honest
# subset for the dossier shape: manifest validity + registered id + license
# class, discover→parse round-trip, ref-id ↔ slug identity, slug uniqueness
# and stability across independent passes, NFC output. The passage-only
# checks have no dossier analogue and are replaced by their record-level
# equivalents.
class LocalSourceTest < Minitest::Test
  WORKDIR = Nabu::TestSupport.fixtures("local-source")

  def adapter = Nabu::Adapters::LocalSource.new

  def test_manifest_is_valid_and_registered_as_local_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "local-source", manifest.id
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_equal "open", manifest.license_class, "owner-authored curation"
    assert_equal "source-dossier", manifest.parser_family
  end

  def test_content_kind_is_source_while_the_base_default_stays_passages
    assert_equal :source, Nabu::Adapters::LocalSource.content_kind
    assert_equal :passages, Nabu::Adapter.content_kind
  end

  def test_discover_yields_one_ref_per_dossier_in_stable_order
    refs = adapter.discover(WORKDIR).to_a
    assert_equal %w[local-source:edh local-source:lexica local-source:local-language], refs.map(&:id)
    refs.each { |ref| assert_equal "local-source", ref.source_id }
  end

  def test_discovery_skips_count_non_slug_markdown_by_rule
    skips = adapter.discovery_skips(WORKDIR)
    assert_equal 1, skips.skipped_by_rule, "README.md is an explicit, benign skip"
    assert_predicate skips, :clean?
  end

  def test_parse_yields_dossiers_whose_slug_matches_the_ref_id
    adapter.discover(WORKDIR).each do |ref|
      dossier = adapter.parse(ref)
      assert_kind_of Nabu::SourceDossier, dossier
      assert_equal ref.id, "local-source:#{dossier.slug}",
                   "the ref id must be recoverable from the parsed dossier"
      refute_empty dossier.records, "#{ref.id} parsed to zero records"
    end
  end

  def test_record_bodies_are_nfc_and_non_empty
    adapter.discover(WORKDIR).each do |ref|
      adapter.parse(ref).records.each do |record|
        refute_empty record.body
        assert record.body.unicode_normalized?(:nfc)
      end
    end
  end

  def test_slugs_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(WORKDIR).map { |ref| [ref.id, adapter.parse(ref).records] }
    end
    first = snapshot.call
    slugs = first.map(&:first)
    assert_equal slugs.uniq, slugs
    assert_equal first, snapshot.call
  end

  def test_parse_wraps_format_defects_in_parse_error
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "edh.md"), "no front matter")
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/front matter/, error.message)
    end
  end

  def test_fetch_scans_and_pins_per_file_and_fails_on_a_missing_tree
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-source")
      FileUtils.cp_r(WORKDIR, tree)
      report = adapter.fetch(tree)
      assert_kind_of Nabu::FetchReport, report
      assert_equal 6, report.repos.size,
                   "one pin per scanned file (3 dossiers + README + manifest + quarantine rig)"
      assert report.repos.key?("local:edh.md")
      assert_nil report.notes

      error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(dir, "empty")) }
      assert_match(/no local tree/, error.message)
    end
  end

  def test_fetch_keeps_a_vanished_files_pin_and_says_so
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-source")
      FileUtils.cp_r(WORKDIR, tree)
      adapter.fetch(tree)
      FileUtils.rm(File.join(tree, "lexica.md"))
      report = adapter.fetch(tree)
      assert report.repos.key?("local:lexica.md"), "the vanished file's pin lingers at its last-known sha"
      assert_match(/VANISHED/, report.notes)
      assert_match(/lexica\.md/, report.notes)
    end
  end

  def test_attic_dossiers_rediscover_as_retained
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "local-source")
      FileUtils.cp_r(WORKDIR, tree)
      adapter.fetch(tree)
      attic = File.join(tree, Nabu::Adapter::ATTIC_DIRNAME)
      FileUtils.mkdir_p(attic)
      FileUtils.mv(File.join(tree, "lexica.md"), File.join(attic, "lexica.md"))
      report = adapter.fetch(tree)
      assert_match(/1 file\(s\) retired/, report.notes)
      refs = adapter.discover_with_attic(tree).to_a
      retained = refs.find { |ref| ref.id == "local-source:lexica" }
      assert retained.metadata[Nabu::Adapter::RETAINED_KEY], "the retired dossier is rediscovered retained"
      assert_match(/reference shelf/, adapter.parse(retained).description)
    end
  end
end
