# frozen_string_literal: true

require "test_helper"

# The lane-lexicon adapter: Lane's Arabic-English Lexicon from the Alpheios
# repository, one dictionary shelf ("lane", language ara). Dictionary-shaped,
# so it mirrors the passage conformance suite's checks for the dictionary
# shape (the lexica precedent): manifest validity, discover -> parse round
# trip, (dictionary, entry_id) uniqueness and stability across independent
# passes, NFC output, license class present — plus the id design's
# duplicate / collision / pointer behaviour and the loader's idempotency.
class LaneLexiconTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("lane-lexicon")
  LAN = File.join("db", "lexica", "ara", "lan")

  def adapter = Nabu::Adapters::LaneLexicon.new

  def entries_by_id(workdir = FIXTURES)
    adapter.discover(workdir).flat_map { |ref| adapter.parse(ref).entries }.to_h { |e| [e.entry_id, e] }
  end

  # -- manifest + registry --------------------------------------------------------

  def test_manifest_is_valid_and_carries_the_by_sa_grant
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "lane-lexicon", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution-ShareAlike 3.0 United States License"
    assert_equal "lane-tei", manifest.parser_family
    assert_equal "https://github.com/alpheios-project/lan", manifest.upstream_url
    assert_equal :dictionary, Nabu::Adapters::LaneLexicon.content_kind
  end

  def test_registry_row_is_wired_manual_and_on_the_arabic_desk
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["lane-lexicon"]
    refute_nil entry, "config/sources/ must register lane-lexicon"
    assert entry.wired, "wired since the verified first sync (37 documents, 48,795 entries)"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[arabic], entry.axes
    assert_equal "lane-lexicon", entry.adapter_class.manifest.id
  end

  # -- discover: the delivery grains ------------------------------------------------

  def test_discover_yields_one_ref_per_bucket_file_with_the_duplicate_collapsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[lane-lexicon:u_0.xml lane-lexicon:u_Y0.xml lane-lexicon:uq1.xml lane-lexicon:uq2.xml],
                 refs.map(&:id)
    refs.each { |ref| assert_equal "lane-lexicon", ref.source_id }
    assert_equal refs.map(&:id).uniq, refs.map(&:id)
  end

  def test_discovery_skips_count_the_duplicate_and_every_rejected_grain
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 4, skips.skipped_by_rule, skips.notes.inspect
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(/ua0\.xml: whitespace-equivalent duplicate of u_0\.xml/, notes)
    assert_match(%r{db/indexes/ara-lan-index\.xml: .*lemma index}, notes)
    assert_match(%r{dat/ara-lan-ids\.dat: .*id list}, notes)
    assert_match(/__contents__\.xml: .*eXist/, notes)
  end

  def test_an_unknown_file_in_the_tree_is_unrecognized
    with_fixture_copy do |dir|
      File.write(File.join(dir, LAN, "notes.xml"), "<x/>")
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(%r{db/lexica/ara/lan/notes\.xml}, skips.notes.join("\n"))
    end
  end

  # -- the id design: duplicates, variants, pointers -----------------------------------

  def test_a_diverged_duplicate_loads_under_its_file_prefix_never_dropped
    with_fixture_copy do |dir|
      path = File.join(dir, LAN, "ua0.xml")
      File.write(path, File.read(path).sub("(a lion)", "(a lion!)"))
      refs = adapter.discover(dir).map(&:id)
      assert_includes refs, "lane-lexicon:ua0.xml"
      entries = entries_by_id(dir)
      assert_includes entries.keys, "ua0.n14041"
      assert_includes entries.keys, "n14041"
      assert_equal "variant", entries.fetch("ua0.n14041").annotations["copy"]
      assert_equal adapter.discovery_skips(FIXTURES).skipped_by_rule - 1, adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  def test_a_colliding_id_keeps_both_entries_under_distinct_ids
    entries = entries_by_id
    assert_equal "قَبَعَ السِّقَاءَ", entries.fetch("n42507").headword, "uq1.xml owns the bare id"
    assert_equal "قَبَّانٌ", entries.fetch("uq2.n42507").headword, "uq2.xml's reuse of n42507 is a different word"
    assert_equal "variant", entries.fetch("uq2.n42507").annotations["copy"]
    refute entries.fetch("n42507").annotations.key?("copy")
  end

  def test_supplement_files_are_marked_and_main_files_are_not
    entries = entries_by_id
    assert_equal "supplement", entries.fetch("n42506").annotations["section"]
    assert_equal "supplement", entries.fetch("uq2.n42477").annotations["section"]
    refute entries.fetch("n14041").annotations.key?("section")
    refute entries.fetch("n42419").annotations.key?("section"), "u_Y0.xml is the main ي letter, not supplement"
  end

  def test_every_pointer_and_stub_entry_loads
    entries = entries_by_id
    assert_equal 42, entries.size, "u_0 29 + u_Y0 2 + uq1 4 + uq2 7 — ua0's 29 collapsed"
    assert_includes entries.keys, "n14041.1"
    assert_equal "See Supplement", entries.fetch("n42419.1").body
  end

  # -- the dictionary conformance checks -----------------------------------------------

  def test_parse_yields_one_lane_dictionary_document_per_ref
    adapter.discover(FIXTURES).each do |ref|
      document = adapter.parse(ref)
      assert_kind_of Nabu::DictionaryDocument, document
      assert_equal %w[lane ara], [document.slug, document.language]
      refute_empty document.entries, "#{ref.id} parsed to zero entries"
    end
  end

  def test_entry_ids_are_unique_across_the_discover_set
    ids = adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).map(&:entry_id) }
    assert_equal ids.uniq, ids
  end

  def test_ids_and_content_are_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(FIXTURES).map do |ref|
        [ref.id, adapter.parse(ref).map { |e| [e.entry_id, Nabu::Store::ContentHash.dictionary_entry(e)] }]
      end
    end
    assert_equal snapshot.call, snapshot.call
  end

  def test_entry_output_is_nfc
    entries_by_id.each_value do |entry|
      assert entry.headword.unicode_normalized?(:nfc), entry.entry_id
      assert entry.body.unicode_normalized?(:nfc), entry.entry_id
    end
  end

  # -- the store ---------------------------------------------------------------------

  def test_loads_idempotently_and_resolves_the_pointers
    db = store_test_db
    source = create_source
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal [42, 0], [first.added, first.errored]
    revisions = db[:dictionary_entries].select_hash(:entry_id, :revision)
    second = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal [0, 42, 0], [second.added, second.skipped, second.errored]
    assert_equal revisions, db[:dictionary_entries].select_hash(:entry_id, :revision)
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:lane:n14041.1"

    ids = db[:dictionary_entries].select_hash(:entry_id, :id)
    resolved = db[:dictionary_crossrefs].where(dictionary_entry_id: ids.fetch("n14041.1")).get(:to_entry_id)
    assert_equal ids.fetch("n14041"), resolved, "'see 1' reaches paragraph 1 of the root"
  ensure
    db&.disconnect
  end

  def test_define_finds_an_entry_from_its_vocalized_spelling
    db = store_test_db
    Nabu::Store::DictionaryLoader.new(db: db, source: create_source).load_from(adapter, workdir: FIXTURES)
    hits = Nabu::Query::Define.new(catalog: db, lila: nil, form_lemma: nil, verb_lemma: nil, lects: nil)
                              .run("ذَمِىَ", limit: nil).map(&:urn)
    assert_includes hits, "urn:nabu:dict:lane:n14061", "the harakat fold away on both sides"
  ensure
    db&.disconnect
  end

  # -- fetch (pinned commit; local repos, no network) -----------------------------------

  def test_fetch_accepts_the_pinned_commit
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        workdir = File.join(root, "work")
        report = Nabu::Adapters::LaneLexicon.new(repo_url: repo_url, pinned_sha: sha).fetch(workdir)
        assert_equal sha, report.sha
        assert File.file?(File.join(workdir, LAN, "u_0.xml"))
      end
    end
  end

  def test_fetch_stops_loudly_when_upstream_drifts_from_the_pin
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        adapter = Nabu::Adapters::LaneLexicon.new(repo_url: repo_url, pinned_sha: "0" * 40)
        error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
        assert_includes error.message, sha[0, 12]
        assert_includes error.message, "pin"
      end
    end
  end

  def test_the_pin_is_the_census_head
    assert_equal "7dd04e1182c13a4b0883978867d2a3b04616542a", Nabu::Adapters::LaneLexicon::PINNED_SHA
  end

  private

  def create_source
    Nabu::Store::Source.create(slug: "lane-lexicon", name: "Lane", adapter_class: "Nabu::Adapters::LaneLexicon",
                               license_class: "attribution")
  end

  def with_fixture_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      FileUtils.rm_f(File.join(dir, "README.md"))
      FileUtils.rm_f(File.join(dir, "manifest.yml"))
      yield dir
    end
  end

  def with_local_upstream
    with_fixture_copy do |upstream|
      Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=master")
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "lexicon")
      yield upstream, Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
    end
  end
end
