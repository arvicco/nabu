# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

# ArmEpiC adapter tests: discovery over the per-file FileFetch layout, the
# authority-list grain skipped by rule, the armepic-epidoc line grain
# (lb @n verbatim inside the textpart path, monogram textparts without
# lbs), the diplomatic text policy (orig over reg, whitespace inside <w>
# is formatting), the word-level lemma/UPOS tokens, the header axes
# (date, place, facets, translations), identity, and the md5-pinned
# Zenodo fetch. Fixtures: 3 whole real inscriptions + 1 authority list
# (test/fixtures/armepic/README.md).
class ArmepicTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("armepic")

  URNS = %w[urn:nabu:armepic:art0001 urn:nabu:armepic:art0013 urn:nabu:armepic:art0026].freeze

  def conformance_adapter
    Nabu::Adapters::Armepic.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "armepic"
  end

  def parse(urn)
    adapter = Nabu::Adapters::Armepic.new
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_nc_and_quotes_the_deposit_license
    manifest = Nabu::Adapters::Armepic.manifest
    assert_equal "armepic", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/Creative Commons Attribution-NonCommercial 4\.0 International License/, manifest.license)
    assert_match(%r{10\.5281/zenodo\.23501516}, manifest.license)
    assert_match(/photographs and drawings/i, manifest.license, "the image carve-out, verbatim")
    assert_equal "armepic-epidoc", manifest.parser_family
    assert_equal "https://zenodo.org/records/23501516", manifest.upstream_url
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_inscription_file_sorted
    refs = Nabu::Adapters::Armepic.new.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    assert(refs.all? { |ref| File.file?(ref.path) })
  end

  def test_authority_lists_are_skipped_by_rule_and_counted
    skips = Nabu::Adapters::Armepic.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("authority") })
  end

  def test_attic_copies_are_never_discovered
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "ART0013"))
      FileUtils.cp(File.join(FIXTURES, "ART0013", "ART0013.xml"), File.join(dir, "ART0013"))
      FileUtils.mkdir_p(File.join(dir, ".attic", "ART0013"))
      FileUtils.cp(File.join(FIXTURES, "ART0013", "ART0013.xml"), File.join(dir, ".attic", "ART0013"))
      assert_equal ["urn:nabu:armepic:art0013"], Nabu::Adapters::Armepic.new.discover(dir).map(&:id)
    end
  end

  # --- the line grain ---------------------------------------------------------

  def test_first_vintage_record_lines_keyed_by_lb_n
    document = parse("urn:nabu:armepic:art0001")
    assert_equal "xcl", document.language
    assert_equal "The donative inscription of Ter Hovhannes, Abbot of Gandzasar Monastery, 1271.",
                 document.title
    assert_equal (1..9).map { |n| "urn:nabu:armepic:art0001:#{n}" }, document.map(&:urn)
    assert(document.all? { |passage| passage.language == "xcl" })
  end

  def test_choice_keeps_the_inscribed_numeral_and_the_regularization_rides_annotations
    line = parse("urn:nabu:armepic:art0001").first
    assert_equal ":Թիւ: ՉԻ", line.text
    assert_equal [{ "orig" => "ՉԻ", "reg" => "720 (1271)" }], line.annotations.fetch("regularized")
    assert_equal [{ "text" => "ՉԻ", "value" => 720 }], line.annotations.fetch("numerals")
  end

  def test_whitespace_inside_a_word_is_formatting
    # "Կ\n<hi>ամ</hi>\n<hi>աւ</hi>\n<hi>ն</hi>" is one carved word. The
    # space before the final comma is upstream's: the first vintage puts
    # "</forename>\n</persName>," on their own lines and the text policy
    # folds whitespace BETWEEN words, never deletes it (no clean-up).
    line = parse("urn:nabu:armepic:art0001").to_a[1]
    assert_equal "Կամաւն Աստուծոյ, ես՝ Յոհանէս ,", line.text
  end

  def test_tokens_carry_lemma_and_upos_on_the_line_the_word_opens
    lines = parse("urn:nabu:armepic:art0001").to_a
    assert_equal({ "form" => "Թիւ", "lemma" => "թիւ", "upos" => "NOUN" }, lines[0].annotations["tokens"].first)
    # "ու|խտիս" breaks across lb 3→4 (break="no"): the token rides line 3
    # with the whole word as its form; line 4 opens on "խտիս".
    assert_includes lines[2].annotations["tokens"], { "form" => "ուխտիս", "lemma" => "ուխտ", "upos" => "NOUN" }
    assert lines[3].text.start_with?("խտիս"), lines[3].text
  end

  def test_nested_textparts_restart_lb_inside_their_path
    document = parse("urn:nabu:armepic:art0013")
    suffixes = document.map { |passage| passage.urn.delete_prefix("urn:nabu:armepic:art0013:") }
    assert_equal %w[section1:column1:1 section1:column1:2 section1:column2:1 section1:column2:2
                    section2:1 section2:2 section2:3 section2:4 section2:5 section2:6], suffixes
    assert_equal "ՈԽԵ", document.to_a[2].text
    assert_equal [{ "subtype" => "section", "n" => "2" }], document.to_a[4].annotations.fetch("textpart")
  end

  def test_supplied_letters_read_through_and_count
    last = parse("urn:nabu:armepic:art0013").to_a.last
    assert last.text.start_with?("սի,"), last.text
    assert_equal 1, last.annotations.dig("leiden", "supplied_chars")
  end

  def test_monogram_textparts_without_lb_mint_the_textpart_itself
    document = parse("urn:nabu:armepic:art0026")
    suffixes = document.map { |passage| passage.urn.delete_prefix("urn:nabu:armepic:art0026:") }
    assert_equal %w[1 2 3 4 5 6 7 8 monogram1 monogram2 monogram3], suffixes
    monograms = document.to_a.last(3)
    assert_equal ["Պետրոս կաթողիկոս", "Ղուկաս վարդապետ", "Բարսեղ եպիսկոպոս"], monograms.map(&:text)
  end

  def test_expansions_read_abbreviation_plus_expansion
    line = parse("urn:nabu:armepic:art0026").first
    assert_equal "Ես՝ Պետրոս կաթողիկ", line.text
    assert_includes line.annotations.fetch("entities"),
                    { "type" => "person", "text" => "Պետրոս" }
  end

  # --- header axes ------------------------------------------------------------

  def test_internal_date_is_a_one_year_envelope
    date = parse("urn:nabu:armepic:art0001").metadata.fetch("date")
    assert_equal 1271, date.fetch("not_before")
    assert_equal 1271, date.fetch("not_after")
    assert_equal "Հայոց 720 (1271)", date.fetch("raw")
    assert_equal "internal-date", date.fetch("evidence")
    assert_equal "urn:armepic:calendar:armenian", date.fetch("calendar")
  end

  def test_palaeographic_dates_are_bounds
    date = parse("urn:nabu:armepic:art0026").metadata.fetch("date")
    assert_equal 1651, date.fetch("not_before")
    assert_equal 1700, date.fetch("not_after")
    assert_equal "second half of the 17th century", date.fetch("raw")
    assert_equal "medium", date.fetch("precision")
  end

  def test_place_names_the_settlement_with_its_own_coordinates
    place = parse("urn:nabu:armepic:art0026").metadata.fetch("place")
    assert_equal "Herher", place.fetch("ancient")
    assert_equal "Հերհեր", place.fetch("name_hy")
    assert_equal "urn:armepic:artsakh:PLC0023", place.fetch("armepic_ref")
    assert_equal "39.70306, 46.96361", place.fetch("geo"), "the settlement's own point, not the monument's"
    assert_equal "St Grigoris church", place.fetch("findspot")
    assert_equal "urn:armepic:monument:MON0018", place.fetch("findspot_ref")
  end

  def test_place_without_coordinates_still_names
    place = parse("urn:nabu:armepic:art0001").metadata.fetch("place")
    assert_equal "Vank", place.fetch("ancient")
    refute place.key?("geo")
    assert_equal "Gandzasar monastery", place.fetch("findspot")
  end

  def test_place_falls_back_to_the_findspot_when_no_origplace_exists
    Dir.mktmpdir do |dir|
      path = copy_fixture(dir, "ART0001") do |xml|
        xml.sub(%r{<origPlace>.*?</origPlace>}m, "")
      end
      document = Nabu::Adapters::ArmepicEpidocParser.new.parse(path, urn: "urn:nabu:armepic:art0001")
      assert_equal "Gandzasar monastery", document.metadata.dig("place", "ancient")
    end
  end

  def test_facets_carry_the_upstream_vocabulary
    facets = parse("urn:nabu:armepic:art0026").metadata.fetch("facets")
    assert_equal({ "values" => ["construction"], "raw" => "construction" }, facets.fetch("genre"))
    assert_equal ["Carved"], facets.dig("technique", "values")
    assert_equal ["Bolorgits Erkatagir"], facets.dig("script_style", "values")
    assert_equal ["khachkar"], parse("urn:nabu:armepic:art0013").metadata.dig("facets", "object_type", "values")
  end

  def test_translations_commentary_and_record_identity_ride_metadata
    metadata = parse("urn:nabu:armepic:art0013").metadata
    assert_match(/Remember us in your prayers\.\z/, metadata.dig("translations", "eng"))
    assert metadata.dig("translations", "hye").start_with?("Հայոց 645 թվականն էր")
    assert metadata.dig("commentary", "eng").start_with?("The upper right portion of the khachkar is broken.")
    assert_equal "urn:armepic:inscription:ART0013", metadata.fetch("armepic_id")
    assert_equal "https://armenianepigraphy.com/inscriptions/ART0013", metadata.fetch("url")
    assert_equal [{ "ref" => "urn:armepic:bibl:007", "range" => "408/3" }], metadata.fetch("bibliography")
    assert_equal 8, metadata.fetch("written_lines")
  end

  # --- identity ---------------------------------------------------------------

  def test_urn_mismatch_is_a_parse_error
    path = File.join(FIXTURES, "ART0013", "ART0013.xml")
    assert_raises(Nabu::ParseError) do
      Nabu::Adapters::ArmepicEpidocParser.new.parse(path, urn: "urn:nabu:armepic:art0014")
    end
  end

  def test_in_file_identity_drift_is_quarantined
    Dir.mktmpdir do |dir|
      path = copy_fixture(dir, "ART0013") do |xml|
        xml.sub("urn:armepic:inscription:ART0013", "urn:armepic:inscription:ART0014")
      end
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::ArmepicEpidocParser.new.parse(path, urn: "urn:nabu:armepic:art0013")
      end
      assert_match(/ART0014/, error.message)
    end
  end

  def test_an_edition_language_outside_the_census_is_refused
    Dir.mktmpdir do |dir|
      path = copy_fixture(dir, "ART0013") do |xml|
        xml.sub('<div type="edition" xml:lang="hy">', '<div type="edition" xml:lang="ka">')
      end
      assert_raises(Nabu::ParseError) do
        Nabu::Adapters::ArmepicEpidocParser.new.parse(path, urn: "urn:nabu:armepic:art0013")
      end
    end
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_lands_each_pinned_file_in_its_own_subdir
    bodies = { "ART0013.xml" => File.binread(File.join(FIXTURES, "ART0013", "ART0013.xml")),
               "LICENSE.txt" => File.binread(File.join(FIXTURES, "LICENSE", "LICENSE.txt")) }
    stub_files(bodies)
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Armepic.new(files: bodies.transform_values { |body| Digest::MD5.hexdigest(body) })
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal bodies["ART0013.xml"], File.binread(File.join(workdir, "ART0013", "ART0013.xml"))
      assert File.file?(File.join(workdir, "LICENSE", "LICENSE.txt"))
      assert_equal ["urn:nabu:armepic:art0013"], adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_refuses_a_body_that_misses_its_md5_pin
    stub_files("ART0013.xml" => "<TEI/>")
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Armepic.new(files: { "ART0013.xml" => "0" * 32 })
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/md5/, error.message)
      refute File.exist?(File.join(workdir, "ART0013", "ART0013.xml")), "the tree is untouched"
    end
  end

  def test_fetch_wraps_http_failure
    stub_request(:get, Nabu::Adapters::Armepic.file_url("ART0013.xml")).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Armepic.new(files: { "ART0013.xml" => "0" * 32 })
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  def test_the_pin_table_is_the_deposit_census
    files = Nabu::Adapters::Armepic::FILES
    assert_equal 65, files.size
    assert_equal 50, files.keys.grep(/\AART\d{4}\.xml\z/).size
    assert_equal 12, files.keys.grep(/\AArmEpiC_List\w+\.xml\z/).size
    refute(files.keys.any? { |name| name.end_with?(".zip") }, "the images zip is never fetched")
    %w[ART0001 ART0013 ART0026].each do |stem|
      assert_equal files.fetch("#{stem}.xml"),
                   Digest::MD5.hexdigest(File.binread(File.join(FIXTURES, stem, "#{stem}.xml"))),
                   "the fixture is byte-identical to the pinned deposit file"
    end
  end

  private

  def copy_fixture(dir, stem)
    xml = File.read(File.join(FIXTURES, stem, "#{stem}.xml"), encoding: "utf-8")
    path = File.join(dir, "#{stem}.xml")
    File.write(path, yield(xml))
    path
  end

  def stub_files(bodies)
    bodies.each do |name, body|
      stub_request(:get, Nabu::Adapters::Armepic.file_url(name)).to_return(
        status: 200, body: body, headers: { "Last-Modified" => "Tue, 20 Oct 2026 00:00:00 GMT" }
      )
    end
  end
end
