# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::MandokuParser (P33-0): the parser family for Kanripo's
# mandoku org-mode text files. Census facts pinned here (probe of seven real
# repos, 2026-07-20): `#+TITLE`/`#+DATE`/`#+PROPERTY` headers (ID/BASEEDITION/
# JUAN/CAT/WITNESS/FILE; ID and BASEEDITION repeat — first wins),
# `<pb:KRid_ED_NNN-Na>` page anchors (leaf-side grain, NO line component in
# the anchor — hence the citation stops at leaf-side), anchors appearing
# mid-line (the page break falls inside a print line), ¶ terminating each
# print line, `**` org headings as navigation (no ¶ — not page text),
# `# src:` alignment comments, `&KR0809;`-style gaiji refs verbatim.
class MandokuParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/kanripo", __dir__)

  def parse(text_id, urn: "urn:nabu:kanripo:#{text_id}")
    Nabu::Adapters::MandokuParser.new.parse(File.join(FIXTURES, text_id), urn: urn, text_id: text_id)
  end

  # -- document identity + headers -----------------------------------------

  def test_document_carries_urn_title_language_and_first_wins_headers
    document = parse("KR1h0004")

    assert_equal "urn:nabu:kanripo:KR1h0004", document.urn
    assert_equal "論語", document.title
    assert_equal "lzh", document.language
    # BASEEDITION and ID repeat in the real header block (KR1h0004 carries
    # three BASEEDITION lines and a second ID H15-21-0081) — first wins.
    assert_equal "CHANT", document.metadata["edition"]
    assert_equal "1pre-han,經學典籍,四書類", document.metadata["cat"]
  end

  def test_baseedition_trailing_whitespace_is_stripped
    # The WYG texts ship "#+PROPERTY: BASEEDITION WYG    " (trailing spaces).
    assert_equal "WYG", parse("KR1a0170").metadata["edition"]
    assert_equal "SBCK", parse("KR3a0001").metadata["edition"]
  end

  # -- the page grain -------------------------------------------------------

  def test_one_passage_per_page_anchor_in_file_then_anchor_order
    document = parse("KR1h0004")

    # 17 pages in juan 001 + 16 in juan 020 (probe census).
    assert_equal 33, document.size
    urns = document.map(&:urn)
    assert_equal "urn:nabu:kanripo:KR1h0004:001:1a", urns.first
    assert_equal "urn:nabu:kanripo:KR1h0004:001:17a", urns[16]
    assert_equal "urn:nabu:kanripo:KR1h0004:020:1a", urns[17]
    assert_equal "urn:nabu:kanripo:KR1h0004:020:16a", urns.last
    assert_equal (1..33).to_a, document.map(&:sequence)
  end

  def test_recto_verso_sides_mint_distinct_pages
    document = parse("KR3g0023")

    assert_equal %w[
      urn:nabu:kanripo:KR3g0023:000:1a
      urn:nabu:kanripo:KR3g0023:000:1b
      urn:nabu:kanripo:KR3g0023:000:2a
      urn:nabu:kanripo:KR3g0023:000:2b
    ], document.map(&:urn)
  end

  def test_page_text_is_print_lines_joined_with_newlines_and_pilcrows_stripped
    document = parse("KR1h0004")
    page = document.passages.first

    assert page.text.start_with?("1.1子曰：\n「學而時習之，\n不亦說乎？\n")
    refute_includes page.text, "¶"
    refute_includes page.text, "<pb:"
  end

  def test_mid_line_anchor_splits_the_print_line_between_pages
    # "不亦君子乎？」<pb:KR1h0004_CHANT_001-2a>¶" — the text before the
    # anchor closes page 1a; page 2a starts with the next print line.
    document = parse("KR1h0004")

    assert document.passages[0].text.end_with?("不亦君子乎？」")
    assert document.passages[1].text.start_with?("1.2有子曰：")
  end

  def test_anchor_verbatim_rides_the_passage_annotations
    page = parse("KR1h0004").passages.first

    assert_equal "KR1h0004_CHANT_001-1a", page.annotations["anchor"]
  end

  # -- annotations: headings, src comments, gaiji ---------------------------

  def test_org_headings_are_annotations_not_page_text
    page = parse("KR1h0004").passages.first

    assert_equal [{ "level" => 2, "text" => "1 《學而篇第一》" }], page.annotations["headings"]
    refute_includes page.text, "學而篇第一"
  end

  def test_src_comments_attach_to_the_open_page
    # `# src: LY 01.02:01; tr. CH` follows the 001-2a anchor.
    page = parse("KR1h0004").passages[1]

    assert_includes page.annotations["src_refs"], "LY 01.02:01; tr. CH"
  end

  def test_src_comment_before_the_first_anchor_attaches_to_the_first_page
    # KR1h0004_020 opens with `# src: LY 20.01:01; tr. CH` BEFORE 020-1a.
    page = parse("KR1h0004").passages[17]

    assert_equal "urn:nabu:kanripo:KR1h0004:020:1a", page.urn
    assert_includes page.annotations["src_refs"], "LY 20.01:01; tr. CH"
    assert_equal [{ "level" => 2, "text" => "20 《堯曰篇第二十》" }], page.annotations["headings"]
  end

  def test_gaiji_refs_are_kept_verbatim_in_text_and_listed_as_annotations
    document = parse("KR3g0023")
    page = document.passages.find { |passage| passage.urn.end_with?(":000:2b") }

    assert_includes page.text, "青&KR0809;奥語"
    assert_equal ["&KR0809;"], page.annotations["gaiji"]
  end

  def test_pages_without_gaiji_or_headings_carry_no_empty_annotation_keys
    page = parse("KR3g0023").passages.first

    refute page.annotations.key?("gaiji")
    refute page.annotations.key?("headings")
    refute page.annotations.key?("src_refs")
  end

  # -- file walking ---------------------------------------------------------

  def test_header_only_juan_files_contribute_no_passages
    # KR1a0170_000.txt is five header lines, no anchor, no text (real bytes).
    document = parse("KR1a0170")

    assert_equal 3, document.size
    assert(document.map(&:urn).all? { |urn| urn.include?(":001:") })
  end

  def test_readme_org_is_not_content
    document = parse("KR3a0001")

    assert_equal 56, document.size
    refute_includes document.passages.map(&:text).join, "目次"
  end

  # -- loud failure paths (synthetic defects on real bytes) ------------------

  def test_duplicate_page_anchor_raises_parse_error
    with_mutated_text("KR3g0023") do |dir|
      file = File.join(dir, "KR3g0023_000.txt")
      content = File.read(file)
      File.write(file, "#{content}<pb:KR3g0023_WYG_000-1a>¶\n再¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR3g0023") }
      assert_match(/duplicate page anchor/, error.message)
    end
  end

  def test_text_before_the_first_page_anchor_raises_parse_error
    with_mutated_text("KR3g0023") do |dir|
      file = File.join(dir, "KR3g0023_000.txt")
      lines = File.readlines(file)
      lines.insert(6, "漂流文字¶\n") # before the 000-1a anchor at line 7
      File.write(file, lines.join)

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR3g0023") }
      assert_match(/text before the first page anchor/, error.message)
    end
  end

  def test_text_file_with_content_but_no_anchor_raises_parse_error
    with_mutated_text("KR1a0170") do |dir|
      file = File.join(dir, "KR1a0170_000.txt")
      File.write(file, "#{File.read(file)}無頁碼之文¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR1a0170") }
      assert_match(/text before the first page anchor/, error.message)
    end
  end

  def test_text_dir_with_no_content_at_all_raises_parse_error
    Dir.mktmpdir("nabu-mandoku") do |root|
      dir = File.join(root, "KR9z9999")
      FileUtils.mkdir_p(dir)

      assert_raises(Nabu::ParseError) { parse_dir(dir, "KR9z9999") }
    end
  end

  private

  def parse_dir(dir, text_id)
    Nabu::Adapters::MandokuParser.new.parse(dir, urn: "urn:nabu:kanripo:#{text_id}", text_id: text_id)
  end

  def with_mutated_text(text_id)
    Dir.mktmpdir("nabu-mandoku") do |root|
      dir = File.join(root, text_id)
      FileUtils.cp_r(File.join(FIXTURES, text_id), dir)
      yield dir
    end
  end
end
