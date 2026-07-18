# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The CCL adapter (P28-3): the Coptic dictionary shelf + the ORAEC egy↔cop
# crosswalk riding as adapter config. Dictionary-shaped, so it cannot
# include the passage-shaped AdapterConformance suite; like LexicaTest/
# BosworthTollerTest/MwTest it mirrors those checks for the dictionary
# shape (manifest validity, discover→parse round-trip, id uniqueness/
# stability, NFC, license class) and adds the two-artifact FileFetch path
# (WebMock stubs) plus the DictionaryLoader contract: idempotency,
# revision-on-crosswalk-change, urn shape, define round-trip, and the
# Scriptorium gold-lemma fold join.
class CclTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ccl")

  LEXICON_URL = "https://refubium.fu-berlin.de/bitstream/handle/fub188/27813/" \
                "Comprehensive_Coptic_Lexicon-v1.2-2020.xml?sequence=1&isAllowed=y"
  CROSSWALK_URL = "https://raw.githubusercontent.com/oraec/coptic_etymologies/main/" \
                  "digitizing_coptic_etymologies_coptic_list_entries.csv"

  def adapter = Nabu::Adapters::Ccl.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_ccl_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "ccl", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/CC ?0/, manifest.license, "the crosswalk's CC0 grant is documented beside BY-SA")
    assert_equal "attribution", manifest.license_class
    assert_equal LEXICON_URL, manifest.upstream_url
    assert_equal "ccl-tei", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Ccl.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_tei
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["ccl:Comprehensive_Coptic_Lexicon-v1.2-2020.xml"], refs.map(&:id)
    assert_equal "ccl", refs.first.source_id
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_cop_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "ccl", document.slug
    assert_equal "cop", document.language
    assert_equal 17, document.size
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

  # --- the crosswalk rides the parse (packaging verdict) -------------------------

  def test_parse_joins_the_crosswalk_into_ancestor_citations
    by_id = adapter.parse(adapter.discover(FIXTURES).first).to_h { |e| [e.entry_id, e] }
    assert_equal %w[urn:nabu:dict:aed:159410 urn:nabu:dict:tla-demotic:6439],
                 by_id.fetch("C1494").citations.map(&:urn_raw),
                 "C1494,159410,6439 — ⲕⲁϩ ← qꜣḥ ← qh, the survey's verified row"
    assert_equal ["urn:nabu:dict:aed:854495"], by_id.fetch("C5").citations.map(&:urn_raw)
    assert by_id.fetch("C1").citations.empty?, "no crosswalk row, no citations"
  end

  def test_parse_without_the_crosswalk_file_yields_citation_less_entries
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "lexicon"))
      FileUtils.cp(File.join(FIXTURES, "lexicon", Nabu::Adapters::Ccl::LEXICON_FILENAME),
                   File.join(workdir, "lexicon"))
      document = adapter.parse(adapter.discover(workdir).first)
      assert_equal 17, document.size
      assert document.all? { |entry| entry.citations.empty? },
             "the day-one pre-crosswalk state parses honestly bare"
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_downloads_both_artifacts_and_returns_report
    stub_request(:get, LEXICON_URL).to_return(
      status: 200,
      body: File.binread(File.join(FIXTURES, "lexicon", Nabu::Adapters::Ccl::LEXICON_FILENAME)),
      headers: { "Last-Modified" => "Thu, 16 Jul 2020 12:00:00 GMT" }
    )
    stub_request(:get, CROSSWALK_URL).to_return(
      status: 200,
      body: File.binread(File.join(FIXTURES, "crosswalk", Nabu::Adapters::Ccl::CROSSWALK_FILENAME)),
      headers: { "Last-Modified" => "Wed, 14 Aug 2024 06:42:43 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/lexicon \h{8} · crosswalk \h{8}/, report.notes)
      assert_equal 1, adapter.discover(workdir).count, "the fetched TEI is discoverable in place"
      document = adapter.parse(adapter.discover(workdir).first)
      refute_empty document.find { |e| e.entry_id == "C1494" }.citations,
                   "the fetched crosswalk joins the fetched TEI"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, LEXICON_URL).to_return(status: 500)
    stub_request(:get, CROSSWALK_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_both_artifacts_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Ccl.remote_probe_strategy
    targets = Nabu::Adapters::Ccl.http_probe_targets
    assert_equal [LEXICON_URL, CROSSWALK_URL], targets.map(&:zip_url)
    assert_equal %w[lexicon crosswalk], targets.map(&:state_subdir)
    assert targets.all? { |target| target.metadata_url.nil? },
           "neither host serves a probe-shaped license endpoint; drift is caught at refetch"
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "ccl", name: "CCL", adapter_class: "Nabu::Adapters::Ccl",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: LEXICON_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 17, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 17, second.skipped
    assert_equal 17, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    kah = db[:dictionary_entries].where(entry_id: "C1494").first
    assert_equal "urn:nabu:dict:ccl:C1494", kah[:urn]
    assert_equal "ⲕⲁϩ", kah[:headword]
    assert_equal "ⲕⲁϩ", kah[:headword_folded]
    assert_equal 2, db[:dictionary_citations].where(dictionary_entry_id: kah[:id]).count,
                 "both ancestor citations persisted"
  end

  def test_a_crosswalk_change_revises_the_entry
    db, loader = loader_setup
    Dir.mktmpdir do |workdir|
      FileUtils.cp_r(File.join(FIXTURES, "lexicon"), workdir)
      FileUtils.cp_r(File.join(FIXTURES, "crosswalk"), workdir)
      loader.load_from(adapter, workdir: workdir)

      crosswalk = File.join(workdir, "crosswalk", Nabu::Adapters::Ccl::CROSSWALK_FILENAME)
      File.write(crosswalk, File.read(crosswalk).sub("C1494,159410,6439", "C1494,159410,"))
      report = loader.load_from(adapter, workdir: workdir)

      assert_equal 1, report.updated, "the crosswalk is entry content — its change is a revision"
      kah = db[:dictionary_entries].where(entry_id: "C1494").first
      assert_equal 2, kah[:revision]
      assert_equal ["urn:nabu:dict:aed:159410"],
                   db[:dictionary_citations].where(dictionary_entry_id: kah[:id]).select_map(:urn_raw)
    end
  end

  # --- define round-trip + the Scriptorium gold-lemma fold join ------------------

  def test_define_finds_the_kah_homographs_by_folded_lookup
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)

    results = Nabu::Query::Define.new(catalog: db, fulltext: nil).run("ⲕⲁϩ")
    assert_equal %w[urn:nabu:dict:ccl:C1494 urn:nabu:dict:ccl:C1495], results.map(&:urn),
                 "homographs are separate entries, entry-id ordered"
    kah = results.first
    assert_equal "urn:nabu:dict:ccl:C1494", kah.urn
    assert_equal "earth, soil", kah.gloss
    assert_includes kah.body, "Erde, Boden"
    assert_includes kah.body, "terre"
    assert_equal %w[urn:nabu:dict:aed:159410 urn:nabu:dict:tla-demotic:6439],
                 kah.citations.map(&:urn_raw)
    assert kah.citations.all? { |c| c.resolved_urn.nil? },
           "ancestor citations resolve through the links journal, not the CTS path"
  end

  # The join census pin (P28-3): the Coptic Scriptorium shelf's gold
  # lemmas and CCL headwords meet in the SAME conventions-§9 cop fold —
  # a real gold token lemma from the Scriptorium fixtures lands on the
  # loaded CCL entry with no new machinery (fixture census 2026-07-18:
  # 319/418 distinct gold lemmas join; misses are punctuation lemmas,
  # names and Greek loanwords).
  def test_a_scriptorium_gold_lemma_reaches_the_ccl_entry_through_the_shared_fold
    tt = File.join(Nabu::TestSupport.fixtures("coptic-scriptorium"),
                   "theodosius-alexandria", "theodosius.alexandria_TT",
                   "Encomium_Michael_BL_OR_6781_part1.tt")
    skip "coptic-scriptorium fixture not present" unless File.file?(tt)

    gold = File.read(tt)[/lemma="(ⲕⲁϩ)"/, 1]
    refute_nil gold, "the Encomium fixture attests the bare gold lemma ⲕⲁϩ"

    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    folded = Nabu::Normalize.search_form(gold, language: "cop")
    hits = db[:dictionary_entries].where(headword_folded: folded).select_map(:entry_id)
    assert_equal %w[C1494 C1495], hits.sort
  end

  # --- registry -------------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ccl"]
    refute_nil entry, "config/sources.yml must register ccl"
    assert_equal Nabu::Adapters::Ccl, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Ccl.manifest, entry.manifest
  end
end
