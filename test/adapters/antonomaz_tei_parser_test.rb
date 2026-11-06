# frozen_string_literal: true

require "test_helper"

# The antonomaz-tei family (first consumer: mazarinades) against real
# Antonomaz corpus files (test/fixtures/mazarinades/tree — see its README):
# a one-page Google Books title page, a Mazarine print with vue-numbered
# pages and lb break="no" continuations, a Gallica verse piece with running
# heads, catchwords and a margin note, a Picard dialogue, a hand-transcribed
# piece, and one of upstream's malformed files.
class AntonomazTeiParserTest < Minitest::Test
  TREE = File.join(Nabu::TestSupport.fixtures("mazarinades"), "tree", "Mazarinades")
  MALFORMED = File.join(Nabu::TestSupport.fixtures("mazarinades"), "malformed", "Mazarinades",
                        "1901-2000", "Moreau1902_MANUAL.xml")

  def parse(rel) = Nabu::Adapters::AntonomazTeiParser.new.parse(File.join(TREE, rel))

  # --- pages and lines ----------------------------------------------------------

  def test_one_page_per_pb_lines_joined_by_newline
    parsed = parse("1401-1500/Moreau1483_GBOOKS.xml")
    assert_equal ["1"], parsed.pages.map(&:key)
    page = parsed.pages.first
    assert_equal "LE\nGENEREVX\nPRINCE\nAVX PARISIENS\nDE\nMOURIR POUR LE SERVICE DV ROY\n" \
                 "& de ne point ſouffrir le retour du Cardinal\nMazarin.\nA PARIS\n" \
                 "Chez NICOLAS L'ANGEVIN.\nM. DC. LII.", page.text
    assert page.manual_correction, "the first page carries upstream's manual_correction=yes"
    assert_equal 1, page.gaps
  end

  def test_vue_pages_skip_empty_scans_and_mark_continued_lines
    parsed = parse("2101-2200/Moreau2135_MAZ.xml")
    assert_equal %w[v9 v12], parsed.pages.map(&:key), "vues 10 and 11 carry no text (a gap only)"
    title, body = parsed.pages
    assert title.text.end_with?("M. DC. LII.\nAVEC PRIVILEGE DU ROY."), "the imprimatur is printed text"
    assert_equal ["decoration"], title.figures
    assert_equal "9", title.vue
    lines = body.text.split("\n")
    assert_equal "laiſſer, en l’interpretant par celuy de noſtre Con", lines[2]
    assert_equal "ſcil, que nous vous enuoyons, Nous auons telle", lines[3]
    assert_includes body.continued_lines, 4, "line 4 opens with lb break=\"no\" — the word continues"
    refute_includes body.continued_lines, 3
  end

  def test_formatting_whitespace_inside_a_line_collapses
    parsed = parse("1001-1100/Moreau1085-i_MAZ.xml")
    assert_equal %w[v9 v11 v12 v13], parsed.pages.first(4).map(&:key), "vue 10 is blank"
    assert_equal "Sur les affaires de cee temps.", parsed.pages.first.text.split("\n")[4]
    assert parsed.pages[1].text.start_with?("DIALOGVE DE\ntrois payſans Picards.\n")
  end

  def test_running_heads_catchwords_and_margin_notes_leave_the_text
    parsed = parse("601-700/Moreau614_GALL.xml")
    assert_equal %w[1 3 4 5 6], parsed.pages.map(&:key), "page 2 is blank"
    assert_equal "https://gallica.bnf.fr/ark:/12148/bpt6k5675043p/f2.highres", parsed.pages.first.facs
    assert parsed.pages.first.text.start_with?("7\nBVRLESQUE\n"), "a run before the first lb is a line"
    four = parsed.pages[2]
    assert_equal [{ "type" => "catch", "place" => "bot-right", "text" => "Pour" }], four.furniture
    refute_includes four.text, "Pour\n"
    six = parsed.pages[4]
    assert_equal [{ "type" => "pageNum", "place" => "top-center", "text" => "6" }], six.furniture
    assert_equal [{ "place" => "margin-left", "text" => "Phoſphorin,\nmot Grec qui\nſignifie Lu\ncifer." }],
                 six.notes
    assert_equal "Le voyez-vous qui prend la fuitte\nAuec ſa deteſtable ſuitte,\nAdieu Demon Incarnadin,\n" \
                 "Bruſle à iamais dedans l'enfer\nAuec ton frere Lucifer.\nFIN.", six.text
  end

  def test_a_pb_used_as_a_container_still_pages_its_lines
    parsed = parse("4001-4100/Moreau4018_GALL.xml")
    assert_equal %w[2 4 5], parsed.pages.map(&:key), "four upstream files wrap each page's lines in <pb>…</pb>"
    assert parsed.pages.first.text.start_with?("VERS PRESENTEZ\nA\n")
    assert parsed.pages.first.text.end_with?("M. DC. XLIX.")
  end

  # --- the header ---------------------------------------------------------------

  def test_header_bibliography
    header = parse("2101-2200/Moreau2135_MAZ.xml").header
    assert_equal "Moreau2135_MAZ", header.xml_id
    assert_equal "Lettre du roy à messieurs les prévôt des marchands et échevins de sa bonne ville de Paris " \
                 "sur l'assurance du payement des rentes, de Saumeur , le seizième de février 1652.", header.title
    assert_equal "Moreau", header.title_source
    assert_equal [{ "source" => "Mazarine", "when" => "1652", "text" => "1652" },
                  { "source" => "Carrier", "when" => "1652", "not_before" => "1652-02-21",
                    "not_after" => "1652-02-28", "text" => "dernière semaine de février 1652" }], header.dates
    assert_equal({ "name" => "Paris", "ref" => "geonames:2988507", "source" => "Mazarine" }, header.pub_place)
    assert_equal [{ "name" => "Louis XIV", "ref" => "isni:0000000383255772", "source" => "Mazarine" }],
                 header.authors
    assert_equal({ "name" => "Pierre Rocolet", "ref" => "isni:0000000008903969" }, header.publisher)
    assert_equal 4, header.extent_pages
    assert_equal "in-4", header.format
    assert_equal ["lettre"], header.genres
    assert_equal ["prose"], header.forms
    assert_equal [{ "text" => "Rentes de l'Hôtel de Ville", "ref" => "institution/fiscalite.xml" }], header.subjects
    assert_equal [{ "id" => "evt_Moreau_65", "source" => "Moreau",
                    "label" => "Arrêt du parlement pour le payement des rentes de l’Hôtel de Ville",
                    "when" => "1652-02-08" }], header.settings
    assert header.abstracts["Moreau"].start_with?("2135. Lettre du roy")
    assert_equal({ "settlement" => "Paris", "institution" => "Bibliothèque Mazarine", "idno" => "M11599" },
                 header.holding)
    assert_equal ["https://mazarinum.bibliotheque-mazarine.fr/ark:/61562/mz14712"], header.digitizations
    assert_equal [{ "source" => "Mazarine", "subtype" => "BM49213", "cert" => "high",
                    "target" => "https://mazarinades.bibliotheque-mazarine.fr/ark:/61562/bm49213" }],
                 header.identifiers
  end

  def test_the_licence_element_and_the_odd_availability
    header = parse("2101-2200/Moreau2135_MAZ.xml").header
    assert_equal "https://creativecommons.org/licenses/by/4.0", header.licence
    assert_equal({ "n" => "cc-by", "status" => "restricted" }, header.availability)
    assert_equal({ "n" => "NaN", "status" => "restricted" },
                 parse("1001-1100/Moreau1021_GBOOKS.xml").header.availability)
  end

  def test_text_origin_reads_the_project_statement
    assert_equal :ocr, parse("1401-1500/Moreau1483_GBOOKS.xml").header.text_origin
    manual = parse("2501-2600/Moreau2542_MANUAL.xml").header
    assert_equal :manual, manual.text_origin
    assert_includes manual.origin_statement, "transcription manuelle réalisée par Karine Abiven"
  end

  def test_languages_follow_the_label
    assert_equal [{ "ident" => "other", "label" => "Document en picard" }],
                 parse("1001-1100/Moreau1085-i_MAZ.xml").header.languages
    assert_equal [{ "ident" => "fra", "label" => "Document en français" }],
                 parse("1401-1500/Moreau1483_GBOOKS.xml").header.languages
  end

  # --- refusal ------------------------------------------------------------------

  def test_malformed_xml_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::AntonomazTeiParser.new.parse(MALFORMED) }
    assert_match(/Moreau1902_MANUAL\.xml: malformed XML/, error.message)
  end
end
