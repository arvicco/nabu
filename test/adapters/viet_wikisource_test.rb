# frozen_string_literal: true

require "test_helper"

# The viet-wikisource adapter (P78-5): the Vietnamese classical shelf on
# the SINITIC axis — 大越史記全書 (Đại Việt sử ký toàn thư) complete
# from zh.wikisource (29 quyển + 卷首) plus the two chữ-Hán showpieces
# (平吳大誥 from vi.wikisource, 諭諸裨將檄文 from zh.wikisource).
# Founds the wikisource-han family (curated title-list scoping).
class VietWikisourceTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("viet-wikisource")

  def adapter = Nabu::Adapters::VietWikisource.new(delay: 0)

  def conformance_adapter = adapter
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "viet-wikisource"

  # --- manifest ---------------------------------------------------------------

  def test_manifest_carries_the_wikisource_grant
    manifest = adapter.manifest
    assert_equal "viet-wikisource", manifest.id
    assert_equal "attribution", manifest.license_class,
                 "PD texts + CC BY-SA 4.0 transcription layer → attribution (the survey ruling)"
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/public domain/i, manifest.license)
    assert_equal "wikisource-han", manifest.parser_family
    assert_match(/Wikisource/, manifest.credit)
  end

  # --- the curated page list ----------------------------------------------------

  def test_the_curated_list_is_the_censused_dvsktt_tree_plus_the_showpieces
    pages = Nabu::Adapters::VietWikisource::PAGES
    assert_equal 32, pages.size, "卷首 + 5 外紀 + 19 本紀 + 5 續編 + two showpieces"
    assert_equal pages.size, pages.map(&:id).uniq.size, "curated ids must be unique"

    dvsktt = pages.select { |page| page.work == "大越史記全書" }
    assert_equal 30, dvsktt.size
    assert(dvsktt.all? { |page| page.wiki == "zh" && page.title.start_with?("大越史記全書/") })
    assert_includes dvsktt.map(&:title), "大越史記全書/本紀卷之十九"
    assert_includes dvsktt.map(&:id), "dvsktt-ban-ky-19"

    hich = pages.find { |page| page.id == "hich-tuong-si" }
    assert_equal %w[zh 諭諸裨將檄文], [hich.wiki, hich.title],
                 "the hịch original script lives on zh.wikisource (censused 2026-08-18 — " \
                 "vi.wikisource's 諭諸裨將檄文 is a redlink)"
    cao = pages.find { |page| page.id == "binh-ngo-dai-cao" }
    assert_equal ["vi", "Bình Ngô đại cáo"], [cao.wiki, cao.title]
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_present_curated_page
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:viet-wikisource:binh-ngo-dai-cao
      urn:nabu:viet-wikisource:dvsktt-ngoai-ky-1
      urn:nabu:viet-wikisource:hich-tuong-si
    ], refs.map(&:id).sort
  end

  def test_discovery_skips_count_the_strays
    skips = adapter.discovery_skips(FIXTURES)
    # The fixture dir's manifest.yml is the ONE counted stray (the sillok
    # precedent — it pins that the census actually counts); README.md and
    # curated page files are recognized.
    assert_equal 1, skips.unrecognized
    assert_equal ["non-corpus file: manifest.yml"], skips.notes
  end

  # --- parse: the DVSKTT quyển (prose mode) -------------------------------------

  def test_parse_mints_hanmun_paragraph_passages_with_section_paths
    document = parse_fixture("urn:nabu:viet-wikisource:dvsktt-ngoai-ky-1")
    assert_equal "lzh", document.language, "classical Chinese — the kanripo/sillok precedent"
    assert_equal "大越史記全書/外紀卷之一", document.title
    assert_equal "大越史記全書", document.metadata["work"]
    assert_equal "外紀卷之一", document.metadata["part"]
    assert_equal "吳士連等", document.metadata["author"], "override_author with the wiki link stripped"
    assert_nil document.metadata["date"], "quyển pages carry no year param — honestly dateless"

    first = document.first
    assert first.text.start_with?("按黃帝時建萬國"), "pre-heading text is a passage (no section)"
    assert_nil first.annotations["section"]

    ruler = document.find { |passage| passage.text == "諱祿續，神農氏之後也。" }
    assert_equal "鴻厖氏紀 · 涇陽王", ruler.annotations["section"],
                 "the == 紀 == / === ruler === heading path rides each passage"

    assert document.map(&:urn).last.end_with?(":#{document.size}")
    assert_equal "大越史記外紀全書卷之一終", document.to_a.last.text
  end

  def test_annotate_templates_ride_inline_as_interlinear_notes
    document = parse_fixture("urn:nabu:viet-wikisource:dvsktt-ngoai-ky-1")
    noted = document.find { |passage| passage.text.include?("生貉龍君") }
    assert_includes noted.text, "生貉龍君【按《唐紀》",
                    "{{annotate|…}} renders as 【…】 inline — the sillok 원주 precedent"
    refute_match(/\{\{|\}\}/, noted.text)
  end

  # --- parse: the hịch (prose mode, header year) ---------------------------------

  def test_the_hich_carries_its_header_year_and_textquality
    document = parse_fixture("urn:nabu:viet-wikisource:hich-tuong-si")
    assert_equal "陳興道", document.metadata["author"]
    assert_equal({ "not_before" => 1284, "not_after" => 1284, "raw" => "1284" },
                 document.metadata["date"], "the header year param — MetadataDates :structured shape")
    assert_equal "25%", document.metadata["textquality"],
                 "{{Textquality}} is the wiki's own proofreading status, honest-noted"
    assert(document.none? { |passage| passage.annotations.key?("section") },
           "the hịch has no headings — no section annotations")
  end

  def test_sub_glosses_ride_inline_as_interlinear_notes
    document = parse_fixture("urn:nabu:viet-wikisource:hich-tuong-si")
    glossed = document.find { |passage| passage.text.include?("骨䚟") }
    assert_includes glossed.text, "骨䚟【䚟，多改切】兀郎何人也",
                    "<sub>…</sub> reading glosses render as 【…】 inline"
  end

  # --- parse: the cáo (parallel-poem mode) ---------------------------------------

  def test_the_cao_pairs_han_stanzas_with_their_phien_am
    document = parse_fixture("urn:nabu:viet-wikisource:binh-ngo-dai-cao")
    assert_equal "lzh", document.language
    assert_equal 18, document.size, "18 chữ-Hán stanzas once the editorial <ref> footnotes are stripped"
    assert_equal "代天行化皇上若曰。", document.first.text
    assert_equal "Đại thiên hành hóa hoàng thượng nhược viết:",
                 document.first.annotations["phien_am"],
                 "the parallel Hán-Việt reading rides as annotation, honestly labeled"
    assert_equal "平吳大誥", document.metadata["work"]
    assert_equal "Nguyễn Trãi", document.metadata["author"]
    assert_nil document.metadata["date"], "no year param — the 1428 in the notes prose is not machine-claimed"
  end

  def test_the_cao_keeps_upstream_spacing_verbatim_and_drops_ref_footnotes
    document = parse_fixture("urn:nabu:viet-wikisource:binh-ngo-dai-cao")
    stanza = document.to_a[2]
    assert stanza.text.start_with?("仁 義 之 舉，要 在 安 民 ，"),
           "the page's per-character spacing is canonical — never cleaned"
    document.each do |passage|
      refute_match(/<ref/, passage.text)
      refute_match(/<ref|Triệu, Đinh, Lý, Trần/, passage.annotations["phien_am"].to_s,
                   "wikisource editorial footnotes are apparatus, not text")
    end
  end

  # --- fetch (WebMock; the curated batched title fetch) ---------------------------

  def test_fetch_batches_curated_titles_per_wiki_and_writes_envelopes
    stub_request(:get, "https://zh.wikisource.org/w/api.php")
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "49748" => {
          "pageid" => 49_748, "ns" => 0, "title" => "諭諸裨將檄文",
          "revisions" => [{ "revid" => 2_345_859, "timestamp" => "2023-12-20T08:37:55Z",
                            "slots" => { "main" => { "*" => "{{header\n|author=陳興道\n}}\n余常聞之。" } } }]
        } } } }
      ))
    stub_request(:get, "https://vi.wikisource.org/w/api.php")
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate(
        { "query" => { "pages" => { "10" => {
          "pageid" => 10, "ns" => 0, "title" => "Bình Ngô đại cáo",
          "revisions" => [{ "revid" => 205_842, "timestamp" => "2026-07-29T09:16:32Z",
                            "slots" => { "main" => { "*" => "<poem>代天行化。</poem>" } } }]
        } } } }
      ))

    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_match(/2 fetched/, report.notes)
      assert_match(/30 missing/, report.notes, "the stubbed response answered 2 of 32 curated titles")
      envelope = JSON.parse(File.read(File.join(dir, "pages", "hich-tuong-si.json")))
      assert_equal ["諭諸裨將檄文", 2_345_859, "zh"], envelope.values_at("title", "revid", "wiki")
      assert File.file?(File.join(dir, "pages", "binh-ngo-dai-cao.json"))
      assert File.file?(File.join(dir, Nabu::Adapters::VietWikisource::STATE_FILE))
      # One batched request per wiki — 31 zh titles fit one 50-title batch.
      assert_requested :get, "https://zh.wikisource.org/w/api.php",
                       query: hash_including("prop" => "revisions"), times: 1
      assert_requested :get, "https://vi.wikisource.org/w/api.php",
                       query: hash_including("prop" => "revisions"), times: 1
    end
  end

  def test_fetch_wraps_transport_errors_as_fetch_errors
    stub_request(:get, "https://zh.wikisource.org/w/api.php")
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 503)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
    end
  end

  def test_fetch_never_deletes_a_previously_fetched_page
    stub_request(:get, "https://zh.wikisource.org/w/api.php")
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate({ "query" => { "pages" => {} } }))
    stub_request(:get, "https://vi.wikisource.org/w/api.php")
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate({ "query" => { "pages" => {} } }))
    Dir.mktmpdir do |dir|
      pages = File.join(dir, "pages")
      FileUtils.mkdir_p(pages)
      File.write(File.join(pages, "hich-tuong-si.json"), JSON.generate(
                                                           "title" => "諭諸裨將檄文", "pageid" => 49_748, "ns" => 0,
                                                           "revid" => 1, "timestamp" => "2020-01-01T00:00:00Z",
                                                           "wiki" => "zh", "wikitext" => "余常聞之。"
                                                         ))
      adapter.fetch(dir)
      assert File.file?(File.join(pages, "hich-tuong-si.json")),
             "a curated page upstream stopped serving is retained, never deleted"
    end
  end

  private

  def parse_fixture(urn)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn }
    refute_nil ref, "fixture ref #{urn} not discovered"
    adapter.parse(ref)
  end
end
