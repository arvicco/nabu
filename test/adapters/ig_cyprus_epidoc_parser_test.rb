# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# IgCyprusEpidocParser: the Berlin IG digital edition's per-record EpiDoc
# for IG XV 1,1 (the Cypriot syllabary fascicle). Fixtures are real,
# byte-identical record GETs (test/fixtures/ig-cyprus/README.md).
class IgCyprusEpidocParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ig-cyprus")
  Parser = Nabu::Adapters::IgCyprusEpidocParser

  def path(stem)
    File.join(FIXTURES, "documents", "#{stem}.xml")
  end

  def parse(stem)
    Parser.new.parse(path(stem), urn: "urn:nabu:ig-cyprus:#{stem.downcase}")
  end

  def passage(document, suffix)
    document.find { |p| p.urn == "#{document.urn}:#{suffix}" } or flunk "no passage #{suffix} in #{document.urn}"
  end

  # --- the id <-> file-stem scheme -----------------------------------------------

  def test_ids_map_to_reversible_file_stems
    { "IG XV 1, 1" => "1", "IG XV 1, 410" => "410", "IG XV 1, 237(I)" => "237-I",
      "IG XV 1, 237(II)" => "237-II", "IG XV 1, 254(1)" => "254-1" }.each do |id, stem|
      assert_equal stem, Parser.stem_for(id)
      assert_equal id, Parser.id_for(stem), "the scheme round-trips"
    end
  end

  def test_ids_outside_the_censused_shape_are_refused
    assert_nil Parser.stem_for("IG XV 2, 1"), "another fascicle never maps"
    assert_nil Parser.stem_for("IG XV 1, 12a")
    assert_nil Parser.id_for("12_a")
  end

  # --- record 1: the Eteocypriot + alphabetic-Greek bilingual from Amathus --------

  def test_bilingual_fragments_carry_their_own_languages
    document = parse("1")
    assert_equal %w[urn:nabu:ig-cyprus:1:I:1 urn:nabu:ig-cyprus:1:II:1 urn:nabu:ig-cyprus:1:II:2],
                 document.map(&:urn)
    eteo = passage(document, "I:1")
    assert_equal "ecy-Latn", eteo.language, "the syllabic fragment of an eteokyprisch record is Eteocypriot"
    assert_equal "] ị-te-ọ-..-..-..-j̣ạ [ ←", eteo.text, "dotted syllabograms ride verbatim (NFC)"
    assert_equal "cypriot-syllabary", eteo.annotations["writing_system"]
    assert_equal ["sinistroverse"], eteo.annotations["direction"]
    greek = passage(document, "II:1")
    assert_equal "grc", greek.language
    assert greek.text.start_with?("θησαυρὸν Κυπρίαι κ̣αὶ̣ [Ὀρε]σ̣θ̣έως"), greek.text
    assert_equal "greek-alphabet", greek.annotations["writing_system"]
    assert_equal "grc", document.language, "the majority line language"
  end

  def test_header_layers_are_mined
    meta = parse("1").metadata
    assert_equal "IG XV 1, 1", meta["idno"], "the localId's trailing space is upstream noise"
    assert_equal({ "ancient" => "Amathus" }, meta["place"])
    assert_equal "Akropolis, jetzt Mus. Limassol", meta["provenance"]
    assert_equal({ "value" => "Basis" }, meta.dig("facets", "object_type"))
    assert_equal({ "value" => "Marmor" }, meta.dig("facets", "material"))
    assert_equal({ "value" => "Weihinschrift" }, meta.dig("facets", "genre"))
    assert_equal "eteokyprisch und griechisch", meta["writing"]
    assert_equal %w[cypriot-syllabary greek-alphabet], meta["writing_systems"]
    assert_equal "Weihinschrift, eteokyprisch und griechisch", parse("1").title
  end

  # The fascicle's dates are unsigned BCE years (the syllabary went out of
  # use in the Hellenistic period); "330-310" is 330–310 BCE.
  def test_bce_date_pin
    assert_equal({ "not_before" => -330, "not_after" => -310, "raw" => "330-310" }, parse("1").metadata["date"])
  end

  # --- the plain syllabic records ---------------------------------------------------

  def test_pure_eteocypriot_record
    document = parse("5")
    assert_equal 5, document.size
    assert(document.all? { |p| p.language == "ecy-Latn" })
    assert_equal "ecy-Latn", document.language
    assert_equal "urn:nabu:ig-cyprus:5:1", document.first.urn, "no textparts → bare line numbers"
    assert_equal({ "not_before" => -400, "not_after" => -301, "raw" => "4.Jh." }, document.metadata["date"])
  end

  def test_suffixed_id_record_reads_syllabic_greek
    document = parse("237-I")
    assert_equal "IG XV 1, 237(I)", document.metadata["idno"]
    assert_equal 1, document.size
    line = document.first
    assert_equal "urn:nabu:ig-cyprus:237-i:1", line.urn
    assert_equal "grc-Latn", line.language, "Greek in the Cypriot syllabary, held in Latin transliteration"
    assert_equal "zo-wi-ja-se e-pe-se-ta-se ta-se ‒?‒ ←", line.text, "the tab before the arrow folds"
    assert_equal({ "value" => "Grabinschrift" }, document.metadata.dig("facets", "genre"))
    assert_equal [-400, -351], document.metadata["date"].values_at("not_before", "not_after"),
                 "Anfang = the century's first half (the house early/mid/late grammar)"
  end

  def test_unnumbered_ruling_lines_drop_and_their_notes_ride_the_next_line
    document = parse("180")
    assert_equal(%w[1 2 3], document.map { |p| p.urn.split(":").last })
    assert(document.all? { |p| p.language == "grc-Latn" })
    first = document.first
    assert_equal "a-ri-si-ta-se | e-[mi ←", first.text, "letterspaced dividers keep their text"
    assert_equal ["linea"], first.annotations["editorial_notes"]
    assert_equal [-600, -301], document.metadata["date"].values_at("not_before", "not_after")
  end

  def test_alphabetic_letters_and_private_use_glyphs_ride_verbatim
    document = parse("254-1")
    assert_equal 1, document.size
    assert_equal "Ε\u{F0011}", document.first.text, "upstream's private-use glyph is never dropped"
    assert_equal "grc", document.first.language
    assert_equal [-500, -301], document.metadata["date"].values_at("not_before", "not_after")
  end

  # Coin legends: syllabic and alphabetic lines alternate inside one
  # fragment — language is decided per LINE.
  def test_mixed_script_lines_within_one_fragment
    document = parse("410")
    assert_equal 23, document.size, "12 legends × 2 lines, minus (d)'s editorial-only line 1"
    assert_equal "grc-Latn", passage(document, "(a):1").language
    assert_equal "pa-(si-le-wo-se)", passage(document, "(a):1").text
    assert_equal "grc", passage(document, "(a):2").language
    assert_equal "Μα(ριεύς).", passage(document, "(a):2").text
    refute(document.any? { |p| p.urn.end_with?(":(d):1") }, "\"tit. evanidus\" is the editor's note, not text")
    assert_equal ["tit. evanidus"], passage(document, "(d):2").annotations["editorial_notes"]
    assert_equal ["upward"], passage(document, "(e):1").annotations["direction"]
    assert_equal "grc-Latn", document.language
    assert_equal [-330, -312], document.metadata["date"].values_at("not_before", "not_after")
  end

  # --- the sibling layers ------------------------------------------------------------

  def test_layer_census_follows_the_extraction
    assert_equal ["de"], Parser.new.layers(path("1")), "record 1's Eteocypriot placeholder is no translation"
    assert_empty Parser.new.layers(path("5")), "a placeholder-only German div mints nothing"
    assert_equal %w[de transcription], Parser.new.layers(path("180")).sort
    assert_empty Parser.new.layers(path("254-1")), "an unnumbered placeholder line mints nothing"
  end

  def test_transcription_layer_pairs_line_for_line
    document = Parser.new.parse(path("180"), urn: "urn:nabu:ig-cyprus:180-transcription", layer: "transcription")
    assert_equal(%w[1 2 3], document.map { |p| p.urn.split(":").last })
    assert(document.all? { |p| p.language == "grc" })
    assert_equal "Ἀρίστας ἠ[μί],", document.first.text
    assert_equal({ "layer" => "transcription" }, document.metadata)
  end

  def test_german_translation_layer
    document = Parser.new.parse(path("1"), urn: "urn:nabu:ig-cyprus:1-de", layer: "de")
    assert_equal %w[urn:nabu:ig-cyprus:1-de:II:1 urn:nabu:ig-cyprus:1-de:II:2], document.map(&:urn)
    assert_equal "deu", document.language
    assert_equal({ "kind" => "translation", "translator" => "Klaus Hallof" }, document.metadata)
    assert_match(/Schatztruhe/, document.first.text)
  end

  # --- the date grammar (unsigned BCE prior; n.Chr. flips it) ----------------------

  def test_date_grammar
    {
      "330-310" => [-330, -310], "750-600" => [-750, -600], "480-70" => [-480, -470],
      "um 420-400" => [-420, -400], "4.Jh." => [-400, -301], "5.-4.Jh." => [-500, -301],
      "Anfang 4.Jh." => [-400, -351], "Ende 5.Jh." => [-450, -401], "Mitte 4. Jh." => [-375, -326],
      "um 710-675 (I) / nach 498 (II)" => [-710, nil], "vor 400" => [nil, -400], "498" => [-498, -498],
      "2. Jh. n.Chr." => [101, 200]
    }.each do |raw, bounds|
      assert_equal bounds, Parser.date_bounds(raw), raw
    end
    assert_nil Parser.date_bounds("Zeit?"), "unparsed prose mints no bounds"
    assert_nil Parser.date_bounds("archaisch")
  end

  # --- identity + malformed input ---------------------------------------------------

  def test_identity_mismatch_raises
    error = assert_raises(Nabu::ParseError) { Parser.new.parse(path("1"), urn: "urn:nabu:ig-cyprus:2") }
    assert_match(/urn mismatch/, error.message)
  end

  def test_malformed_xml_quarantines
    Dir.mktmpdir do |dir|
      bad = File.join(dir, "1.xml")
      File.write(bad, "<TEI><teiHeader>")
      assert_raises(Nabu::ParseError) { Parser.new.parse(bad, urn: "urn:nabu:ig-cyprus:1") }
    end
  end

  def test_an_unnumbered_citable_edition_line_quarantines
    Dir.mktmpdir do |dir|
      broken = File.join(dir, "237-I.xml")
      File.write(broken, File.read(path("237-I")).sub('<lb n="1"/>zo-wi', "<lb/>zo-wi"))
      error = assert_raises(Nabu::ParseError) { Parser.new.parse(broken, urn: "urn:nabu:ig-cyprus:237-i") }
      assert_match(/missing its @n/, error.message)
    end
  end
end
