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
    assert_equal %w[tocha001 tocha026 tocha119 tocha234 tocha304 tocha314 tocha348 tocha364 tocha365
                    tocha373 tocha414 tocha453 tocha466], pages
  end

  def test_a_catalogue_only_page_skips_by_rule_and_is_censused
    require_fixtures!
    refute(@adapter.discover(FIXTURES).any? { |ref| ref.metadata["page"] == "tocha227" },
           "A 227 = THT 860 carries the catalogue entry alone — no part, no line")
    skips = @adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_predicate skips, :clean?
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

  # --- the first-sync census shapes (2026-10-10, all 467 pages) -------------

  def test_the_preservation_remark_lane_rides_document_metadata_never_text
    document = documents_by_page.fetch("tocha026")
    citations = document.passages.map { |p| p.urn.split(":").last }
    assert_equal %w[659.26.1 659.26.2 659.26.3], citations
    assert_equal [{ "line" => "659.26.4-6", "note" => "nicht erhalten" }], document.metadata["preservation"]
    refute(document.passages.any? { |p| p.text.include?("erhalten") })
  end

  def test_a_lane_quoted_inside_the_catalogue_prose_folds_into_the_note
    quoted = documents_by_page.fetch("tocha026").metadata["catalogue"].join
    assert_match(/die Silbe po \(oder ṣo\?\) undeutlich/, quoted)
    catalogue = documents_by_page.fetch("tocha373").metadata["catalogue"].join
    assert_includes catalogue, "die akṣara: rmeṣṣe kartse tāko zu lesen sind."
  end

  def test_the_plain_sanskrit_lanes_are_the_same_family_as_the_c_variants
    line = passage("urn:nabu:titus-tocharian-a:tocha365:998.364.2b")
    assert_equal "san", line.language, "iosbpl16 / iosbplx16"
    assert_equal "sujātaṃ yad bravīṣi me |Tn16", line.text, "the generator's '|Tn16' residue rides verbatim"
  end

  def test_an_off_language_syllabic_run_rides_inline_not_as_the_claim
    line = passage("urn:nabu:titus-tocharian-a:tocha348:981.347b.3")
    assert_equal "xto", line.language
    assert_equal({ "san" => "hā hā hā - - -" }, line.annotations["inline_syllabic"])
    refute_includes line.annotations["syllabic"], "hā"
  end

  def test_a_mislabelled_syllabic_mirror_is_the_lines_own_notation
    line = passage("urn:nabu:titus-tocharian-a:tocha453:1087.453a.2b")
    assert_equal "xto", line.language, "the Tocharian transcription decides; the syllabic lane does not vote"
    assert_equal "rapurñe ////", line.text
    assert_equal "rapurñe ////", line.annotations["syllabic"]
    assert_nil line.annotations["inline_syllabic"]
  end

  def test_leaked_whitespace_never_votes_a_language
    line = passage("urn:nabu:titus-tocharian-a:tocha364:997.363.2b")
    assert_equal "san", line.language
    assert_equal "dʰarmaṃ deśaya ////", line.text
  end

  def test_an_interleaved_bilingual_line_claims_tocharian_with_sanskrit_inline
    line = passage("urn:nabu:titus-tocharian-a:tocha414:1048.414a.2")
    assert_equal "xto", line.language
    assert_equal "vāckāñce tRAṅKAL\\ ; |", line.text
    assert_equal({ "san" => "anāgatānām āyuṣmant yaccʰandaṃ pāriśuddʰiṃ cārocayata ārocitañ ca" },
                 line.annotations["inline"])
    assert_match(/\Aʽa-nā-ga-tā/, line.annotations["inline_syllabic"]["san"])
  end

  def test_the_facsimile_link_label_and_leaked_headings_are_never_text
    document = documents_by_page.fetch("tocha119")
    assert_equal 12, document.passages.size
    all = documents_by_page.values.flat_map(&:passages)
    texts = all.flat_map { |p| [p.text, p.annotations["syllabic"].to_s] }
    refute(texts.any? { |t| t.include?("Line:") }, "an unclosed lane span must not swallow the next h5 heading")
    refute(texts.any? { |t| t.match?(/\b(recto|verso)\b/) }, "the image-link label is layout")
    assert_equal 16, documents_by_page.fetch("tocha304").passages.size
  end

  def test_a_severed_utf8_sequence_is_rejoined
    path = File.join(FIXTURES, "tocha314.htm")
    require_fixtures!
    refute_predicate File.binread(path).force_encoding(Encoding::UTF_8), :valid_encoding?
    assert_predicate Parser.read_page(path), :valid_encoding?
    line = documents_by_page.fetch("tocha314").passages.find { |p| p.text.include?("yśe") }
    assert_includes line.text, "yśe k..Ä\\ _ _ _"
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

  def test_blank_lane_text_before_any_line_anchor_carries_nothing
    html = <<~HTML
      <html><body><span id=iotoaxc16>
      <A NAME="TochA_THT_9_1a_1">&nbsp;</A><span id=iotoa16>kus</span></span></body></html>
    HTML
    assert_equal "kus", Parser.parse(html).lines.first.text
  end

  def test_the_note_lane_never_votes_and_never_becomes_text
    html = <<~HTML
      <html><body>
      <A NAME="TochA_THT_9_1a_1">&nbsp;</A><span id=iotoa16>kus</span><span id=iocd16>(unsicher)</span>
      <A NAME="TochA_THT_9_1a_2-3">&nbsp;</A><span id=iocd16>(nicht erhalten)</span>
      </body></html>
    HTML
    page = Parser.parse(html)
    assert_equal ["kus"], page.lines.map(&:text)
    assert_equal "(unsicher)", page.lines.first.note
    assert_equal [%w[9 1a 2-3]], page.notes.map(&:components)
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
