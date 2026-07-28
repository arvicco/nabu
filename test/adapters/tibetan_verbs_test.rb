# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Tibetan Verbs Database adapter (P48-4): 2,491 rows of verb tense
# stems (present/past/future/imperative, Tibetan script) with per-row
# lexicographic source attributions — the tense stems as entry apparatus.
# Dictionary-shaped, so it cannot include the passage-shaped
# AdapterConformance suite; like WiktionaryCuTest it mirrors those checks
# for the dictionary shape (manifest validity, discover→parse round-trip,
# id uniqueness/stability, NFC, license class) and adds the
# DictionaryLoader contract and the define integration on the classic
# "read" paradigm ཀློག.
class TibetanVerbsTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("tibetan-verbs")

  def adapter = Nabu::Adapters::TibetanVerbs.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_tibetan_verbs_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "tibetan-verbs", manifest.id
    assert_match(/CC0-1\.0/, manifest.license, "the in-repo LICENSE grant, verified 2026-07-28")
    assert_equal "open", manifest.license_class
    assert_equal "https://github.com/tibetan-nlp/tibetan-verbs-database", manifest.upstream_url
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::TibetanVerbs.content_kind
  end

  def test_remote_probe_strategy_is_git
    assert_equal :git, Nabu::Adapters::TibetanVerbs.remote_probe_strategy
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_csv
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["tibetan-verbs:db.csv"], refs.map(&:id)
    assert_equal "tibetan-verbs", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_bod_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "tibetan-verbs", document.slug
    assert_equal "bod", document.language, "stored 639-3, the san/chu convention"
    assert_equal 28, document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    adapter.parse(adapter.discover(FIXTURES).first).each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- the golden entry: ཀློག, the classic "read" paradigm ------------------------

  def test_klog_entry_carries_the_full_paradigm_and_sources
    entry = parsed_entries.find { |e| e.headword == "ཀློག" } || flunk("ཀློག missing")
    assert_equal "ཀློག:བཀླགས:བཀླག:ཀློགས", entry.entry_id, "the 4-stem tuple IS the stable id"
    assert_nil entry.gloss, "no glosses upstream — nil is honest, never invented"
    assert_equal "bod", entry.language
    assert_equal <<~BODY.strip, entry.body
      Present: ཀློག
      Past: བཀླགས
      Future: བཀླག
      Imperative: ཀློགས
      Sources: TDC · PH · GT · KN
    BODY
    assert_empty entry.citations
  end

  # --- the pinned upstream quirks (fixture README census) -------------------------

  def test_same_present_stem_under_different_paradigms_stays_separate_rows
    entries = parsed_entries.select { |e| e.headword == "ཀེར" }
    assert_equal 3, entries.size, "upstream keeps the grammarians' disagreements uncollapsed"
    assert_equal entries.map(&:entry_id).uniq, entries.map(&:entry_id)
    with_da_drag = entries.find { |e| e.entry_id.include?("ཀེར༼ད༽") } || flunk("༼ད༽ row missing")
    assert_includes with_da_drag.body, "Past: ཀེར༼ད༽",
                    "the second-suffix ད rides upstream's own Tibetan-parenthesis notation verbatim"
  end

  def test_empty_stems_omit_their_lanes_and_ride_ids_as_dashes
    entry = parsed_entries.find { |e| e.headword == "དཀའ" } || flunk("དཀའ missing")
    assert_equal "དཀའ:དཀའ:དཀའ:-", entry.entry_id
    refute_includes entry.body, "Imperative:", "an empty stem omits its lane, never faked"

    present_only = parsed_entries.find { |e| e.headword == "ཁ" } || flunk("ཁ missing")
    assert_equal "ཁ:-:-:-", present_only.entry_id
    assert_equal "Present: ཁ\nSources: TDC", present_only.body
  end

  def test_duplicate_paradigm_tuples_get_positional_suffixes
    pair = parsed_entries.select { |e| e.headword == "བྱེད" && e.body.include?("Imperative: བྱོས") }
    assert_equal %w[བྱེད:བྱས:བྱ:བྱོས བྱེད:བྱས:བྱ:བྱོས:2], pair.map(&:entry_id)
    assert_includes pair[0].body, "Sources: KN"
    assert_includes pair[1].body, "Sources: TDC · PH"
  end

  def test_a_renamed_upstream_column_fails_loudly
    Dir.mktmpdir do |workdir|
      File.write(File.join(workdir, "db.csv"), "a,b,c,d,TDC,PH,GT,KN\nx,y,z,w,TDC,,,\n")
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(workdir).first) }
    end
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "tibetan-verbs", name: "Tibetan Verbs Database",
      adapter_class: "Nabu::Adapters::TibetanVerbs",
      license: "CC0-1.0", license_class: "open",
      upstream_url: "https://github.com/tibetan-nlp/tibetan-verbs-database", enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 28, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 28, second.skipped
    assert_equal 28, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    row = db[:dictionary_entries].where(entry_id: "ཀློག:བཀླགས:བཀླག:ཀློགས").first
    assert_equal "urn:nabu:dict:tibetan-verbs:ཀློག:བཀླགས:བཀླག:ཀློགས", row[:urn]
  end

  # --- the define integration -----------------------------------------------------

  def test_define_finds_the_read_paradigm_in_any_tibetan_spelling
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db, lila: nil)
    %w[bod bo tib].each do |lang|
      results = define.run("ཀློག", lang: lang)
      assert_equal 1, results.size, "--lang #{lang} must reach the bod shelf (code variants)"
      assert_includes results.first.body, "Past: བཀླགས"
    end
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["tibetan-verbs"]
    refute_nil entry, "config/sources.yml must register tibetan-verbs"
    assert_equal Nabu::Adapters::TibetanVerbs, entry.adapter_class
    refute entry.wired, "unwired until the owner-fired first sync + eyeball (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[tibetan], entry.axes
    assert_equal Nabu::Adapters::TibetanVerbs.manifest, entry.manifest
  end

  private

  def parsed_entries
    adapter.parse(adapter.discover(FIXTURES).first).entries
  end
end
