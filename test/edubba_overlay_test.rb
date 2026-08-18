# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::EdubbaOverlay (P72-6): the sister school's didactic overlay read
# seam — the extraction contract's stable fields, the 101/102 voice
# divergence folded honestly, codex front matter merged, certainty
# grade carried. Fixtures are trimmed REAL Edubba files.
class EdubbaOverlayTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("edubba-overlay")

  def overlay
    @overlay ||= Nabu::EdubbaOverlay.new(FIXTURES)
  end

  def test_h101_entries_carry_the_contract_fields
    entry = overlay["G43"]
    assert_equal "chick", entry.keyword
    assert_equal "quail chick", entry.label
    assert_equal "w / u", entry.voice
    assert_equal "sound", entry.voice_kind, "H101 teaches by sound"
    assert_equal "classic", entry.certainty
    assert_equal ["Z7"], entry.confusables
    assert_equal "H101", entry.course
    assert_equal 4, entry.chapter
  end

  def test_codex_front_matter_merges_with_deep_link_and_body_stays_out
    entry = overlay["G43"]
    assert_equal "G43 · chick", entry.title
    assert_match(/quail chick/, entry.description)
    assert_equal "https://edubba.ac/hieroglyphs/addenda/signs/g43/", entry.link

    # A codex-only sign (a24 has no pool row in the trimmed fixture set)
    # still gets an entry from front matter alone.
    a24 = overlay["A24"]
    assert_equal "A24 · effort", a24.title
    assert_match(%r{/signs/a24/\z}, a24.link)
  end

  def test_certainty_unclear_is_preserved_verbatim
    entry = overlay["AA1"]
    assert_equal "unclear", entry.certainty, "the never-present-as-fact grade must survive load"
  end

  def test_code_lookup_is_case_insensitive_and_misses_are_nil
    assert_equal overlay["G43"], overlay["g43"]
    assert_nil overlay["Z99"]
  end

  # -- the cuneiform lanes (P77-8, Q25): the school's FIRST subject joins --

  def test_c101_sign_teaching_entries_carry_the_richest_record
    entry = overlay.cuneiform("AŠ")
    assert_equal "𒀸", entry.glyph
    assert_equal "12038", entry.codepoint
    assert_equal "one", entry.keyword
    assert_equal "aš (ash/asz)", entry.value
    assert_equal "one; single", entry.meaning
    assert_match(/atomic horizontal wedge/, entry.iconicity)
    assert_equal "classic", entry.certainty
    assert_equal %w[DIŠ U], entry.confusables
    assert_equal "C101", entry.course
    assert_equal 5, entry.chapter, "taught_in is C101's chapter key"
  end

  def test_c102_and_c103_pools_load_with_their_own_chapter_key
    e_sign = overlay.cuneiform("E")
    assert_equal "levee", e_sign.keyword
    assert_equal "C102", e_sign.course
    assert_equal 1, e_sign.chapter
    assert_equal ["É"], e_sign.confusables
    sza = overlay.cuneiform("ŠA")
    assert_equal "C103", sza.course
    assert_equal "which", sza.keyword
    assert_equal "unclear", sza.certainty, "the never-present-as-fact grade survives"
    assert_nil sza.iconicity, "iconicity is a C101-only lane"
  end

  def test_cuneiform_osl_name_indexes_the_card_join
    nin = overlay.cuneiform("|SAL.TUG2|")
    refute_nil nin, "the card holds the OSL name — the osl_name field must index"
    assert_equal "NIN", nin.name
    assert_equal nin, overlay.cuneiform("NIN"), "both keys reach the same entry"
    assert_equal overlay.cuneiform("|IGI.DIB|"), overlay.cuneiform("U3")
  end

  def test_cuneiform_codex_pages_merge_from_both_addenda_dirs
    nin = overlay.cuneiform("NIN")
    assert_match(/NIN/, nin.title)
    assert_equal "https://edubba.ac/cuneiform/addenda/signs/nin/", nin.link
    sza = overlay.cuneiform("ŠA")
    assert_match(%r{/addenda-akk/signs/sza/\z}, sza.link, "the Akkadian addenda dir merges too")
    a_sign = overlay.cuneiform("A")
    refute_nil a_sign, "a codex-only sign (no pool row in the trim) still gets an entry"
    assert_match(/water/, a_sign.title)
    assert_nil a_sign.keyword
  end

  def test_cuneiform_lookup_is_case_insensitive_and_separate_from_hiero
    assert_equal overlay.cuneiform("NIN"), overlay.cuneiform("nin")
    assert_nil overlay.cuneiform("ZZZ")
    assert_nil overlay["NIN"], "the hiero lookup never answers for a cuneiform name"
  end

  def test_load_default_feature_detects
    Dir.mktmpdir do |root|
      config = Nabu::Config.load(path: File.join(root, "config", "nabu.yml"), root: root)
      assert_nil Nabu::EdubbaOverlay.load_default(config: config), "unsynced module -> nil, never an error"

      dest = File.join(root, "canonical", "edubba-overlay")
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp_r(FIXTURES, dest)
      loaded = Nabu::EdubbaOverlay.load_default(config: config)
      refute_nil loaded
      assert_operator loaded.size, :>=, 5
    end
  end
end
