# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The HDIC adapter (P32-4): five Heian-period hanzi dictionaries as one
# git-fetched source (the sl-lexica multi-dictionary precedent on the
# lexica git path). Dictionary-shaped, so it mirrors the passage
# conformance checks for the dictionary shape and adds the git fetch
# (local tmp repo, no network), the recorded license discrepancy, the
# language-notes rider, the DictionaryLoader contract and the registry row.
class HdicTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("hdic")

  EXPECTED_REF_IDS = ["yyp:YYP.tsv", "ktb:KTB.tsv", "tsj:TSJ_definitions.tsv",
                      "syp:SYP.tsv", "krm:KRM.tsv"].freeze

  def adapter = Nabu::Adapters::Hdic.new

  # --- manifest + content kind ----------------------------------------------------

  def test_manifest_carries_the_by_sa_grant_and_the_recorded_license_discrepancy
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "hdic", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Creative Commons Attribution-ShareAlike 4\.0 International License \(CC BY-SA 4\.0\)/,
                 manifest.license, "the README + per-file grant travels verbatim")
    assert_match(/Open access/, manifest.license)
    assert_match(/BY-NC-SA legalcode/, manifest.license,
                 "the contradicting repo LICENSE file is journaled IN the manifest — owner gate")
    assert_equal "https://github.com/shikeda/HDIC", manifest.upstream_url,
                 "the ACTIVE upstream — never the stale nk2028 mirror"
    assert_equal "hdic-tsv", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Hdic.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_per_published_database_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal EXPECTED_REF_IDS, refs.map(&:id)
    assert_equal %w[hdic] * 5, refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    adapter.parse(ref)
  end

  def test_parse_yields_five_dictionary_documents_with_censused_languages
    { "yyp" => "lzh", "ktb" => "lzh", "tsj" => "lzh", "syp" => "lzh", "krm" => "jpn" }
      .each do |slug, language|
      document = parse(slug)
      assert_kind_of Nabu::DictionaryDocument, document
      assert_equal slug, document.slug
      assert_equal language, document.language,
                   "#{slug}: lzh for the Literary Chinese definition databases, " \
                   "jpn for KRM's kana-reading definitions"
      assert_equal 12, document.size
    end
  end

  def test_entry_ids_are_upstream_ids_unique_and_stable
    %w[yyp ktb tsj syp krm].each do |slug|
      first = parse(slug).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parse(slug).map(&:entry_id)
    end
    assert_equal "Y08000001-1", parse("yyp").entries.first.entry_id
    assert_equal "a005a101", parse("syp").entries.first.entry_id
  end

  def test_entry_output_is_nfc
    %w[yyp ktb tsj syp krm].each do |slug|
      parse(slug).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  def test_the_yupian_lane_carries_the_cross_dictionary_ids
    wei = parse("yyp").entries.first
    assert_equal "愇", wei.headword
    assert_includes wei.body, "TBID: 3_005_A61", "YYP→KTB link"
    assert_includes wei.body, "SYID: a078b062", "YYP→SYP link"
  end

  # --- language-notes rider --------------------------------------------------------

  def test_language_notes_cover_the_lzh_shelf_and_the_krm_jpn_stratum
    notes = Nabu::Adapters::Hdic.language_notes
    assert_equal([%w[lzh witness:hdic], %w[jpn witness:hdic]],
                 notes.map { |lang, kind, _| [lang, kind] })
    notes.each { |_, _, body| assert body.unicode_normalized?(:nfc) }
  end

  # --- fetch (local git repo, no network) ------------------------------------------

  def with_local_upstream
    Dir.mktmpdir do |tmp|
      upstream = File.join(tmp, "HDIC")
      FileUtils.mkdir_p(upstream)
      Dir.glob(File.join(FIXTURES, "*.tsv")).each { |file| FileUtils.cp(file, upstream) }
      git(upstream, "init", "-q")
      git(upstream, "add", ".")
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
      yield upstream, File.join(tmp, "workdir")
    end
  end

  def test_fetch_clones_the_repo_and_discovers_all_five_databases
    with_local_upstream do |upstream, workdir|
      local = adapter
      local.define_singleton_method(:repo_url) { upstream }
      report = local.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal EXPECTED_REF_IDS, local.discover(workdir).to_a.map(&:id)
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "hdic", name: "HDIC", adapter_class: "Nabu::Adapters::Hdic",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: "https://github.com/shikeda/HDIC", enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_across_all_five_dictionaries
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 60, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 60, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    ktb_one = db[:dictionary_entries].where(entry_id: "1_016_A51").first
    assert_equal "urn:nabu:dict:ktb:1_016_A51", ktb_one[:urn]
    assert_equal "一", ktb_one[:headword]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["hdic"]
    refute_nil entry, "config/sources.yml must register hdic"
    assert_equal Nabu::Adapters::Hdic, entry.adapter_class
    assert entry.enabled, "live (D36-d owner ruling 2026-07-20: license GO; first sync owner-fired as usual)"
    assert_equal "manual", entry.sync_policy
  end

  private

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
