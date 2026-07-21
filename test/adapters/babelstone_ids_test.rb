# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The BabelStone IDS adapter (P37-4): Andrew West's Ideographic Description
# Sequences, the decomposition spine behind `nabu char` and
# `search --char-component`. Dictionary-shaped (one entry per codepoint,
# keyed "U+XXXX"), single sha-pinned UTF-8 file. Mirrors the dictionary-shape
# conformance checks + the FileFetch path (WebMock only) + the ids-txt
# component-extraction contract.
class BabelstoneIdsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("babelstone-ids")
  URL = "https://www.babelstone.co.uk/CJK/IDS.TXT"

  def adapter = Nabu::Adapters::BabelstoneIds.new

  # --- manifest + content kind -----------------------------------------------------

  def test_manifest_carries_the_verbatim_public_domain_dedication
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "babelstone-ids", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/IDS sequences in themselves are not eligible for copyright protection/, manifest.license,
                 "the file header §2 dedication travels verbatim into the manifest")
    assert_match(/without asking permission or providing attribution/, manifest.license)
    assert_equal "ids-txt", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::BabelstoneIds.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_anchored_on_the_ids_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["babelstone-ids:IDS.TXT"], refs.map(&:id)
    assert_equal ["babelstone-ids"], refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse = adapter.parse(adapter.discover(FIXTURES).first)

  def test_parse_yields_one_zho_dictionary_document
    document = parse
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "babelstone-ids", document.slug
    assert_equal "zho", document.language
    assert_equal 12, document.size, "the 12 trimmed data lines"
  end

  def test_entry_ids_are_codepoints_that_join_unihan_and_are_stable
    ids = parse.map(&:entry_id)
    assert_includes ids, "U+68C4", "the acceptance character 棄"
    assert(ids.all? { |id| id.match?(/\AU\+\h{4,6}\z/) }, "keyed like Unihan/KANJIDIC2")
    assert_equal ids.uniq, ids
    assert_equal ids, parse.map(&:entry_id), "stable across two independent parses"
  end

  def test_the_qi_entry_carries_both_regional_ids_forms_verbatim
    qi = parse.find { |e| e.headword == "棄" }
    refute_nil qi
    assert_nil qi.gloss, "IDS has no gloss — an unbacked field stays absent"
    assert_includes qi.body, "⿳亠厶⿻廿木", "the G/H/T/P source form"
    assert_includes qi.body, "⿳亠厶⿱丗木", "the J/K regional source form kept whole"
  end

  # --- the ids-txt component contract (the containment seam) ------------------------

  def test_components_strip_the_operators_and_yield_the_real_components
    field = "^⿳亠厶⿻廿木$(GHTP)"
    components = Nabu::Adapters::IdsTxtParser.components(field)
    assert_equal %w[亠 厶 廿 木], components, "IDCs (⿳⿻) dropped, the four components kept"
  end

  def test_ext_b_components_survive_as_full_codepoints
    # 木 = ⿻十𠆢 — 𠆢 (U+201A2) is a plane-2 CJK Ext-B component: the honest
    # Ext-B census the fonts doc rider records (Jigmo territory).
    field = Nabu::Adapters::IdsTxtParser.components("^⿻十𠆢$(GHTJKPV)")
    assert_includes field, "𠆢"
    assert_equal 0x201A2, "𠆢".ord, "a real Ext-B codepoint, not a surrogate pair"
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  def test_fetch_downloads_the_single_file_and_pins_it
    stub_request(:get, URL).to_return(
      status: 200, body: File.binread(File.join(FIXTURES, "IDS.TXT")),
      headers: { "Last-Modified" => "Fri, 27 Jun 2025 00:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.file?(File.join(workdir, "IDS.TXT"))
      assert File.file?(File.join(workdir, Nabu::FileFetch::STATE_FILE)),
             "the Last-Modified pin sits at the workdir root (single file)"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_the_file_with_root_state
    assert_equal :http_zip, Nabu::Adapters::BabelstoneIds.remote_probe_strategy
    target = Nabu::Adapters::BabelstoneIds.http_probe_targets.first
    assert_equal URL, target.zip_url
    assert_equal "", target.state_subdir
    assert_nil target.metadata_url
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "babelstone-ids", name: "BabelStone IDS", adapter_class: "Nabu::Adapters::BabelstoneIds",
      license: "PD dedication", license_class: "open",
      upstream_url: URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 12, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 12, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    qi = db[:dictionary_entries].where(entry_id: "U+68C4").first
    assert_equal "urn:nabu:dict:babelstone-ids:U+68C4", qi[:urn]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["babelstone-ids"]
    refute_nil entry, "config/sources.yml must register babelstone-ids"
    assert_equal Nabu::Adapters::BabelstoneIds, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (house rule)"
    assert_equal "manual", entry.sync_policy
  end
end
