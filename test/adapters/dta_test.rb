# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Dta (P94-0/1): the Deutsches Textarchiv (BBAW) —
# 5,481 TEI/P5 (DTA-Basisformat) texts, 1473–1969, one stable komplett
# zip, CC BY-SA 4.0. The fixture trio (Luther 1524 / Kant 1784 /
# Fontane 1899) documents the format's load-bearing quirks:
#
# - PAGE-GRAIN passages (the openMGH mold): DTA texts are cited by
#   page/facsimile; the reading flow accumulates and flushes on <pb>,
#   so no element inventory across 5,481 heterogeneous texts (novels,
#   plays, newspapers, dictionaries) can silently lose text. Citation:
#   printed page number when the pb carries @n ("p482"), else the
#   facsimile ordinal ("f0009"); text before any pb is "p0".
# - The ¬<lb/> hyphenation join: "Maſchi¬<lb/>nen" is ONE printed word
#   broken by the typesetter's line, rejoined "Maſchinen" (canonical
#   means canonical, but markup is markup — the openMGH w-pair
#   precedent). A join interrupted by a <pb> defers the page flush so
#   the whole word lands on the page it starts on.
# - AS PRINTED: <choice> keeps the sic/abbr half (the printed reading,
#   errors and abbreviation tildes included); corr/expan/reg — the
#   editors' normalized layers — are deliberately not ingested (v1).
# - <fw> running heads / signature marks / catchwords drop; authorial
#   footnotes (<note>) append at the TAIL of their page's passage —
#   physically where the print puts them.
# - Header: identity is the DTADirName idno; the print year lives ONLY
#   under sourceDesc/biblFull (fileDesc's publicationStmt date is the
#   digital edition's timestamp and must not win).
class DtaTest < Minitest::Test
  include AdapterConformance

  KANT = "urn:nabu:dta:kant_aufklaerung_1784"
  LUTHER = "urn:nabu:dta:luther_elltern_1524"
  FONTANE = "urn:nabu:dta:fontane_stechlin_1899"

  def conformance_adapter
    Nabu::Adapters::Dta.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("dta")
  end

  def conformance_expected_source_id
    "dta"
  end

  def documents
    @documents ||= begin
      adapter = conformance_adapter
      adapter.discover(conformance_workdir).to_h { |ref| [ref.id, adapter.parse(ref)] }
    end
  end

  def doc_text(urn)
    documents.fetch(urn).map(&:text).join("\n")
  end

  # -- discovery / identity -------------------------------------------------

  def test_discovers_the_three_fixtures_by_dirname_identity
    assert_equal [FONTANE, KANT, LUTHER], documents.keys.sort
  end

  def test_header_metadata_rides_the_document
    kant = documents.fetch(KANT)
    assert_equal "Beantwortung der Frage: Was ist Aufklärung?", kant.title
    assert_equal "Kant, Immanuel", kant.metadata["author"]
    assert_equal "1784", kant.metadata["date"]
    assert_equal "Fachtext", kant.metadata["genre"]
    assert_equal "Philosophie", kant.metadata["subgenre"]

    fontane = documents.fetch(FONTANE)
    assert_equal "Der Stechlin", fontane.title
    assert_equal "1899", fontane.metadata["date"]
    assert_equal "Belletristik", fontane.metadata["genre"]

    assert_equal "1524", documents.fetch(LUTHER).metadata["date"]
  end

  def test_the_print_year_wins_over_the_digital_timestamp
    # fileDesc's publicationStmt carries the DTA edition's 2025 timestamp
    # under the SAME date @type; only sourceDesc/biblFull holds the print
    # year. A parser capturing the first date in document order would
    # store the timestamp.
    documents.each_value do |document|
      refute_match(/\A20/, document.metadata["date"].to_s,
                   "#{document.urn}: date must be the print year, not the digital timestamp")
    end
  end

  def test_documents_claim_german
    documents.each_value { |document| assert_equal "de", document.language }
  end

  # -- page grain -----------------------------------------------------------

  def test_passages_are_pages_cited_by_printed_number_or_facsimile
    fontane_urns = documents.fetch(FONTANE).map(&:urn)
    assert_includes fontane_urns, "#{FONTANE}:p1",
                    "printed page numbers (pb @n) mint p-citations"
    kant_urns = documents.fetch(KANT).map(&:urn)
    assert_includes kant_urns, "#{KANT}:f0009",
                    "facs-only page breaks mint f-citations (the title page)"
    assert_includes kant_urns, "#{KANT}:p482",
                    "kant's body pages carry printed numbers"
  end

  def test_blank_scan_pages_mint_no_passages
    kant_urns = documents.fetch(KANT).map(&:urn)
    %w[f0001 f0002 f0003 f0004 f0005 f0006 f0007 f0008].each do |page|
      refute_includes kant_urns, "#{KANT}:#{page}",
                      "the blank front scan pages must not mint empty passages"
    end
  end

  def test_known_page_content
    page1 = documents.fetch(FONTANE).find { |passage| passage.urn.end_with?(":p1") }
    assert_includes page1.text, "Schloß Stechlin.",
                    "the part-title page — bracketed unprinted page numbers ([1]) strip to p1"
    page3 = documents.fetch(FONTANE).find { |passage| passage.urn.end_with?(":p3") }
    assert_includes page3.text, "Im Norden der Grafſchaft Ruppin",
                    "the novel's opening line, long-s orthography as printed"
    title_page = documents.fetch(KANT).find { |passage| passage.urn.end_with?(":f0009") }
    assert_includes title_page.text, "Berliniſche",
                    "front-matter title pages are printed text and parse"
  end

  # -- the hyphenation join -------------------------------------------------

  def test_line_break_hyphenations_rejoin
    assert_includes doc_text(KANT), "Maſchinen",
                    "Maſchi¬<lb/>nen is one printed word"
    assert_includes doc_text(KANT), "Geſellſchaft",
                    "the join also crosses transparent inline markup"
  end

  def test_no_hyphenation_marker_leaks_into_any_passage
    documents.each_value do |document|
      document.each do |passage|
        refute_includes passage.text, "¬",
                        "#{passage.urn}: the ¬ line-break marker is markup, never reading text"
      end
    end
  end

  # -- as printed -----------------------------------------------------------

  def test_choice_keeps_the_printed_reading
    assert_includes doc_text(KANT), "Geſellſchaft ptaktiſcher",
                    "the sic half (a real printing error) is what the page shows — and the " \
                    "Geſell¬<lb/>ſchaft join right before it holds too"
    assert_includes doc_text(FONTANE), "richige Livree",
                    "sic kept in fontane too"
    refute_includes doc_text(FONTANE), "richtige Livree",
                    "the corr half is the editors' layer, not ingested"
    assert_includes doc_text(LUTHER), "deñ",
                    "the abbr half keeps the abbreviation tilde (den + combining tilde, NFC)"
  end

  # -- dropped vs kept apparatus --------------------------------------------

  def test_running_heads_and_signature_marks_drop
    refute_includes doc_text(LUTHER), "Aiij",
                    "fw signature marks are the binder's apparatus, not reading text"
  end

  def test_footnotes_append_at_their_page_tail
    assert_includes doc_text(KANT), "wöchentlichen Nachrichten",
                    "kant's place=foot authorial footnote is printed text and must survive"
  end

  # -- fetch ----------------------------------------------------------------

  def test_fetch_is_zip_fetch_of_the_komplett_archive
    assert_equal "https://www.deutschestextarchiv.de/media/download/dta_komplett_2026-02-10.zip",
                 Nabu::Adapters::Dta::ZIP_URL
  end
end
