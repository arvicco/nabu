# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The Monier-Williams adapter (P17-4): the fourth dictionary-shelf occupant.
# Dictionary-shaped, so it cannot include the passage-shaped
# AdapterConformance suite; like LexicaTest/BosworthTollerTest it mirrors
# those checks for the dictionary shape (manifest validity, discover→parse
# round-trip, id uniqueness/stability, NFC, license class) and adds the
# FileFetch path (WebMock stubs of the CDSL zip URL), the zip-member parse,
# the DictionaryLoader contract (idempotency, urns, citation + reflex rows)
# and the per-siglum citation coverage report.
class MwTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("mw")

  CDSL_URL = "https://www.sanskrit-lexicon.uni-koeln.de/scans/MWScan/2020/downloads/mwxml.zip"

  def adapter = Nabu::Adapters::Mw.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_mw_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "mw", manifest.id
    assert_match(/CC BY-NC-SA 3\.0/, manifest.license)
    assert_match(/The Sanskrit Library and Thomas Malten/, manifest.license, "the credit line travels verbatim")
    assert_equal "nc", manifest.license_class, "the GRETIL class — MCP-surface default-excluded"
    assert_equal CDSL_URL, manifest.upstream_url
    assert_equal "mw-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Mw.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_plain_xml
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["mw:mw.xml"], refs.map(&:id)
    assert_equal "mw", refs.first.source_id
    assert_nil refs.first.metadata["member"], "a plain mw.xml streams straight off disk"
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_san_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "mw", document.slug
    assert_equal "san", document.language
    assert_equal 11, document.size
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

  # --- the zip shape (the real post-fetch canonical) ------------------------------

  def with_fixture_zip
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "staging", "xml"))
      FileUtils.cp(File.join(FIXTURES, "mw.xml"), File.join(workdir, "staging", "xml", "mw.xml"))
      Nabu::Shell.run("zip", "-q", File.join(workdir, "mwxml.zip"), "xml/mw.xml",
                      chdir: File.join(workdir, "staging"))
      FileUtils.rm_rf(File.join(workdir, "staging"))
      yield workdir
    end
  end

  def test_discover_falls_back_to_the_zip_under_the_same_stable_id
    with_fixture_zip do |workdir|
      refs = adapter.discover(workdir).to_a
      assert_equal ["mw:mw.xml"], refs.map(&:id), "same ref id for both shapes — urn stability"
      assert_equal "xml/mw.xml", refs.first.metadata["member"]
    end
  end

  def test_parse_streams_the_zip_member_identically_to_the_plain_file
    plain = adapter.parse(adapter.discover(FIXTURES).first)
    with_fixture_zip do |workdir|
      zipped = adapter.parse(adapter.discover(workdir).first)
      assert_equal plain.map(&:entry_id), zipped.map(&:entry_id)
      assert_equal plain.map(&:body), zipped.map(&:body)
    end
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def zip_bytes
    bytes = nil
    with_fixture_zip { |workdir| bytes = File.binread(File.join(workdir, "mwxml.zip")) }
    bytes
  end

  def test_fetch_downloads_the_zip_and_returns_report
    stub_request(:get, CDSL_URL).to_return(
      status: 200, body: zip_bytes,
      headers: { "Last-Modified" => "Sun, 05 Jul 2026 10:53:32 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      refs = adapter.discover(workdir).to_a
      assert_equal ["mw:mw.xml"], refs.map(&:id), "the fetched zip is discoverable in place"
      assert_equal 11, adapter.parse(refs.first).size

      stub_request(:get, CDSL_URL)
        .with(headers: { "If-Modified-Since" => "Sun, 05 Jul 2026 10:53:32 GMT" })
        .to_return(status: 304)
      assert_equal report.sha, adapter.fetch(workdir).sha, "a 304 keeps the pinned sha"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, CDSL_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_the_zip_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Mw.remote_probe_strategy
    targets = Nabu::Adapters::Mw.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal CDSL_URL, target.zip_url
    assert_nil target.metadata_url, "no probe-shaped license endpoint — the grant lives INSIDE the zip " \
                                    "(mwheader.xml) and re-lands in canonical at every real refetch"
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "mw", name: "Monier-Williams",
      adapter_class: "Nabu::Adapters::Mw",
      license: "CC BY-NC-SA 3.0", license_class: "nc",
      upstream_url: CDSL_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 11, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 11, second.skipped
    assert_equal 11, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    amsha = db[:dictionary_entries].where(entry_id: "10").first
    assert_equal "urn:nabu:dict:mw:10", amsha[:urn], "the Cologne L-id IS the entry id"
    assert_equal "aṃśa", amsha[:headword]
    assert_equal "amsa", amsha[:headword_folded]
  end

  def test_citation_and_reflex_rows_land_and_replace_wholesale
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 32, db[:dictionary_citations].count
    assert_equal 5, db[:dictionary_reflexes].count, "the aṃsa cognate note: Goth. + 2 Gk. + 2 Lat."

    gothic = db[:dictionary_reflexes].where(lang_code: "Goth.").first
    assert_equal "got", gothic[:language]
    assert_equal "amsa", gothic[:word]
    entry = db[:dictionary_entries].where(id: gothic[:dictionary_entry_id]).first
    assert_equal "urn:nabu:dict:mw:88", entry[:urn], "MW provenance — the owning entry is the mw shelf's"

    loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 32, db[:dictionary_citations].count, "idempotent reload keeps counts"
    assert_equal 5, db[:dictionary_reflexes].count
  end

  # --- per-siglum citation coverage (survey §3 as verifiable output) ---------------

  def seed_rgveda(passages: [])
    texts = Nabu::Store::Source.create(
      slug: "gretil", name: "GRETIL", adapter_class: "Nabu::Adapters::Gretil", license_class: "nc"
    )
    doc = Nabu::Store::Document.create(
      source_id: texts.id, urn: "urn:nabu:gretil:sa_Rgveda-edAufrecht", title: "Ṛgveda",
      language: "san-Latn", content_sha256: "x", revision: 1, withdrawn: false
    )
    passages.each_with_index do |citation, index|
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:#{citation}", sequence: index,
        language: "san-Latn", text: "agním īḷe", text_normalized: "agnim ile",
        content_sha256: "x", revision: 1
      )
    end
    doc
  end

  def test_coverage_reports_tier_totals_and_live_resolution_per_siglum
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    seed_rgveda(passages: %w[5.086.05a 5.086.05c 10.109.01a])

    lines = Nabu::Adapters::Mw.citation_coverage(catalog: db)
    assert_equal "mw citations: 32 — 3 passage-grain · 9 document-grain · 7 authority · 13 not-held",
                 lines.first
    rv = lines.find { |line| line.strip.start_with?("RV.") }
    assert_match(%r{2/3 live at passage grain — urn:nabu:gretil:sa_Rgveda-edAufrecht}, rv,
                 "RV. v,86,5 and x,109,1 resolve via pada probing; v,39,2 is an honest miss")
    mn = lines.find { |line| line.strip.start_with?("Mn.") }
    assert_match(/held — document not in catalog/, mn, "Manusmṛti not synced here — never faked")
    assert_match(/authority labels: .*L\. 2/, lines.join("\n"))
    assert_match(/not held: MBh\. 4/, lines.join("\n"))
  end

  def test_coverage_is_empty_on_a_catalog_without_the_shelf
    assert_empty Nabu::Adapters::Mw.citation_coverage(catalog: store_test_db)
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_enabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["mw"]
    refute_nil entry, "config/sources.yml must register mw"
    assert_equal Nabu::Adapters::Mw, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-13 after first sync + eyeball)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Mw.manifest, entry.manifest
  end
end
