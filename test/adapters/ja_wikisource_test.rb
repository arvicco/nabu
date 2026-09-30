# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ja-wikisource (P109-1, Q90 under №R-74): the Japanese Wikisource
  # premodern era cone. Fixture envelopes are real api.php captures
  # (2026-09-29): 土佐日記 (a {{versions}} disambiguation shell — skip
  # by rule), 万葉集/第一巻 (the structured per-poem block grammar,
  # trimmed to 3 poems — man'yōgana 原文 + kundoku/kana layers),
  # 方丈記 (國文大觀) (a <pages index> scan-transclusion shell — the
  # declared residue class), 徒然草 (校註日本文學大系) (direct prose
  # with 底本 line, ruby {{r|漢字|よみ}}, editorial {{smaller|〔…〕}}
  # glosses, dan numbers).
  class JaWikisourceTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ja-wikisource")

    def conformance_adapter = Nabu::Adapters::JaWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ja-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def test_payload_less_shells_skip_by_rule
      ids = conformance_adapter.discover(FIXTURES).map(&:id).sort
      assert_equal %w[urn:nabu:ja-wikisource:11940 urn:nabu:ja-wikisource:12868
                      urn:nabu:ja-wikisource:46951 urn:nabu:ja-wikisource:7285
                      urn:nabu:ja-wikisource:8082], ids,
                   "shells WITH expansion payloads (方丈記 pages, 北条五代記 expanded) are " \
                   "documents; 土佐日記 ({{versions}}) and the payload-less 東照宮御実紀附録 " \
                   "dispatcher shell stay skips"
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule
    end

    # -- the <pages index> expansion (P111-2, Q109-1 mold A) -----------------

    def test_pages_index_shell_parses_from_its_page_payloads
      d = doc(8082)
      assert_equal "jpn", d.language
      texts = d.passages.map(&:text)
      assert(texts.any? { |t| t.start_with?("行く川のながれは絕えずして") },
             "the Page:-namespace text is the document body")
      assert(texts.any? { |t| t.include?("民部の省まで移りて、ひとよがほどに") },
             "page 43→44 joins mid-sentence — the scan's own flow, one paragraph")
      refute(texts.any? { |t| t.include?("pagequality") }, "noinclude furniture never leaks")
      assert(texts.any? { |t| t.include?("或はこぞ破れてことしは造り") },
             "the {{*|…}} marginal apparatus strips — modern-edition variant notes, not text")
      assert_includes d.metadata["base_edition"], "国文大観", "the shell header's 底本 still rides"
    end

    def test_pages_tag_attribute_variants_enumerate_page_titles
      quoted = Nabu::Adapters::JaWikisource.pages_tag_titles(
        '<pages index="Kokubun taikan 09 part2.djvu" from="43" to="45"/>'
      )
      assert_equal ["Page:Kokubun taikan 09 part2.djvu/43", "Page:Kokubun taikan 09 part2.djvu/44",
                    "Page:Kokubun taikan 09 part2.djvu/45"], quoted
      bare = Nabu::Adapters::JaWikisource.pages_tag_titles(
        "<pages index=NDL-DC.pdf from=3 to=4 />"
      )
      assert_equal ["Page:NDL-DC.pdf/3", "Page:NDL-DC.pdf/4"], bare
      include_form = Nabu::Adapters::JaWikisource.pages_tag_titles(
        '<pages index="Hōbun.pdf" include="1-3,7"/>'
      )
      assert_equal ["Page:Hōbun.pdf/1", "Page:Hōbun.pdf/2", "Page:Hōbun.pdf/3",
                    "Page:Hōbun.pdf/7"], include_form
    end

    # -- the dispatcher-shell expansion (P111-2, Q109-1 mold B) --------------

    def test_expanded_dispatcher_shell_parses_with_furniture_stripped
      d = doc(46_951)
      assert_equal "jpn", d.language
      assert_equal "北条五代記/巻第二", d.title
      texts = d.passages.map(&:text)
      assert(texts.any? { |t| t.start_with?("聞しは昔。管領上杉修理") },
             "ruby readings (<rt>) drop, base text (<rb>) stays")
      refute(texts.any? { |t| t.include?("巻第一") && t.include?("巻第三") },
             "the navigationHeader prev/next furniture never leaks")
      refute(texts.any? { |t| t.include?("姉妹プロジェクト") || t.include?("仮名草子") },
             "the navigationNotes editorial block never leaks")
      refute(texts.any? { |t| t.include?("北条氏綱と上杉朝定合戦の事") },
             "TOC self-links and heading links strip — headings ride as sections, not text")
      body = d.passages.find { |p| p.text.start_with?("聞しは昔") }
      assert_equal "一　北条氏綱と上杉朝定合戦の事", body.annotations["section"],
                   "the parent-page heading link becomes the section annotation"
    end

    def test_prose_page_parses_at_paragraph_grain_with_dan_sections
      d = doc(7285)
      assert_equal "jpn", d.language
      assert_equal "徒然草 (校註日本文學大系)", d.title
      first = d.passages.first
      assert_equal "1", first.annotations["section"], "the bare dan number is the section"
      assert first.text.start_with?("つれ〲なるまゝに、日ぐらし硯に向ひて"),
             "iteration-mark templates render their character; editorial 〔…〕 glosses strip"
      refute(d.passages.any? { |p| p.text.include?("{{") }, "no template syntax leaks")
      assert(d.passages.any? { |p| p.text.include?("唯人") },
             "ruby {{r|漢字|よみ}} keeps the base text")
    end

    def test_prose_page_carries_the_botsubon_verbatim_and_era_band
      meta = doc(7285).metadata
      assert_includes meta["base_edition"], "『日本文学大系 : 校註』第3巻",
                      "the 底本 line rides verbatim (№R-74)"
      assert_equal %w[鎌倉時代 南北朝時代], meta["eras"]
      band = meta["era_band"]
      assert_equal [1185, 1392], [band["not_before"], band["not_after"]],
                   "the era envelope spans every era category the page carries"
      assert_equal "鎌倉時代・南北朝時代", band["raw"]
    end

    def test_manyo_blocks_parse_one_poem_per_passage_in_old_japanese
      d = doc(11_940)
      assert_equal "ojp", d.language, "the 原文 man'yōgana layer IS Old Japanese"
      assert_equal 3, d.passages.size
      first = d.passages.first
      assert_equal "#{d.urn}:01/0001", first.urn, "the corpus's own 歌番号 is the citation"
      assert first.text.start_with?("篭毛與 美篭母乳"), "原文 is the passage text"
      assert first.annotations["kundoku"].start_with?("篭もよ み篭持ち")
      assert first.annotations["kana"].start_with?("こもよ みこもち")
      assert_includes first.annotations["heading"], "泊瀬朝倉宮御宇天皇代"
    end

    def test_manyo_variant_verse_keeps_the_corpus_own_suffix
      d = doc(12_868)
      assert_equal ["#{d.urn}:03/0235", "#{d.urn}:03/0235S"], d.passages.map(&:urn),
                   "the 或本歌 variant's own letter suffix survives — stripping it " \
                   "collided URNs on the live 第三巻 (first-sync lesson)"
    end

    def test_unstated_edition_recorded_honestly
      meta = doc(11_940).metadata
      assert_equal "unstated", meta["base_edition"], "№R-74: absence is recorded, never guessed"
    end
  end
end
