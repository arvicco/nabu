# frozen_string_literal: true

require "test_helper"

# The calfa-tsv parser family: the Calfa definitions tables
# (calfa-co/lexical-databases definitions/ + definitions_proper/) — a
# Title / Complement / POS_n / Definition_n table, TAB-separated with
# CSV-style quoting (a quoted field may carry a TAB or doubled quotes),
# CRLF line ends, and a small inline markup set (<letter>, <a href>,
# <ab>, <fr>, <i>, <br />). All pins run on the real trimmed fixture rows.
class CalfaTsvParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("calfa-lexicon")

  def parse(relative, id_prefix: nil)
    text = File.read(File.join(FIXTURES, relative), encoding: "UTF-8")
    Nabu::Adapters::CalfaTsvParser.new.entries(text, language: "xcl", id_prefix: id_prefix,
                                                     label: relative)
  end

  def en = parse("definitions/en-definitions01.tsv")
  def fr = parse("definitions/fr-definitions01.tsv")

  def by_id(entries) = entries.to_h { |entry| [entry.entry_id, entry] }

  def test_every_row_is_one_entry_in_upstream_order
    assert_equal 14, en.size, "15 fixture lines minus the header"
    assert_equal 13, fr.size, "14 fixture lines minus the header"
    assert_equal %w[Ա Ա՜ Աբ Աբաս *Աբեղուկ Աբիոն Ակն Ակն:2 Ակն:3 Ահաբեկ Ահաբեկեմ Անտի Բնութիւն Տրամագիծ],
                 en.map(&:entry_id),
                 "headword ids; homographs take the occurrence suffix (the house idiom)"
  end

  def test_the_letter_row_strips_its_markup_and_keeps_the_raw_title
    letter = en.first
    assert_equal "<letter>Ա</letter> (aïp)", letter.key_raw, "the upstream Title verbatim"
    assert_equal "Ա", letter.headword, "the <letter> markup and the letter-name gloss leave the headword"
    assert_equal Nabu::Normalize.search_form("Ա", language: "xcl"), letter.headword_folded
    assert_match(/\(aïp\)/, letter.body, "the letter name stays readable in the body")
  end

  def test_body_carries_the_complement_and_numbered_senses_with_pos
    abion = by_id(en).fetch("Աբիոն")
    assert_equal "Աբիոն, ացի\n1. (adj.) poor; Ebionitan;\n2. (np.) Ebion.", abion.body
    assert_equal "poor", abion.gloss, "the first sense up to its first semicolon"
    assert_equal({ "pos" => %w[adj. np.] }, abion.annotations)
  end

  def test_an_empty_pos_cell_is_honest
    entry = by_id(en).fetch("Տրամագիծ")
    assert_equal "Տրամագիծ\n1. cf. Տրամաչափ.", entry.body
    assert_equal({}, entry.annotations, "no POS upstream — no pos annotation")
    fr_entry = by_id(fr).fetch("Աղօտ")
    assert_match(/^2\. ընդ —, adv\. obscurément\.$/, fr_entry.body, "an empty POS_2 cell renders bare")
  end

  def test_the_asterisk_mark_rides_the_headword_and_an_annotation_never_the_fold
    star = by_id(en).fetch("*Աբեղուկ")
    assert_equal "*Աբեղուկ", star.headword, "upstream's middle/pre-modern mark stays on display"
    assert_equal Nabu::Normalize.search_form("Աբեղուկ", language: "xcl"), star.headword_folded
    assert_equal "*", star.annotations.fetch("headword_mark")
  end

  def test_inline_markup_is_read_not_kept
    anti = by_id(en).fetch("Անտի")
    assert_includes anti.body, "tho world to come; pl. the blessings", "<ab> unwraps (upstream typo 'tho' kept)"
    bnut = by_id(en).fetch("Բնութիւն")
    assert_match(/own head \?\n {3}բնութեամբ, naturally/, bnut.body, "<br /> opens an indented continuation line")
    ayl = by_id(fr).fetch("Այլանդակ")
    assert_match(/\(adj\.\) bizarre, étrange, drôle/, ayl.body, "<fr> unwraps")
    ner = by_id(fr).fetch("Ներ")
    assert_includes ner.body, "belle-sœur (ainsi s'appellent", "<i> unwraps"
    [en, fr].flatten.each { |entry| refute_match(%r{<[a-z/]}, entry.body, entry.entry_id) }
  end

  def test_anchor_links_mint_cf_crossrefs_by_headword
    entry = by_id(en).fetch("Ահաբեկեմ")
    assert_equal "Ահաբեկեմ, եցի\n1. (va.) cf. Ահաբեկ առնել.", entry.body,
                 "the doubled quotes of upstream's CSV quoting decode; the anchor reads as its label"
    assert_equal 1, entry.crossrefs.size
    ref = entry.crossrefs.first
    assert_equal ["cf.", "Ահաբեկ առնել", "Ահաբեկ"], [ref.kind, ref.label, ref.target]
    assert_equal Nabu::Normalize.search_form("Ահաբեկ", language: "xcl"), ref.target_folded
    assert_empty by_id(en).fetch("Աբաս").crossrefs, "plain-text 'cf. Աբբայ.' is prose, not a machine pointer"
  end

  def test_a_tab_inside_a_quoted_field_stays_inside_the_sense
    entry = by_id(fr).fetch("Վերստեայ")
    assert_equal "Վերստեայ\n1. (adj.) susdit, susnommé. .", entry.body,
                 "upstream's quoted TAB is whitespace inside Definition_1, never a column break"
  end

  def test_the_non_nfc_row_composes_at_the_boundary
    raw = File.read(File.join(FIXTURES, "definitions/fr-definitions01.tsv"), encoding: "UTF-8")
    refute raw.unicode_normalized?(:nfc), "the fixture carries upstream's e + U+0301 bytes"
    entry = by_id(fr).fetch("Տրամագիծ")
    assert entry.body.unicode_normalized?(:nfc)
    assert_includes entry.body, "édit"
    assert_equal "édit, décret, prescription", entry.gloss
  end

  def test_the_id_prefix_keeps_the_proper_name_lane_apart
    proper = parse("definitions_proper/en-definitions01.tsv", id_prefix: "np")
    assert_equal %w[np:Աբաս np:Աբգար np:Աբգարոս np:Յակոբ np:Յակոբ:2], proper.map(&:entry_id)
    assert_equal "Abas.", proper.first.gloss
    assert_equal "Յակոբ, բայ (նահապետն)\n1. (np.) Jacob.", proper[3].body
  end

  def test_a_header_mismatch_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CalfaTsvParser.new.entries("Word\tGloss\r\nԱ\ta\r\n", language: "xcl", label: "x.tsv")
    end
    assert_match(/header/, error.message)
  end

  def test_multiword_headwords_join_their_id_with_underscores
    entry = by_id(fr).fetch("*Ապրիմ_մեռնիմ")
    assert_equal "*Ապրիմ մեռնիմ", entry.headword
    assert_equal Nabu::Normalize.search_form("Ապրիմ մեռնիմ", language: "xcl"), entry.headword_folded
    assert_equal "*Ապրիմ մեռնիմ\n1. (sv.) cf. Երիցուկ.", entry.body
  end
end
