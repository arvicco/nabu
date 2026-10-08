# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TITUS Tocharian A adapter tests (P114-1a): the Berlin Turfan collection's
# East Tocharian manuscripts as TITUS presents them (Sieg & Siegling 1921
# on the data entry of P. Olivier / T. Tamai / K. Kupfer, collated with the
# manuscripts), one document per text page, manuscript LINES as passages
# keyed off the <A NAME="TochA_THT_<ms>_<part>_<line>"> anchors.
#
# The grant (J. Gippert, by email 2026-10-06 — the third extension on the
# Avestan terms) is local personal research only with NO redistribution,
# so the fixture bytes live under the gitignored local/fixtures/
# titus-tocharian-a/ (the seal / corpus-oudnederlands restricted mold) and
# every data-bearing case SKIPs when they are absent — public clones pass
# without the bytes, the owner's box (StrictSkips) tests against reality.
#
# Fixture ground truth (whole real pages retrieved 2026-10-07, see the
# README there): tocha001 (A 1 = THT 634 — word-linked lanes, the
# editorial credit header, a footnote marker), tocha234 (A 234 = THT 867
# — unlinked lanes), tocha466 (A 466 = THT 1100 — the Sanskrit–Tocharian
# bilingual: sub-line anchors 1a/1b alternating san/xto lanes).
class TitusTocharianATest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-tocharian-a"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  Parser = Nabu::Adapters::TitusTocharianParser

  def conformance_adapter
    Nabu::Adapters::TitusTocharianA.new
  end

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id
    SLUG
  end

  def setup
    @adapter = Nabu::Adapters::TitusTocharianA.new
  end

  # --- manifest: the grant's display duty (runs everywhere, no bytes) --------

  def test_manifest_identifies_the_source_with_the_credit_duty
    manifest = Nabu::Adapters::TitusTocharianA.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_tocharian", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Sieg/, manifest.credit, "the edition's editors are part of the display duty")
    assert_match(/Olivier/, manifest.credit, "the data-entry editors are part of the display duty")
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/toch/tocha/tocha.htm", manifest.upstream_url
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_yields_one_document_per_text_page_and_skips_the_frameset
    require_fixtures!
    pages = @adapter.discover(FIXTURES).map { |ref| ref.metadata.fetch("page") }.sort
    assert_equal %w[tocha001 tocha234 tocha466], pages
  end

  def test_page_pattern_excludes_the_frameset_and_index_frames
    re = Nabu::Adapters::TitusTocharianA::PAGE_RE
    assert_match re, "tocha001.htm"
    %w[tocha.htm tochax.htm tochaxx.htm tochax1.htm tochalex.htm].each { |name| refute_match re, name }
  end

  # --- the three page classes ----------------------------------------------

  def test_linked_page_parses_every_manuscript_line
    document = documents_by_page.fetch("tocha001")
    assert_equal "xto", document.language
    assert_equal 12, document.passages.size, "THT 634: six lines recto + six verso"
    assert_equal "Tocharian A Corpus — A 1, THT 634 (tocha001)", document.title
  end

  def test_line_text_is_the_transcription_with_the_syllabic_lane_as_annotation
    line = passage("urn:nabu:titus-tocharian-a:tocha001:634.1a.1")
    refute_nil line
    assert_equal "(kā)su ñoM\\ klyu tsraṣiśśi śäK\\ KAlymentwaṃ SAtkaTAR\\ : yärK\\ ynāñmune " \
                 "nam poto tsraṣṣuneyā PùKAṢ KAl(pnā)-", line.text
    assert_match(/\Asu ño-M\\ klyu tsra-ṣi-śśi/, line.annotations["syllabic"])
    assert_equal "634", line.annotations["manuscript"]
    assert_equal "1a", line.annotations["part"]
    assert_equal "1", line.annotations["line"]
    assert_equal "Vorderseite", line.annotations["side"]
  end

  def test_the_editions_footnote_marker_leaves_the_text_and_rides_as_annotation
    line = passage("urn:nabu:titus-tocharian-a:tocha001:634.1a.1")
    refute_includes line.text, "1 ñoM", "the superscript footnote number is apparatus, not text"
    assert_equal ["1"], line.annotations["footnotes"]
  end

  def test_unlinked_page_keeps_damage_markup_verbatim
    document = documents_by_page.fetch("tocha234")
    assert_equal "xto", document.language
    assert_equal 14, document.passages.size, "THT 867: seven lines each side"
    line = passage("urn:nabu:titus-tocharian-a:tocha234:867.234a.3")
    assert_equal "//// (KA)ṣṣiṃ śpālmeṃ metraKAṃ : pùKAṢ\\ [pu] ////", line.text
    assert_equal "Vorderseite?", line.annotations["side"], "the edition's own uncertainty mark rides verbatim"
  end

  def test_bilingual_page_claims_each_sub_line_by_its_own_lane
    document = documents_by_page.fetch("tocha466")
    assert_equal "xto", document.language, "the corpus language; Sanskrit rides per passage"
    assert_equal 19, document.passages.size
    languages = document.passages.map(&:language).tally
    assert_equal({ "san" => 9, "xto" => 10 }, languages)
    sanskrit = passage("urn:nabu:titus-tocharian-a:tocha466:1100.466a.3b")
    assert_equal "san", sanskrit.language
    assert_equal "kṣemeṇa ;", sanskrit.text
    tocharian = passage("urn:nabu:titus-tocharian-a:tocha466:1100.466a.3c")
    assert_equal "xto", tocharian.language
    assert_equal "ysa ////", tocharian.text
  end

  def test_a_line_without_the_syllabic_lane_carries_no_syllabic_annotation
    html = <<~HTML
      <html><body>
      <span id=h3>Manuscript: 783<A NAME="TochA_THT_783">&nbsp;</A></span>
      <span id=iocd12>No._150 = T_III_Š_80.20</span>
      <span id=h4>Part: 150a<A NAME="TochA_THT_783_150a">&nbsp;</A></span>
      <span id=h5>Line: 1<A NAME="TochA_THT_783_150a_1">&nbsp;</A></span>
      <span id=iotoac16>//// [ku]s n(e) ptāñäktaśśi</span>
      </body></html>
    HTML
    page = Parser.parse(html)
    assert_equal 1, page.lines.size
    assert_nil page.lines.first.syllabic
  end

  # --- document metadata: the catalogue block, mined -------------------------

  def test_document_metadata_carries_the_catalogue_block
    meta = documents_by_page.fetch("tocha234").metadata
    assert_equal "234", meta["edition_number"], "Sieg & Siegling's own number"
    assert_equal "T_III_Š_93.3", meta["signature"], "the Berlin find signature, verbatim"
    assert_equal ["867"], meta["manuscripts"]
    assert_match(/\AKleines Bruchstück aus der Mitte eines Blattes\./, meta["catalogue"].join(" "))
  end

  def test_the_find_signature_site_siglum_mines_the_findspot
    assert_equal "Šorčuq", documents_by_page.fetch("tocha001").metadata["findspot"], "T III Š"
    assert_equal "Qočo", documents_by_page.fetch("tocha466").metadata["findspot"], "T I D"
  end

  def test_an_unknown_site_siglum_mints_no_findspot
    assert_nil Nabu::Adapters::TitusTocharianA.findspot_for("T_II_X_5"),
               "only the censused sigla resolve — never a guessed place"
    assert_nil Nabu::Adapters::TitusTocharianA.findspot_for(nil)
  end

  # --- urn shape ------------------------------------------------------------

  def test_passage_urns_cite_manuscript_part_and_line
    urns = documents_by_page.fetch("tocha001").passages.map(&:urn)
    assert_equal "urn:nabu:titus-tocharian-a:tocha001:634.1a.1", urns.first
    assert_equal "urn:nabu:titus-tocharian-a:tocha001:634.1b.6", urns.last
  end

  # --- defensive quarantines ------------------------------------------------

  def test_an_unknown_content_lane_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h5>Line: 1<A NAME="TochA_THT_9_1a_1">&nbsp;</A></span>
      <span id=iotobx16>something</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { Parser.parse(html) }
    assert_match(/unknown content lane "iotobx16"/, error.message)
  end

  def test_catalogue_and_layout_spans_are_never_lane_text
    html = <<~HTML
      <html><body>
      <span id=h5>Line: 1<A NAME="TochA_THT_9_1a_1">&nbsp;</A></span>
      <span id=iotoa16>kus</span><span id=iocd12>Vorderseite</span><span id=n16> recto</span>
      </body></html>
    HTML
    assert_equal "kus", Parser.parse(html).lines.first.text
  end

  def test_lane_text_before_any_line_anchor_quarantines_the_page
    html = "<html><body><span id=iotoa16>stray words</span></body></html>"
    assert_raises(Nabu::ParseError) { Parser.parse(html) }
  end

  def test_an_over_deep_anchor_quarantines_the_page
    html = '<html><body><A NAME="TochA_THT_9_1a_1_x">&nbsp;</A></body></html>'
    assert_raises(Nabu::ParseError) { Parser.parse(html) }
  end

  def test_a_page_with_no_lines_quarantines_whole
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tocha777.htm"), "<html><body><p>empty</p></body></html>")
      ref = @adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
    end
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (the TITUS grant forbids redistribution — " \
         "bytes live in local/fixtures/, never in git)"
  end

  def documents_by_page
    require_fixtures!
    @documents_by_page ||= @adapter.discover(FIXTURES).to_h do |ref|
      [ref.metadata.fetch("page"), @adapter.parse(ref)]
    end
  end

  def passage(urn)
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn }
  end
end
