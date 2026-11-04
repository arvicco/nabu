# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::CantusCsvParser — the cantus-csv family: one Cantus
# Database chant record (a row of a source's CSV export) → one document
# whose single passage is the chant's full text as the manuscript spells
# it. Fixtures: the trimmed real exports under test/fixtures/cantus/sources.
class CantusCsvParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/cantus", __dir__)
  Parser = Nabu::Adapters::CantusCsvParser

  def rows(id) = Parser.new.each_row(File.join(FIXTURES, "sources", "#{id}.csv")).to_a

  def row(id, node) = rows(id).find { |r| r["node_id"] == node.to_s }

  def source(id) = Nabu::Adapters::CantusSourceIndex.load(FIXTURES).fetch(id)

  def document(id, node)
    Parser.new.document(row(id, node), urn: "urn:nabu:cantus:#{node}", source: source(id),
                                       canonical_path: File.join(FIXTURES, "sources", "#{id}.csv"))
  end

  # --- the full-text rule ------------------------------------------------------

  def test_the_manuscript_spelling_is_the_text_when_present
    assert_equal "manuscript", Parser.text_form(row(123_717, 455_845))
  end

  def test_a_standardized_full_text_answers_when_the_manuscript_field_is_empty
    assert_equal "standardized", Parser.text_form(row(123_738, 276_273)),
                 "Dabo in Sion — the standardized field carries more than the incipit"
  end

  def test_incipit_only_rows_skip_by_rule
    assert_equal :no_text, Parser.skip_reason(row(123_738, 276_139)), "Benedictus* — incipit only"
    assert_equal :incipit_echo, Parser.skip_reason(row(123_738, 276_272)),
                 "the standardized field merely repeats the incipit (Jerusalem gaude gaudio magno)"
    assert_equal :incipit_echo, Parser.skip_reason(row(123_717, 457_954)), "the LACUNA placeholder row"
    assert_nil Parser.skip_reason(row(123_717, 455_849)),
               "a manuscript cue that IS its incipit (Alma redemptoris) is still the manuscript's text"
  end

  def test_a_renamed_column_fails_loudly
    Dir.mktmpdir do |dir|
      path = File.join(dir, "1.csv")
      File.write(path, "shelfmark,folio,node_id\nX,1r,9\n")
      error = assert_raises(Nabu::ParseError) { Parser.new.each_row(path).to_a }
      assert_match(/fulltext_ms/, error.message)
    end
  end

  # --- the document ----------------------------------------------------------------

  def test_document_text_metadata_and_layers
    doc = document(123_717, 455_854)
    assert_equal "urn:nabu:cantus:455854", doc.urn
    assert_equal "lat", doc.language
    assert_equal 1, doc.size
    passage = doc.passages.first
    assert_equal "urn:nabu:cantus:455854:1", passage.urn
    assert passage.text.start_with?("Iudea et ierusalem nolite timere"), "the manuscript spelling verbatim"
    assert passage.annotations["standardized"].start_with?("Judaea et Jerusalem"), "the standardized layer rides"
    assert_equal "manuscript", passage.annotations["text_form"]
    meta = doc.metadata
    assert_equal "007040", meta["cantus_id"]
    assert_equal "455854", meta["node_id"]
    assert_equal "123717", meta["source_id"]
    assert_equal "CH-SGs 390", meta["siglum"]
    assert_equal "007", meta["folio"]
    assert_equal "Vigilia Nat. Domini", meta["feast"]
    assert_equal "V", meta["office"]
    assert_equal "First Vespers", meta["office_name"]
    assert_equal "R", meta["genre"]
    assert_equal "Responsory", meta["genre_name"]
    assert_equal "https://cantusdatabase.org/chant/455854/", meta["url"]
    assert_equal "Judaea et Jerusalem nolite timere (CH-SGs 390, 007)", doc.title,
                 "the incipit (upstream derives it from the standardized text) + siglum, folio"
    assert_equal "Judaea et Jerusalem nolite timere cras egrediemini et dominus erit vobiscum",
                 passage.annotations["standardized"], "trailing upstream whitespace trimmed"
  end

  def test_the_source_century_dates_and_its_provenance_places_the_chant
    meta = document(123_717, 455_854).metadata
    assert_equal({ "not_before" => 975, "not_after" => 1000, "raw" => "10th century (975-1000)",
                   "basis" => "source" }, meta["date"])
    assert_equal "St. Gall (Sankt-Gallen)", meta["place"]
    assert_equal ["St. Gall (Sankt-Gallen)"], meta["provenance"]
  end

  def test_a_religious_order_provenance_rides_metadata_but_places_nothing
    meta = document(123_738, 276_273).metadata
    assert_equal ["Dominican"], meta["provenance"]
    refute meta.key?("place")
    assert_equal 1251, meta.dig("date", "not_before")
  end

  def test_a_source_without_century_or_provenance_mints_neither
    meta = document(1_000_458, 1_017_752).metadata
    refute meta.key?("date")
    refute meta.key?("place")
  end

  def test_facets_carry_genre_and_office_names_with_the_codes_raw
    facets = document(123_717, 455_854).metadata["facets"]
    assert_equal({ "value" => "Responsory", "raw" => "R" }, facets["genre"])
    assert_equal({ "value" => "First Vespers", "raw" => "V" }, facets["office"])
    assert_equal "Vigilia Nat. Domini", facets["feast"]
  end

  def test_a_genre_less_row_carries_no_genre_facet
    doc = document(123_717, 455_861)
    refute doc.metadata.key?("genre")
    refute doc.metadata["facets"].key?("genre")
  end

  def test_a_standardized_only_row_says_so_on_the_passage
    passage = document(123_738, 276_273).passages.first
    assert_equal "Dabo in Sion salutem et in Jerusalem gloriam meam alleluia", passage.text
    assert_equal "standardized", passage.annotations["text_form"]
    refute passage.annotations.key?("standardized"), "the text IS the standardized layer"
  end

  def test_melody_and_lacuna_marks_ride_verbatim
    passage = document(693_666, 693_668).passages.first
    assert_equal "Ecce virgo concipiet et {#}", passage.text, "upstream's lacuna mark, verbatim"
    assert passage.annotations["volpiano"].start_with?("1---d--dfe"), "the melody transcription rides"
    assert_equal "Communion", document(693_666, 693_668).metadata["genre_name"]
  end
end
