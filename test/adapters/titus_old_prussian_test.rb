# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TITUS Old Prussian Corpus adapter tests: the frame-based edition of the
# whole Old Prussian record (W. Euler's data entry after Mažiulis), one
# document per text page, the Old Prussian lines as passages keyed off the
# <A NAME="OPr.Corp._…"> line anchors, a parallel German lane riding as
# the `german` annotation. Fixtures are FULL real pages — one per page
# class (catechism text, Enchiridion front matter with its few Prussian
# lines, the diplomatic superscript page, the Elbing Vocabulary, Grunau's
# vocabulary, the Basel epigram) — plus the two skip classes (German-only
# front matter, an editorial notes page) and the frameset. No network:
# fetch is owner-run only.
#
# The fixture bytes are grant-gated (Gippert, by email 2026-11-12: one
# retrieval, local personal research use, NO redistribution), so they live
# under the gitignored local/fixtures/titus-old-prussian/ (that dir's
# README carries the re-cut recipe + sha256) and every data-bearing case
# SKIPs when absent — on the owner's box StrictSkips makes a skip fail.
class TitusOldPrussianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-old-prussian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  URN = "urn:nabu:titus-old-prussian"

  def conformance_adapter
    Nabu::Adapters::TitusOldPrussian.new
  end

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id
    SLUG
  end

  def setup
    @adapter = Nabu::Adapters::TitusOldPrussian.new
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

  # --- manifest -------------------------------------------------------------

  def test_manifest_identifies_the_source_with_the_credit_duty
    manifest = Nabu::Adapters::TitusOldPrussian.manifest
    assert_equal "titus-old-prussian", manifest.id
    assert_equal "titus_old_prussian", manifest.parser_family
    assert_equal "nc", manifest.license_class, "the titus family's display posture: servable, credited"
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Euler/, manifest.credit, "the data-entry editor is part of the display duty")
    assert_match(/Mažiulis/, manifest.credit, "the edition the text follows is part of the display duty")
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_yields_one_document_per_prussian_text_page
    require_fixtures!
    pages = @adapter.discover(FIXTURES).map { |ref| ref.metadata.fetch("page") }.sort
    assert_equal %w[apreu002 apreu003 apreu015 apreu017 apreu028 apreu029 apreu030 apreu032 apreu033
                    apreu037], pages
  end

  def test_pages_without_an_old_prussian_lane_skip_by_rule_with_accounting
    # apreu001 is Catechism I's German title page and preface (German lanes
    # only); apreu007 is Catechism I's editorial notes page (footnote lanes
    # only). Neither carries Old Prussian text — skipped, counted, named.
    require_fixtures!
    pages = @adapter.discover(FIXTURES).map { |ref| ref.metadata.fetch("page") }
    refute_includes pages, "apreu001"
    refute_includes pages, "apreu007"
    skips = @adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_match(/no Old Prussian text lane/, skips.notes.join(" "))
  end

  # --- Catechism I (1545): the catechism page class -------------------------

  def test_catechism_page_lines_are_old_prussian_passages
    document = documents_by_page.fetch("apreu002")
    assert_equal "prg", document.language
    assert_equal 29, document.passages.size, "the Decalogue page carries 29 Prussian lines"
    assert_equal "Old Prussian Corpus — Catechism I (1545), I._Decal. (apreu002)", document.title
    line = passage("#{URN}:apreu002:Kat.I_I._Decal._1_5_3")
    refute_nil line
    assert_equal "Thou ni tur kittans deiwans tur=", line.text,
                 "the diplomatic line as printed, its hyphenated break kept"
    assert_equal({ "text" => "Kat.I", "part" => "I._Decal.", "paragraph" => "1",
                   "page" => "5", "line" => "3" }, line.annotations)
  end

  def test_footnote_markers_and_their_numbers_are_stripped_from_the_text
    # Line 6 carries two footnote links (* + superscript 1, 2) — apparatus,
    # never text.
    line = passage("#{URN}:apreu002:Kat.I_I._Decal._2_5_6")
    assert_equal "Thou ny tur ſchan emnen twaiſe", line.text
  end

  def test_catechism_pages_carry_the_title_page_print_year
    metadata = documents_by_page.fetch("apreu002").metadata
    assert_equal "Kat.I", metadata["text"]
    assert_equal({ "not_before" => 1545, "not_after" => 1545, "raw" => "1.5.45", "class" => "edition" },
                 metadata["date"])
    refute metadata.key?("place"), "Catechism I's title page names no print place"
  end

  # --- Enchiridion (Catechism III, 1561) ------------------------------------

  def test_enchiridion_front_matter_keeps_only_its_prussian_lines
    # apreu015 is the Enchiridion's title + Duke Albrecht's German preface
    # (hundreds of German lines) with the Prussian title/preface lines among
    # them: only the lines carrying the Prussian lane become passages.
    document = documents_by_page.fetch("apreu015")
    assert_equal 10, document.passages.size
    assert(document.passages.all? { |p| p.text.match?(/\p{L}/) })
    metadata = document.metadata
    assert_equal "Kat.III", metadata["text"]
    assert_equal({ "not_before" => 1561, "not_after" => 1561, "raw" => "M.D. LXI.", "class" => "edition" },
                 metadata["date"])
    assert_equal "Königsberg", metadata["place"], "the title page: Gedruckt zu Kőnigsperg in Preuſſen"
  end

  def test_diplomatic_superscripts_that_are_not_footnotes_stay_in_the_text
    # Kat.III II._Cr. line 21: "giwít ²ſʒ" — the print's own superscript,
    # beside a real footnote link (* 21) that is stripped.
    line = passage("#{URN}:apreu017:Kat.III_II._Cr._2_43_21")
    refute_nil line
    assert_match(/giwít 2ſʒ/, line.text)
    refute_match(/prabuſkai 21/, line.text)
    assert_match(/prabuſkai\z/, line.text)
  end

  # --- the vocabularies -----------------------------------------------------

  def test_the_elbing_vocabulary_parses_its_802_entries
    document = documents_by_page.fetch("apreu028")
    assert_equal "prg", document.language
    assert_equal 802, document.passages.size, "the Elbing Vocabulary's 802 German-Prussian entries"
    assert_equal "Old Prussian Corpus — Elbing Vocabulary (apreu028)", document.title
    assert_equal "Gloss.", document.metadata["text"]
    refute document.metadata.key?("date"), "the edition's header states no date for the vocabulary"
  end

  def test_an_elbing_entry_is_the_prussian_word_with_its_german_headword
    first = passage("#{URN}:apreu028:Gloss._E_1_169a_1")
    assert_equal "Deywis", first.text
    assert_equal "GOt", first.annotations["german"]
    assert_equal "E", first.annotations["part"]
    assert_equal "169a", first.annotations["page"]
    moon = passage("#{URN}:apreu028:Gloss._E_8_169a_8")
    assert_equal "Menig", moon.text, "the footnote link and its number are apparatus"
    assert_equal "Monde", moon.annotations["german"]
  end

  def test_the_elbing_notes_section_mints_no_passages
    notes = documents_by_page.fetch("apreu028").passages.select { |p| p.annotations["paragraph"] == "Anm." }
    assert_empty notes, "footnote lanes (…f12/…fi12) are the editors' apparatus"
  end

  def test_grunau_vocabulary_entries_and_its_german_prose
    document = documents_by_page.fetch("apreu029")
    assert_equal "Old Prussian Corpus — Simon Grunau's vocabulary, GrG (apreu029)", document.title
    assert_equal 106, document.passages.size
    god = passage("#{URN}:apreu029:Gloss._GrG_1_38Ra_2")
    assert_equal "Dewes", god.text
    assert_equal "Gott", god.annotations["german"]
    refute god.annotations.key?("repetition")
    # The chronicle's German prose before the list reuses "Line: 3" down
    # the column (anchor Gloss._GrG__38R_3, repeatedly) — German lanes
    # only, so none of it becomes a passage.
    assert_nil passage("#{URN}:apreu029:Gloss._GrG__38R_3")
    refute(document.passages.any? { |p| p.text.include?("ſprach") })
  end

  def test_a_repeated_line_anchor_keys_its_repeat_by_occurrence
    html = <<~HTML
      <html><body>
      <span id=h3>Part: GrG</span>
      <span id=h5>Page: 38R</span>
      <span id=h6>Line: 3<A NAME="OPr.Corp._Gloss._GrG__38R_3">&nbsp;</A></span>
      <span id=baap16>Dewes</span>
      <span id=h6>Line: 3<A NAME="OPr.Corp._Gloss._GrG__38R_3">&nbsp;</A></span>
      <span id=baap16>Angol</span>
      </body></html>
    HTML
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "apreu777.htm"), html)
      document = @adapter.parse(@adapter.discover(dir).first)
      assert_equal ["#{URN}:apreu777:Gloss._GrG__38R_3", "#{URN}:apreu777:Gloss._GrG__38R_3#2"],
                   document.passages.map(&:urn)
      assert_equal 2, document.passages.last.annotations["repetition"]
    end
  end

  # --- the fragments --------------------------------------------------------

  def test_basel_epigram_keeps_the_prussian_line_and_drops_the_translations
    document = documents_by_page.fetch("apreu033")
    assert_equal 1, document.passages.size,
                 "the English and Lithuanian renderings are the editors' lines, not Old Prussian"
    line = document.passages.first
    assert_equal "#{URN}:apreu033:Fragm._BPT_1___1", line.urn
    assert_match(/\AKayle rekyſe\. thoneaw labonache thewelyſe\. Eg koyte\. poyte\./, line.text)
    refute line.annotations.key?("page"), "the edition's '_' page placeholder is no page"
    assert_equal "Fragm.", document.metadata["text"]
  end

  # --- the first sync's quarantine classes, classified ----------------------

  def test_a_paragraph_break_mid_line_keeps_the_line_tail
    document = documents_by_page.fetch("apreu003")
    line11 = document.passages.find { |passage| passage.urn.end_with?(":apreu003:Kat.I_II._Cr._1_7_11") }
    assert line11, "line 11 of the Creed parses under paragraph 1"
    assert_match(/dangon bah/, line11.text)
    assert_match(/Bah an/, line11.text,
                 "the print line straddles the paragraph break — its tail after the mid-line " \
                 "Paragraph header belongs to the same line (the header's own anchor says the " \
                 "new paragraph begins AT this line)")
  end

  def test_grunau_collation_lanes_ride_as_variant_annotations
    document = documents_by_page.fetch("apreu030")
    with_variants = document.passages.select do |passage|
      passage.annotations.key?("variant_c") || passage.annotations.key?("variant_h")
    end
    refute_empty with_variants,
                 "GrA survives in the C and H manuscript copies — their readings ride as annotations"
    assert(document.passages.all? { |passage| !passage.text.strip.empty? })
  end

  def test_an_absent_page_header_accepts_the_anchor_placeholder
    document = documents_by_page.fetch("apreu037")
    line = document.passages.find { |passage| passage.urn.end_with?(":apreu037:Fragm._OT____1") }
    assert line, "the OT fragment has no Page header and spells the empty page as '_' in its anchors"
    refute line.annotations.key?("page")
  end

  def test_the_collation_table_page_parses_at_paragraph_grain
    document = documents_by_page.fetch("apreu032")
    first = document.passages.find { |passage| passage.urn.end_with?(":apreu032:Gloss._GrColl._1") }
    assert first, "GrColl has no Line headers — each entry is one Paragraph-grain unit"
    assert_match(/\ADewes\b/, first.text)
    assert_equal "dewus", first.annotations["variant_c"]
    assert_equal "Dewus", first.annotations["variant_h"]
  end

  # --- defensive quarantines ------------------------------------------------

  def test_an_unknown_content_lane_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h3>Part: I._Decal.</span>
      <span id=h4>Paragraph: 1</span>
      <span id=h5>Page: 5</span>
      <span id=h6>Line: 1<A NAME="OPr.Corp._Kat.I_I._Decal._1_5_1">&nbsp;</A></span>
      <span id=sapo16>something</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::TitusOldPrussianParser.parse(html) }
    assert_match(/unknown content lane "sapo16"/, error.message)
  end

  def test_prussian_text_outside_any_line_quarantines_the_page
    html = "<html><body><span id=baap16>stray words</span></body></html>"
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::TitusOldPrussianParser.parse(html) }
    assert_match(/outside any line anchor/, error.message)
  end

  def test_an_anchor_disagreeing_with_its_headers_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h3>Part: I._Decal.</span>
      <span id=h4>Paragraph: 1</span>
      <span id=h5>Page: 5</span>
      <span id=h6>Line: 3<A NAME="OPr.Corp._Kat.I_II._Cr._1_5_3">&nbsp;</A></span>
      <span id=baap16>Thou</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::TitusOldPrussianParser.parse(html) }
    assert_match(/does not match its headers/, error.message)
  end

  def test_a_page_with_prussian_lanes_but_no_keyable_line_quarantines
    # An empty Prussian lane passes discovery's byte needle; nothing keys.
    html = <<~HTML
      <html><body>
      <span id=h3>Part: N.</span>
      <span id=baap16></span>
      <span id=baapf12>only a footnote</span>
      </body></html>
    HTML
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "apreu777.htm"), html)
      ref = @adapter.discover(dir).first
      refute_nil ref
      error = assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
      assert_match(/no Old Prussian lines/, error.message)
    end
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (personal grant forbids redistribution — " \
         "bytes live in local/fixtures/, never in git)"
  end
end
