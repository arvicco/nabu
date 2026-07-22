# frozen_string_literal: true

require "test_helper"
require "stringio"

# OpenitiMarkdownParser tests (P41-1): the openiti-markdown family — OpenITI
# mARkdown structured plaintext (premodern Arabic/Persian). Censused from the
# six real fixtures in test/fixtures/openiti/ (P41-g; never invented):
#
#   - magic value ######OpenITI# on line 1 (the Shamela hadith carries a real
#     leading U+FEFF BOM before it);
#   - a #META# block terminated by #META#Header#End# in FOUR incompatible
#     vocabularies (KITAB numbered, Shamela Arabic-keyed, PDL minimal,
#     eScriptorium OCR) — captured as OPAQUE raw lines, never parsed;
#   - "# " paragraphs with "~~" wrapped-line continuations (the Shamela and
#     OCR files also use the fused "# ~~" continuation shape);
#   - "### |"…  section headers, level = pipe count, "AUTO" annotation;
#   - TWO poetry notations: PDL "# <n> hemi1 %~% hemi2" (Hafiz) and legacy
#     "# % hemi1 % hemi2 % <n>" with "% %" empty fields (Diwan);
#   - inline/standalone PageVNNPNNN (variable padding) and msNN milestones —
#     citation structure, stripped from text but never lost;
#   - editorial content that STAYS verbatim: meter notes (البحر : طويل),
#     folio notes (73 ظ), footnote digits fused to words, guillemets.
class OpenitiMarkdownParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("openiti")
  HADITH = File.join(FIXTURES, "0390AbuFarajCukbari.Hadith.ShamAY0032805-ara1")
  DIWAN = File.join(FIXTURES, "0001AbuTalibCabdManaf.Diwan.JK007501-ara1")
  ZIYADAT = File.join(FIXTURES, "0500Anonymous.ZiyadatMakhtutatTarikhJurjan.Shamela0011077BK2-ara1.mARkdown")
  JUMAL = File.join(FIXTURES, "0646IbnNamawarKhunaji.JumalFiMantiq.JK010719-ara1")
  HAFIZ = File.join(FIXTURES, "0792Hafiz.Muntasab.PDL00074-per1")
  IBN_SINA = File.join(FIXTURES, "0428IbnSina.RisalaJudiya.AOCP202502141162-per1")
  ALL = [HADITH, DIWAN, ZIYADAT, JUMAL, HAFIZ, IBN_SINA].freeze

  def parser
    Nabu::Adapters::OpenitiMarkdownParser.new
  end

  # --- header: the four-vocabulary #META# block stays opaque ----------------

  def test_shamela_arabic_keyed_meta_survives_as_opaque_raw_lines
    header = parser.header(HADITH)
    assert_equal 20, header.meta_lines.size
    assert_equal "#META# ملاحظة: [هذا الكتاب من كتب المستودع بموقع المكتبة الشاملة]",
                 header.meta_lines.first
    assert_includes header.meta_lines, "#META# المتوفى: حوالي سنة 390ه"
    assert_includes header.meta_lines, "#META# DownloadSource: Abū Yaʿqūb's Shamela database",
                    "Arabic keys, Latin keys and free prose coexist — no key=value model fits"
  end

  def test_kitab_numbered_meta_survives_verbatim_including_the_tab
    header = parser.header(DIWAN)
    assert_equal "#META# 000.SortField\t:: JK_007501", header.meta_lines.first,
                 "the KITAB vocabulary separates key and '::' with a literal TAB — verbatim capture keeps it"
    assert_includes header.meta_lines, "#META# 020.BookTITLE\t:: ديوان أبو طالب"
  end

  def test_pdl_minimal_meta_survives_as_its_three_lines
    assert_equal ["#META# title: montasab",
                  "#META# ed_info: Ed. n.n. (n.d.), , Ganjoor corpus: n.n..",
                  "#META# url: https://ganjoor.net/hafez/montasab/"],
                 parser.header(HAFIZ).meta_lines
  end

  def test_escriptorium_ocr_meta_survives_as_opaque_raw_lines
    header = parser.header(IBN_SINA)
    assert_equal 6, header.meta_lines.size
    assert_includes header.meta_lines, "#META# Creator: escriptorium"
    assert_includes header.meta_lines, "#META# transcription layer name: kraken:all_arabic_scripts"
  end

  def test_a_shamela_bom_is_stripped_before_the_magic_check_and_recorded
    assert parser.header(HADITH).bom, "the hadith carries a real leading U+FEFF"
    refute parser.header(DIWAN).bom
  end

  # --- structural breakage is ParseError ------------------------------------

  def test_missing_magic_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { parser.header(StringIO.new("not a mARkdown file\n")) }
    assert_match(/magic/, error.message)
  end

  def test_unterminated_meta_header_is_a_parse_error
    input = "######OpenITI#\n#META# title: x\n# body text without a header end\n"
    assert_raises(Nabu::ParseError) { parser.header(StringIO.new(input)) }
    assert_raises(Nabu::ParseError) { parser.body(StringIO.new(input)) }
  end

  def test_invalid_utf8_is_a_parse_error
    input = "######OpenITI#\n#META#Header#End#\n# bad \xFF\xFE bytes\n".b
    assert_raises(Nabu::ParseError) { parser.body(StringIO.new(input)) }
  end

  # --- prose units: "#" + "~~" grain ----------------------------------------

  def test_paragraphs_and_wrapped_lines_become_units_with_single_space_joins
    units = parser.body(JUMAL).units
    assert_equal "بسم الله الرحمن الرحيم", units[0].text
    assert_equal :prose, units[0].kind
    assert_includes units[2].text, "محمد ابن نامور الشهير بالخونجى",
                    "the ~~ wrap joins with a single space (محمد | ابن نامور)"
  end

  def test_hash_tilde_continuations_join_the_open_unit
    body = parser.body(IBN_SINA)
    basmala = body.units.find { |u| u.text.start_with?("بم الله") }
    assert_equal "بم الله الرحمن الرحیم وبه نستعین الحمد لله رب العالمین والصلوة علی خیرخلقه محمد و آله اجمعین",
                 basmala.text,
                 "the OCR file's '# ~~' shape is a continuation, not a new unit"
  end

  def test_an_empty_continuation_line_adds_nothing
    unit = parser.body(ZIYADAT).units.find { |u| u.text.include?("سمعت سفيان الثوري") }
    assert_includes unit.text, "يقول ما رأيت أحدا أورع في الحديث من جابر",
                    "a bare '~~' line between the wrap parts injects no stray text"
  end

  def test_editorial_content_stays_verbatim
    ziyadat = parser.body(ZIYADAT).units
    assert_includes ziyadat.map(&:text), "...", "the upstream ellipsis paragraph is canonical text"
    assert(ziyadat.any? { |u| u.text.include?("روى بن شاهين1 بإسناده") },
           "footnote digits fused to words stay")
    assert(ziyadat.any? { |u| u.text.include?("[67/ألف] بسم الله الرحمن الرحيم") },
           "bracketed folio notes stay")
    jumal = parser.body(JUMAL).units
    assert(jumal.any? { |u| u.text.include?("(73 وجه)") }, "inline folio notes stay")
    ibn_sina = parser.body(IBN_SINA).units
    assert(ibn_sina.any? { |u| u.text.include?("مسمی بجودیه1که") },
           "OCR footnote digit fused inside a word stays")
    assert(ibn_sina.any? { |u| u.text.include?("حاشیه از صفحهآ قبل»") },
           "guillemet marginalia stays")
  end

  def test_hadith_body_has_the_censused_unit_grain
    units = parser.body(HADITH).units
    assert_equal 10, units.size, "1 section header + 9 paragraphs"
    first_hadith = units.find { |u| u.text.start_with?("1) أخبرنا") }
    assert_includes first_hadith.text, "\" تلمظ الفقير عند الشهوة",
                    "the hadith ordinal '1)' and the quote marks are text, not markup"
    assert_includes first_hadith.text, "أو قال : سبعين عاما"
  end

  # --- section headers -------------------------------------------------------

  def test_section_header_levels_are_the_pipe_count
    units = parser.body(ZIYADAT).units
    assert_equal :section_header, units[1].kind
    assert_equal 1, units[1].level
    assert_equal "فوائد ثبتت في نسخة الأصل وليست من تاريخ جرجان ولا تتعلق به جمعناها هنا", units[1].text
    assert_equal :section_header, units[2].kind
    assert_equal 2, units[2].level
    assert_equal ["ذكر أبان بن أبي عياش والخلاف فيه",
                  "أسد بن عمرو البجلي قاضي واسط والخلاف فيه",
                  "جابر الجعفي والكلام فيه",
                  "ذكر جعفر بن سليمان الضبعي"],
                 units.select { |u| u.level == 2 }.map(&:text)
  end

  def test_units_carry_the_enclosing_section_path
    units = parser.body(ZIYADAT).units
    assert_equal [], units[0].section_path, "the opening paragraph precedes any header"
    late = units.find { |u| u.text.include?("جعفر بن سليمان الضبعي ثقة يتشيع") }
    assert_equal ["فوائد ثبتت في نسخة الأصل وليست من تاريخ جرجان ولا تتعلق به جمعناها هنا",
                  "ذكر جعفر بن سليمان الضبعي"],
                 late.section_path,
                 "a same-level header replaces its sibling; the level-1 parent stays"
  end

  def test_auto_annotation_is_extracted_from_a_section_header
    units = parser.body(HADITH).units
    assert_equal :section_header, units[0].kind
    assert_equal 1, units[0].level
    assert_equal "الجزء من حديث", units[0].text
    assert_equal({ "auto" => true }, units[0].annotations)
    assert_equal ["الجزء من حديث"], units[3].section_path
  end

  # --- poetry: both notations -----------------------------------------------

  def test_pdl_notation_splits_hemistichs_with_the_leading_verse_number
    unit = parser.body(HAFIZ).units[0]
    assert_equal :verse, unit.kind
    assert_equal 1, unit.verse_number
    assert_equal ["ما برفتیم تو دانی و دل غمخور ما",
                  "بخت بد تا به کجا می برد آبشخور ما"],
                 unit.hemistichs, "the ~~ wrap joins before the %~% split"
  end

  def test_pdl_verse_numbering_restarts_per_poem
    units = parser.body(HAFIZ).units
    assert_equal 3, units.count { |u| u.verse_number == 1 },
                 "three ghazals in the trim, delimited only by the numbering reset"
  end

  def test_legacy_notation_splits_hemistichs_with_the_trailing_verse_number
    units = parser.body(DIWAN).units
    assert_equal :prose, units[0].kind
    assert_equal "البحر : متقارب تام 1", units[0].text, "the meter note is a plain paragraph"
    assert_equal :verse, units[1].kind
    assert_equal 2, units[1].verse_number
    assert_equal ["تطاول ليلي بهم وصب", "ودمع كسح السقاء السرب"], units[1].hemistichs
  end

  def test_legacy_empty_percent_fields_drop_without_minting_hemistichs
    unit = parser.body(DIWAN).units[2]
    assert_equal 3, unit.verse_number
    assert_equal ["للعب قصي بأحلامها", "وهل يرجع الحلم بعد اللعب ؟"], unit.hemistichs,
                 "'% %' is an empty field, not an empty hemistich"
  end

  def test_legacy_trailing_field_without_a_number_stays_as_content
    unit = parser.body(DIWAN).units.find { |u| u.hemistichs&.first == "عليها كرام بني هاشم" }
    assert_nil unit.verse_number
    assert_equal ["عليها كرام بني هاشم", "هم الأنجبون مع المنتخب", "البحر : طويل 1"],
                 unit.hemistichs,
                 "fixture reality: the next poem's meter note rides the last field of the " \
                 "page-final verse — canonical means canonical, it stays in the unit"
  end

  # --- page markers: citation structure, stripped but never lost ------------

  def test_a_trailing_page_marker_covers_the_whole_preceding_text
    units = parser.body(HADITH).units
    assert(units.all? { |u| u.volume == 1 && u.page == 1 },
           "PageVNNPNNN is an END-of-page marker: the single PageV01P001 places every unit")
    assert_equal [[1, 1]], units.last.page_breaks, "the page closes at the last unit"
  end

  def test_an_inline_page_marker_is_stripped_recorded_and_retro_assigned
    units = parser.body(DIWAN).units
    verse11 = units.find { |u| u.verse_number == 11 }
    assert_equal ["ورمتم بأحمد ما رمتمو", "على الأصرات وقرب النسب"], verse11.hemistichs,
                 "PageV01P001 vanishes from the verse fields"
    assert_equal [1, 1], [verse11.volume, verse11.page]
    assert_equal [[1, 1]], verse11.page_breaks
    assert(units.take(10).all? { |u| u.page == 1 }, "everything before the marker is page 1")
    assert_equal 2, units[11].page, "after PageV01P001 ends page 1, the next units start on page 2"
  end

  def test_two_digit_pdl_padding_parses_the_same
    units = parser.body(HAFIZ).units
    ninth = units.find { |u| u.verse_number == 9 }
    assert_equal "گو به زاری سفری کرد و برفت از بر ما", ninth.hemistichs.last
    assert_equal [1, 1], [ninth.volume, ninth.page], "PageV01P01 — 2-digit padding, same marker"
    assert_equal [[1, 1]], ninth.page_breaks
  end

  def test_a_standalone_page_marker_line_updates_position_without_minting_a_unit
    units = parser.body(ZIYADAT).units
    assert_equal "قال المؤتمن: لما بلغ هنا سمعت هذه الزيادات.", units[0].text
    assert_equal [1, 548], [units[0].volume, units[0].page], "the bare PageV01P548 line places it"
    assert_equal 550, units[1].page,
                 "units after the 548 marker start on the page the NEXT marker (550) closes"
    isnad = units.find { |u| u.text.include?("روى بن شاهين1 بإسناده") }
    assert_equal 550, isnad.page
    assert_equal [[1, 550]], isnad.page_breaks, "the page break falls mid-unit and is kept"
  end

  def test_units_after_the_last_marker_have_no_page
    unit = parser.body(IBN_SINA).units.find { |u| u.text.include?("ازخوردن بسیار معده") }
    assert_nil unit.page, "the body trim cut the closing marker off — honestly unplaced"
    assert_nil unit.volume
    placed = parser.body(IBN_SINA).units.find { |u| u.text == "سالهآ جودیه" }
    assert_equal [1, 1], [placed.volume, placed.page], "the standalone PageV01P001 places what precedes it"
  end

  def test_no_unit_text_or_hemistich_carries_a_marker
    ALL.each do |path|
      parser.body(path).units.each do |unit|
        strings = [unit.text, *unit.hemistichs]
        strings.each do |s|
          refute_match(/PageV\d+P\d+/, s, "#{File.basename(path)}: page marker leaked into text")
          refute_match(/(?<![A-Za-z0-9])ms\d+(?![A-Za-z0-9])/, s,
                       "#{File.basename(path)}: milestone leaked into text")
        end
      end
    end
  end

  # --- milestones ------------------------------------------------------------

  def test_milestones_are_stripped_and_recorded_on_their_unit
    jumal = parser.body(JUMAL).units.find { |u| u.milestones.any? }
    assert_equal ["ms1"], jumal.milestones
    assert_includes jumal.text, "حمل على غيرها ايضا كان عرضا عاما",
                    "the inline ms1 is removed without scarring the prose"
    assert_includes jumal.text, "(73 ظ)", "the folio note two words later stays"
    hafiz = parser.body(HAFIZ).units.find { |u| u.milestones.any? }
    assert_equal ["ms1"], hafiz.milestones
    assert_equal "ز چشم عشق توان دید روی شاهد غیب", hafiz.hemistichs.first,
                 "ms1 sat mid-hemistich (ز ms1 چشم) — stripped, single space restored"
  end

  def test_a_milestone_on_a_bare_trailing_line_attaches_to_the_last_unit
    units = parser.body(HADITH).units
    assert_equal ["ms1"], units.last.milestones, "the 'PageV01P001 ms1' closing line"
    assert(units[0..-2].all? { |u| u.milestones.empty? })
  end

  def test_variable_milestone_padding_is_kept_verbatim
    input = <<~MARKDOWN
      ######OpenITI#
      #META#Header#End#
      # alpha ms01 beta PageV02P0159 gamma
    MARKDOWN
    unit = parser.body(StringIO.new(input)).units[0]
    assert_equal "alpha beta gamma", unit.text
    assert_equal ["ms01"], unit.milestones
    assert_equal [2, 159], [unit.volume, unit.page]
  end

  # --- OCR image references --------------------------------------------------

  def test_page_image_references_are_censused_and_kept_out_of_text
    body = parser.body(IBN_SINA)
    assert_equal({ "image" => 2 }, body.census)
    assert(body.units.none? { |u| u.text.include?("![") })
  end

  # --- loud census ------------------------------------------------------------

  def test_the_real_fixtures_census_clean
    [HADITH, DIWAN, ZIYADAT, JUMAL, HAFIZ].each do |path|
      assert_empty parser.body(path).census, File.basename(path)
    end
  end

  def test_spec_only_tags_are_censused_not_fatal
    input = <<~MARKDOWN
      ######OpenITI#
      #META# title: doctored census probe
      #META#Header#End#
      ### $BIO_MAN$ 748 Trjmt
      # $RWY$ isnad text here
      ### |EDITOR|
      stray bare text line
      ## half marker
      # normal para
      ~~wrapped tail
    MARKDOWN
    body = parser.body(StringIO.new(input))
    assert_equal({ "##" => 1, "### $BIO_MAN$" => 1, "### |EDITOR|" => 1,
                   "$RWY$" => 1, "bare-line" => 1 }, body.census)
    assert_includes body.units.map(&:text), "$RWY$ isnad text here",
                    "no fixture teaches the riwāyāt semantics — the tag stays in the text, counted"
    assert_includes body.units.map(&:text), "stray bare text line",
                    "bare lines are censused loudly but their text is not dropped"
    assert_includes body.units.map(&:text), "normal para wrapped tail"
  end

  # --- NFC at the boundary ---------------------------------------------------

  def test_output_text_is_nfc_clean_across_all_six_fixtures
    ALL.each do |path|
      parser.body(path).units.each do |unit|
        assert_equal Nabu::Normalize.nfc(unit.text), unit.text,
                     "#{File.basename(path)}: Arabic/Persian here is NOT NFC-exempt"
      end
      parser.header(path).meta_lines.each do |line|
        assert_equal Nabu::Normalize.nfc(line), line
      end
    end
  end

  def test_decomposed_input_normalizes_at_the_parser_boundary
    input = "######OpenITI#\n#META#Header#End#\n# \u0627\u0653\n"
    unit = parser.body(StringIO.new(input)).units[0]
    assert_equal "\u0622", unit.text, "alef + combining maddah composes to U+0622"
  end

  # --- stability -------------------------------------------------------------

  def test_two_parses_of_the_same_file_are_identical
    first = parser.body(ZIYADAT)
    second = parser.body(ZIYADAT)
    assert_equal first.units, second.units
    assert_equal first.census, second.census
  end
end
