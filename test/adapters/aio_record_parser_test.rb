# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::AioRecordParser (P154): one Attic Inscriptions Online
# record pair (API JSON + inscription page) → the Greek document (where AIO
# publishes its own text) and the -en translation document. Ground truth is
# the real fixture pairs under test/fixtures/aio/records (README):
# aio-2103 = AIUK 11 no. 9 (Greek + translation, 175/6 AD), aio-2586 = SEG
# 46.153 (translation only, 341/0 BC, terms + a Pleiades placeName),
# aio-3869 = IG II2 5271 (translation only, "2nd century BC", a persName
# and an inline rubric).
class AioRecordParserTest < Minitest::Test
  RECORDS = File.expand_path("../fixtures/aio/records", __dir__)

  def parser = Nabu::Adapters::AioRecordParser.new

  def record(number) = File.join(RECORDS, "aio-#{number}.json")

  def parse(number, translation: false)
    urn = "urn:nabu:aio:#{number}#{'-en' if translation}"
    parser.parse(record(number), urn: urn)
  end

  # --- layers --------------------------------------------------------------------

  def test_layers_read_the_api_record
    assert_equal %w[greek translation], Nabu::Adapters::AioRecordParser.layers(record(2103))
    assert_equal %w[translation], Nabu::Adapters::AioRecordParser.layers(record(2586)),
                 "an SEG-based record translates a print edition and carries no Greek"
  end

  # --- the Greek document ----------------------------------------------------------

  def test_the_greek_edition_parses_line_by_line
    document = parse(2103)
    assert_equal "grc", document.language
    assert_equal "List of ephebic friends", document.title
    assert_equal 12, document.passages.size
    first = document.passages.first
    assert_equal "urn:nabu:aio:2103:p1:1", first.urn
    assert_equal "ἐπὶ ἄρχοντος Κλαυδίου Ἡρακλεί", first.text, "expan reads abbr+ex expanded"
    fifth = document.passages[4]
    assert_equal "καὶ συστάται αὑτοὺς ἀνέ", fifth.text
    assert_equal "5", fifth.annotations["line"], "upstream's own <lb n=\"5\"/> label rides the annotation"
    assert_equal({ "supplied_chars" => 1 }, fifth.annotations["leiden"])
    assert_equal({ "n" => "1" }, first.annotations["textpart"])
  end

  def test_the_greek_document_carries_the_record_axes
    meta = parse(2103).metadata
    assert_equal({ "raw" => "175/6 AD", "not_before" => 175, "not_after" => 176 }, meta["date"])
    assert_equal({ "ancient" => "Athens", "pleiades" => "579885" }, meta["place"],
                 "the Pleiades-linked findspot wins over the ToposText-only original location")
    assert_equal "[Diogeneion?]", meta["original_location"]
    assert_equal({ "values" => ["List of names"], "raw" => "List of names" }, meta["facets"]["genre"])
    assert_equal({ "values" => ["Stele"], "raw" => "Stele" }, meta["facets"]["object_type"])
    assert_equal "AIUK 11 (Ashmolean Museum, Oxford) no. 9", meta["citation"]
    assert_equal ["Chris de Lisle"], meta["translators"]
    assert_equal "CC BY-SA 3.0", meta["license"]
    assert_equal "https://www.atticinscriptions.com/inscription/AIUK11/9", meta["url"]
    refute meta.key?("kind"), "the Greek is the edition, not a translation"
  end

  # --- the translation document -------------------------------------------------------

  def test_the_translation_of_a_greek_bearing_record_leaves_the_axes_to_the_edition
    document = parse(2103, translation: true)
    assert_equal "eng", document.language
    meta = document.metadata
    assert_equal "translation", meta["kind"]
    assert_equal "urn:nabu:aio:2103", meta["translation_of"]
    refute meta.key?("date"), "the axes ride the primary (Greek) document only"
    refute meta.key?("facets")
    assert_match(/George Wheler/, meta["notes"]["1"], "the page's footnote text rides metadata")
    line = document.passages.find { |passage| passage.annotations["notes"] }
    assert_equal "themselves:", line.text, "the footnote marker never enters the text"
    assert_equal ["1"], line.annotations["notes"]
  end

  def test_the_translation_renders_rubrics_and_pairs_terms
    passages = parse(2103, translation: true).passages
    assert_equal "of Melite (175/6), the superintendent being", passages[1].text,
                 "an already-parenthesized inline rubric reads verbatim"
    assert_equal [{ "text" => "superintendent", "translit" => "kosmēteuontos" }], passages[1].annotations["terms"]
    assert_equal "(uninscribed space) of Philaidai", passages[11].text,
                 "a bare rubric reads in parentheses, as the page renders it"
  end

  def test_a_translation_only_record_carries_the_axes_on_the_translation
    document = parse(2586, translation: true)
    assert_equal "Decree of Halai Araphenides honouring choregoi, 341/0 BC", document.title,
                 "the title's inline HTML (<i>choregoi</i>) is stripped"
    meta = document.metadata
    assert_equal({ "raw" => "341/0 BC", "not_before" => -341, "not_after" => -340 }, meta["date"],
                 "the archon year straddles two Julian years")
    assert_equal({ "ancient" => "Dionysion", "pleiades" => "579940" }, meta["place"])
    assert_equal ["Decree"], meta["facets"]["genre"]["values"]
    assert_equal 19, document.passages.size
    places = document.passages[2].annotations["places"]
    assert_equal "579940", places.first["pleiades"]
  end

  def test_a_persname_ref_and_a_line_of_rubric
    document = parse(3869, translation: true)
    assert_equal({ "raw" => "2nd century BC", "not_before" => -200, "not_after" => -101 }, document.metadata["date"])
    refute document.metadata.key?("place"), "Findspot: Unknown places nothing"
    assert_equal "Unknown (EM 11614)", document.metadata["findspots"].first["text"]
    persons = document.passages.first.annotations["persons"]
    assert_equal "https://athnames.org/r4.php?id=42762", persons.first["ref"]
    assert_equal "(relief)", document.passages.last.text
  end

  # --- identity --------------------------------------------------------------------

  def test_a_greek_urn_on_a_translation_only_record_quarantines
    error = assert_raises(Nabu::ParseError) { parse(2586) }
    assert_match(/no greek_epidoc/, error.message)
  end

  def test_a_urn_the_filename_does_not_mint_quarantines
    assert_raises(Nabu::ParseError) { parser.parse(record(2586), urn: "urn:nabu:aio:2103-en") }
  end

  def test_aio_key_drift_quarantines
    Dir.mktmpdir do |dir|
      data = JSON.parse(File.read(record(2586)))
      File.write(File.join(dir, "aio-2586.json"), JSON.generate(data.merge("aio_key" => "AIO_1")))
      FileUtils.cp(File.join(RECORDS, "aio-2586.html"), dir)
      error = assert_raises(Nabu::ParseError) { parser.parse(File.join(dir, "aio-2586.json"), urn: "urn:nabu:aio:2586-en") }
      assert_match(/aio_key drift/, error.message)
    end
  end

  def test_a_missing_page_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.cp(record(2586), dir)
      error = assert_raises(Nabu::ParseError) { parser.parse(File.join(dir, "aio-2586.json"), urn: "urn:nabu:aio:2586-en") }
      assert_match(/inscription page .* is missing/, error.message)
    end
  end

  # --- the Inscription type heads ------------------------------------------------------

  def test_type_heads_split_outside_parentheses_and_drop_qualifiers
    heads = ->(raw) { Nabu::Adapters::AioRecordParser.type_heads(raw) }
    assert_equal ["Decree"],
                 heads.call("Decree 1 (People?), Decree 2 (Cleruchy Hephaistia), Decree 3 (Cleruchy Hephaistia)")
    assert_equal ["Statue base", "Metrical"], heads.call("Statue base, Metrical (elegaic couplets)")
    assert_equal ["Dedication"],
                 heads.call("1: Dedication (deme Halai Aixonides), 2: Dedication (deme Halai Aixonides)")
    assert_equal ["Dedication"], heads.call("Dedication (private, Amynos), Dedication (private, Asklepios)")
    assert_equal ["Graffito?", "Topos-inscription?"], heads.call("Graffito?, Topos-inscription?")
    assert_equal ["List of names"], heads.call("List of names (Council)")
  end
