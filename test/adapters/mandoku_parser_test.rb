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
#
# P33-1 (KR2 wave-2 census, seven KR2 + three KR5 repos probed 2026-07-20)
# adds two REAL shapes the wave-1 probe set missed, both attested in the
# fixture set: re-asserted anchors for the still-open page (pervasive in
# SBCK 大清一統志 — 1,507 instances, every one the OPEN page; a closed
# page's anchor stays a loud duplicate) and the text's own edition-VOLUME
# anchors `<pb:KR2a0038_WYG_WYG0297-0606c>` (alpha-prefixed volume ordinal,
# a/b/c print registers) interleaved mid-page in the WYG 明史 — annotated,
# never page text, never a page boundary.
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

  # -- KR2 wave-2 shapes (P33-1 census) --------------------------------------

  def test_reasserted_anchor_for_the_open_page_is_a_no_op
    # 明史 juan 46 re-asserts <pb:KR2a0038_WYG_046-10b> mid-page after an
    # interleaved edition-volume anchor: one page, text spanning the
    # re-assertion, no duplicate error (the 大清一統志 shows the same shape
    # 1,507 times — always the OPEN page).
    document = parse("KR2a0038")

    pages = document.passages.select { |passage| passage.urn.end_with?(":046:10b") }
    assert_equal 1, pages.size
    assert_includes pages.first.text, "祿勸州"   # before the re-assertion
    assert_includes pages.first.text, "鎮沅府"   # after the re-assertion
  end

  def test_edition_volume_anchors_are_annotations_not_text_and_not_pages
    # <pb:KR2a0038_WYG_WYG0297-0606c>: the text's own id + edition with an
    # ALPHA-prefixed volume ordinal and an a/b/c print register — the WYG
    # print edition's volume pagination riding inside the leaf-side page.
    document = parse("KR2a0038")

    open_page = document.passages.find { |passage| passage.urn.end_with?(":046:10b") }
    assert_equal ["KR2a0038_WYG_WYG0297-0606c"], open_page.annotations["edition_pages"]
    fifteen_a = document.passages.find { |passage| passage.urn.end_with?(":046:15a") }
    assert_equal ["KR2a0038_WYG_WYG0297-0609b"], fifteen_a.annotations["edition_pages"]
    refute_includes open_page.text, "<pb:"
    assert open_page.text.include?("西距府二十\n里"), "mid-line text around the volume anchor must survive"
    assert(document.passages.none? { |passage| passage.urn.include?("WYG0297") })
  end

  def test_tls_base_edition_sections_parse_at_the_anchor_grain
    # 史記 (BASEEDITION tls) files are SECTION ordinals, not juan (_201 is
    # 表 part 1; its header says JUAN 1): the anchor's NNN still matches the
    # file suffix and the urn takes the digits verbatim.
    document = parse("KR2a0001")

    assert_equal "史記", document.title
    assert_equal "tls", document.metadata["edition"]
    assert_equal 8, document.size
    assert_equal "urn:nabu:kanripo:KR2a0001:201:1a", document.passages.first.urn
    assert_includes document.passages.first.annotations["headings"],
                    { "level" => 2, "text" => "2 表" }
    assert_includes document.passages.first.text, "太史公曰："
  end

  def test_wyg_biography_fixture_parses_whole
    document = parse("KR2g0007")

    assert_equal "杜工部年譜", document.title
    assert_equal "WYG", document.metadata["edition"]
    assert_equal 25, document.size
  end

  # -- KR5 witness overlays (P37-1 census, ten witness + four plain KR5 repos
  #    probed 2026-07-20) ----------------------------------------------------
  #
  # DZJY overlay repos transcribe the WITNESS edition (CK-KZ 重刊道藏輯要):
  # file lines are the witness's print columns, witness `<pb:>` anchors carry
  # a `<juan>p<leaf><side>` page component (THREE id arrangements censused —
  # `CK-KZ_JY001_01p001a`, `KR5a0004_CK-KZ_01p001a`, `CK-KZ_KR5i0030_01p001a`)
  # and become the citable page structure; `<md:>` milestones mark where the
  # BASE edition's pages fall inside the witness text (annotations, never
  # boundaries); `@fw` running headers are the witness page's forme work.
  # Witness pages SPAN file boundaries (the carry), and ¶ marks the base
  # edition's line ends mid-line.

  def test_witness_overlay_document_carries_witness_metadata
    document = parse("KR5a0001")

    assert_equal "元始無量度人上品妙經", document.title
    assert_equal "HFL", document.metadata["edition"]
    assert_equal "CK-KZ", document.metadata["witness"]
    assert_equal "witness", document.metadata["page_scheme"]
    assert_equal "KR5", document.metadata["class"]
  end

  def test_witness_pages_mint_at_witness_juan_leafside_grain
    document = parse("KR5a0001")

    # 111 witness pages in the fixture files (_001–_003), 109 minted — the
    # two empty pages (adjacent anchors, below) never mint a citation.
    assert_equal 109, document.size
    assert_equal "urn:nabu:kanripo:KR5a0001:01:001a", document.passages.first.urn
    assert_equal "urn:nabu:kanripo:KR5a0001:01:056a", document.passages.last.urn
    assert_equal (1..109).to_a, document.map(&:sequence)
  end

  def test_witness_page_text_is_witness_columns_with_overlay_markup_stripped
    page = parse("KR5a0001").passages.first

    # File lines are the WITNESS's print columns — the newline preserves the
    # witness's breaks; ¶ (the BASE edition's line ends, falling mid-column)
    # and every overlay construct are stripped out of the text.
    assert page.text.start_with?("道言昔於始青天中碧落空歌大浮黎土受元始度人无量上\n品元始天尊當說是經周")
    assert page.text.end_with?("皆開聰說經")
    refute_includes page.text, "¶"
    refute_includes page.text, "<md:"
    refute_includes page.text, "@fw"
    assert_equal "CK-KZ_JY001_01p001a", page.annotations["anchor"]
  end

  def test_running_heads_and_base_pages_ride_the_witness_page_annotations
    page = parse("KR5a0001").passages.first

    # "@fw重<md:KR5a0001_HFL_001-001a>¶刋道藏輯要" — the fw text carries an
    # embedded base-page milestone and a ¶: both extracted, the running head
    # recorded as it reads.
    assert_equal %w[重刋道藏輯要 元始无量度人上品妙經卷之一], page.annotations["fw"]
    # The base edition's front-matter pages (000-001a…000-002b, pilcrow-only
    # runs BEFORE the first witness anchor) attach pending to the first
    # witness page, then 001-001a/001-001b fall inside it.
    assert_equal %w[
      KR5a0001_HFL_000-001a KR5a0001_HFL_000-001b KR5a0001_HFL_000-002a
      KR5a0001_HFL_000-002b KR5a0001_HFL_001-001a KR5a0001_HFL_001-001b
    ], page.annotations["base_pages"]
  end

  def test_empty_witness_pages_are_dropped_without_minting
    document = parse("KR5a0001")

    # <pb:CK-KZ_JY001_01p034b><pb:CK-KZ_JY001_01p035a> — adjacent anchors,
    # the witness page is blank: dropped, the neighbours mint.
    urns = document.map(&:urn)
    refute_includes urns, "urn:nabu:kanripo:KR5a0001:01:022b"
    refute_includes urns, "urn:nabu:kanripo:KR5a0001:01:034b"
    assert_includes urns, "urn:nabu:kanripo:KR5a0001:01:034a"
    assert_includes urns, "urn:nabu:kanripo:KR5a0001:01:035a"
  end

  def test_overlay_headings_shed_pilcrows_and_embedded_milestones
    document = parse("KR5a0001")
    page = document.passages.find { |passage| passage.urn.end_with?(":01:012b") }

    # "** 諸天中大梵隱語无量音　　道君譔¶<md:KR5a0001_HFL_001-015a>¶"
    assert_includes page.annotations["headings"],
                    { "level" => 2, "text" => "諸天中大梵隱語无量音　　道君譔" }
    assert_includes page.annotations["headings"], { "level" => 3, "text" => "元始靈書上篇" }
    assert_includes page.annotations["base_pages"], "KR5a0001_HFL_001-015a"
  end

  def test_witness_pages_carry_across_file_boundaries
    # KR5a0004 (textid_CK-KZ arrangement): page 02p048a opens in _006 and its
    # text runs into _007 (whose body is the single carried column "諸") —
    # witness pages span files, unlike the plain family's juan-file grain.
    document = parse("KR5a0004")

    assert_equal 1, document.size
    page = document.passages.first
    assert_equal "urn:nabu:kanripo:KR5a0004:02:048a", page.urn
    assert_equal "KR5a0004_CK-KZ_02p048a", page.annotations["anchor"]
    assert_includes page.text, "顯功德品" # from _006
    assert page.text.end_with?("是時善音童子及諸仙\n諸"), "the _007 column must carry"
    assert_equal %w[KR5a0004_HFL_005-012b KR5a0004_HFL_006-001a], page.annotations["base_pages"]
  end

  def test_witness_first_arrangement_with_the_text_id_as_container
    # KR5i0030: <pb:CK-KZ_KR5i0030_01p001a> — witness siglum first, the text
    # id in the container slot; BASEEDITION CK-KZ IS the witness (no <md:>).
    document = parse("KR5i0030")

    # "#+TITLE:唱道真言 Changdao Zhenyan" — no space after the colon (the
    # KR5i header variant), value verbatim including the romanization.
    assert_equal "唱道真言 Changdao Zhenyan", document.title
    assert_equal 9, document.size
    assert_equal "urn:nabu:kanripo:KR5i0030:01:001a", document.passages.first.urn
    assert_equal "urn:nabu:kanripo:KR5i0030:02:003a", document.passages.last.urn
    assert document.passages.first.text.start_with?("唱道眞言序")
    assert_equal "CK-KZ", document.metadata["edition"]
    assert_equal "CK-KZ", document.metadata["witness"]
    refute document.passages.first.annotations.key?("base_pages")
  end

  def test_md_edition_rides_verbatim_even_against_the_declared_baseedition
    # KR5c0091 declares BASEEDITION HFL but its milestones say WYG — headers
    # lie in real repos, so the md edition is recorded verbatim, never
    # validated.
    document = parse("KR5c0091")

    assert_equal 42, document.size
    assert_equal "HFL", document.metadata["edition"]
    assert_equal %w[KR5c0091_WYG_000-1a KR5c0091_WYG_001-1a KR5c0091_WYG_001-1b],
                 document.passages.first.annotations["base_pages"]
  end

  def test_plain_mandoku_kr5_repo_parses_at_the_leafside_grain_today
    document = parse("KR5g0001")

    assert_equal "大慧靜慈妙樂天尊說福德五聖經", document.title
    assert_equal 16, document.size
    assert_equal "urn:nabu:kanripo:KR5g0001:000:001a", document.passages.first.urn
    assert_equal "urn:nabu:kanripo:KR5g0001:000:008b", document.passages.last.urn
    assert_equal "DZ1192", document.metadata["dzid"]
    refute document.metadata.key?("page_scheme")
    assert document.passages.first.text.start_with?("三經同卷滿一")
  end

  # -- witness overlay loud paths (real-byte defects) ------------------------

  STRAY_KR5A0004_000 = <<~STRAY # the real KR5a0004_000.txt, byte-verbatim
    # -*- mode: mandoku-view -*-
    #+TITLE: 元始天尊説無上内祕眞藏經
    #+DATE: 2015-08-28 23:34:16
    #+PROPERTY: BASEEDITION HFL
    #+PROPERTY: WITNESS CK-KZ
    #+PROPERTY: JUAN 0

    八
  STRAY

  def test_stray_text_outside_any_witness_page_raises_parse_error
    # The REAL KR5a0004_000.txt is a header block plus one stray 八 — text
    # with no page anchor anywhere. Unciteable text quarantines the text
    # loudly (the file is kept out of the fixture mirror for exactly this
    # reason; the trim is documented in the fixture README).
    with_mutated_text("KR5a0004") do |dir|
      File.write(File.join(dir, "KR5a0004_000.txt"), STRAY_KR5A0004_000)

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5a0004") }
      assert_match(/text before the first page anchor/, error.message)
    end
  end

  def test_witness_anchor_in_a_leafside_document_raises_mixed_schemes
    with_mutated_text("KR5g0001") do |dir|
      file = File.join(dir, "KR5g0001_000.txt")
      File.write(file, "#{File.read(file)}<pb:CK-KZ_JY001_01p001a>\n殘¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5g0001") }
      assert_match(/mixed page anchor schemes/, error.message)
    end
  end

  def test_leafside_anchor_in_a_witness_document_raises_mixed_schemes
    with_mutated_text("KR5i0030") do |dir|
      file = File.join(dir, "KR5i0030_002.txt")
      File.write(file, "#{File.read(file)}<pb:KR5i0030_HFL_002-1a>¶\n殘¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5i0030") }
      assert_match(/mixed page anchor schemes/, error.message)
    end
  end

  def test_base_page_milestone_in_a_leafside_document_raises
    with_mutated_text("KR5g0001") do |dir|
      file = File.join(dir, "KR5g0001_000.txt")
      File.write(file, "#{File.read(file)}<md:KR5g0001_HFL_000-1a>¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5g0001") }
      assert_match(/base-page milestone/, error.message)
    end
  end

  def test_witness_anchor_with_an_unknown_head_component_raises
    with_mutated_text("KR5a0001") do |dir|
      file = File.join(dir, "KR5a0001_003.txt")
      File.write(file, "#{File.read(file)}<pb:QQ-ZZ_JY001_99p001a>\n殘¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5a0001") }
      assert_match(/unrecognized witness page anchor/, error.message)
    end
  end

  def test_unrecognized_page_anchor_shape_raises
    # A c-register witness page (real shape only in edition-volume anchors,
    # never in witness pages) matches no censused anchor form — loud, never
    # silent text pollution.
    with_mutated_text("KR5a0001") do |dir|
      file = File.join(dir, "KR5a0001_003.txt")
      File.write(file, "#{File.read(file)}<pb:CK-KZ_JY001_99p001c>\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5a0001") }
      assert_match(/unrecognized page anchor/, error.message)
    end
  end

  def test_unknown_at_code_raises
    with_mutated_text("KR5a0001") do |dir|
      file = File.join(dir, "KR5a0001_003.txt")
      File.write(file, "#{File.read(file)}@kr 異碼¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5a0001") }
      assert_match(/unrecognized at-code/, error.message)
    end
  end

  def test_duplicate_witness_page_anchor_raises
    with_mutated_text("KR5i0030") do |dir|
      file = File.join(dir, "KR5i0030_002.txt")
      File.write(file, "#{File.read(file)}<pb:CK-KZ_KR5i0030_01p001a>¶\n再¶\n")

      error = assert_raises(Nabu::ParseError) { parse_dir(dir, "KR5i0030") }
      assert_match(/duplicate page anchor/, error.message)
    end
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
