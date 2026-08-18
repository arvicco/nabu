# frozen_string_literal: true

require "test_helper"
require "json"

# The ko-wikisource-mk adapter (P78-4 — the korean axis's vernacular
# leg): 용비어천가 from Korean Wikisource, the first hangul print (1447),
# curated-title-list scoping. Document = one work page; passages = per
# canto, the hanmun ruby verse (lzh) in page order then the Middle
# Korean verse (okm) with the modern rendering riding as annotation.
class KoWikisourceMkTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ko-wikisource-mk")
  DOC_URN = "urn:nabu:ko-wikisource-mk:yongbieocheonga"

  def adapter = Nabu::Adapters::KoWikisourceMk.new

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "ko-wikisource-mk"

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_dual_grant
    manifest = adapter.manifest
    assert_equal "ko-wikisource-mk", manifest.id
    assert_equal "attribution", manifest.license_class,
                 "PD 1447 text + CC BY-SA 4.0 transcription layer → attribution"
    assert_match(/PD/, manifest.license)
    assert_match(/Attribution-Share Alike 4\.0/, manifest.license)
    assert_equal "ko-wikisource", manifest.parser_family
    assert_match(/Wikisource/, manifest.credit)
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_curated_work_page
    refs = adapter.discover(FIXTURES).to_a
    assert_equal [DOC_URN], refs.map(&:id)
    assert refs.first.path.end_with?("pages/yongbieocheonga.json")
  end

  def test_discovery_census_counts_the_one_stray
    skips = adapter.discovery_skips(FIXTURES)
    # The fixture dir's manifest.yml is the ONE counted stray (the sillok/
    # achemenet precedent — it pins that the census actually counts);
    # pages/*.json and the README are recognized.
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  # --- parse: the grain -------------------------------------------------------

  def test_document_is_the_work_in_middle_korean
    assert_equal DOC_URN, document.urn
    assert_equal "okm", document.language, "ISO 639-3 Middle Korean — the shelf's claim"
    assert_equal "용비어천가(龍飛御天歌)", document.title
  end

  def test_passages_are_per_canto_per_layer
    mk = document.select { |p| p.language == "okm" }
    hanmun = document.select { |p| p.language == "lzh" }
    assert_equal 125, mk.size, "the MK layer is complete across all 125 cantos"
    assert_equal 34, hanmun.size,
                 "34 cantos carry hanmun CONTENT (2026-08-18 census; 32–34 have empty 한문 headings)"
    assert_equal document.size, mk.size + hanmun.size, "no third passage language"
  end

  def test_the_mk_passage_carries_the_archaic_hangul_verbatim_nfc
    passage = document.find { |p| p.urn == "#{DOC_URN}:2" }
    assert_equal "okm", passage.language
    assert passage.text.start_with?("불휘〮 기픈〮 남ᄀᆞᆫ〮"), passage.text
    assert_includes passage.text, "ᆞ", "U+119E arae-a survives NFC byte-identical"
    assert_includes passage.text, "〮", "방점 tone marks ride verbatim"
    assert passage.text.unicode_normalized?(:nfc)
    assert_equal 2, passage.annotations["canto"]
  end

  def test_the_modern_rendering_rides_as_annotation_never_as_text
    passage = document.find { |p| p.urn == "#{DOC_URN}:2" }
    assert passage.annotations["modern"].start_with?("뿌리 깊은 나무는"),
           "the CC BY-SA modern rendering is carried — as a translation annotation"
    document.each do |p|
      refute_equal "ko", p.language, "modern Korean never masquerades as passage text"
    end
  end

  def test_the_hanmun_passage_precedes_its_mk_sibling_in_page_order
    hanmun = document.find { |p| p.urn == "#{DOC_URN}:2:hanmun" }
    mk = document.find { |p| p.urn == "#{DOC_URN}:2" }
    assert_equal "lzh", hanmun.language
    assert_equal "根深之木 風亦不扤 有灼其華 有蕡其實\n源遠之水 旱亦不竭 流斯爲川 于海必達", hanmun.text
    assert_equal "근심지목 풍역불올 유작기화 유분기실\n원원지수 한역불갈 유사위천 우해필달",
                 hanmun.annotations["reading"], "the wiki's reading gloss rides the hanmun passage"
    assert hanmun.sequence < mk.sequence, "page order: 한문 then 중세국어"
  end

  def test_a_bare_canto_mints_only_its_mk_passage
    assert(document.find { |p| p.urn == "#{DOC_URN}:113" })
    assert_nil(document.find { |p| p.urn == "#{DOC_URN}:113:hanmun" })
    passage = document.find { |p| p.urn == "#{DOC_URN}:113" }
    assert_nil passage.annotations["modern"]
  end

  def test_canto_47_plain_hanmun_carries_no_reading_annotation
    passage = document.find { |p| p.urn == "#{DOC_URN}:47:hanmun" }
    assert_includes passage.text, "大箭一發"
    assert_nil passage.annotations["reading"]
  end

  def test_document_metadata_carries_the_structured_date_for_the_timeline
    assert_equal({ "not_before" => 1447, "not_after" => 1447, "raw" => "1447" },
                 document.metadata["date"],
                 "머리말 연도 = 1447 through the MetadataDates :structured shape")
  end

  # --- fetch (WebMock — no network in tests, ever) ----------------------------

  API_URL = "https://ko.wikisource.org/w/api.php"

  def api_payload(revid: 454_577)
    { "query" => { "pages" => { "1740" => {
      "pageid" => 1740, "ns" => 0, "title" => "용비어천가",
      "revisions" => [{ "revid" => revid, "timestamp" => "2026-06-26T07:35:34Z",
                        "slots" => { "main" => { "*" => "== 제1장 ==\n{{옛한글 인라인|海東 六龍이〮}}\n" } } }]
    } } } }
  end

  def stub_api(payload)
    stub_request(:get, API_URL)
      .with(query: hash_including("action" => "query", "prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate(payload),
                 headers: { "Content-Type" => "application/json" })
  end

  def test_fetch_writes_the_curated_page_envelopes_and_pins_the_revid_map
    stub_api(api_payload)
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      envelope = JSON.parse(File.read(File.join(workdir, "pages", "yongbieocheonga.json")))
      assert_equal "용비어천가", envelope["title"]
      assert_equal 454_577, envelope["revid"]
      assert_includes envelope["wikitext"], "옛한글 인라인"
      state = JSON.parse(File.read(File.join(workdir, Nabu::Adapters::KoWikisourceMk::STATE_FILE)))
      assert_equal report.sha, state["sha256"]
      # The pin is the slug→revid map: a revid bump changes the sha.
      assert_match(/\A\h{64}\z/, report.sha)
    end
  end

  def test_fetch_raises_when_a_curated_title_is_missing_upstream
    stub_api({ "query" => { "pages" => {} } })
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/용비어천가/, error.message)
    end
  end
end