end

# The AIO "Date:" grammar (the 2026-11-02 80-page sample census).
class AioDateTest < Minitest::Test
  def bounds(raw) = Nabu::Adapters::AioDate.bounds(raw)

  def test_archon_years_and_single_years
    assert_equal [-352, -351], bounds("352/1 BC")
    assert_equal [175, 176], bounds("175/6 AD")
    assert_equal [-432, -432], bounds("432 BC")
    assert_equal [-236, -235], bounds("236/5? BC")
    assert_equal [132, 132], bounds("132 AD")
  end

  def test_ranges_decades_and_circa
    assert_equal [-350, -325], bounds("ca. 350-325 BC")
    assert_equal [-153, -143], bounds("153/2–144/3 BC")
    assert_equal [-286, -262], bounds("286–262? BC")
    assert_equal [-300, -262], bounds("300–262 BC(?)")
    assert_equal [220, 239], bounds("220s-230s AD?")
    assert_equal [-470, -460], bounds("ca. 470-60 BC"), "a short range end borrows the head's digits"
    assert_equal [-101, -88], bounds("ca. 101-88 BC"), "…but never backwards in its era"
  end

  def test_centuries_with_the_house_halves
    assert_equal [-200, -101], bounds("2nd century BC")
    assert_equal [-375, -326], bounds("Mid-iv BC")
    assert_equal [-400, -351], bounds("Early 4th cent. BC")
    assert_equal [1, 300], bounds("1st-3rd century AD")
    assert_equal [101, 300], bounds("ii-iii AD")
    assert_equal [-400, -301], bounds("iv BC ?")
  end

  def test_alternatives_take_the_envelope_and_inherit_the_era
    assert_equal [-30, -16], bounds("30/29 BC or 17/6 BC")
    assert_equal [-354, -343], bounds("ca. 354/3 or 344/3 BC")
  end

  def test_open_ended_and_eraless_prose_stay_raw
    assert_nil bounds("Shortly after 403 BC")
    assert_nil bounds("Before mid-4th cent. BC (?)")
    assert_nil bounds("mid-4th cent. BC or later")
    assert_nil bounds("350-300"), "no era anywhere — never guessed"
    assert_nil bounds("30 BC - AD 14"), "a mixed-era range is declared residue"
    assert_nil bounds("")
  end
end
