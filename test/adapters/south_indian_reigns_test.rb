# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/adapters/south_indian_reigns"

# Nabu::SouthIndianReigns: the South-Indian regnal accession table —
# config/south_indian_reigns.yml rows (one cited chronology per dynasty,
# accession RANGES kept) turning the DHARMA titles' regnal statements
# ("time of Rājarāja I Cōḻa, year 19") into CE envelopes. Homonyms convert
# as the envelope over their candidate reigns; alternating titles and
# floating chronologies mint nothing. Every title below is a verbatim
# DHARMA title spelling from the dharma-tamil census.
class SouthIndianReignsTest < Minitest::Test
  def teardown = Nabu::SouthIndianReigns.reset!

  def table = Nabu::SouthIndianReigns.default

  def bounds(title, year)
    conversion = table.convert(title, year)
    conversion && [conversion.not_before, conversion.not_after]
  end

  def test_the_shipped_table_loads_with_a_source_per_dynasty
    refute_nil table, "config/south_indian_reigns.yml is repo config"
    assert_operator table.size, :>=, 40
    table.reign_keys.each do |key|
      refute_empty table.source(key).to_s, "#{key}: every reign cites its dynasty's chronology"
    end
    assert_match(/Nilakanta Sastri, The Cōḷas/, table.source("chola_rajaraja_1"))
    assert_match(/Mahalingam/, table.source("pallava_kampavarman"))
    assert_match(/Sethuraman/, table.source("pandya_maravarman_sundara_1"))
  end

  def test_a_single_accession_year_n_straddles_two_julian_years
    assert_equal [1003, 1004], bounds("Rājarāja I Cōḻa", 19),
                 "accession 985: year 19 runs from the 1003 anniversary into 1004"
    assert_equal [907, 908], bounds("Parāntaka I", 1)
  end

  def test_an_accession_range_widens_the_envelope_never_picks
    assert_equal [866, 877], bounds("Kampavarman", 2),
                 "Kampavarman's accession is held as 865–875: year 2 = [866, 877]"
  end

  def test_a_homonym_converts_as_the_envelope_over_its_candidates
    conversion = table.convert("Kulottuṅga Cōḻa", 5)
    assert_equal [1074, 1183], [conversion.not_before, conversion.not_after],
                 "Kulottuṅga I, II or III: the union, never a pick"
    assert_equal %w[chola_kulottunga_1 chola_kulottunga_2 chola_kulottunga_3], conversion.reigns
  end

  def test_a_regnal_year_beyond_a_candidates_reign_drops_that_candidate
    conversion = table.convert("Rājādhirāja", 31)
    assert_equal %w[chola_rajadhiraja_1], conversion.reigns,
                 "Rājādhirāja II's reign (1163/6–1179) never reached year 31"
    assert_equal [1048, 1049], [conversion.not_before, conversion.not_after]
    assert_equal %w[pallava_nandivarman_2], table.convert("Nandivikramavarman", 61).reigns,
                 "only Nandivarman II reigned 61 years"
  end

  def test_a_year_beyond_every_candidate_mints_nothing
    assert_nil table.convert("Vikrama Cōḻa", 40), "Vikrama Cōḻa reigned 1118–1136"
  end

  def test_an_envelope_wider_than_the_cap_mints_nothing
    assert_equal 150, table.max_envelope, "the table's ruled ceiling"
    assert_nil table.convert("Rājendra Cōḻa", 29),
               "Rājendra I (1040/41) or Rājendra III (1274/75): a 235-year union says less than the dynasty"
    assert_nil table.convert("Rājādhirāja", nil), "Rājādhirāja I–II whole span 1018–1179 exceeds the cap"
    refute_nil table.convert("Rājādhirāja", 6), "year 6 keeps the union inside the cap (1023–1172)"
  end

  def test_no_year_is_the_whole_reign_span
    assert_equal [1509, 1529], bounds("Vīrapratāpa Kr̥ṣṇadeva Mahārāya", nil)
    assert_equal [731, 869], bounds("Nandivikramavarman", nil), "a homonym's year-less span covers every candidate"
  end

  def test_titles_match_after_nfc_case_and_space_folding
    assert_equal bounds("Rājarāja I Cōḻa", 3), bounds("rājarāja i  cōḻa", 3)
    assert_equal bounds("Rājarāja I Cōḻa", 3), bounds("Rājarāja I Cōḻa".unicode_normalize(:nfd), 3)
  end

  def test_alternating_titles_and_floating_chronologies_mint_nothing
    assert_nil table.convert("Rājakesarivarman", 9), "ten Cōḻa kings bore Rājakesari"
    assert_nil table.convert("Parakesarivarman", 3)
    assert_nil table.convert("Māṟaṉ Caṭaiyaṉ", 4), "the alternating first-empire Pāṇḍya title"
    assert_nil table.convert("Nandivarman", 1), "the bare name covers the early Nandivarman I"
    assert_nil table.convert("Siṁhavarman", 11), "early Pallava chronology floats"
    assert_nil table.convert("Mahendravarman (?)", 5), "an editor's doubt is not converted"
    assert_nil table.convert("Tammusiddhi", 1), "an unlisted ruler: never a guess"
    assert table.unconvertible?("Parakesarivarman")
    refute table.unconvertible?("Rājarāja I")
  end

  def test_no_spelling_is_both_convertible_and_declared_unconvertible
    table.title_keys.each do |title|
      refute table.unconvertible?(title), "#{title}: both a title row and declared unconvertible"
    end
  end

  def test_regnal_year_reads_the_censused_year_shapes
    year = ->(text) { Nabu::SouthIndianReigns.regnal_year(text) }
    assert_equal 9, year.call("9")
    assert_equal 17, year.call("17 ")
    assert_equal 13, year.call("4 + 9"), "the 'year N opposite to year M' count reads as the sum"
    assert_equal 8, year.call("7+1")
    assert_equal 7, year.call("4 + 1 + 1 + 1")
    assert_equal 29, year.call("29 (SII 2.1)"), "a trailing reference is not part of the year"
    assert_equal 5, year.call("(5)")
    assert_equal 3, year.call("3rd")
    [nil, "lost", "[figure lost]", "2[.]", "4[0]", "3?", "40 something", "unclear", "Kara", "X", "0"].each do |text|
      assert_nil year.call(text), "#{text.inspect} gives no number: the whole-reign span applies"
    end
  end

  def test_load_validates_rows
    Dir.mktmpdir do |dir|
      path = File.join(dir, "reigns.yml")
      File.write(path, <<~YAML)
        dynasties: { d: { label: D, source: S } }
        reigns: { r: { label: R, dynasty: d, accession: [900, 890], end: 950 } }
        titles: {}
      YAML
      assert_raises(ArgumentError) { Nabu::SouthIndianReigns.load(path) }
      File.write(path, <<~YAML)
        dynasties: { d: { label: D, source: S } }
        reigns: { r: { label: R, dynasty: d, accession: 900, end: 950 } }
        titles: { T: [missing] }
      YAML
      assert_raises(ArgumentError) { Nabu::SouthIndianReigns.load(path) }
      assert_nil Nabu::SouthIndianReigns.load(File.join(dir, "absent.yml"))
    end
  end
end
