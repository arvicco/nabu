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
