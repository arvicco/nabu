# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# DbnlTeiParser — the dbnl-tei family (DBNL's house TEI.2, teixlite). The
# fixture facts pinned here are the upstream quirks the six real titles
# document (test/fixtures/dbnl/README.md): folio-cited manuscript pages
# (Rubben), print pages with signature numbering (Vaenius), the pb-less
# div fallback (Dousa), the <c type="shy"> line-end break (Vaenius), the
# <hy> page-end break with its deferred page (Willems), notes and DBNL's
# interp links aside from the text, the header's DBNL fields, and the
# undeclared HTML entities.
module Adapters
  class DbnlTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("dbnl")
    PARSER = Nabu::Adapters::DbnlTeiParser

    def read(name) = PARSER.new.read(File.join(FIXTURES, "#{name}_01.xml"))

    def unit(result, citation) = result.units.find { |u| u.citation == citation } || flunk("#{citation} missing")

    def flat(text) = text.gsub(/[[:space:]]+/, " ").strip

    # -- grain ---------------------------------------------------------------

    def test_a_manuscript_title_is_cited_by_folio
      rubben = read("_rub001rubb01")
      assert_equal :page, rubben.grain
      assert_equal %w[f239vb f240ra f240rb f240va f240vb f241ra f241rb f241va f241vb], rubben.units.map(&:citation)
      first = flat(unit(rubben, "f239vb").text)
      assert first.start_with?("Rubben. Hier beghint die sotternie. Rubben. Ay boy, nu es mi wel becant"), first
      assert_includes flat(unit(rubben, "f240ra").text), "Ic ben hier selve en hebbe een jonc wijf getrout;"
    end

    def test_a_print_is_cited_by_its_page_numbers_and_signatures
      assert_equal %w[p1 p3 p4 p5 p6 p7], read("_cor008cort01").units.map(&:citation),
                   "the blank p2 (pb rend=blank) mints nothing"
      assert_equal %w[pA2r pA2v pB1r pB1v pB2r], read("vaen001embl01").units.map(&:citation)
    end

    def test_a_title_without_page_breaks_falls_back_to_its_outermost_divs
      dousa = read("dous003adia01")
      assert_equal :div, dousa.grain
      assert_equal %w[d1 d2], dousa.units.map(&:citation)
      assert flat(dousa.units.first.text).start_with?("Ad Ianvm Havtenvm HAUTENE, quò me, quò rapis enthei")
      assert flat(dousa.units.last.text).start_with?("Vertaling Jan van der Does de Jonge aan Jan van Hout")
    end

    # -- the joins -----------------------------------------------------------

    def test_a_soft_hyphen_line_break_joins_the_word
      text = flat(unit(read("vaen001embl01"), "pA2r").text)
      assert_includes text, "QVo tempore huic urbi te habere, mihi tecum interdum esse contigit, vidi"
      refute_includes text, "habe-"
    end

    def test_a_page_end_word_break_finishes_on_the_page_it_started_on
      willems = read("will028lala01")
      assert flat(unit(willems, "p40").text).end_with?("aussi faible qu'elle est riche et énergique, puisqu'elle")
      assert flat(unit(willems, "p41").text).start_with?("est la langue du pays, elle doit nécessairement")
      # the deliberate lossy case (the DTA ¬ precedent): a real hyphen at a page end joins too
      assert flat(unit(willems, "p42").text).end_with?("pourquoi les quatre-vingtdix-neuf")
    end

    # -- aside from the text: notes, DBNL links, figures ------------------------

    def test_notes_ride_the_page_annotation_not_the_text
      page = unit(read("will028lala01"), "p2")
      assert_equal [{ "n" => "(1)", "place" => "foot", "text" => "Fables de La Fontaine, liv. 1, fab. 1." }],
                   page.annotations["notes"]
      refute_includes page.text, "La Fontaine"
    end

    def test_dbnl_interp_links_ride_the_page_and_the_text_level_group_the_document
      beeldenstorm = read("_cor008cort01")
      links = unit(beeldenstorm, "p3").annotations["dbnl_interp"]
      assert_equal %w[ieper001 antwe001 midde005 lier_001], links["primair"]
      assert_equal %w[15660815 15660820 15660821], links["secundair"]
      refute_includes unit(beeldenstorm, "p3").text, "ieper001"
      rubben = read("_rub001rubb01")
      assert_equal({ "editeur" => ["leen006"], "primair" => %w[_abe001 _abe001abel01 _rub001rubb01] }, rubben.interps)
      assert_empty unit(rubben, "f239vb").annotations
    end

    def test_figures_drop_but_the_page_text_around_them_stays
      reader = read("_ges002gesc01")
      assert_equal (1..12).map { |n| "p#{n}" }, reader.units.map(&:citation)
      first = flat(unit(reader, "p1").text)
      assert_includes first, "VIERDE DRUK. Genoeg'lijk wordt de Kindertijd"
      refute_includes first, "ill01.gif"
    end

    # Regression (the 2026-11-08 full-zip census: six titles quarantined with
    # "text must not be empty"): a page holding only &nbsp; paragraphs is
    # textless — String#strip keeps U+00A0, so the emptiness test must not.
    def test_an_nbsp_only_page_mints_nothing
      Dir.mktmpdir do |dir|
        path = File.join(dir, "_cor008cort01_01.xml")
        source = File.read(File.join(FIXTURES, "_cor008cort01_01.xml"))
        File.write(path, source.sub('<pb rend="blank" n="2"/>', '<pb rend="blank" n="2"/><p>&nbsp;</p><p>&nbsp;</p>'))
        assert_equal %w[p1 p3 p4 p5 p6 p7], PARSER.new.read(path).units.map(&:citation)
      end
    end

    # -- entities and header -------------------------------------------------

    def test_undeclared_html_entities_expand_and_unknown_ones_are_loud
      assert_equal "a b ǵń &amp; ’", PARSER.expand_entities("a&nbsp;b &gacute;&nacute; &amp; &rsquo;")
      error = assert_raises(Nabu::ParseError) { PARSER.expand_entities("&nosuchentity;", path: "x.xml") }
      assert_includes error.message, "&nosuchentity;"
    end

    def test_the_header_fields
      header = read("_ges002gesc01").header
      assert_equal "De geschiedenis van een goed en van een kwaad kind", header["title"]
      assert_equal "_ges002gesc01_01", header["dbnl_id"]
      assert_includes header["edition_statement"], "een diplomatische weergave van de 4de druk"
      assert_includes header["edition_statement"], "De eerste druk dateert uit 1838."
      assert_equal ["p. 1: De afbeelding en het gedicht op de titelpagina zijn in deze digitale versie in de " \
                    "lopende tekst opgenomen."], header["editorial_interventions"]
      assert_equal "De geschiedenis van een goed en van een kwaad kind. J. Zender, Dordrecht 1840 (4de druk)",
                   header["source_edition"]
      assert_equal "exemplaar Koninklijke Bibliotheek Den Haag, signatuur: 1088 G 107", header["used_copy"]
      assert_equal ["nl"], header["lang_usage"]

      dousa = read("dous003adia01").header
      assert_equal ["Janus Dousa Filius"], dousa["authors"]
      assert_equal ["Joan de Stoppelaar"], dousa["editors"]
      assert_equal %w[la nl], dousa["lang_usage"]
    end

    def test_the_cd_rom_provenance_header_of_a_medieval_title
      header = read("_rub001rubb01").header
      assert_equal ["editie P. Leendertz jr."], header["editors"]
      assert_includes header["edition_statement"], "Cd-rom Middelnederlands"
      assert_includes header["edition_statement"], "Datum: 1400-1420"
      refute header.key?("lang_usage"), "the medieval titles carry no profileDesc"
    end

    def test_a_document_builds_with_nfc_text_and_the_page_urns
      result = read("_rub001rubb01")
      doc = PARSER.new.document(result, urn: "urn:nabu:dbnl:_rub001rubb01_01", language: "dum",
                                        path: File.join(FIXTURES, "_rub001rubb01_01.xml"))
      assert_equal "Rubben", doc.title
      assert_equal "urn:nabu:dbnl:_rub001rubb01_01:f239vb", doc.passages.first.urn
      assert(doc.passages.all? { |p| p.text == p.text.unicode_normalize(:nfc) && !p.text.match?(/\s{2}/) })
    end
  end
end
