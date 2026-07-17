# frozen_string_literal: true

require "test_helper"

# RiigEpidocParser (P25-1): line-grain extraction of one RIIG EpiDoc record
# under the CelticLeiden reading-text policy — every editorial reading (seg)
# mints passages, choice keeps reg, word-internal pretty-print whitespace
# strips, <space/> divides, gaps mark, supplied/unclear count. All against
# the real fixture records (test/fixtures/riig/documents/).
class RiigEpidocParserTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("riig"), "documents")

  def parse(id)
    Nabu::Adapters::RiigEpidocParser.new.parse(
      File.join(FIXTURES, "#{id}.xml"), urn: "urn:nabu:riig:#{id.downcase}"
    )
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_mismatch_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::RiigEpidocParser.new.parse(
        File.join(FIXTURES, "AHP-01-01.xml"), urn: "urn:nabu:riig:wrong-01-01"
      )
    end
    assert_match(/urn mismatch/, error.message)
    assert_match(/ahp-01-01/, error.message)
  end

  # --- the Segomaros dedication (VAU-13-01, three concurring readings) --------

  def test_vau_13_01_mints_seven_lines_per_reading
    document = parse("VAU-13-01")
    assert_equal "xtg-Grek", document.language
    assert_equal 21, document.size, "three readings × seven lines"
    assert_equal %w[MLE-a PLT-a RIIG-a],
                 document.map { |p| p.annotations.dig("reading", "id") }.uniq
  end

  def test_vau_13_01_reg_branch_is_the_reading_text
    document = parse("VAU-13-01")
    line1 = document.find { |p| p.urn == "urn:nabu:riig:vau-13-01:MLE-a:1" }
    assert_equal "σεγομαρος", line1.text, "reg governs; orig's per-glyph letter forms drop"
    assert_equal "ουιλλονεος",
                 document.find { |p| p.urn == "urn:nabu:riig:vau-13-01:MLE-a:2" }.text
    assert_equal "νεμητον",
                 document.find { |p| p.urn == "urn:nabu:riig:vau-13-01:PLT-a:7" }.text
  end

  def test_vau_13_01_word_tokens_carry_the_msd_layer
    document = parse("VAU-13-01")
    words = document.find { |p| p.urn == "urn:nabu:riig:vau-13-01:MLE-a:1" }.annotations["words"]
    assert_equal [{ "form" => "σεγομαρος", "msd" => "sg m 2", "pos" => "NOM", "type" => "idionym" }],
                 words
  end

  def test_vau_13_01_reading_annotation_carries_resp_and_cert
    document = parse("VAU-13-01")
    reading = document.first.annotations["reading"]
    assert_equal "MLE-a", reading["id"]
    assert_equal "MLE", reading["resp"]
    assert_equal "medium", reading["cert"]
  end

  # --- alternative readings + mid-word gap (AHP-01-01) ------------------------

  def test_ahp_01_01_keeps_both_alternative_readings_apart
    document = parse("AHP-01-01")
    assert_equal %w[urn:nabu:riig:ahp-01-01:HRD-a:1 urn:nabu:riig:ahp-01-01:PTL-b:1],
                 document.map(&:urn)
    assert_equal "καρε[…]μ", document.first.text, "the gap marker fuses mid-word"
    assert_equal "καρβ[…]μ", document.to_a.last.text
  end

  def test_ahp_01_01_counts_unclear_and_records_the_gap
    document = parse("AHP-01-01")
    leiden = document.first.annotations["leiden"]
    assert_equal 1, leiden["unclear_chars"]
    assert_equal([{ "extent" => "unknown", "unit" => "character", "reason" => "lost" }],
                 leiden["gaps"].map { |gap| gap.slice("extent", "unit", "reason") })
  end

  # --- Gallo-Latin: expansions, surplus, break="no" (ALL-01-01) ---------------

  def test_all_01_01_gallo_latin_expansion_surplus_and_word_break
    document = parse("ALL-01-01")
    assert_equal "xtg-Latn", document.language
    plt = document.select { |p| p.annotations.dig("reading", "id") == "PLT-a" }
    assert_equal ["bratronos", "nanton{t}icnos", "epađateχto", "rici leucutio", "suiorebe logi", "toi"],
                 plt.map(&:text),
                 "abbr+ex read expanded, surplus wraps {}, break=no splits at the print margin"
  end

  # --- bilingual textparts + <space/> word division (GAR-10-03) ---------------

  def test_gar_10_03_latin_reading_language_and_space_division
    document = parse("GAR-10-03")
    assert_equal "xtg-Grek", document.language
    latin = document.find { |p| p.urn == "urn:nabu:riig:gar-10-03:MLE-2-a:2" }
    assert_equal "lat", latin.language, "seg xml:lang=la maps to 639-3 per passage"
    assert_equal "[…] ati votum solvit libens merito", latin.text,
                 "explicit <space/> divides words inside <w>; pretty-print whitespace strips"
    greek = document.find { |p| p.urn == "urn:nabu:riig:gar-10-03:MLE-1-a:2" }
    assert_equal "xtg-Grek", greek.language
    assert_equal "[…] βρατουδεκαντεν", greek.text
    assert_equal 9, greek.annotations.dig("leiden", "supplied_chars")
  end

  # --- header metadata --------------------------------------------------------

  def test_ahp_01_01_metadata_date_place_rig_and_tm
    metadata = parse("AHP-01-01").metadata
    assert_equal(-100, metadata.dig("date", "not_before"))
    assert_equal(-1, metadata.dig("date", "not_after"))
    assert_equal "low", metadata.dig("date", "cert")
    assert_equal "context", metadata.dig("date", "evidence")
    assert_equal "Chastelard de Lardiers", metadata.dig("place", "name")
    assert_equal "Lardiers", metadata.dig("place", "settlement")
    assert_equal "https://www.trismegistos.org/place/21492", metadata.dig("place", "ref")
    assert_equal "44,0655 5,688", metadata.dig("place", "geo"), "WGS84 verbatim, decimal comma included"
    assert_equal ["G593"], metadata["rig"], "the altIdentifier's G-593 dedupes on the compact spelling"
    assert_equal ["rig:G593"], metadata["related"]
    assert_equal "978943", metadata["tm"]
  end

  def test_ahp_01_01_facets_carry_value_and_vocabulary_uri
    facets = parse("AHP-01-01").metadata["facets"]
    assert_equal "Vasque", facets.dig("object_type", "value")
    assert_equal "https://www.eagle-network.eu/voc/objtyp/lod/144", facets.dig("object_type", "raw")
    assert_equal "pierre", facets.dig("material", "value")
    assert_equal "Indéterminé", facets.dig("genre", "value")
  end

  # --- translations ----------------------------------------------------------

  def test_vau_13_01_translations_cited_by_reading
    pairs = Nabu::Adapters::RiigEpidocParser.new.translations(File.join(FIXTURES, "VAU-13-01.xml"))
    assert_equal %w[MLE-a PLT-a], pairs.map(&:first), "one translation div per reading"
    assert_match(/Segomaros fils de Villo\(nos\), citoyen de Nîmes/, pairs.first.last)
    assert_match(/avec ses concitoyens/, pairs.last.last)
  end

  def test_ahp_01_01_has_no_translation_prose
    assert_empty Nabu::Adapters::RiigEpidocParser.new.translations(File.join(FIXTURES, "AHP-01-01.xml"))
  end
end
