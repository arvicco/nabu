# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The oshb-lexicon parser family (P30-1): the four openscriptures/
# HebrewLexicon XML files in the OSHB project's own namespace. Two public
# surfaces: #strongs_entries assembles the augmented-Strong shelf from
# AugIndex (entry ids) + LexicalIndex (headword/xlit/pos/gloss/xrefs) +
# HebrewStrong (the full Strong body); #bdb_entries reads the BDB outline
# with its <status p> print-page anchors. Fixtures are byte-verbatim slices
# of the real files (see test/fixtures/hebrew-lexicon/README.md).
class OshbLexiconParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("hebrew-lexicon")

  # בָּרָא as upstream ships it - bet, dagesh, qamats … - NOT NFC
  # (NFC swaps to qamats-dagesh); escapes so no editor can reorder it.
  BARA = "\u05D1\u05BC\u05B8\u05E8\u05B8\u05D0"

  def parser = Nabu::Adapters::OshbLexiconParser.new

  def strongs
    @strongs ||= parser.strongs_entries(
      aug_path: File.join(FIXTURES, "AugIndex.xml"),
      lexical_index_path: File.join(FIXTURES, "LexicalIndex.xml"),
      strong_path: File.join(FIXTURES, "HebrewStrong.xml")
    )
  end

  def bdb
    @bdb ||= parser.bdb_entries(File.join(FIXTURES, "BrownDriverBriggs.xml"))
  end

  def strong_entry(id) = strongs.find { |e| e.entry_id == id }
  def bdb_entry(id) = bdb.find { |e| e.entry_id == id }

  # --- the augmented-Strong shelf -----------------------------------------------

  def test_strongs_yields_one_entry_per_aug_row_in_file_order
    assert_equal 43, strongs.size
    assert_equal %w[7 410 413], strongs.first(3).map(&:entry_id)
    assert_equal strongs.map(&:entry_id).uniq, strongs.map(&:entry_id)
  end

  def test_entry_ids_are_augmented_strong_ids_verbatim
    # THE JOIN CONTRACT: the @aug value IS what an OSHB lemma normalizes to
    # ("b/1254 a" → "1254a") — kept verbatim, never renumbered.
    assert_includes strongs.map(&:entry_id), "1254a"
    assert_includes strongs.map(&:entry_id), "l"
  end

  def test_the_bara_entry_assembles_all_three_files
    e = strong_entry("1254a")
    # Headword: the LexicalIndex citation form, BYTE-VERBATIM — upstream is
    # dagesh-before-qamats, which NFC would reorder (P26-3 ruling).
    assert_equal BARA, e.headword
    refute e.headword.unicode_normalized?(:nfc)
    assert_equal "hbo", e.language
    assert_equal "bxy", e.key_raw, "key_raw carries the upstream LexicalIndex id"
    assert_equal "shape", e.gloss
    assert_equal <<~BODY.strip, e.body
      xlit: bārāʾ
      pos: V
      source: a primitive root;
      meaning: (absolutely) to create; (qualified) to cut down (a wood), select, feed (as formative processes)
      usage: choose, create (creator), cut down, dispatch, do, make (fat).
      strong: 1254
      aug: a
      bdb: b.cw.aa
      twot: 278
    BODY
    assert_empty e.citations, "the Strong shelf mints no citation rows (BDB pages live on the bdb shelf)"
  end

  def test_the_particle_l_has_no_hebrew_strong_entry_and_falls_back_to_the_index
    # One of the eight non-numeric particle ids (the OSHB prefix morphemes):
    # no HebrewStrong entry exists, so the body is the LexicalIndex lane only.
    e = strong_entry("l")
    assert_equal "לְ", e.headword
    assert_equal "to", e.gloss
    assert_equal <<~BODY.strip, e.body
      xlit: lĕ
      pos: R
      strong: l
      bdb: l.aa.ab
      twot: 1063
    BODY
  end

  def test_aramaic_entries_take_arc_from_the_lexical_index_part
    census = strongs.group_by(&:language).transform_values(&:size)
    assert_equal({ "hbo" => 28, "arc" => 15 }, census)
    jegar = strong_entry("3026a")
    assert_equal "arc", jegar.language
    assert_equal "heap", jegar.gloss
    assert_match(/^source: \(Aramaic\)/, jegar.body)
  end

  def test_proper_noun_entries_keep_the_lexical_index_part_language
    # HebrewStrong tags proper nouns xml:lang="x-pn" (not a language);
    # the entry language comes from the LexicalIndex part (heb → hbo).
    bethel = strong_entry("1008")
    assert_equal "hbo", bethel.language
    assert_match(/meaning: Beth-El, a place in Palestine/, bethel.body)
  end

  def test_headword_folded_is_the_minted_search_form
    e = strong_entry("1254a")
    assert_equal Nabu::Normalize.search_form(e.headword, language: "hbo"), e.headword_folded
    assert_equal "ברא", e.headword_folded, "niqqud falls to the generic mark strip"
  end

  def test_inline_w_refs_flatten_to_their_text
    assert_match(/source: from 1004 and 410; house of God;/, strong_entry("1008").body)
  end

  def test_strongs_is_stable_across_independent_parses
    snapshot = lambda do
      parser.strongs_entries(
        aug_path: File.join(FIXTURES, "AugIndex.xml"),
        lexical_index_path: File.join(FIXTURES, "LexicalIndex.xml"),
        strong_path: File.join(FIXTURES, "HebrewStrong.xml")
      ).map { |e| [e.entry_id, e.headword, e.body] }
    end
    assert_equal snapshot.call, snapshot.call
  end

  # --- damage stays loud --------------------------------------------------------

  def test_dangling_aug_target_is_a_parse_error
    Dir.mktmpdir do |dir|
      aug = File.join(dir, "AugIndex.xml")
      File.write(aug, File.read(File.join(FIXTURES, "AugIndex.xml"))
                          .sub("aqq", "zzz"))
      error = assert_raises(Nabu::ParseError) do
        parser.strongs_entries(
          aug_path: aug,
          lexical_index_path: File.join(FIXTURES, "LexicalIndex.xml"),
          strong_path: File.join(FIXTURES, "HebrewStrong.xml")
        )
      end
      assert_match(/zzz/, error.message)
    end
  end

  def test_missing_strong_entry_for_a_numeric_base_is_a_parse_error
    # Upstream measures 0 missing — a numeric base without its HebrewStrong
    # entry is damage, never silently glossed over.
    Dir.mktmpdir do |dir|
      strong = File.join(dir, "HebrewStrong.xml")
      File.write(strong, File.read(File.join(FIXTURES, "HebrewStrong.xml"))
                             .sub(%(<entry id="H1254">), %(<entry id="H99991254">)))
      assert_raises(Nabu::ParseError) do
        parser.strongs_entries(
          aug_path: File.join(FIXTURES, "AugIndex.xml"),
          lexical_index_path: File.join(FIXTURES, "LexicalIndex.xml"),
          strong_path: strong
        )
      end
    end
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "AugIndex.xml")
      File.write(bad, "<index><w aug=\"1\">aac</w>")
      assert_raises(Nabu::ParseError) do
        parser.strongs_entries(
          aug_path: bad,
          lexical_index_path: File.join(FIXTURES, "LexicalIndex.xml"),
          strong_path: File.join(FIXTURES, "HebrewStrong.xml")
        )
      end
    end
  end

  # --- the BDB outline shelf ----------------------------------------------------

  def test_bdb_yields_every_outline_entry_in_file_order
    assert_equal 19, bdb.size
    assert_equal %w[a.aa.aa a.aa.ab a.ab.aa], bdb.first(3).map(&:entry_id)
  end

  def test_the_bara_outline_entry_carries_senses_and_the_print_page
    e = bdb_entry("b.cw.aa")
    assert_equal BARA, e.headword
    assert_equal "hbo", e.language
    assert_equal "shape", e.gloss, "gloss is the first def"
    lines = e.body.lines.map(&:chomp)
    assert_equal "mod: I", lines[0]
    assert_equal "type: root", lines[1]
    assert_equal "#{BARA} 53 vb. shape, create", lines[2]
    assert_includes lines, "Qal Pf.—shape, fashion, create"
    assert_includes lines, "1. be created"
    assert_includes lines, "2. cut out"
    refute_match(/\bbase\b/, e.body, "the <status> workflow value is metadata, not body text")
    assert_equal ["BDB p. 135"], e.citations.map(&:label)
    assert_equal ["135"], e.citations.map(&:citation)
    assert_equal [nil], e.citations.map(&:cts_work), "print pages resolve to nothing until the 1906 scan lands"
  end

  def test_a_mid_entry_page_turn_mints_a_second_citation_row
    # a.ac.aa (אבד perish) spans the p.1→2 turn: <status p="1"> + the rare
    # mid-entry <page p="2"/> (one of two in the whole upstream file).
    e = bdb_entry("a.ac.aa")
    assert_equal ["BDB p. 1", "BDB p. 2"], e.citations.map(&:label)
    assert_equal %w[1 2], e.citations.map(&:citation)
  end

  def test_aramaic_parts_take_arc
    census = bdb.group_by(&:language).transform_values(&:size)
    assert_equal({ "hbo" => 16, "arc" => 3 }, census)
    e = bdb_entry("xa.ab.aa")
    assert_equal "arc", e.language
    assert_equal "אֲבַד", e.headword
  end

  def test_cross_reference_entries_without_defs_have_nil_gloss
    e = bdb_entry("a.aa.ab")
    assert_nil e.gloss
    assert_match(/v\. II\./, e.body)
  end

  def test_bdb_scripture_refs_read_as_display_text_in_the_body
    # <ref r="Job.8.12">Jb 8:12</ref> keeps its display text; the machine @r
    # is deliberately not minted this packet (print pages only — P30-1).
    assert_match(/Jb 8:12/, bdb_entry("a.ab.ab").body)
  end

  def test_bdb_is_stable_across_independent_parses
    snapshot = -> { parser.bdb_entries(File.join(FIXTURES, "BrownDriverBriggs.xml")).map(&:entry_id) }
    assert_equal snapshot.call, snapshot.call
  end

  def test_bdb_headwords_keep_upstream_bytes
    non_nfc = bdb.reject { |e| e.headword.unicode_normalized?(:nfc) }
    refute_empty non_nfc, "the fixture must carry non-NFC Masoretic headwords"
    non_nfc.each { |e| assert e.headword.valid_encoding? }
  end
end
