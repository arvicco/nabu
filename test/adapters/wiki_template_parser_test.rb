# frozen_string_literal: true

require "test_helper"

# The wiki-template parser family (P29-3): Semantic-MediaWiki wikitext from
# the Vienna wiki pair (lexlep.univie.ac.at / tir.univie.ac.at) — template
# blocks, the censused reading grammar, and the prose scrub. Every literal
# here is byte-verbatim from the 2026-07-18 api.php probes (fixture
# READMEs); nothing is invented.
class WikiTemplateParserTest < Minitest::Test
  def parser
    Nabu::Adapters::WikiTemplateParser.new
  end

  BI8_WIKITEXT = File.read(
    File.join(Nabu::TestSupport.fixtures("lexlep"), "pages", "Inscription", "BI%C2%B78.json")
  ).then { |json| JSON.parse(json).fetch("wikitext") }

  # --- template extraction --------------------------------------------------

  def test_template_params_reads_the_inscription_block
    params = parser.template_params(BI8_WIKITEXT, "inscription")
    assert_equal "sipiu space koilios!koil&#91; space koilios!&#93;ios", params["reading"]
    assert_equal "BI·8 Cerrione", params["object"]
    assert_equal "dextroverse", params["direction"]
    assert_equal "Celtic", params["language"]
    assert_equal "funerary", params["type_inscription"]
  end

  def test_template_params_keeps_nested_templates_verbatim_in_values
    params = parser.template_params(BI8_WIKITEXT, "inscription")
    assert_includes params["reading_lepontic"], "{{c|K|K5|d}}"
  end

  def test_template_params_returns_nil_when_the_template_is_absent
    assert_nil parser.template_params("== Commentary ==\nplain prose", "inscription")
  end

  def test_template_params_handles_the_site_shape
    wikitext = <<~WIKI
      {{site
      |sigla=BZ
      |province=Bozen / Bolzano
      |coordinate_n=46.497978
      |coordinate_e=11.354783
      }}
    WIKI
    params = parser.template_params(wikitext, "site")
    assert_equal "BZ", params["sigla"]
    assert_equal "46.497978", params["coordinate_n"]
  end

  # --- the reading grammar (censused 2026-07-18, 200 inscriptions) ----------
  #
  # Lines split on " / "; tokens on whitespace; a token "A!B" renders B (the
  # diacritic-marked scholarly form — verified against the wiki's own HTML
  # rendering of AK-1.1 and BI·8) while A is the Word-page link form; the
  # literal token "space" is the word-divider marker (renders as a gap);
  # numeric character references decode.

  def test_reading_lines_renders_the_display_form_and_keeps_word_links
    lines = parser.reading_lines("sipiu space koilios!koil&#91; space koilios!&#93;ios")
    assert_equal 1, lines.size
    assert_equal "sipiu koil[ ]ios", lines.first.text
    assert_equal %w[sipiu koilios koilios], lines.first.words
  end

  def test_reading_lines_splits_lines_on_the_slash_separator
    lines = parser.reading_lines("tnake space piθamnu!p&#x0323;iθamu / laþe!laþe?")
    assert_equal 2, lines.size
    assert_equal "tnake p̣iθamu".unicode_normalize(:nfc), lines[0].text.unicode_normalize(:nfc)
    assert_equal %w[tnake piθamnu], lines[0].words
    assert_equal "laþe?", lines[1].text
    assert_equal ["laþe"], lines[1].words
  end

  def test_reading_lines_of_unknown_is_empty
    assert_empty parser.reading_lines("unknown")
    assert_empty parser.reading_lines("")
    assert_empty parser.reading_lines(nil)
  end

  def test_reading_lines_keeps_the_unknown_token_when_it_carries_a_display_form
    # AK-1.10 (tir): the link form is "unknown" but the rendered form exists.
    lines = parser.reading_lines("unknown!k&#x0323;e&#x0323;sa")
    assert_equal 1, lines.size
    assert_equal "ḳẹsa".unicode_normalize(:nfc), lines.first.text.unicode_normalize(:nfc)
    assert_empty lines.first.words, "an 'unknown' link form is not a Word-page link"
  end

  def test_reading_lines_keeps_the_single_illegible_marker
    # AK-1.12 (tir): reading "?" — upstream's notation for an illegible
    # inscription that still has a reading line. Canonical means canonical.
    lines = parser.reading_lines("?")
    assert_equal ["?"], lines.map(&:text)
  end

  def test_reading_lines_drops_whitespace_only_display_tokens
    # AK-1.13 (tir): a bare "!&nbsp;" token renders as whitespace only.
    lines = parser.reading_lines("!&#93;?e&#x0323;?&#91; !&nbsp; !&#93;n&#x0323;&#91;")
    assert_equal 1, lines.size
    assert_equal "]?ẹ?[ ]ṇ[".unicode_normalize(:nfc), lines.first.text.unicode_normalize(:nfc)
  end

  def test_reading_lines_drops_empty_trailing_lines
    # FI-1 (tir) ends "… / " — five declared lines, the last empty.
    lines = parser.reading_lines("a / b / ")
    assert_equal %w[a b], lines.map(&:text)
  end

  # --- prose scrub ----------------------------------------------------------

  def test_plain_flattens_bib_and_link_markup
    scrubbed = parser.plain(
      "First published in {{bib|Vitali & Kaenel 2000}}: 121. " \
      "See {{bib|Morandi 2004|2004}} and [[AO·1.2]]; per [[User:Corinna Salomon|Corinna Salomon]], ''anθine''."
    )
    assert_equal "First published in Vitali & Kaenel 2000: 121. " \
                 "See 2004 and AO·1.2; per Corinna Salomon, anθine.", scrubbed
  end

  def test_plain_drops_named_param_only_templates_and_html_tags
    assert_equal "Examined on 22nd April 2024.",
                 parser.plain("Examined on 22<sup>nd</sup> April 2024.\n{{sig\n|user=Sindy Kluge\n}}\n{{bibliography}}")
  end

  def test_plain_flattens_morpheme_and_word_templates
    # The real analysis_morphemic shape (Word acisius, 2026-07-18) plus the
    # empty-first-arg {{w||…}} shape (TIR Word aχvil).
    assert_equal "akis-i̯us See akisios and aχvil.".unicode_normalize(:nfc),
                 parser.plain("{{m|akis-}}{{m|-i̯us|i̯us}} See {{w|akisios}} and {{w||aχvil}}.")
                       .unicode_normalize(:nfc)
  end

  def test_section_returns_the_commentary_body
    wikitext = "{{inscription\n|reading=ap\n}}\n== Commentary ==\nFirst line.\n\nSecond line.\n{{bibliography}}"
    assert_equal "First line.\n\nSecond line.\n{{bibliography}}", parser.section(wikitext, "Commentary")
  end

  def test_section_tolerates_missing_space_in_the_heading
    assert_equal "Body.", parser.section("== Commentary==\nBody.", "Commentary")
    assert_nil parser.section("no sections here", "Commentary")
  end
end
