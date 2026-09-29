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

    def test_versions_and_pages_index_shells_skip_by_rule
      ids = conformance_adapter.discover(FIXTURES).map(&:id).sort
      assert_equal %w[urn:nabu:ja-wikisource:11940 urn:nabu:ja-wikisource:12868
                      urn:nabu:ja-wikisource:7285], ids,
                   "土佐日記 ({{versions}}), 方丈記 (<pages index>) and the 北条五代記 " \
                   "sibling-transclusion shell never become documents"
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 3, skips.skipped_by_rule
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
