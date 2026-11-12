# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Old Albanian adapter tests: the multi-edition titus_levels family.
# Fixtures are FULL real pages — Buzuku's Missal (XLevel printed lines,
# the manuscript-page location), Bogdani's Cuneus Prophetarum (paragraph
# units), Blanchus's dictionary front matter (the Latin lanes, the special
# letters legend inside an editorial note), Matrënga's preface (Level
# lines) — plus every edition's frameset + index frames (the page census).
#
# The bytes are gated (no redistribution): gitignored
# local/fixtures/titus-old-albanian/ (README: re-cut recipe + sha256); every
# data-bearing case SKIPs when absent — StrictSkips fails it on this box.
class TitusOldAlbanianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-old-albanian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  URN = "urn:nabu:titus-old-albanian"
  ADAPTER = Nabu::Adapters::TitusOldAlbanian

  def conformance_adapter = ADAPTER.new

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id = SLUG

  def setup
    @adapter = ADAPTER.new
  end

  def documents
    require_fixtures!
    @documents ||= @adapter.discover(FIXTURES).to_h { |ref| [ref.id.split(":").last, @adapter.parse(ref)] }
  end

  def passage(urn)
    documents.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  def test_manifest_carries_the_credit_duty_for_every_edition
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_levels", manifest.parser_family
    assert_equal "nc", manifest.license_class
    ["TITUS", "Hock", "de Vaan", "Demiraj"].each { |name| assert_includes manifest.credit, name }
  end

  def test_the_index_frames_census_286_pages
    require_fixtures!
    census = ADAPTER::EDITIONS.to_h do |id, edition|
      [id, Nabu::TestSupport::TitusIndexCensus.pages(File.join(FIXTURES, id), edition.prefix)]
    end
    assert_equal({ "buzuku" => 146, "blanchus" => 9, "bogdani" => 15, "casasi" => 114, "matranga" => 2 }, census)
    assert_equal 286, census.values.sum
  end

  def test_discover_yields_one_document_per_albanian_page
    require_fixtures!
    assert_equal %w[blanchus.blanc001 bogdani.bogda003 buzuku.buzuk002 matranga.matra001],
                 @adapter.discover(FIXTURES).map { |ref| ref.id.split(":").last }.sort
    assert_equal 0, @adapter.discovery_skips(FIXTURES).skipped_by_rule
  end

  def test_a_page_without_an_albanian_lane_skips_by_rule
    # The rule's shape on a copy of a real page with its Albanian lanes
    # renamed to an editorial-note lane: counted, never parsed.
    require_fixtures!
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "casasi"))
      html = File.read(File.join(FIXTURES, "buzuku", "buzuk002.htm")).gsub("id=bual", "id=ncf")
      File.write(File.join(dir, "casasi", "casas047.htm"), html)
      assert_empty @adapter.discover(dir)
      assert_equal 1, @adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  def test_buzuku_lines_carry_the_print_and_manuscript_pages
    document = documents.fetch("buzuku.buzuk002")
    assert_equal "sqi", document.language
    assert_equal "Old Albanian — Buzuku, Missale (buzuk002)", document.title
    assert_equal 34, document.passages.size
    first = passage("#{URN}:buzuku.buzuk002:Buz._Miss._2_4_62")
    assert_equal "₡ Comemoɿaciona / e ћiξe ſegñtet.", first.text
    last = document.passages.last
    assert_equal "#{URN}:buzuku.buzuk002:Buz._Miss._2_6_5", last.urn
    assert_equal({ "unit" => "Line", "page" => "6", "page_of_ms_a" => "009v" }, last.annotations)
  end

  def test_bogdani_paragraphs_with_their_headings
    document = documents.fetch("bogdani.bogda003")
    assert_equal 81, document.passages.size
    assert_equal({ "Scala" => 1, "Chapter" => 4, "Paragraph" => 74, "Verse" => 2 },
                 document.passages.map { |p| p.annotations["unit"] }.tally)
    assert_match(/\AProfetia ansctè gni tè früm/, passage("#{URN}:bogdani.bogda003:Bogd._Cun.proph._VT_II_I_1").text)
  end

  def test_blanchus_front_matter_keeps_the_albanian_and_annotates_the_latin
    document = documents.fetch("blanchus.blanc001")
    assert_equal 2, document.passages.size, "the Latin title page and dedication mint nothing"
    preface = passage("#{URN}:blanchus.blanc001:Blanch._Dict._(Intr.)_Praef.")
    assert_match(/\AGIξξE ATÜNE TARBENESCEVE GHI/, preface.text)
    assert_match(/\AHoc est ad Epirotas/, preface.annotations["latin"])
    refute(document.passages.any? { |p| p.text.start_with?("ξ ") || p.text.include?("Albanian") },
           "the special-letters legend sits in an editorial note — apparatus")
  end

  def test_the_dated_editions_state_their_own_year
    blanchus = documents.fetch("blanchus.blanc001").metadata
    assert_equal({ "not_before" => 1635, "not_after" => 1635,
                   "raw" => "Romae, Typis Sac.Congr.de Propag. Fide. 1635", "class" => "edition" },
                 blanchus["date"])
    assert_equal "Rome", blanchus["place"]
    assert_match(/Romae: Typis Sac\.Congr\.de Propag\. Fide\. 1635/, blanchus["bibliography"])
    matranga = documents.fetch("matranga.matra001").metadata
    assert_equal "composition", matranga["date"]["class"]
    assert_match(/Dottrina Christiana \(1592\)/, File.read(File.join(FIXTURES, "matranga", "matra001.htm")))
    refute documents.fetch("buzuku.buzuk002").metadata.key?("date")
  end

  def test_matranga_lines
    document = documents.fetch("matranga.matra001")
    assert_equal 8, document.passages.size
    line = passage("#{URN}:matranga.matra001:Matr._Dottr._Pref._XXV_3")
    assert_equal "BAEAERAE per tae Urtaenae Atae Ladesmae", line.text
    assert_equal({ "unit" => "Line", "page" => "XXV" }, line.annotations)
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (no redistribution — bytes live in local/fixtures/, never in git)"
  end
end
