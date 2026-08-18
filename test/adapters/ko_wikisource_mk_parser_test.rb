# frozen_string_literal: true

require "test_helper"
require "json"

# The ko-wikisource page grammar (P78-4): ONE wikitext page carries the
# whole 용비어천가 — a {{머리말}} header (연도 = the machine date), a
# hanmun preface (ignored: paratext outside the canto grain), then all
# 125 cantos as == 제N장 == sections whose LAYERS are template-marked:
# {{옛한글 인라인|…}} = Middle Korean, {{윗주|漢字|reading}} under
# === 한문 === = hanmun ruby pairs, plain hangul under === 현대어 === =
# the modern rendering. 84 cantos are bare (MK templates only); canto 47
# carries plain (윗주-less) hanmun lines; canto 125 carries its modern
# rendering as headingless plain lines — all witnessed by the fixture.
class KoWikisourceMkParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ko-wikisource-mk")

  def wikitext
    @wikitext ||= JSON.parse(File.read(File.join(FIXTURES, "pages", "yongbieocheonga.json")))
                      .fetch("wikitext")
  end

  def work
    @work ||= Nabu::Adapters::KoWikisourceMkParser.new.parse(wikitext)
  end

  def canto(number)
    work.cantos.find { |c| c.number == number } || flunk("canto #{number} missing")
  end

  # --- the header -------------------------------------------------------------

  def test_header_title_and_machine_year
    assert_equal "용비어천가(龍飛御天歌)", work.title
    assert_equal 1447, work.year, "머리말 연도 — the print year, upstream's own machine date"
  end

  # --- the canto census -------------------------------------------------------

  def test_all_125_cantos_parse_in_page_order
    assert_equal (1..125).to_a, work.cantos.map(&:number)
  end

  def test_every_canto_carries_the_middle_korean_layer
    assert(work.cantos.all? { |c| c.mk_lines.any? }, "the MK layer is complete across all 125 cantos")
    assert_equal 250, work.cantos.sum { |c| c.mk_lines.size }, "the 2026-08-18 census: 250 옛한글 인라인 lines"
  end

  def test_layer_census_matches_the_page
    # Content-based, not heading-based: cantos 32–34 carry EMPTY 한문/현대어
    # heading scaffolding — a heading with no text is no layer.
    assert_equal(34, work.cantos.count { |c| c.hanmun_lines.any? })
    assert_equal 29, work.cantos.count { |c| c.modern_lines.any? },
                 "28 filled 현대어 sections + canto 125's headingless modern rendering"
  end

  def test_empty_layer_headings_claim_nothing
    c = canto(33)
    assert_equal 2, c.mk_lines.size
    assert_empty c.hanmun_lines, "canto 33's 한문 heading is empty scaffolding"
    assert_empty c.modern_lines
  end

  # --- a fully layered canto (제2장 — the root-deep-tree verse) ---------------

  def test_canto_two_extracts_all_three_layers
    c = canto(2)
    assert_equal 2, c.mk_lines.size
    assert c.mk_lines[0].start_with?("불휘〮 기픈〮 남ᄀᆞᆫ〮"), c.mk_lines[0]
    assert_includes c.mk_lines[0], "ᆞ", "archaic conjoining jamo (U+119E arae-a) survive verbatim"
    assert_equal 2, c.hanmun_lines.size
    assert_equal "根深之木 風亦不扤 有灼其華 有蕡其實", c.hanmun_lines[0].text
    assert_equal "근심지목 풍역불올 유작기화 유분기실", c.hanmun_lines[0].reading
    assert_equal 2, c.modern_lines.size
    assert c.modern_lines[0].start_with?("뿌리 깊은 나무는"), c.modern_lines[0]
  end

  # --- the parser branches the page forces ------------------------------------

  def test_bare_canto_is_mk_only
    c = canto(113)
    assert_equal 2, c.mk_lines.size
    assert_empty c.hanmun_lines
    assert_empty c.modern_lines
  end

  def test_canto_47_carries_plain_hanmun_lines_without_ruby
    c = canto(47)
    plain = c.hanmun_lines.select { |line| line.reading.nil? }
    refute_empty plain, "canto 47's 한문 lines have no 윗주 wrapper"
    assert_includes plain.map(&:text), "大箭一發, 突厥驚懾. 何地之逖, 而威不及."
  end

  def test_canto_125_headingless_modern_rendering_is_captured_but_never_as_mk
    c = canto(125)
    assert_equal 3, c.mk_lines.size
    assert_equal 3, c.modern_lines.size
    assert c.modern_lines[0].start_with?("천 년 전에 미리 정하신"), c.modern_lines[0]
    refute(c.modern_lines.any? { |l| l.include?("위키백과") }, "template lines never leak into the modern layer")
  end

  # --- text discipline ----------------------------------------------------------

  def test_no_markup_leaks_into_any_layer
    work.cantos.each do |c|
      (c.mk_lines + c.hanmun_lines.map(&:text) + c.modern_lines).each do |line|
        refute_match(/<br|<big|\{\{|\[\[/, line, "canto #{c.number}: markup leaked into #{line.inspect}")
        refute_empty line.strip
      end
    end
  end
end
