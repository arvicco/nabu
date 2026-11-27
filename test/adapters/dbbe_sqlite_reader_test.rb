# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# Nabu::Adapters::DbbeSqliteReader — the read-only reader over the DBBE
# archive (dbbe_archive.sqlite), run against the schema-intact trim in
# test/fixtures/dbbe/ (its README's recipe).
class DbbeSqliteReaderTest < Minitest::Test
  READER = Nabu::Adapters::DbbeSqliteReader
  ARCHIVE = File.join(Nabu::TestSupport.fixtures("dbbe"), "dbbe_archive.sqlite")

  def reader = @reader ||= READER.new(ARCHIVE)

  def test_occurrence_census_flags_the_textless_record
    census = reader.occurrence_census
    assert_equal [16_897, 17_280, 17_332, 18_852, 20_028, 24_315, 24_466, 28_432], census.map(&:id)
    assert_equal [17_280], census.reject(&:textual).map(&:id)
  end

  def test_record_counts_census_the_non_document_classes
    assert_equal({ "manuscripts" => 8, "persons" => 35, "bibliography" => 88 }, reader.record_counts)
  end

  def test_translation_census_carries_upstreams_language_rows
    census = reader.translation_census
    assert_equal 11, census.size
    greek = census.find { |row| row.id == 31_673 }
    assert_equal ["GR", "Greek", 6372], [greek.language_code, greek.language_name, greek.type_id]
  end

  def test_verses_arrive_in_upstream_order_verbatim
    verses = reader.occurrence(17_332).verses
    assert_equal (0..16).to_a, verses.map(&:order)
    assert_equal "", verses[6].text, "the blank row is handed through; the adapter decides"
    assert_equal 15_428, reader.occurrence(24_315).verses.first.verse_group_id
  end

  def test_the_manuscript_hierarchies_resolve_leaf_to_root
    manuscript = reader.occurrence(24_315).manuscript
    assert_equal "MESSINA - Biblioteca Universitaria - S. Salv. 117", manuscript.name
    assert_equal ["Calabria", "Southern Italy", "Italy"], manuscript.origin
    assert_equal "Biblioteca Universitaria", manuscript.repository
    assert_equal "Messina", manuscript.repository_place
    assert_equal ["Biblica > Vetus Testamentum > Psalterium"], manuscript.content
    assert_equal "1115-01-01", manuscript.date_floor, "the manuscript's own bounds, beside the occurrence's"
  end

  def test_only_historical_roles_are_carried
    persons = reader.occurrence(24_315).persons
    assert_equal({ "Scribe" => ["Leon"] }, persons,
                 "the record's Creator/Contributor/Transcriber staff credits are not carried")
    assert_equal({ "Poet" => ["Ignatios Methymnaeos"] }, reader.type(1865).persons)
  end

  def test_type_statuses_and_links
    type = reader.type(2095)
    assert_equal "Critical text", type.editorial_status
    assert_equal "Text completely known", type.text_status
    assert_equal [17_332], type.occurrence_ids
    assert_equal [2175, 3753], reader.occurrence(28_432).type_ids
  end

  def test_an_unknown_id_answers_nil
    assert_nil reader.occurrence(1)
    assert_nil reader.type(1)
    assert_nil reader.translation(1)
  end

  def test_immutable_uri_escapes_uri_reserved_characters
    uri = READER.immutable_uri("/tmp/a?b#c%d/dbbe_archive.sqlite")
    assert_equal "file:/tmp/a%3Fb%23c%25d/dbbe_archive.sqlite?immutable=1", uri
  end

  def test_a_path_with_reserved_characters_still_opens
    Dir.mktmpdir do |dir|
      odd = File.join(dir, "odd ?#% dir")
      FileUtils.mkdir_p(odd)
      FileUtils.cp(ARCHIVE, File.join(odd, "dbbe_archive.sqlite"))
      assert_equal 8, READER.new(File.join(odd, "dbbe_archive.sqlite")).occurrence_census.size
    end
  end

  def test_a_missing_file_raises_a_parse_error
    error = assert_raises(Nabu::ParseError) { READER.new("/nonexistent/dbbe_archive.sqlite").type_ids }
    assert_match(/no such file/, error.message)
  end
end
