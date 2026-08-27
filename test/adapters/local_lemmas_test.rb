# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-lemmas adapter (P84-1): the FIFTH shelf-shaped source. Like
# LocalNotesTest it cannot include the passage-shaped AdapterConformance
# suite — a lemma shard mints no Document/Passage; its derived product is
# FULLTEXT-side (SilverLemmaIndexer → passage_lemmas), so the loader lane
# only VALIDATES. This test covers the honest subset: manifest validity +
# registered id + license class, discover→parse round-trip against the
# real-output fixture shard, ref stability, and quarantine on a malformed
# shard.
class LocalLemmasTest < Minitest::Test
  WORKDIR = Nabu::TestSupport.fixtures("local-lemmas")

  def adapter = Nabu::Adapters::LocalLemmas.new

  def test_manifest_is_valid_and_registered_as_local_lemmas
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "local-lemmas", manifest.id
    assert_equal Nabu::LemmaShelf::SLUG, manifest.id, "gateway and adapter agree on the shelf slug"
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_equal "open", manifest.license_class, "locally computed annotation, no upstream text"
  end

  def test_content_kind_is_lemmas
    assert_equal :lemmas, Nabu::Adapters::LocalLemmas.content_kind
    assert_empty Nabu::Adapters::LocalLemmas.upstream_repo_urls, "a shelf has no upstream"
  end

  def test_discover_yields_one_ref_per_shard_in_stable_order
    refs = adapter.discover(WORKDIR).to_a
    assert_equal %w[local-lemmas:lat/shard-000001], refs.map(&:id)
    assert_equal refs.map(&:id), adapter.discover(WORKDIR).to_a.map(&:id),
                 "ids stable across independent passes"
    assert_equal "lat", refs.first.metadata["language"]
  end

  def test_parse_validates_the_real_fixture_shard
    ref = adapter.discover(WORKDIR).first
    shard = adapter.parse(ref)
    assert_equal 2, shard.records
    assert_equal "lat", shard.language
  end

  def test_parse_quarantines_a_malformed_shard
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lat"))
      File.write(File.join(dir, "lat", "shard-000001.jsonl"), "not json\n")
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_state_furniture_is_not_discovered
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lat"))
      FileUtils.cp(File.join(WORKDIR, "lat", "shard-000001.jsonl"), File.join(dir, "lat"))
      File.write(File.join(dir, "lat", Nabu::LemmaShelf::STATE_FILE), "{}")
      assert_equal 1, adapter.discover(dir).to_a.size, "the campaign checkpoint is furniture, not content"
    end
  end
end
