# frozen_string_literal: true

require "test_helper"

# The kanripo gaiji display ladder DATA TABLES (P38-1). Four rungs resolve each
# `&KR\d+;` reference per character: FAITHFUL real codepoint → IDS composition →
# SUBSTITUTE normalization → ⬚ placeholder. This packet ships lanes 1–3 as three
# DISJOINT config/gaiji tables; P38-2 renders the ladder. These tests pin the
# lanes' well-formedness, the (era-bound) census counts, and — mechanically —
# the exclusion policies each table's header states.
class GaijiTablesTest < Minitest::Test
  GAIJI_DIR = File.join(Nabu::Config::PROJECT_ROOT, "config", "gaiji")
  FAITHFUL  = File.join(GAIJI_DIR, "kanripo.tsv")
  SUBST     = File.join(GAIJI_DIR, "kanripo-substitutes.tsv")
  IDS       = File.join(GAIJI_DIR, "kanripo-ids.tsv")

  # Private-Use Area ranges — never a "real assigned codepoint" (they render as
  # tofu off the mandoku font; the honesty gate forbids shipping them as glyphs).
  def pua?(codepoint)
    (0xE000..0xF8FF).cover?(codepoint) ||
      (0xF0000..0xFFFFD).cover?(codepoint) ||
      (0x100000..0x10FFFD).cover?(codepoint)
  end

  # Ideographic Description Characters (the IDS operators U+2FF0–U+2FFB).
  def idc?(codepoint) = (0x2FF0..0x2FFB).cover?(codepoint)

  # Parse a lane the way Display.load_gaiji_map does, but keep every row so the
  # tests can see duplicates rather than silently collapsing them.
  def rows(path)
    File.readlines(path, encoding: Encoding::UTF_8).filter_map do |line|
      line = line.chomp
      next if line.empty? || line.start_with?("#")

      line.split("\t", -1)
    end
  end

  def refs(path) = rows(path).map { |r| r[0] }

  # --- well-formedness (all three lanes) ------------------------------------

  def test_every_data_row_is_ref_id_tab_glyph
    [FAITHFUL, SUBST, IDS].each do |path|
      rows(path).each do |cells|
        assert_equal 2, cells.size, "#{File.basename(path)} row must be exactly ref<TAB>value: #{cells.inspect}"
        assert_match(/\AKR\d+\z/, cells[0], "#{File.basename(path)} ref-id shape")
        refute cells[1].empty?, "#{File.basename(path)} value non-empty for #{cells[0]}"
      end
    end
  end

  def test_no_duplicate_refs_within_a_lane
    [FAITHFUL, SUBST, IDS].each do |path|
      ids = refs(path)
      assert_equal ids.uniq.size, ids.size,
                   "#{File.basename(path)} has duplicate refs: #{ids.tally.select { |_, n| n > 1 }.keys.inspect}"
    end
  end

  # --- the ladder invariant: the three shipped lanes are DISJOINT by ref -----
  #
  # Upstream DOES let a ref carry both a faithful glyph (col 3) and a substitute
  # (col 4) — 744 of the 983 col-3 rows do. The ladder resolves such a ref at its
  # highest rung (FAITHFUL wins), so the lower lanes deliberately EXCLUDE it: the
  # substitute lane holds only refs faithful can't render. Hence disjoint files.
  def test_lanes_are_disjoint_by_ref
    f = refs(FAITHFUL).to_set
    s = refs(SUBST).to_set
    i = refs(IDS).to_set
    assert_empty (f & s), "faithful∩substitute must be empty (faithful wins the ladder)"
    assert_empty (f & i), "faithful∩ids must be empty"
    assert_empty (s & i), "substitute∩ids must be empty"
  end

  # --- exclusion policies, enforced mechanically ----------------------------

  def test_faithful_and_substitute_glyphs_are_single_real_codepoints_in_nfc
    [FAITHFUL, SUBST].each do |path|
      rows(path).each do |id, g|
        where = "#{File.basename(path)} #{id}"
        assert_equal 1, g.codepoints.size, "#{where}: exactly one codepoint (#{g.inspect})"
        refute pua?(g.codepoints.first), "#{where}: no Private-Use codepoint (#{format('U+%04X', g.codepoints.first)})"
        assert_equal g.unicode_normalize(:nfc), g, "#{where}: stored NFC"
        refute_match(/[?？\[\],]/, g, "#{where}: no uncertainty/composition/list marks")
        refute_match(/\p{White_Space}/, g, "#{where}: no whitespace")
      end
    end
  end

  # The IDS lane is the ONE place a multi-codepoint value is legal, and only as a
  # well-formed IDS sequence (an IDC operator plus components). It ships empty
  # today (KR0198 resolved to an encoded char → faithful), so this guards the
  # shape Aozora (P38-3) will populate.
  def test_ids_lane_values_are_wellformed_ids_sequences
    rows(IDS).each do |id, seq|
      assert_operator seq.codepoints.size, :>, 1, "#{id}: an IDS sequence is more than one codepoint"
      assert(seq.codepoints.any? { |cp| idc?(cp) }, "#{id}: must contain an IDC operator (U+2FF0–2FFB)")
      assert_equal seq.unicode_normalize(:nfc), seq, "#{id}: stored NFC"
    end
  end

  # --- census pins (era-bound; recalibrate after a charlist refresh) ---------

  # census: 427, 2026-07-21, faithful refs (was 972 in P37-3; −547 private-use).
  def test_faithful_count_pinned
    assert_equal 427, refs(FAITHFUL).size
  end

  # census: 562, 2026-07-21, substitute refs.
  def test_substitute_count_pinned
    assert_equal 562, refs(SUBST).size
  end

  # census: 0, 2026-07-21, IDS refs (the sole charlist composition is faithful).
  def test_ids_count_pinned
    assert_equal 0, refs(IDS).size
  end

  # --- reconciliation landmarks (document the P38-1 findings as assertions) ---

  def test_faithful_carries_known_reconciled_refs
    map = rows(FAITHFUL).to_h
    assert_equal "𫠦", map["KR0001"], "the canonical faithful example ships"
    assert_equal "𦒿", map["KR0132"], "trailing-whitespace cell stripped and admitted (was excluded)"
    assert_equal "沔", map["KR0198"], "the mandoku composition resolved (via IDS) to encoded 沔"
    # compatibility ideographs NFC-folded to their unified codepoints:
    assert_equal "篆", map["KR0144"], "U+2F962 → U+7BC6"
    assert_equal "形", map["KR0305"], "U+2F899 → U+5F62"
  end

  def test_purged_private_use_refs_are_absent_from_every_lane
    # KR5254 / KR1643 were shipped in P37-3's faithful map as Private-Use glyphs.
    %w[KR5254 KR1643 KR4708].each do |id|
      refute_includes refs(FAITHFUL), id, "#{id} (Private-Use) purged from faithful"
    end
    # KR4711 carried a Private-Use "faithful" cell AND no clean substitute → gone.
    refute_includes refs(FAITHFUL), "KR4711"
  end

  def test_substitute_rescues_a_ref_whose_faithful_cell_was_private_use
    # KR4710's col-3 was Private-Use (purged from faithful) but col-4 is a clean
    # substitute (脊) — the ladder keeps it covered one rung down instead of tofu.
    assert_includes refs(SUBST), "KR4710", "a purged-faithful ref with a clean substitute stays covered"
    assert_equal "脊", rows(SUBST).to_h["KR4710"]
    refute_includes refs(FAITHFUL), "KR4710"
  end
end
