# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::CdliSignReadings (P65-1): the read seam over the CDLI sign-reading
# concordance that rides INSIDE the held OSL repo
# (canonical/osl/00etc/cdli_sign_readings.tsv, CC0 with the repo) — sign
# name → readings with the CDLI meaning gloss ("A → n. water"), the one
# humanist-gloss column the ASL itself lacks. CDLI spells names and
# readings in C-ATF ASCII (SZESZ, szesz, 'a3); the seam folds BOTH to the
# OSL spelling (ŠEŠ, šeš, ʾa₃) so card-side joins need no fold of their
# own. Fixture: trimmed REAL rows from the held file.
class CdliSignReadingsTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("osl"), "00etc", "cdli_sign_readings.tsv")

  def readings
    @readings ||= Nabu::CdliSignReadings.load(FIXTURE)
  end

  def test_readings_are_keyed_by_the_folded_osl_sign_name
    rows = readings.readings_for("ŠEŠ")
    assert_equal %w[mun₄ ses šeš uri₃], rows.map(&:reading),
                 "CDLI ASCII readings (mun4, szesz, uri3) folded to OSL spelling, file order"
    assert_empty readings.readings_for("SZESZ"), "the ASCII spelling is folded away at load"
  end

  def test_the_meaning_gloss_rides_where_cdli_has_one_and_is_nil_where_not
    rows = readings.readings_for("ŠEŠ")
    assert_equal "n. brother", rows.find { |r| r.reading == "šeš" }.meaning
    assert_nil rows.find { |r| r.reading == "ses" }.meaning, "empty gloss column → nil, never \"\""
  end

  def test_compound_names_and_apostrophes_fold_too
    assert_equal ["abgal"], readings.readings_for("|NUN.ME|").map(&:reading)
    assert_includes readings.readings_for("E₂").map(&:reading), "ʾa₃",
                    "'a3 folds to ʾa₃ (the C-ATF apostrophe)"
  end

  def test_every_held_row_is_preferred_the_2026_08_09_census
    assert readings.readings_for("ŠEŠ").all?(&:preferred),
           "the whole upstream file carries preferred_reading=1 (censused 2026-08-09)"
  end

  def test_load_default_is_nil_without_the_held_file
    Dir.mktmpdir do |dir|
      config = Nabu::Config.load(root: dir)
      assert_nil Nabu::CdliSignReadings.load_default(config: config)
    end
  end
end
