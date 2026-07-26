# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Dillmann (P46-2): the Gǝʿǝz dictionary shelf — Dillmann's
# Lexicon linguae aethiopicae (1865) in the TraCES project's TEI digitization
# (BetaMasaheft/DillmannData; the sibling `Dillmann` repo is only the eXist-db
# app). Dictionary-shaped, so it cannot include the passage-shaped
# AdapterConformance suite; like LexicaTest/MwTest/CclTest it mirrors those
# checks for the dictionary shape (manifest validity, discover→parse
# round-trip, id uniqueness/stability, NFC, license class) and adds the
# DictionaryLoader contract plus the source-specific pins.
#
# THE MALFORMED-URL LICENSE (row 124): every entry file's licence target reads
# "http(s)://creativecommons.org/licenses/by-sa-nc/4.0/" — a URL Creative
# Commons does not serve; the prose beside it names Attribution-ShareAlike
# Non Commercial 4.0, i.e. CC BY-NC-SA 4.0 → class nc. Pinned here on the
# real fixture bytes (both URL-scheme variants).
class DillmannTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("dillmann")

  ASM = "L3c8821a46d56420283fc3bdedc1c341a"   # ዐፅም "os/bone", n=7417
  MOTA = "L2d417be91261494990015aae6b9b5d81"  # ሞተ "mori/die", n=1472 — the TraCES crosswalk anchor
  DARABA = "L844cd3b8849f4c16b5f3390e611a4f7b" # ደረባ, the TraCES-addition shape, n=12860

  def adapter = Nabu::Adapters::Dillmann.new

  # --- manifest + content kind ----------------------------------------------

  def test_manifest_identifies_the_dillmann_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "dillmann", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/CC BY-NC-SA 4\.0/, manifest.license)
    assert_match(/by-sa-nc/, manifest.license,
                 "the malformed in-file URL quirk is recorded verbatim in the manifest")
    assert_equal "dillmann-tei", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Dillmann.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------

  def test_discover_yields_one_ref_per_entry_file_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["dillmann:#{MOTA}", "dillmann:#{ASM}", "dillmann:#{DARABA}"], refs.map(&:id),
                 "one ref per */<entry-id>.xml, sorted by id"
    assert(refs.all? { |ref| ref.source_id == "dillmann" })
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_gez_dictionary_document_per_file
    document = adapter.parse(ref_for(ASM))
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "dillmann", document.slug
    assert_equal "gez", document.language
    assert_equal 1, document.size, "one upstream file IS one entry"
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).map(&:entry_id) }
    end
    first = snapshot.call
    assert_equal first.uniq.sort, first.sort
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    adapter.discover(FIXTURES).each do |ref|
      adapter.parse(ref).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  # --- the entry shape -------------------------------------------------------

  def test_asm_entry_parses_headword_gloss_and_sense_body
    entry = adapter.parse(ref_for(ASM)).first
    assert_equal ASM, entry.entry_id, "the entry @xml:id (== the filename stem) is the id"
    assert_equal "7417", entry.key_raw, "the Dillmann running number rides key_raw"
    assert_equal "ዐፅም", entry.headword
    assert_equal "os", entry.gloss, "the first <cit type=\"translation\"> quote is the gloss"
    assert_match(/Gen\.\s+2,23/, entry.body, "biblical citations stay readable in the body")
    assert_match(/cranium/, entry.body, "lettered sub-senses flow into the body")
    assert_match(/^a\./, entry.body, "a lettered sense opens its own body line with its label")
  end

  def test_headword_folded_speaks_the_gez_search_form
    entry = adapter.parse(ref_for(ASM)).first
    assert_equal Nabu::Normalize.search_form("ዐፅም", language: "gez"), entry.headword_folded
  end

  def test_traces_addition_entry_parses_with_nil_gloss
    entry = adapter.parse(ref_for(DARABA)).first
    assert_equal DARABA, entry.entry_id
    assert_equal "ደረባ", entry.headword
    assert_nil entry.gloss, "no translation cit upstream — nil gloss is honest"
    assert_match(/darabā/, entry.body, "the prefixed-namespace <t:quote> transcription is read")
    assert_match(/meaning unknown/, entry.body)
  end

  def test_mota_is_the_traces_crosswalk_anchor
    entry = adapter.parse(ref_for(MOTA)).first
    assert_equal MOTA, entry.entry_id
    assert_equal "ሞተ", entry.headword
    assert_equal "1472", entry.key_raw
  end

  # --- the malformed-URL license, pinned on real bytes -----------------------

  def test_both_malformed_licence_url_variants_are_pinned_by_the_fixtures
    http = File.read(File.join(FIXTURES, "1", "#{MOTA}.xml"))
    https = File.read(File.join(FIXTURES, "new1", "#{DARABA}.xml"))
    assert_includes http, 'licence target="http://creativecommons.org/licenses/by-sa-nc/4.0/"'
    assert_includes https, 'licence target="https://creativecommons.org/licenses/by-sa-nc/4.0/"'
    assert_match(/Attribution-ShareAlike Non Commercial 4\.0/, http,
                 "the prose names BY-NC-SA — the intent behind the malformed URL → class nc")
  end

  # --- DictionaryLoader contract (idempotency / urn) -------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                         .load_from(adapter, workdir: FIXTURES)
    assert_equal 0, first.errored
    assert_equal 3, db[:dictionary_entries].count

    second = Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                          .load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 3, db[:dictionary_entries].count, "a byte-identical reload upserts, never duplicates"
    urns = db[:dictionary_entries].select_map(:urn)
    assert_includes urns, "urn:nabu:dict:dillmann:#{MOTA}"
  ensure
    db&.disconnect
  end

  # --- fetch (local git only, no network) ------------------------------------

  def test_fetch_sparse_clones_the_entry_cone
    Dir.mktmpdir("nabu-dillmann-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      dillmann = adapter
      dillmann.define_singleton_method(:repo_url) { upstream }
      report = dillmann.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "1", "#{MOTA}.xml")), "the entry cone materializes"
      refute File.exist?(File.join(work, "icon.png")), "outside-cone binaries must not materialize"
      refute_empty dillmann.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(entry_id)
    adapter.discover(FIXTURES).to_a.find { |ref| ref.id == "dillmann:#{entry_id}" } ||
      flunk("no ref for #{entry_id}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "dillmann", name: "Dillmann, Lexicon linguae aethiopicae",
      adapter_class: "Nabu::Adapters::Dillmann", license_class: "nc"
    )
  end

  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    FileUtils.cp_r(File.join(FIXTURES, "1"), upstream)
    FileUtils.cp_r(File.join(FIXTURES, "new1"), upstream)
    File.binwrite(File.join(upstream, "icon.png"), "\x89PNG outside the cone")
    Nabu::Shell.run("git", "init", "-q", upstream)
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
