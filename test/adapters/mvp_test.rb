# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The Mahāvyutpatti adapter (P48-4): the 9th-century imperial
# Sanskrit–Tibetan(–Chinese) glossary in the DILA (Dharma Drum) TEI P5
# digital edition — the Tibetan shelf's crosswalk prize. Dictionary-shaped,
# so it cannot include the passage-shaped AdapterConformance suite; like
# MwTest/WiktionaryCuTest it mirrors those checks for the dictionary shape
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the sha-pinned FileFetch path (WebMock), the
# zip-member parse, the DictionaryLoader contract and the define
# integration on the bodhisattva golden entry (Mvy. 625).
class MvpTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("mvp")

  ZIP_URL = "https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.tei.p5.xml.zip"

  def adapter(zip_sha256: nil)
    zip_sha256 ? Nabu::Adapters::Mvp.new(zip_sha256: zip_sha256) : Nabu::Adapters::Mvp.new
  end

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_mvp_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "mvp", manifest.id
    # The honest-license doctrine: DILA's own phrasing is a PD-BELIEF
    # assertion on a 9th-century text, carried verbatim.
    assert_match(/We believe this text is in the public domain/, manifest.license)
    assert_equal "open", manifest.license_class
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "mvp-tei", manifest.parser_family
    assert_match(/Dharma Drum/, manifest.credit)
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Mvp.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_for_the_plain_xml
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["mvp:mahavyutpatti.dila.tei.p5.xml"], refs.map(&:id)
    assert_equal "mvp", refs.first.source_id
    assert_nil refs.first.metadata["member"], "a plain XML streams straight off disk"
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_one_san_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "mvp", document.slug
    assert_equal "san", document.language, "the glossary's own organization is Sanskrit-headed"
    assert_equal 15, document.size
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
      assert entry.headword_folded.unicode_normalized?(:nfc)
    end
  end

  # --- the golden entry: Mvy. 625, bodhisattvaḥ / byang chub sems dpa' ------------

  def test_bodhisattva_entry_lands_all_three_languages
    entry = parsed_entry("625")
    assert_equal "bodhisattvaḥ", entry.headword
    assert_equal "625", entry.key_raw
    assert_equal "san", entry.language
    assert_equal "byang chub sems dpa'", entry.gloss, "the first Wylie equivalent is the gloss"
    assert_equal <<~BODY.strip, entry.body
      Sanskrit: bodhisattvaḥ — बोधिसत्त्वः
      Tibetan: byang chub sems dpa' — བྱང་ཆུབ་སེམས་དཔའ་
      Chinese: 菩薩 (corr. 菩提薩埵) · 開士
      Section: 菩薩通稱
    BODY
    assert_empty entry.citations, "MVP quotes are unanchored — no CTS urns upstream"
    assert_empty entry.reflexes
  end

  def test_headword_folded_reaches_ascii_iast_typists
    entry = parsed_entry("625")
    assert_equal Nabu::Normalize.search_form("bodhisattvaḥ", language: "san"), entry.headword_folded
    assert_includes Nabu::Normalize.query_forms("bodhisattvah"), entry.headword_folded,
                    "an ASCII query (visarga typed as plain h, the MW convention) must reach " \
                    "the IAST headword through the fold union"
  end

  # --- the pinned upstream quirks (fixture README census) -------------------------

  def test_editorial_additions_ride_the_lanes
    entry = parsed_entry("2")
    assert_includes entry.body, "Chinese: 出有壞 · 薄伽梵 · 世尊",
                    "the <add resp=\"ddbc\"> 世尊 is part of the current text"
  end

  def test_deleted_equivalents_drop_from_the_lanes
    entry = parsed_entry("1040")
    assert_includes entry.body, "Chinese: 阿難 · 阿難陀",
                    "plain quotes stay in file order"
    refute_includes entry.body, "喜",
                    "<del resp=\"ddbc\">-marked equivalents are upstream-deleted text, never a lane"
  end

  def test_duplicate_keys_get_positional_suffixes
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    pair = entries.select { |e| e.key_raw == "1055" }
    assert_equal %w[1055 1055:2], pair.map(&:entry_id)
    assert_equal %w[mahāpanthakaḥ], [pair[0].headword]
    assert_match(/śroṇakoṭīviṃśaḥ/, pair[1].headword)
    second_pair = entries.select { |e| e.key_raw == "2347" }
    assert_equal %w[2347 2347:2], second_pair.map(&:entry_id)
  end

  def test_trailing_space_keys_strip_for_ids_but_stay_verbatim_in_key_raw
    entries = adapter.parse(adapter.discover(FIXTURES).first).entries
    entry = entries.find { |e| e.entry_id == "7752a" } || flunk("7752a missing")
    assert_equal "7752a ", entry.key_raw, "canonical means canonical — the upstream @key keeps its space"
  end

  def test_empty_tibetan_script_quote_degrades_to_wylie_only
    entry = parsed_entry("8418")
    assert_includes entry.body, "Tibetan: ltung byed 'ba' zhig tu 'gyur ba rnams pa\n"
  end

  def test_duplicated_tibetan_quotes_stay_verbatim
    entry = parsed_entry("3824")
    assert_includes entry.body, "Tibetan: zhing pa — ཞིང་རྨོད་པ་ · ཞིང་རྨོད་པ་",
                    "canonical means canonical — upstream's doubled bod-Tibt cit is not deduped"
  end

  # --- the zip shape (the real post-fetch canonical) ------------------------------

  def with_fixture_zip
    Dir.mktmpdir do |workdir|
      FileUtils.cp(File.join(FIXTURES, "mahavyutpatti.dila.tei.p5.xml"), workdir)
      Nabu::Shell.run("zip", "-q", File.join(workdir, "mahavyutpatti.dila.tei.p5.xml.zip"),
                      "mahavyutpatti.dila.tei.p5.xml", chdir: workdir)
      File.delete(File.join(workdir, "mahavyutpatti.dila.tei.p5.xml"))
      yield workdir
    end
  end

  def test_discover_falls_back_to_the_zip_under_the_same_stable_id
    with_fixture_zip do |workdir|
      refs = adapter.discover(workdir).to_a
      assert_equal ["mvp:mahavyutpatti.dila.tei.p5.xml"], refs.map(&:id)
      assert_equal "mahavyutpatti.dila.tei.p5.xml", refs.first.metadata["member"]
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

  # --- fetch (WebMock only, no network; the frozen sha pin) -----------------------

  def zip_bytes
    bytes = nil
    with_fixture_zip { |workdir| bytes = File.binread(File.join(workdir, "mahavyutpatti.dila.tei.p5.xml.zip")) }
    bytes
  end

  def test_fetch_downloads_the_zip_and_returns_report
    body = zip_bytes
    sha = Digest::SHA256.hexdigest(body)
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body,
      headers: { "Last-Modified" => "Mon, 20 Mar 2017 00:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter(zip_sha256: sha).fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal sha, report.sha
      assert_equal ["mvp:mahavyutpatti.dila.tei.p5.xml"],
                   adapter.discover(workdir).map(&:id), "the fetched zip is discoverable in place"
    end
  end

  def test_fetch_refuses_a_sha_drift_before_touching_the_tree
    stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_bytes)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/drifted/, error.message)
      assert_empty adapter.discover(workdir).to_a, "a drifted zip never lands in canonical"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 404)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_the_zip_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Mvp.remote_probe_strategy
    targets = Nabu::Adapters::Mvp.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert_equal ZIP_URL, target.zip_url
    assert_nil target.metadata_url, "the PD-belief statement lives on the glossary HTML page, " \
                                    "not a probe-shaped endpoint; re-read it at any refetch"
    assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "mvp", name: "Mahāvyutpatti (DILA)",
      adapter_class: "Nabu::Adapters::Mvp",
      license: "public domain (upstream belief statement)", license_class: "open",
      upstream_url: ZIP_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 15, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 15, second.skipped
    assert_equal 15, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    row = db[:dictionary_entries].where(entry_id: "625").first
    assert_equal "urn:nabu:dict:mvp:625", row[:urn]
    assert_equal "bodhisattvaḥ", row[:headword]
  end

  # --- the define integration: Sanskrit-side lookup surfaces the equivalents ------

  def test_define_finds_bodhisattva_with_its_tibetan_and_chinese_equivalents
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db, lila: nil)
    results = define.run("bodhisattvaḥ", lang: "san")
    assert_equal 1, results.size
    result = results.first
    assert_equal "byang chub sems dpa'", result.gloss
    assert_includes result.body, "བྱང་ཆུབ་སེམས་དཔའ་"
    assert_includes result.body, "菩薩"
    assert_equal "open", result.license_class

    # The ASCII typist's spelling reaches the same entry (fold union).
    assert_equal ["urn:nabu:dict:mvp:625"], define.run("bodhisattvah", lang: "san").map(&:urn)
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["mvp"]
    refute_nil entry, "config/sources.yml must register mvp"
    assert_equal Nabu::Adapters::Mvp, entry.adapter_class
    refute entry.wired, "unwired until the owner-fired first sync + eyeball (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[tibetan buddhist], entry.axes
    assert_equal Nabu::Adapters::Mvp.manifest, entry.manifest
  end

  private

  def parsed_entry(key)
    adapter.parse(adapter.discover(FIXTURES).first).entries.find { |e| e.entry_id == key } ||
      flunk("entry #{key} missing from the fixture parse")
  end
end
