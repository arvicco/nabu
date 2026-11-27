# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# The dio-epidoc parser family: one Epigraf EpiDoc article of the
# Deutsche Inschriften (DI) volume dumps. Covers the Epigraf markup
# dialect (add = restored letters, supplied[omitted] = expanded
# abbreviation, del = the wrapper of a lost-text gap), the textpart grain
# with its per-inscription language/genre/script rows, the German date
# grammar of origDate, identity cross-checks, and the closed element set.
# Fixtures: three whole real articles (test/fixtures/dio-epidoc/README.md).
class DioEpidocParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("dio-epidoc")
  PARSER = Nabu::Adapters::DioEpidocParser

  BSS001 = File.join(FIXTURES, "di7", "article-BSS-001-nsn~3212.xml")
  HGW246 = File.join(FIXTURES, "di77", "article-hgw-246-mv~477.xml")
  HST083 = File.join(FIXTURES, "di102", "article-HST-083-mv~2048.xml")

  def parse(path, volume:)
    PARSER.new.parse(path, urn: PARSER.urn_for(path, volume: volume), volume: volume)
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_is_the_volume_and_the_printed_article_number
    assert_equal "urn:nabu:dio-epidoc:di7-001", PARSER.urn_for(BSS001, volume: "di7")
    assert_equal "urn:nabu:dio-epidoc:di102-083", PARSER.urn_for(HST083, volume: "di102")
  end

  def test_urn_mismatch_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      PARSER.new.parse(BSS001, urn: "urn:nabu:dio-epidoc:di7-002", volume: "di7")
    end
  end

  def test_in_file_identity_drift_is_quarantined
    Dir.mktmpdir do |dir|
      issue = 'sameAs="articles/epi-article/nsn~3212">'
      path = copy(dir, BSS001) { |xml| xml.sub("#{issue}001", "#{issue}002") }
      error = assert_raises(Nabu::ParseError) { parse(path, volume: "di7") }
      assert_match(/002/, error.message)
    end
  end

  def test_a_file_of_another_volume_is_refused
    assert_raises(Nabu::ParseError) do
      PARSER.new.parse(BSS001, urn: "urn:nabu:dio-epidoc:di77-001", volume: "di77")
    end
  end

  # --- the textpart grain + the Epigraf markup dialect ------------------------

  def test_expansions_read_through_and_the_glyphs_are_carved_text
    document = parse(BSS001, volume: "di7")
    assert_equal "nördliches Portal der Klostermauer", document.title
    assert_equal "lat", document.language
    passage = document.first
    assert_equal "urn:nabu:dio-epidoc:di7-001:A1", passage.urn
    assert_equal "M CXLVo · FVNDATA ABBATIA · RIDDAGSHVSANA", passage.text
    assert_equal "lat", passage.language
    assert_equal "1145 wurde die Abtei Riddagshausen gegründet.", passage.annotations.dig("translation", "deu")
  end

  def test_one_passage_per_textpart_each_in_its_inscriptions_language
    document = parse(HGW246, volume: "di77")
    assert_equal(%w[A1 B1 C1], document.map { |passage| passage.urn.split(":").last })
    assert_equal %w[gml deu und], document.map(&:language)
    assert_equal "gml", document.language, "the article's first language row"
    assert_equal(["niederdeutsch", "hochdeutsch", nil], document.map { |passage| passage.annotations["language_raw"] })
  end

  def test_del_wrapping_a_gap_is_the_lost_text_marker_never_a_cancellation
    passage = parse(HGW246, volume: "di77").first
    assert_equal "[…] ERVEN 1575", passage.text
    assert_equal [{ "reason" => "lost", "unit" => "character", "extent" => "unknown" }],
                 passage.annotations.dig("leiden", "gaps")
    refute passage.annotations["leiden"].key?("cancelled")
  end

  def test_add_counts_as_restored_letters_and_unclear_as_dotted
    passage = parse(HGW246, volume: "di77").to_a[1]
    assert_equal "DISER STEIN VND BEGREBNIS GEHÖRET CHRISTOFER MICHGELIS VND SEINEN ERBEN ANNO 1656", passage.text
    assert_equal 1, passage.annotations.dig("leiden", "supplied_chars")
    assert_equal 1, passage.annotations.dig("leiden", "unclear_chars")
  end

  def test_apparatus_notes_ride_the_passage_never_the_text
    passage = parse(HGW246, volume: "di77").to_a[1]
    assert_equal [{ "type" => "alphabetic", "text" => "MICHGELIS] Verhauen für MICHAELIS." }],
                 passage.annotations["notes"]
  end

  def test_the_printed_lines_ride_the_annotation
    passage = parse(HGW246, volume: "di77").to_a[1]
    assert_equal(["DISER STEIN VND BEGREBNIS", "GEHÖRET CHRISTOFER", "MICHGELIS VND SEINEN", "ERBEN ANNO 1656"],
                 passage.annotations["lines"].map { |line| line["text"] })
    assert_equal "neue Zeile", passage.annotations["lines"].last["break"]
  end

  def test_verse_breaks_are_flagged_and_a_leading_break_opens_no_empty_line
    passage = parse(HST083, volume: "di102").to_a[2]
    assert_equal "MORS TVA CHRISTE MIHI VITA EST VICTORIA REGNVM LABE MEA MORIOR SANGVINE VIVO TVO·", passage.text
    lines = passage.annotations["lines"]
    assert_equal(["MORS TVA CHRISTE MIHI VITA EST VICTORIA", "REGNVM", "LABE MEA MORIOR SANGVINE VIVO TVO·"],
                 lines.map { |line| line["text"] })
    assert_equal({ "text" => "REGNVM", "break" => "eingerückt", "verse" => true }, lines[1])
    assert_equal 1, passage.annotations["notes"].size, "the numeric footnote rides, the text stays clean"
  end

  def test_a_textpart_without_a_language_row_is_honestly_undetermined
    document = parse(HST083, volume: "di102")
    assert_equal %w[und gml lat], document.map(&:language)
    assert_equal "[…]en", document.first.text
    assert_equal "gml", document.language
  end

  def test_per_inscription_genre_and_script_ride_their_passage
    passages = parse(HGW246, volume: "di77").to_a
    assert_equal ["Eigentumsvermerk"], passages[0].annotations["genre"]
    assert_equal ["Nummerierung"], passages[2].annotations["genre"]
    assert_equal ["arabische Ziffern", "Kapitalis mit Versal"], passages[1].annotations["script"]
    assert_equal ["3,5", "5,5"], passages[1].annotations["letter_height"]
    assert_equal ["vertieft"], passages[1].annotations["technique"]
  end

  def test_a_textless_article_has_no_citable_text
    Dir.mktmpdir do |dir|
      lost = '<ab type="block"><del><gap reason="lost" quantity="0" unit="character"/></del></ab>'
      path = copy(dir, BSS001) { |xml| xml.sub(%r{<ab type="block">M CXLV.*?</ab>}m, lost) }
      refute PARSER.citable?(path)
      assert_raises(Nabu::ParseError) { parse(path, volume: "di7") }
    end
    assert PARSER.citable?(BSS001)
  end

  def test_a_del_carrying_text_is_outside_the_census
    Dir.mktmpdir do |dir|
      path = copy(dir, BSS001) { |xml| xml.sub("FV<supplied", "<del>X</del>FV<supplied") }
      assert_raises(Nabu::ParseError) { parse(path, volume: "di7") }
    end
  end

  def test_an_element_outside_the_census_is_refused
    Dir.mktmpdir do |dir|
      path = copy(dir, BSS001) { |xml| xml.sub("FV<supplied", "<choice><orig>F</orig></choice>FV<supplied") }
      assert_raises(Nabu::ParseError) { parse(path, volume: "di7") }
    end
  end

  def test_a_language_label_outside_the_census_is_refused
    Dir.mktmpdir do |dir|
      path = copy(dir, BSS001) { |xml| xml.sub("lateinisch </language>", "französisch</language>") }
      assert_raises(Nabu::ParseError) { parse(path, volume: "di7") }
    end
  end

  def test_language_labels_fold_on_their_first_named_language
    assert_equal "deu", PARSER.language_code("hochdeutsch-niederdeutsche Mischsprache")
    assert_equal "gml", PARSER.language_code("niederdeutsch mit hochdeutschen Elementen")
    assert_equal "lat", PARSER.language_code("lateinisch-griechisch")
    assert_equal "deu", PARSER.language_code("deutsch-lateinische Mischsprache")
    assert_equal "heb", PARSER.language_code("hebräisch")
    assert_equal "grc", PARSER.language_code("griechisch")
    assert_nil PARSER.language_code("französisch")
  end

  # --- header axes ------------------------------------------------------------

  def test_document_metadata_carries_identity_and_the_print_citation
    metadata = parse(BSS001, volume: "di7").metadata
    assert_equal "DI 7, Nr. 1", metadata["citation"]
    assert_equal "nsn~3212", metadata["dio_id"]
    assert_equal "https://epigraf.inschriften.net/iri/articles/epi-article/nsn~3212", metadata["iri"]
    assert_equal "urn:nbn:de:0238-dio007g003k0000104", metadata["urn_nbn"]
    assert_equal "Anna Weissmüller", metadata["author"]
    assert_equal({ "di" => 7, "title" => "Braunschweig (BSS)" }, metadata["volume"])
  end

  def test_a_year_date_is_a_one_year_envelope
    assert_equal({ "not_before" => 1145, "not_after" => 1145, "raw" => "1145" },
                 parse(BSS001, volume: "di7").metadata["date"])
  end

  def test_a_century_range_date_bands_both_ends
    assert_equal({ "not_before" => 1326, "not_after" => 1475, "raw" => "M.14.–M.15.Jh." },
                 parse(HST083, volume: "di102").metadata["date"])
  end

  def test_place_is_the_epigraf_location_verbatim_with_its_settlement
    place = parse(BSS001, volume: "di7").metadata["place"]
    assert_equal "Kloster, Riddagshausen, Braunschweig", place["ancient"]
    assert_equal "Braunschweig", place["settlement"]
    assert_equal ["Kloster, Riddagshausen, Braunschweig"], place["locations"]
  end

  def test_facets_carry_the_upstream_vocabulary
    facets = parse(BSS001, volume: "di7").metadata["facets"]
    assert_equal ["historische Nachricht"], facets.dig("genre", "values"), "the X / X doublet folds once"
    assert_equal ["Portal"], facets.dig("object_type", "values")
    assert_equal ["Stein"], facets.dig("material", "values")
    assert_equal ["† Objekt und Inschrift im Original verloren"], facets.dig("condition", "values")
    assert_equal ["vertieft"], facets.dig("technique", "values")
    hst = parse(HST083, volume: "di102").metadata["facets"]
    assert_equal ["mit Wappen", "mit bildlicher Darstellung"], hst.dig("object_type", "values")
    assert_equal "mit Wappen, mit bildlicher Darstellung", hst.dig("object_type", "raw")
    assert_equal %w[Eigentumsvermerk Devise], hst.dig("genre", "values")
    assert_includes hst.dig("script_style", "values"), "gotische Minuskel"
  end

  def test_object_description_dimensions_heraldry_commentary_and_bibliography_ride
    metadata = parse(HST083, volume: "di102").metadata
    assert metadata["description"].start_with?("Grabplatte für Heinrich Sten (B). Kalkstein.")
    assert_equal [{ "dimension" => "width", "quantity" => 134, "unit" => "cm" },
                  { "dimension" => "height", "quantity" => 241, "unit" => "cm" }], metadata["dimensions"]
    assert_equal ["Sten {1}: Schrägbalken, darüber und darunter je zwei Steine; geflügelter Greif"],
                 metadata["heraldry"]
    refute_empty metadata["commentary"]
    assert_equal 4, parse(BSS001, volume: "di7").metadata["bibliography"].size
  end

  # --- the origDate grammar ---------------------------------------------------

  DATES = {
    "1145" => [1145, 1145], "1590–1600" => [1590, 1600], "um 1600" => [1600, 1600],
    "um 1630–1640" => [1630, 1640], "vor 1650?" => [nil, 1650], "nach 1420" => [1420, nil],
    "1581 o. früher" => [nil, 1581], "1581 o. später" => [1581, nil], "1616 o. früher?" => [nil, 1616],
    "15.Jh." => [1401, 1500], "1.H.14.Jh." => [1301, 1350], "2.H.16.Jh." => [1551, 1600],
    "2.V.17.Jh." => [1626, 1650], "4.V.14.Jh." => [1376, 1400], "1.D.17.Jh." => [1601, 1633],
    "2.D.16.Jh." => [1534, 1566], "3.D.14.Jh." => [1367, 1400], "A.16.Jh." => [1501, 1550],
    "M.15.Jh." => [1426, 1475], "E.15.Jh." => [1451, 1500], "M.14.–M.15.Jh." => [1326, 1475],
    "2.–3.V.15.Jh." => [1426, 1475], "16.–17.Jh.?" => [1501, 1700], "E.16.Jh.–1630" => [1551, 1630],
    "3.D.16.–1.D.17.Jh." => [1567, 1633], "M.16.–17.Jh." => [1526, 1700], "15.–M.16.Jh." => [1401, 1575],
    "2.V.17.–A.18.Jh." => [1626, 1750], "1349–1351?" => [1349, 1351]
  }.freeze

  def test_the_origdate_grammar
    DATES.each do |raw, (low, high)|
      date = PARSER.date_of(raw)
      assert_equal [low, high], [date["not_before"], date["not_after"]], raw
      assert_equal raw, date["raw"]
    end
  end

  def test_circa_and_uncertainty_are_flagged
    assert PARSER.date_of("um 1600")["circa"]
    assert PARSER.date_of("vor 1650?")["uncertain"]
    refute PARSER.date_of("1145").key?("uncertain")
  end

  def test_unparsed_prose_keeps_raw_only
    assert_equal({ "raw" => "Zeit?" }, PARSER.date_of("Zeit?"))
  end

  private

  def copy(dir, path)
    target = File.join(dir, File.basename(path))
    File.write(target, yield(File.read(path, encoding: "utf-8")))
    target
  end
end
