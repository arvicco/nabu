# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The DILA Pentaglot adapter: the Wuyi hebi jiyao 五譯合璧集要 (Raghu
# Vira's 1961 "Pentaglot Dictionary of Buddhist Terms" reprint) in the
# DILA (Dharma Drum) TEI P5 digital edition — 1,071 Buddhist terms in
# Sanskrit / Manchu / Mongolian / Chinese (the Tibetan column was never
# digitized upstream). The mvp sibling: same delivery (one frozen,
# sha-pinned zip from glossaries.dila.edu.tw), same dictionary-shaped
# conformance mirror (manifest, discover→parse round-trip, id
# uniqueness/stability, NFC, license class), plus the four-shelf split —
# a five-way mirror dictionary is headed by every one of its columns, so
# each digitized language gets its own shelf (ptg-san / ptg-mnc /
# ptg-cmg / ptg-lzh) and `define` folds each with its own language.
class PtgTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ptg")

  ZIP_URL = "https://glossaries.dila.edu.tw/data/pentaglot.dila.tei.p5.xml.zip"
  XML = "pentaglot.dila.tei.p5.xml"
  SHELVES = %w[ptg-san ptg-mnc ptg-cmg ptg-lzh].freeze

  def adapter(zip_sha256: nil)
    zip_sha256 ? Nabu::Adapters::Ptg.new(zip_sha256: zip_sha256) : Nabu::Adapters::Ptg.new
  end

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_ptg_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "ptg", manifest.id
    # Both statements of the glossary page, verbatim: the PD belief on the
    # text AND the CC BY-SA 3.0 TW license on the digital version.
    assert_match(/We believe this text is in the public domain/, manifest.license)
    assert_match(/Creative Commons Attribution-Share Alike 3\.0 Taiwan License/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal ZIP_URL, manifest.upstream_url
    assert_equal "ptg-tei", manifest.parser_family
    assert_match(/Dharma Drum/, manifest.credit)
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Ptg.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_per_language_shelf_for_the_plain_xml
    refs = adapter.discover(FIXTURES).to_a
    assert_equal SHELVES.map { |slug| "#{slug}:#{XML}" }, refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "ptg" })
    assert_equal(SHELVES, refs.map { |ref| ref.metadata["dictionary"] })
    assert(refs.all? { |ref| ref.metadata["member"].nil? }, "a plain XML streams straight off disk")
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_each_shelf_is_headed_by_its_own_language
    documents = parsed_documents
    assert_equal SHELVES, documents.keys
    assert_equal({ "ptg-san" => "san", "ptg-mnc" => "mnc", "ptg-cmg" => "cmg", "ptg-lzh" => "lzh" },
                 documents.transform_values(&:language))
    assert(documents.values.all?(Nabu::DictionaryDocument))
    documents.each_value do |document|
      assert(document.all? { |entry| entry.language == document.language })
    end
  end

  # 17 fixture <entry> elements = 16 real + the p341A.1 placeholder; a shelf
  # carries only the entries whose own column upstream filled (fixture
  # README census: Manchu empty ×2, Mongolian ×1, Chinese ×1).
  def test_shelf_sizes_follow_the_filled_columns
    assert_equal({ "ptg-san" => 16, "ptg-mnc" => 14, "ptg-cmg" => 15, "ptg-lzh" => 15 },
                 parsed_documents.transform_values(&:size))
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { parsed_documents.transform_values { |document| document.map(&:entry_id) } }
    first = snapshot.call
    first.each_value { |ids| assert_equal ids.uniq, ids }
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    parsed_documents.each_value do |document|
      document.each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        assert entry.headword_folded.unicode_normalized?(:nfc)
        assert entry.gloss.nil? || entry.gloss.unicode_normalized?(:nfc)
      end
    end
  end

  # --- the golden entry: p005.2, buddhaḥ / fucihi / burkhan / 佛 -------------------

  def test_buddha_entry_lands_on_all_four_shelves_with_the_same_body
    body = <<~BODY.strip
      Sanskrit: buddhaḥ
      Manchu: fucihi
      Mongolian: burkhan
      Chinese: 佛
    BODY
    expected = { "ptg-san" => %w[buddhaḥ 佛], "ptg-mnc" => %w[fucihi buddhaḥ],
                 "ptg-cmg" => %w[burkhan buddhaḥ], "ptg-lzh" => %w[佛 buddhaḥ] }
    expected.each do |slug, (headword, gloss)|
      entry = parsed_entry(slug, "p005.2")
      assert_equal headword, entry.headword, slug
      assert_equal gloss, entry.gloss, "#{slug}: Sanskrit glosses the other shelves; Chinese glosses san"
      assert_equal "p005.2", entry.key_raw
      assert_equal body, entry.body, slug
      assert_empty entry.citations
    end
  end

  def test_known_manchu_headword_and_its_fold
    entry = parsed_entry("ptg-mnc", "p005.3")
    assert_equal "eteme yongkiyafi colgo-roko", entry.headword, "canonical means canonical — hyphen kept"
    entry = parsed_entry("ptg-mnc", "p015.2")
    assert_equal "jergi akū budg’ali", entry.headword
    assert_equal Nabu::Normalize.search_form("jergi akū budg’ali", language: "mnc"), entry.headword_folded
    assert_includes Nabu::Normalize.query_forms("jergi aku budg’ali"), entry.headword_folded,
                    "a plain-ASCII Möllendorff typist (u for ū) reaches the entry"
  end

  # --- the pinned upstream quirks (fixture README census) -------------------------

  def test_mongolian_combining_diaeresis_is_composed_at_the_boundary
    raw = File.read(File.join(FIXTURES, XML), encoding: Encoding::UTF_8)
    refute raw.include?("ilejü tekhün nögchigsen"), "upstream writes this ö decomposed (fixture pin)"
    assert raw.include?("nögchigsen"), "the decomposed o + U+0308 sequence is in the fixture"
    entry = parsed_entry("ptg-cmg", "p005.3")
    assert_equal "ilejü tekhün nögchigsen", entry.headword
    assert entry.headword.unicode_normalized?(:nfc)
  end

  def test_manchu_editorial_parentheses_stay_in_the_headword_but_leave_the_lookup_key
    entry = parsed_entry("ptg-mnc", "p338.1")
    assert_equal "ufuku(sic？for ufuhu)", entry.headword, "canonical means canonical"
    assert_equal Nabu::Normalize.search_form("ufuku", language: "mnc"), entry.headword_folded
    long = parsed_entry("ptg-mnc", "p155.1")
    assert_equal "gūsin nadan hacin bodi jugūn i nomun dorgi (BN dorgi i)duin jondon be kiceme tebure gebu",
                 long.headword, "upstream's run of spaces squashes to one"
    assert_equal Nabu::Normalize.search_form("gūsin nadan hacin bodi jugūn i nomun dorgi duin jondon " \
                                             "be kiceme tebure gebu", language: "mnc"),
                 long.headword_folded
  end

  def test_rubric_entries_keep_their_brackets
    entry = parsed_entry("ptg-san", "p005.1")
    assert_equal "[buddha paryāya - nāmāni]", entry.headword
    assert_equal "fucihi i gebu", parsed_entry("ptg-mnc", "p005.1").headword
  end

  def test_empty_columns_drop_from_shelf_and_lane
    refute parsed_entry?("ptg-cmg", "p031.2"), "no Mongolian upstream → not on the cmg shelf"
    assert_equal "Sanskrit: susaṃvṛttaskandhaḥ\nManchu: umesi muheliyengge dabsi\nChinese: 兩臂圓滿相",
                 parsed_entry("ptg-san", "p031.2").body
    refute parsed_entry?("ptg-lzh", "p166.2")
    refute parsed_entry?("ptg-mnc", "p336.4")
    refute parsed_entry?("ptg-mnc", "p340B.1")
  end

  def test_the_lone_placeholder_entry_skips_by_rule
    assert(SHELVES.none? { |slug| parsed_entry?(slug, "p341A.1") },
           "p341A.1 carries only upstream's comment (an untraceable index ref) — no column, no entry")
  end

  def test_irregular_upstream_ids_are_kept_verbatim
    assert_equal "spraṣṭavyam", parsed_entry("ptg-san", "p192A.").headword
    assert_equal "持戒生福", parsed_entry("ptg-lzh", "p209").headword
  end

  # --- the zip shape (the real post-fetch canonical) ------------------------------

  def with_fixture_zip
    Dir.mktmpdir do |workdir|
      FileUtils.cp(File.join(FIXTURES, XML), workdir)
      Nabu::Shell.run("zip", "-q", File.join(workdir, "#{XML}.zip"), XML, chdir: workdir)
      File.delete(File.join(workdir, XML))
      yield workdir
    end
  end

  def test_discover_falls_back_to_the_zip_under_the_same_stable_ids
    with_fixture_zip do |workdir|
      refs = adapter.discover(workdir).to_a
      assert_equal SHELVES.map { |slug| "#{slug}:#{XML}" }, refs.map(&:id)
      assert(refs.all? { |ref| ref.metadata["member"] == XML })
    end
  end

  def test_parse_streams_the_zip_member_identically_to_the_plain_file
    plain = parsed_documents
    with_fixture_zip do |workdir|
      zipped = adapter.discover(workdir).to_h { |ref| [ref.metadata["dictionary"], adapter.parse(ref)] }
      SHELVES.each do |slug|
        assert_equal plain[slug].map(&:entry_id), zipped[slug].map(&:entry_id)
        assert_equal plain[slug].map(&:body), zipped[slug].map(&:body)
      end
    end
  end

  # --- fetch (WebMock only, no network; the frozen sha pin) -----------------------

  def zip_bytes
    bytes = nil
    with_fixture_zip { |workdir| bytes = File.binread(File.join(workdir, "#{XML}.zip")) }
    bytes
  end

  def test_fetch_downloads_the_zip_and_returns_report
    body = zip_bytes
    sha = Digest::SHA256.hexdigest(body)
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body, headers: { "Last-Modified" => "Mon, 20 Mar 2017 06:37:38 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter(zip_sha256: sha).fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal sha, report.sha
      assert_equal SHELVES.size, adapter.discover(workdir).count, "the fetched zip is discoverable in place"
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

  def test_probe_targets_head_the_zip_with_no_metadata_endpoint
    assert_equal :http_zip, Nabu::Adapters::Ptg.remote_probe_strategy
    targets = Nabu::Adapters::Ptg.http_probe_targets
    assert_equal [ZIP_URL], targets.map(&:zip_url)
    assert_nil targets.first.metadata_url
  end

  # --- DictionaryLoader contract (idempotency / revision / urn) -------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "ptg", name: "Pentaglot (DILA)", adapter_class: "Nabu::Adapters::Ptg",
      license: "CC BY-SA 3.0 TW", license_class: "attribution", upstream_url: ZIP_URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_with_stable_urns
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 60, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 60, second.skipped
    assert_equal 60, db[:dictionary_entries].count
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal SHELVES.sort, db[:dictionaries].select_map(:slug).sort

    row = db[:dictionary_entries].where(urn: "urn:nabu:dict:ptg-cmg:p005.2").first
    assert_equal "burkhan", row[:headword]
  end

  # --- the define integration: each column is a lookup direction ------------------

  def test_define_reaches_the_pentaglot_from_manchu_mongolian_and_chinese
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    define = Nabu::Query::Define.new(catalog: db, lila: nil)
    assert_equal ["urn:nabu:dict:ptg-mnc:p005.2"], define.run("fucihi", lang: "mnc").map(&:urn)
    assert_equal ["urn:nabu:dict:ptg-cmg:p005.3"], define.run("ilejü tekhün nögchigsen", lang: "cmg").map(&:urn)
    assert_equal ["urn:nabu:dict:ptg-lzh:p005.2"], define.run("佛", lang: "lzh").map(&:urn)
    result = define.run("buddhaḥ", lang: "san").first
    assert_equal "attribution", result.license_class
    assert_includes result.body, "Manchu: fucihi"
  end

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ptg"]
    refute_nil entry, "config/sources.yml must register ptg"
    assert_equal Nabu::Adapters::Ptg, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[mongolic buddhist], entry.axes
    assert_equal Nabu::Adapters::Ptg.manifest, entry.manifest
  end

  private

  def parsed_documents
    adapter.discover(FIXTURES).to_h { |ref| [ref.metadata["dictionary"], adapter.parse(ref)] }
  end

  def parsed_entry?(slug, id)
    parsed_documents.fetch(slug).any? { |e| e.entry_id == id }
  end

  def parsed_entry(slug, id)
    parsed_documents.fetch(slug).find { |e| e.entry_id == id } || flunk("#{slug} #{id} missing from the fixture parse")
  end
end
