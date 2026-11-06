# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# LEME — Lexicons of Early Modern English on TSpace, one dictionary shelf
# per lexical work. Real fixtures: four held items (record + XML) — three
# accepted lexicons and Cotton's prose essay, the no-word-entry grain —
# plus the trimmed discovery listing (test/fixtures/leme/README.md). A
# dictionary shelf serves entries, not passages, so — the littre /
# DefinitionsShelfChecks stance — the passage conformance suite is
# mirrored for the dictionary shape: manifest, discover round-trip, rule
# skips with notes, entry-id uniqueness and stability, NFC, and the
# DictionaryLoader contract.
class LemeTest < Minitest::Test
  include StoreTestDB

  ADAPTER = Nabu::Adapters::Leme

  def fixtures = Nabu::TestSupport.fixtures("leme")

  def documents
    @documents ||= begin
      adapter = ADAPTER.new
      adapter.discover(fixtures).map { |ref| adapter.parse(ref) }
    end
  end

  def document(slug) = documents.find { |d| d.slug == slug }

  def with_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(fixtures, "."), dir)
      yield dir
    end
  end

  def test_manifest_carries_the_verbatim_license
    manifest = ADAPTER.manifest
    assert_equal "leme", manifest.id
    assert_match(/The following materials in LEME are licensed under a Creative Commons Attribution 4\.0 /,
                 manifest.license)
    assert_match(/International license: All files provided on the LEME website/, manifest.license)
    assert_match(/the XML encoded texts of lexical works, made available through the TSpace institutional repository/,
                 manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "https://hdl.handle.net/1807/99021", manifest.upstream_url
    assert_equal "leme-xml", manifest.parser_family
    assert_equal :dictionary, ADAPTER.content_kind
  end

  def test_discover_yields_one_ref_per_held_lexicon_and_nothing_before_a_fetch
    refs = ADAPTER.new.discover(fixtures).to_a
    assert_equal %w[leme:102611 leme:124555 leme:131265], refs.map(&:id)
    assert(refs.all? { |r| r.source_id == "leme" })
    assert_equal "leme-102611", refs.first.metadata["dictionary"]
    Dir.mktmpdir { |empty| assert_empty ADAPTER.new.discover(empty).to_a }
  end

  def test_the_prose_essay_and_the_unnamed_bitstreams_skip_by_rule_with_notes
    skips = ADAPTER.new.discovery_skips(fixtures)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(%r{\A1807/102105: skipped by rule — the XML carries no headworded <wordentry>}, skips.notes.first)
    assert_match(%r{\A1807/102611: 1 unnamed ORIGINAL bitstream\(s\) skipped by rule}, skips.notes.last)
    Dir.mktmpdir { |empty| assert_equal 0, ADAPTER.new.discovery_skips(empty).skipped_by_rule }
  end

  # 1807/111075 (Manlove's lead-mine terms, 1653) wraps its verse word
  # list in one <wordentry> with no <form> — no headword anywhere.
  def test_word_entries_without_any_form_skip_by_rule_too
    with_copy do |dir|
      path = File.join(dir, "xml", "124555.xml")
      File.binwrite(path, File.binread(path).gsub(%r{</?form[^>]*>}n, ""))
      refute_includes ADAPTER.new.discover(dir).map(&:id), "leme:124555"
      assert_equal 3, ADAPTER.new.discovery_skips(dir).skipped_by_rule
    end
  end

  def test_an_item_record_without_its_xml_is_unrecognized
    with_copy do |dir|
      File.delete(File.join(dir, "xml", "124555.xml"))
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |n| n.start_with?("1807/124555: item record held without its XML") })
      refute_includes ADAPTER.new.discover(dir).map(&:id), "leme:124555"
    end
  end

  def test_parse_yields_one_shelf_per_lexicon_titled_from_the_item_record
    assert_equal [15, 11, 13], documents.map(&:size)
    assert_equal %w[hbo en hbo], documents.map(&:language)
    assert_equal "Baldwin, William, The Canticles or Balades of Salomon (1549; STC 2768)", document("leme-102611").title
    assert_equal "Aubrey, John, The Natural History and Antiquities of the County of Surrey (1719; ESTC T89094)",
                 document("leme-124555").title
    assert_equal "Udall, John; Martinius, Petrus, The Key of the Holy Tongue (1593; STC 17523)",
                 document("leme-131265").title
  end

  def test_the_lexicon_year_and_author_ride_every_entry
    baldwin = document("leme-102611").entries
    assert(baldwin.all? { |e| e.annotations["lexicon_year"] == "1549" })
    assert(baldwin.all? { |e| e.annotations["lexicon_author"] == "Baldwin, William" })
    assert(document("leme-124555").entries.all? { |e| e.annotations["lexicon_year"] == "1719" })
  end

  def test_the_lexicon_year_is_the_typed_dc_date_created_with_the_one_erratum
    assert_equal "1593", ADAPTER.lexicon_year(JSON.parse(File.read(File.join(fixtures, "items", "131265.json"))))
    assert_equal "1475–1500", ADAPTER.lexicon_year({ "handle" => "1807/139760",
                                                     "metadata" => { "dc.date.created" => [{ "value" => "1884" }] } })
    assert_nil ADAPTER.lexicon_year({ "handle" => "1807/1",
                                      "metadata" => { "dc.date.created" => [{ "value" => "s.d." }] } })
  end

  def test_a_drifted_rights_uri_quarantines_the_lexicon
    with_copy do |dir|
      path = File.join(dir, "items", "124555.json")
      record = JSON.parse(File.read(path))
      record["metadata"]["dc.rights.uri"] = [{ "value" => "http://creativecommons.org/licenses/by-nc/4.0/" }]
      File.write(path, JSON.generate(record))
      adapter = ADAPTER.new
      ref = adapter.discover(dir).find { |r| r.id == "leme:124555" }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/drifted from CC BY 4\.0/, error.message)
    end
  end

  def test_entry_ids_are_unique_per_shelf_and_stable
    snapshot = lambda do
      adapter = ADAPTER.new
      adapter.discover(fixtures).map { |ref| adapter.parse(ref) }.flat_map { |d| d.map { |e| [d.slug, e.entry_id] } }
    end
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc_and_non_empty
    documents.flat_map(&:entries).each do |entry|
      refute_empty entry.body
      next if Nabu::Normalize.nfc_exempt?(entry.language)

      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "leme", name: "leme", adapter_class: ADAPTER.name,
      license: ADAPTER.manifest.license, license_class: "attribution"
    )
    load = -> { Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(ADAPTER.new, workdir: fixtures) }
    load.call
    urns = db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    load.call
    assert_equal urns, db[:dictionary_entries].order(:urn).select_map(%i[urn revision])
    assert_equal 39, urns.size
    assert(urns.all? { |urn, _| urn.start_with?("urn:nabu:dict:leme-") })
    assert_equal 3, db[:dictionaries].count
  end

  def test_registry_row_exists_wired_with_manual_sync_policy
    entry = Nabu::SourceRegistry.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"))["leme"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert_equal "manual", entry.sync_policy
    assert entry.wired, "first real sync verified (311 dictionaries / 943,211 entries)"
  end

  def test_the_probe_is_liveness_only_on_the_listing
    target = ADAPTER.http_probe_targets.first
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert target.liveness_only
    assert_equal Nabu::Adapters::LemeFetch.list_url(0), target.zip_url
  end
end
