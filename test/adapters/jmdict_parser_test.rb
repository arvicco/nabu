# frozen_string_literal: true

require "test_helper"

# The edrdg-xml family, JMdict half (P32-4): one entry per <entry> keyed by
# ent_seq, kanji-first headwords with kana-only fallback, and the
# internal-DTD entity expansion (&n; → prose) via the NOENT reader.
class JmdictParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("edrdg")

  def entries
    @entries ||= File.open(File.join(FIXTURES, "JMdict_e.xml")) do |io|
      Nabu::Adapters::JmdictParser.new.entries(io)
    end
  end

  def by_id
    @by_id ||= entries.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_one_entry_per_ent_seq_in_file_order
    assert_equal %w[1000000 1150410 1318970 1358280 1366410 1438210
                    1667700 2291580 2853279 2860641 2860645 2863934].sort,
                 entries.map(&:entry_id).sort
    assert_equal entries.map(&:entry_id).uniq, entries.map(&:entry_id)
  end

  def test_kanji_first_headword_with_first_gloss
    love = by_id.fetch("1150410")
    assert_equal "愛", love.headword
    assert_equal "jpn", love.language
    assert_equal "love", love.gloss
    assert_match(/^kanji: 愛/, love.body)
    assert_match(/^readings: /, love.body)
  end

  def test_kana_only_entries_fall_back_to_the_first_reading
    mark = by_id.fetch("1000000")
    assert_equal "ヽ", mark.headword
    assert_equal "repetition mark in katakana", mark.gloss
  end

  def test_pos_entities_expand_to_prose_never_raw_entity_names
    mark = by_id.fetch("1000000")
    assert_includes mark.body, "(unclassified)",
                    "&unc; must expand through the internal DTD (NOENT)"
    entries.each { |entry| refute_match(/&[a-z-]+;/, entry.body) }
  end

  def test_senses_are_numbered_with_their_glosses
    taberu = by_id.fetch("1358280")
    assert_match(/^1\. /, taberu.body)
    assert_includes taberu.body, "eat"
  end

  # P123-1: sense-level <xref> pointers become "see" crossrefs; the target
  # is the first "・" part (the keb/reb this parser keys headwords by).
  def test_xref_pointers_mint_see_crossrefs
    love = by_id.fetch("1150410")
    assert_equal([["see", "see 愛する", "愛する"], ["see", "see アガペー・1", "アガペー"]],
                 love.crossrefs.map { |c| [c.kind, c.label, c.target] })
    assert_equal Nabu::Normalize.search_form("アガペー", language: "jpn"), love.crossrefs.last.target_folded
    assert_empty by_id.fetch("1358280").crossrefs, "an entry without xref/ant mints none"
  end

  # The sense labels become entry annotations — the entity texts the DTD
  # expands them to (NOENT), deduped across senses in document order:
  # <field> domains, <misc> usage marks, <dial> dialects.
  def test_field_misc_and_dial_labels_become_annotations
    assert_equal({ "field" => ["law"], "misc" => ["historical term"] }, by_id.fetch("1667700").annotations)
    assert_equal({ "misc" => ["archaic"], "dial" => ["Kansai-ben"] }, by_id.fetch("2863934").annotations)
    assert_equal %w[Buddhism Christianity], by_id.fetch("1150410").annotations["field"],
                 "one value per distinct label across the entry's senses"
    assert_empty by_id.fetch("1358280").annotations, "an unlabeled entry carries no annotations"
  end

  # <lsource>: the donor code verbatim (an absent xml:lang is the DTD
  # default "eng"); wasei-eigo sources are their own annotation.
  def test_loanword_sources_annotate_the_donor_code
    assert_equal %w[ger], by_id.fetch("2860641").annotations["lsource"]
    assert_equal %w[eng fre], by_id.fetch("2860645").annotations["lsource"]
    assert_equal %w[rus], by_id.fetch("2853279").annotations["lsource"]
    calc = by_id.fetch("2291580").annotations
    assert_equal({ "field" => ["computing"], "wasei" => ["eng"] }, calc)
  end

  # Genuine loans with a source word mint donor-language reflexes,
  # borrowed: true (the WOLD donor-edge pattern): lang_code verbatim,
  # language the ISO 639-3 tag the catalog speaks. A wasei source is no
  # loan of that word and an empty <lsource/> names no word — neither
  # mints an edge.
  def test_loanword_sources_with_a_word_mint_borrowed_donor_reflexes
    prozent = by_id.fetch("2860641").reflexes
    assert_equal([["ger", "deu", "Pro(zent)", true]],
                 prozent.map { |r| [r.lang_code, r.language, r.word, r.borrowed] })
    assert_equal Nabu::Normalize.search_form("Pro(zent)", language: "deu"), prozent.first.word_folded
    assert_equal([%w[eng eng pie], %w[fre fra choux]],
                 by_id.fetch("2860645").reflexes.map { |r| [r.lang_code, r.language, r.word] })
    assert_empty by_id.fetch("2291580").reflexes, "wasei: a made-in-Japan word, not a loan"
    assert_empty by_id.fetch("2853279").reflexes, "an empty lsource names no donor word"
  end

  # The labels also read in the sense line (the body was POS + glosses
  # only): bracketed labels, then the loan source.
  def test_sense_lines_carry_labels_and_loan_sources
    assert_match(/^1\. \(noun \(common\) \(futsuumeishi\)\) \[law; historical term\] misdemeanor$/,
                 by_id.fetch("1667700").body)
    assert_includes by_id.fetch("2860645").body, "← eng pie (part); fre choux (part)"
    assert_includes by_id.fetch("2291580").body, "← wasei eng calc"
    assert_includes by_id.fetch("2853279").body, "← rus"
  end

  def test_output_is_nfc
    entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
      refute_empty entry.body
    end
  end
end
