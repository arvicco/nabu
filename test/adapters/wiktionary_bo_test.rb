# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Wiktionary-Tibetan adapter (P48-4): English Wiktionary's Tibetan
# entries via the kaikki.org wiktextract extraction — the wiktionary-cu
# shape exactly (per-language JSONL, FileFetch, wiktionary-jsonl parser,
# reflexes on). Dictionary-shaped, so it cannot include the passage-shaped
# AdapterConformance suite; like WiktionaryCuTest it mirrors those checks
# for the dictionary shape and adds the FileFetch path (WebMock), the
# DictionaryLoader contract and the define integration on
# བྱང་ཆུབ་སེམས་དཔའ (bodhisattva).
class WiktionaryBoTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-bo")

  KAIKKI_URL = "https://kaikki.org/dictionary/Tibetan/kaikki.org-dictionary-Tibetan.jsonl"

  def adapter = Nabu::Adapters::WiktionaryBo.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_wiktionary_bo_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wiktionary-bo", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license) # the kaikki statement, verbatim
    assert_equal "attribution", manifest.license_class
    assert_equal KAIKKI_URL, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::WiktionaryBo.content_kind
  end

  def test_reflex_bearing_promise
    assert Nabu::Adapters::WiktionaryBo.reflex_bearing?,
           "descendants crosswalk as reflexes (134 bearing records / 307 edges censused live)"
  end

  # P48-4: kaikki spells Tibetan with the 639-1 code; the parser map must
  # land bo-coded reflex nodes (e.g. the zh extract's Tibetan descendants)
  # on the catalog tag the bod shelves store.
  def test_parser_lang_code_map_carries_bo_to_bod
    assert_equal "bod", Nabu::Adapters::WiktionaryJsonlParser::LANG_CODE_MAP["bo"]
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_jsonl
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-bo:kaikki.org-dictionary-Tibetan.jsonl"], refs.map(&:id)
    assert_equal "wiktionary-bo", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_bod_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wiktionary-bo", document.slug
    assert_equal "bod", document.language, "stored 639-3, the san/chu convention"
    assert_equal 172, document.size
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

  # --- the golden entries ---------------------------------------------------------

  def test_bodhisattva_entry_keeps_gloss_and_compound_etymology
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    entry = entries.find { |e| e.entry_id == "བྱང་ཆུབ་སེམས་དཔའ:noun" } || flunk("bodhisattva missing")
    assert_match(/\Abodhisattva \(derived from Sanskrit\)/, entry.gloss)
    assert_includes entry.body, "byang chub", "the compound etymology (Wylie chain) is KEPT in the body"
  end

  def test_homograph_pos_split_yields_distinct_entries
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    chos = entries.select { |e| e.key_raw == "ཆོས" }.map(&:entry_id)
    assert_includes chos, "ཆོས:noun"
    assert_includes chos, "ཆོས:verb"
  end

  # --- reflexes: the descendants crosswalk ----------------------------------------

  def test_parse_extracts_descendants_as_reflexes
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    bearing = entries.count { |entry| !entry.reflexes.empty? }
    minted = entries.sum { |entry| entry.reflexes.size }
    assert_equal 18, bearing
    assert_equal 88, minted
  end

  # བོད "Tibet" descends into held languages: grc Βαῖται → la Baetae, and
  # Prakrit *bhŏṭṭa → sa भोट (borrowed) — the crosswalk edges the etym desk
  # rides. dz (Dzongkha) passes through shape-valid; sa/la map to san/lat.
  def test_bod_reflexes_map_into_catalog_language_tags
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    bod = entries.find { |e| e.entry_id == "བོད:name" } || flunk("བོད:name missing")

    sa = bod.reflexes.select { |r| r.lang_code == "sa" }
    assert_equal %w[san], sa.map(&:language).uniq, "the sa nodes join the Sanskrit shelves"
    bhota = sa.find { |r| r.word == "भोट" } || flunk("भोट reflex missing")
    assert_equal "bhoṭa", bhota.roman
    assert bhota.borrowed, "upstream flags the Indic forms as borrowings from Tibetan"

    la = bod.reflexes.find { |r| r.lang_code == "la" } || flunk("la reflex missing")
    assert_equal "lat", la.language
    assert_equal "Baetae", la.word

    dz = bod.reflexes.find { |r| r.lang_code == "dz" } || flunk("dz reflex missing")
    assert_equal "dz", dz.language, "a shape-valid unmapped code passes through as itself"
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_the_jsonl_and_returns_report
    stub_request(:get, KAIKKI_URL).to_return(
      status: 200,
      body: File.binread(File.join(FIXTURES, "kaikki.org-dictionary-Tibetan.jsonl")),
      headers: { "Last-Modified" => "Sat, 25 Jul 2026 05:52:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 1, adapter.discover(workdir).count, "the fetched jsonl is discoverable in place"

      stub_request(:get, KAIKKI_URL)
        .with(headers: { "If-Modified-Since" => "Sat, 25 Jul 2026 05:52:00 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    # the upstream file is flagged DEPRECATED — a future 404 must fail clean
    stub_request(:get, KAIKKI_URL).to_return(status: 404)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_the_jsonl_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::WiktionaryBo.remote_probe_strategy
    targets = Nabu::Adapters::WiktionaryBo.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal KAIKKI_URL, target.zip_url
    assert_nil target.metadata_url, "kaikki serves no probe-shaped license endpoint; the " \
                                    "license is re-read from the dictionary index page at any refetch"
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn / reflexes) --------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wiktionary-bo", name: "Wiktionary Tibetan (kaikki.org)",
      adapter_class: "Nabu::Adapters::WiktionaryBo",
      license: "CC-BY-SA + GFDL", license_class: "attribution",
      upstream_url: KAIKKI_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 172, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 172, second.skipped
    assert_equal 172, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal 88, db[:dictionary_reflexes].count, "an unchanged re-parse re-mints nothing"

    buddha = db[:dictionary_entries].where(entry_id: "སངས་རྒྱས:noun").first
    assert_equal "urn:nabu:dict:wiktionary-bo:སངས་རྒྱས:noun", buddha[:urn]
    assert_equal "Buddha", buddha[:gloss]
  end

  # --- the define integration -----------------------------------------------------

  def test_define_finds_bodhisattva_in_any_tibetan_spelling
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db, lila: nil)
    %w[bod bo tib].each do |lang|
      results = define.run("བྱང་ཆུབ་སེམས་དཔའ", lang: lang)
      assert_equal 1, results.size, "--lang #{lang} must reach the bod shelf (code variants)"
      assert_match(/\Abodhisattva/, results.first.gloss)
    end
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wiktionary-bo"]
    refute_nil entry, "config/sources.yml must register wiktionary-bo"
    assert_equal Nabu::Adapters::WiktionaryBo, entry.adapter_class
    refute entry.wired, "unwired until the owner-fired first sync + eyeball (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[tibetan], entry.axes
    assert_equal Nabu::Adapters::WiktionaryBo.manifest, entry.manifest
  end
end
