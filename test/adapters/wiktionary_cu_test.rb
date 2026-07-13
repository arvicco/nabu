# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The Wiktionary-OCS adapter (P13-10): the fourth dictionary-shelf occupant
# and the first JSONL dictionary source (kaikki.org wiktextract). Dictionary-
# shaped, so it cannot include the passage-shaped AdapterConformance suite;
# like BosworthTollerTest it mirrors those checks for the dictionary shape
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the FileFetch path (WebMock stubs of the
# kaikki URL) plus the DictionaryLoader contract and the define-glosses
# integration a TOROT gold lemma rides on.
class WiktionaryCuTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-cu")

  KAIKKI_URL = "https://kaikki.org/dictionary/Old%20Church%20Slavonic/" \
               "kaikki.org-dictionary-OldChurchSlavonic.jsonl"

  def adapter = Nabu::Adapters::WiktionaryCu.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_wiktionary_cu_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wiktionary-cu", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license) # the kaikki statement, verbatim
    assert_equal "attribution", manifest.license_class
    assert_equal KAIKKI_URL, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::WiktionaryCu.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_jsonl
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-cu:kaikki.org-dictionary-OldChurchSlavonic.jsonl"], refs.map(&:id)
    assert_equal "wiktionary-cu", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_chu_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wiktionary-cu", document.slug
    assert_equal "chu", document.language
    assert_equal 278, document.size
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

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_the_jsonl_and_returns_report
    stub_request(:get, KAIKKI_URL).to_return(
      status: 200,
      body: File.binread(File.join(FIXTURES, "kaikki.org-dictionary-OldChurchSlavonic.jsonl")),
      headers: { "Last-Modified" => "Thu, 09 Jul 2026 00:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 1, adapter.discover(workdir).count, "the fetched jsonl is discoverable in place"

      stub_request(:get, KAIKKI_URL)
        .with(headers: { "If-Modified-Since" => "Thu, 09 Jul 2026 00:00:00 GMT" })
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
    assert_equal :http_zip, Nabu::Adapters::WiktionaryCu.remote_probe_strategy
    targets = Nabu::Adapters::WiktionaryCu.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal KAIKKI_URL, target.zip_url
    assert_nil target.metadata_url, "kaikki serves no probe-shaped license endpoint; the " \
                                    "license is re-read from the dictionary index page at any refetch"
    assert_equal "", target.state_subdir
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wiktionary-cu", name: "Wiktionary OCS (kaikki.org)",
      adapter_class: "Nabu::Adapters::WiktionaryCu",
      license: "CC-BY-SA + GFDL", license_class: "attribution",
      upstream_url: KAIKKI_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 278, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 278, second.skipped
    assert_equal 278, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    bog = db[:dictionary_entries].where(entry_id: "богъ:noun").first
    assert_equal "urn:nabu:dict:wiktionary-cu:богъ:noun", bog[:urn]
    assert_equal "богъ", bog[:headword]
    assert_equal "богъ", bog[:headword_folded]
    assert_includes bog[:body], "Inherited from Proto-Slavic *bogъ."
  end

  # --- P16-5 (a): the descendants backfill — OCS entries crosswalk too ------------

  # The attested-OCS records carry the same `descendants` trees the recon
  # shelves do; since P16-5 the adapter parses them (reflexes: true), so OCS
  # entries mint dictionary_reflexes edges (census over the live extract,
  # 2026-07-13: 589/4,615 entries, 2,210 edges; the trimmed fixture carries
  # 38 entries / 127 edges).
  def test_parse_extracts_descendants_as_reflexes
    document = adapter.parse(adapter.discover(FIXTURES).first)
    entries = document.map { |entry| entry }
    bearing = entries.count { |entry| !entry.reflexes.empty? }
    minted = entries.sum { |entry| entry.reflexes.size }
    assert_equal 38, bearing
    assert_equal 127, minted

    stopa = entries.find { |entry| entry.entry_id == "стопа:noun" }
    assert_equal 6, stopa.reflexes.size
    ru = stopa.reflexes.find { |reflex| reflex.lang_code == "ru" }
    assert_equal "ru", ru.language
    assert_equal "стопа́", ru.word
    assert_equal "stopá", ru.roman
    assert_equal "стопа", ru.word_folded, "the combining acute folds away"
    assert_equal "stopa", ru.roman_folded
  end

  def test_loader_mints_reflex_rows_and_reindexing_is_idempotent
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 127, db[:dictionary_reflexes].count

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 278, second.skipped
    assert_equal 127, db[:dictionary_reflexes].count, "an unchanged re-parse re-mints nothing"
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
  end

  # cu-minted rows are owned by cu entries, recon-minted rows by recon
  # entries — loading both shelves into one catalog duplicates nothing, and
  # re-loading either leaves the crosswalk byte-stable.
  def test_cu_reflexes_coexist_with_recon_minted_rows_without_duplication
    db, loader = loader_setup
    recon_source = Nabu::Store::Source.create(
      slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
      adapter_class: "Nabu::Adapters::WiktionaryRecon",
      license: "CC-BY-SA + GFDL", license_class: "attribution", enabled: false
    )
    recon_loader = Nabu::Store::DictionaryLoader.new(db: db, source: recon_source)
    recon_workdir = Nabu::TestSupport.fixtures("wiktionary-recon")

    loader.load_from(adapter, workdir: FIXTURES)
    recon_loader.load_from(Nabu::Adapters::WiktionaryRecon.new, workdir: recon_workdir)
    total = db[:dictionary_reflexes].count
    assert_operator total, :>, 127, "both shelves mint edges"

    loader.load_from(adapter, workdir: FIXTURES)
    recon_loader.load_from(Nabu::Adapters::WiktionaryRecon.new, workdir: recon_workdir)
    assert_equal total, db[:dictionary_reflexes].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
  end

  # --- the define integration a TOROT gold lemma rides on -------------------------

  def test_torot_gold_lemma_finds_its_wiktionary_gloss
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    # богъ and глаголати are gold lemmas in the TOROT Zographensis fixture
    # (test/fixtures/torot/zogr-head40.xml) — the fold contract must connect them.
    define = Nabu::Query::Define.new(catalog: db)
    results = define.run("богъ", lang: "chu")
    assert_equal 1, results.size
    assert_equal "god", results.first.gloss
    assert_equal "chu", results.first.language

    glosses = define.glosses([%w[богъ chu], %w[глаголати chu]])
    assert_equal "god", glosses[%w[богъ chu]]
    assert_equal "say, speak", glosses[%w[глаголати chu]]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wiktionary-cu"]
    refute_nil entry, "config/sources.yml must register wiktionary-cu"
    assert_equal Nabu::Adapters::WiktionaryCu, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-11 after first sync + eyeball)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::WiktionaryCu.manifest, entry.manifest
  end
end
