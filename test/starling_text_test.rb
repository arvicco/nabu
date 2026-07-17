# frozen_string_literal: true

require "test_helper"

# Nabu::StarlingText (P22-0): the StarLing → Unicode text decoder behind the
# starling-dbf parser family. Table-driven from the vendored unipro.lst
# (config/starling/README.md) — no byte meaning is guessed; every mapping
# asserted here was verified against the live starlingdb.org rendering of the
# same record on 2026-07-15 (the offending byte runs come verbatim from the
# fixture records, per the CLAUDE.md encoding-fix rule).
class StarlingTextTest < Minitest::Test
  def decode(bytes) = Nabu::StarlingText.decode(bytes)

  def test_the_vendored_tables_are_present
    assert_equal %w[unipro.lst chslav.lst], Nabu::StarlingText::TABLE_PATHS.map { |path| File.basename(path) },
                 "unipro.lst first (first mapping per byte sequence wins), then the Church Slavonic table"
    Nabu::StarlingText::TABLE_PATHS.each do |path|
      assert File.file?(path), "#{File.basename(path)} must ship with the repo (config/starling/README.md)"
    end
  end

  def test_plain_ascii_passes_through
    assert_equal "WP. I 1, WH. I 1.", decode(+"WP. I 1, WH. I 1.")
  end

  # pokorny #1 ROOT payload, verbatim: \B\I markup around the single-byte
  # \xB0 (unipro.lst: U+0101). Live web renders "ā" in bold italics.
  def test_style_markup_is_stripped_and_the_single_byte_page_decodes
    assert_equal "ā", decode(+"\\B\\I\xB0\\b\\i")
  end

  def test_a_lone_backslash_that_is_not_a_style_marker_survives
    assert_equal "a\\z", decode(+"a\\z")
  end

  # THE survey pin (.docs/surveys/pie-survey.md §3.1): the Greek font-shift run from
  # pokorny #1 MATERIAL. \x01 opens doublebyte set 1; \x83\xC2 is α and the
  # \x83\xC0 pair composes psili+perispomeni — unipro.lst maps the whole run
  # to U+1F06 ἆ. Verified against the live record (".. gr. ἆ Ausruf ..").
  def test_the_greek_font_shift_run_decodes_to_alpha_with_psili_and_perispomeni
    assert_equal "ἆ", decode(+"\x01\x83\xC2\x83\xC0")
  end

  # pokorny #34 MATERIAL: a full Greek word crosses SEVERAL doublebyte pairs
  # after ONE \x01 shift — the decoder must keep the mode across matches
  # (the table keys carry the shift byte only once). Web-verified: αἰγίλωψ.
  def test_a_greek_run_continues_across_pairs_without_repeating_the_shift
    bytes = +"\x01\x83\xC2\x83\xCA\x83\xA1\x83\xC8\x83\xCA\x83\x93\x83\xCD\x83\xD8\x83\xDA"
    assert_equal "αἰγίλωψ", decode(bytes)
  end

  def test_a_low_byte_terminates_the_doublebyte_mode
    assert_equal "α x", decode(+"\x01\x83\xC2 x")
  end

  def test_accented_greek_composes_to_nfc
    decoded = decode(+"\x01\x83\xC6\x83\x93")
    assert_equal "έ", decoded
    assert decoded.unicode_normalized?(:nfc)
  end

  # \x15 is the in-database paragraph mark (the live site renders it as <P>;
  # pokorny #1 MATERIAL separates language sections with it).
  def test_paragraph_mark_becomes_a_newline
    assert_equal "a;\nb", decode(+"a;\x15b")
  end

  def test_crlf_becomes_a_single_newline
    assert_equal "a\nb", decode(+"a\r\nb")
  end

  # pokorny #284 MATERIAL: "ags. bær" — \x1D introduces the extended-latin
  # two-byte escapes of unipro.lst.
  def test_the_extended_latin_escape_decodes
    assert_equal "bær", decode(+"b\x1Dar")
  end

  # piet #1 RUSMEAN: the single-byte Cyrillic page (CP866-derived).
  def test_single_byte_cyrillic_decodes
    assert_equal "утро", decode(+"\xE3\xE2\xE0\xAE")
  end

  # An alias row (unipro.lst maps \xB5 to the byte sequence "c" + \xDC):
  # resolved through the table itself, never hand-guessed.
  def test_alias_rows_resolve_through_the_table
    assert_equal "c̣", decode(+"\xB5")
  end

  # pokorny #1089 MATERIAL carries the corpus's ONE unmapped byte pair —
  # \x80\xA8 after τέλλω (an upstream stray; the official web converter
  # drops it silently). We mark it honestly instead of losing it.
  def test_the_unmapped_pair_from_the_corpus_becomes_a_replacement_character
    bytes = +"\x01\x83\xD5\x83\xC6\x83\x93\x83\xCD\x83\xCD\x83\xD8\x80\xA8"
    assert_equal "τέλλω�", decode(bytes)
  end

  # vasmer #1 GENERAL, verbatim (P23-0): the Church Slavonic font range —
  # \x01-shifted \x87/\x88 doublebyte pairs — is NOT in unipro.lst; its
  # official mapping is the package's second Unicode conversion table,
  # chslav.lst (config.str [Chslav font]), vendored beside unipro.lst.
  # Live web renders the run as азъ (the OCS citation for "я").
  def test_the_church_slavonic_font_range_decodes_through_the_chslav_table
    assert_equal "азъ", decode(+"\x01\x87\xBE\x87\xC8\x87\xB8")
  end

  # vasmer #489 GENERAL, verbatim: a whole OCS word in the chslav range —
  # багрѣница with the yat (U+0463) mid-word. Web-verified 2026-07-15.
  def test_a_chslav_word_with_yat_decodes_across_continuing_pairs
    bytes = +"\x01\x87\x84\x87\xBE\x87\xCD\x87\xC0\x87\xD5\x87\xD1\x87\xBA\x87\xCF\x87\xBE"
    assert_equal "багрѣница", decode(bytes)
  end

  # A stray high byte inside a per-character \x01-shifted run (vasmer #3364
  # GENERAL, verbatim: τέ[stray]νη — τέχνη missing its χ upstream) consumes
  # its pair — the \x01 it swallows would only have re-opened set 1, so the
  # following Greek decodes intact and the stray reads as one honest U+FFFD
  # (the corpus carries 28 such stray occurrences, all in vasmer; the
  # official web converter garbles them too — censused in P23-0).
  def test_a_stray_byte_before_a_reshift_marks_one_replacement_and_self_heals
    assert_equal "τέ�νη", decode(+"\x01\x83\xD5\x01\x83\xC6\x01\x83\x93\xF9\x01\x83\xCF\x01\x83\xC9")
  end

  # \x7F is StarLing's invisible doublebyte-flow breaker (encoding.htm) —
  # it must vanish AND terminate the shifted mode.
  def test_the_flow_breaker_is_invisible_and_ends_the_shifted_mode
    assert_equal "αx", decode(+"\x01\x83\xC2\x7Fx")
  end

  # Table sequences deliberately SPAN the mode transition: alpha + breaker +
  # single-byte macron is one unipro.lst entry (U+1FB1 ᾱ) — longest match
  # must win over the bare-alpha prefix.
  def test_table_sequences_spanning_the_flow_breaker_match_longest_first
    assert_equal "ᾱ", decode(+"\x01\x83\xC2\x7F\xC4")
  end

  def test_output_is_always_utf8_nfc
    decoded = decode(+"\x01\x83\xC2\x83\xC0 \xB0")
    assert_equal Encoding::UTF_8, decoded.encoding
    assert decoded.unicode_normalized?(:nfc)
  end

  def test_decoding_is_deterministic_across_calls
    bytes = +"\x01\x83\xC2\x83\xC0 \xB0\x15x"
    assert_equal decode(bytes), decode(bytes)
  end
end
