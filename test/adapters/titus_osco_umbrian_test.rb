# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TITUS Osco-Umbrian adapter tests (P90-2): the frame-based Sabellic edition,
# one document per text page, inscription lines as passages keyed off the
# <A NAME="Inscr.OU_…"> anchors, the unified Latin transliteration as text
# with the original-script lane riding as annotation. Fixtures are four FULL
# real pages (one per lane class) + the frameset. No network: fetch is
# owner-run only.
class TitusOscoUmbrianTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("titus-osco-umbrian")

  def conformance_adapter
    Nabu::Adapters::TitusOscoUmbrian.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "titus-osco-umbrian"
  end

  def setup
    @adapter = Nabu::Adapters::TitusOscoUmbrian.new
  end

  def documents_by_page
    @documents_by_page ||= @adapter.discover(FIXTURES).to_h do |ref|
      [ref.metadata.fetch("page"), @adapter.parse(ref)]
    end
  end

  def passage(urn)
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_identifies_the_source_with_the_credit_duty
    manifest = Nabu::Adapters::TitusOscoUmbrian.manifest
    assert_equal "titus-osco-umbrian", manifest.id
    assert_equal "titus_osco_umbrian", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Slunečko/, manifest.credit, "the text-entry editors are part of the display duty")
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_yields_one_document_per_text_page_and_skips_the_frameset
    pages = @adapter.discover(FIXTURES).map { |ref| ref.metadata.fetch("page") }.sort
    assert_equal %w[oskum001 oskum012 oskum014 oskum150], pages
  end

  # --- the four page classes (real full-page counts, censused 2026-08-31) ---

  def test_native_umbrian_page_parses_every_line_as_xum
    document = documents_by_page.fetch("oskum001")
    assert_equal "xum", document.language
    assert_equal 34, document.passages.size, "Tabula Ia has 34 lines"
    assert_equal "Osco-Umbrian Corpus — Tabulae Iguvinae Ia (oskum001)", document.title
  end

  def test_native_umbrian_line_carries_transliteration_text_and_italic_original
    first = passage("urn:nabu:titus-osco-umbrian:oskum001:IT.Ia.1")
    refute_nil first
    assert_match(/ESTE: PERSKLUM: AVES: ANZERIATES: ENETU:/, first.text)
    assert_equal "italic", first.annotations["alphabet"]
    assert_equal "IT", first.annotations["monument"]
    assert_equal "Ia", first.annotations["inscription"]
    assert_equal "1", first.annotations["line"]
  end

  def test_latin_alphabet_umbrian_page_is_xum_with_latin_original
    document = documents_by_page.fetch("oskum012")
    assert_equal "xum", document.language
    assert_equal 4, document.passages.size, "Tabula VIIb has 4 lines"
    line = passage("urn:nabu:titus-osco-umbrian:oskum012:IT.VIIb.1")
    assert_equal "latin", line.annotations["alphabet"]
    refute_nil line.annotations["original"], "the capitals lane differs from the lowercase transliteration"
    assert_equal line.text.downcase, line.annotations["original"].downcase.gsub(/\s+/, " ").strip
  end

  def test_oscan_page_parses_as_osc
    document = documents_by_page.fetch("oskum014")
    assert_equal "osc", document.language
    assert_equal 4, document.passages.size, "POMP-2 has 4 lines"
    line = passage("urn:nabu:titus-osco-umbrian:oskum014:BaI.POMP-2.1")
    assert_match(/P\(AAKIS\)/, line.text)
    assert_equal "italic", line.annotations["alphabet"]
  end

  def test_greek_alphabet_oscan_line_keeps_the_greek_original_as_annotation
    document = documents_by_page.fetch("oskum150")
    assert_equal "osc", document.language
    assert_equal 1, document.passages.size
    line = passage("urn:nabu:titus-osco-umbrian:oskum150:WeI.Ross-10.1")
    assert_match(/\]allies dekmas/, line.text, "the unified transliteration is the text")
    assert_equal "greek", line.annotations["alphabet"]
    assert_match(/\]ΑΛΛΙΕΣ ΔΕΚΜΑΣ/, line.annotations["original"])
  end

  # --- urn shape ------------------------------------------------------------

  def test_the_doubled_underscore_empty_level_drops_from_the_citation
    # Anchor Inscr.OU_IT_Ia__1 → citation IT.Ia.1, never IT.Ia..1.
    refute_nil passage("urn:nabu:titus-osco-umbrian:oskum001:IT.Ia.1")
    assert_nil passage("urn:nabu:titus-osco-umbrian:oskum001:IT.Ia..1")
  end

  # --- defensive quarantines ------------------------------------------------

  def test_an_unknown_content_lane_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h5>Line: 1<A NAME="Inscr.OU_IT_Xx__1">&nbsp;</A></span>
      <span id=wevol16><a id=wevol16 href="#">something</a></span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::TitusOscoUmbrianParser.parse(html) }
    assert_match(/unknown content lane "wevol16"/, error.message)
  end

  def test_lane_text_before_any_anchor_quarantines_the_page
    html = "<html><body><span id=weum16>stray words</span></body></html>"
    assert_raises(Nabu::ParseError) { Nabu::Adapters::TitusOscoUmbrianParser.parse(html) }
  end

  def test_a_page_mixing_language_lanes_across_sections_quarantines_whole
    html = <<~HTML
      <html><body>
      <span id=h5>Line: 1<A NAME="Inscr.OU_IT_Ia__1">&nbsp;</A></span>
      <span id=weum16>umbrian words</span>
      <span id=h5>Line: 2<A NAME="Inscr.OU_IT_Ia__2">&nbsp;</A></span>
      <span id=weos16>oscan words</span>
      </body></html>
    HTML
    Dir.mktmpdir do |dir|
      path = File.join(dir, "oskum777.htm")
      File.write(path, html)
      ref = @adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
      assert_match(/mixes language lanes/, error.message)
    end
  end
end
