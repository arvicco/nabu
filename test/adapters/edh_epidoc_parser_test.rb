# frozen_string_literal: true

require "test_helper"
require "stringio"

# EdhEpidocParser unit tests against the three real EDH fixtures (P17-2,
# docs/edh-survey.md §5 fixture plan). Every expected string below is derived
# from the fixture bytes under the policy in the parser header: expansions
# read EXPANDED, supplied read through, gap → "[…]" (a gap-only line is not
# citable), <del> KEPT in ⟦…⟧ (the per-source damnatio divergence), line =
# passage, textpart-relative line numbering in the urn, per-passage language
# by script (the langUsage header lies — survey §1).
class EdhEpidocParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/edh/epidoc", __dir__)
  HD1 = File.join(FIXTURES, "HD000001-HD010000", "HD000001.xml")
  HD82 = File.join(FIXTURES, "HD000001-HD010000", "HD000082.xml")
  HD80825 = File.join(FIXTURES, "HD080001-HD082828", "HD080825.xml")
  HD29093 = File.join(FIXTURES, "HD020001-HD030000", "HD029093.xml")
  HD81183 = File.join(FIXTURES, "HD080001-HD082828", "HD081183.xml")

  HD1_URN = "urn:nabu:edh:hd000001"
  HD82_URN = "urn:nabu:edh:hd000082"
  HD80825_URN = "urn:nabu:edh:hd080825"
  HD29093_URN = "urn:nabu:edh:hd029093"
  HD81183_URN = "urn:nabu:edh:hd081183"

  def parser
    Nabu::Adapters::EdhEpidocParser.new
  end

  def parse1(csv: {}, persons: [])
    parser.parse(HD1, urn: HD1_URN, language: "lat", csv: csv, persons: persons)
  end

  def parse82
    parser.parse(HD82, urn: HD82_URN, language: "lat")
  end

  def parse80825
    parser.parse(HD80825, urn: HD80825_URN, language: "lat")
  end

  # --- core extraction: expansions, lines (HD000001) ------------------------

  def test_abbreviations_read_expanded
    doc = parse1
    assert_equal "Dis Manibus", doc.passages[0].text
    assert_equal "Noniae Publi filiae Optatae", doc.passages[1].text
    assert_equal "Caius Iulius Cai filius Optatus", doc.passages[6].text
  end

  def test_line_grain_urns_without_textparts
    doc = parse1
    assert_equal 8, doc.size
    assert_equal (1..8).map { |n| "#{HD1_URN}:#{n}" }, doc.passages.map(&:urn)
  end

  def test_title_captured_from_the_header
    assert_match(/\AEpitaph from Cumae/, parse1.title)
  end

  # --- supplied + gap + the lb n="0" skip (HD080825) -------------------------

  def test_supplied_reads_through_with_grapheme_count
    doc = parse80825
    line1 = doc.passages[0]
    assert_equal "#{HD80825_URN}:1", line1.urn
    assert_equal "Severus", line1.text
    assert_equal 1, line1.annotations.dig("leiden", "supplied_chars")
  end

  def test_supplied_expansions_expand_inside_the_restoration
    line2 = parse80825.passages[1]
    assert_equal "votum solvit libens merito", line2.text
    assert_equal "solvitlibensmerito".size, line2.annotations.dig("leiden", "supplied_chars")
  end

  def test_gap_only_line_zero_is_not_citable
    doc = parse80825
    assert_equal 2, doc.size
    refute_includes doc.passages.map(&:urn), "#{HD80825_URN}:0",
                    "a lost-line-only lb n=\"0\" extracts no citable text"
  end

  # --- the whole-inscription fallback (P23-3c; the 26 EDH quarantines) --------
  #
  # The P18-gate triage called these "lb-less"; the fixture bytes correct the
  # mechanism: each record HAS <lb> milestones (mostly n="0"), but every line
  # extracts to gap markers only — the WHOLE edition is lost lines (CSV atext
  # "[------]" …). The gap-only-line skip stays the line-grain rule; when it
  # leaves ZERO passages, the parser falls back to ONE whole-inscription
  # passage carrying the edition's own lacuna notation (stable suffix :text),
  # so the real, catalogued inscription lands with all its metadata layers
  # instead of a false "parser failed" quarantine.

  def test_fully_lost_inscription_falls_back_to_one_whole_inscription_passage
    doc = parser.parse(HD29093, urn: HD29093_URN, language: "lat")
    assert_equal 1, doc.size
    passage = doc.passages.first
    assert_equal "#{HD29093_URN}:text", passage.urn
    assert_equal "[…] […]", passage.text, "the edition's own lacuna notation, nothing invented"
    assert_equal "lat", passage.language
    assert_equal [{ "reason" => "lost", "quantity" => 1, "unit" => "line" }] * 2,
                 passage.annotations.dig("leiden", "gaps")
  end

  # The textpart-shaped variant of the same class: the fallback is
  # whole-INSCRIPTION grain, so no textpart path enters the suffix.
  def test_fallback_suffix_is_flat_even_across_textparts
    doc = parser.parse(HD81183, urn: HD81183_URN, language: "lat")
    assert_equal ["#{HD81183_URN}:text"], doc.passages.map(&:urn)
    assert_equal "[…] […]", doc.passages.first.text
  end

  # The edition <head> ("Text") is never reading text — it must not leak into
  # the fallback passage (it was invisible to line grain only because no line
  # was open around it).
  def test_edition_head_label_does_not_leak_into_the_fallback
    doc = parser.parse(HD29093, urn: HD29093_URN, language: "lat")
    refute_match(/Text/, doc.passages.first.text)
  end

  def test_fallback_urns_are_stable_across_two_parses
    first = parser.parse(HD29093, urn: HD29093_URN, language: "lat")
    second = parser.parse(HD29093, urn: HD29093_URN, language: "lat")
    assert_equal first.passages.map(&:urn), second.passages.map(&:urn)
    assert_equal first.passages.map(&:text), second.passages.map(&:text)
  end

  # Line-grain documents never fall back: HD080825 still skips its lb n="0"
  # lost line and keeps exactly its two citable lines (no :text passage).
  def test_documents_with_citable_lines_never_mint_the_fallback
    refute_includes parse80825.passages.map(&:urn), "#{HD80825_URN}:text"
  end

  # Malformed upstream XML (hd059778's class) stays an honest permanent
  # quarantine — the fallback is for parsed-but-lost editions only.
  def test_malformed_xml_still_quarantines_not_falls_back
    assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new("<TEI><teiHeader><link></head></TEI>"),
                   urn: HD29093_URN, language: "lat", canonical_path: "/x/HD059778.xml")
    end
  end

  # --- the <del> divergence: damnatio kept in ⟦…⟧ (HD000082) -----------------

  def test_erasure_is_kept_wrapped_in_leiden_double_brackets
    doc = parse82
    # The closing bracket sits MID-WORD (the final -s survived the chisel),
    # exactly where the erasure ends — the gap-marker placement philosophy.
    assert_equal "Lucius Licinius Luci ⟦filius Crassu⟧s", doc.passages[0].text
    assert_equal "consularis ⟦orator⟧", doc.passages[1].text
  end

  def test_erased_lines_carry_the_cancelled_annotation
    doc = parse82
    assert doc.passages[0].annotations.dig("leiden", "cancelled")
    assert doc.passages[1].annotations.dig("leiden", "cancelled")
    assert_nil doc.passages[2].annotations.dig("leiden", "cancelled"), "the Greek side is not erased"
  end

  # --- bilingual textparts: urns restart, language by script -----------------

  def test_textpart_line_restarts_mint_textpart_urns
    doc = parse82
    assert_equal %W[#{HD82_URN}:1:1 #{HD82_URN}:1:2 #{HD82_URN}:2:1 #{HD82_URN}:2:2 #{HD82_URN}:2:3],
                 doc.passages.map(&:urn)
  end

  def test_greek_textpart_lines_are_tagged_grc_per_passage
    doc = parse82
    assert_equal "lat", doc.language, "document language comes from the CSV nl_text, not the header"
    assert_equal %w[lat lat grc grc grc], doc.passages.map(&:language)
    assert_equal "Ὅμηρος", doc.passages[2].text
    assert_equal "θεῖος ποιητής", doc.passages[4].text
  end

  def test_greek_lines_fold_as_greek
    homer = parse82.passages[2]
    assert_equal Nabu::Normalize.search_form("Ὅμηρος", language: "grc"), homer.text_normalized
  end

  # --- header layers → metadata facets ---------------------------------------

  def test_facet_values_come_from_the_records_own_eagle_terms
    facets = parse80825.metadata["facets"]
    assert_equal "votive inscription", facets.dig("genre", "value")
    assert_equal "Germania inferior", facets.dig("province", "value")
    assert_equal "Sandstein", facets.dig("material", "value")
    assert_equal "altar", facets.dig("object_type", "value")
  end

  def test_facet_raws_come_from_the_csv_verbatim
    csv = { "i_gattung" => "titsac", "provinz" => "GeI", "material" => "Sandstein", "denkmaltyp" => "Altar" }
    facets = parser.parse(HD80825, urn: HD80825_URN, language: "lat", csv: csv).metadata["facets"]
    assert_equal({ "value" => "votive inscription", "raw" => "titsac" }, facets["genre"])
    assert_equal({ "value" => "Germania inferior", "raw" => "GeI" }, facets["province"])
    assert_equal({ "value" => "altar", "raw" => "Altar" }, facets["object_type"])
  end

  def test_uncertainty_survives_in_the_raw
    facets = parser.parse(HD1, urn: HD1_URN, language: "lat",
                               csv: { "i_gattung" => "titsep?" }).metadata["facets"]
    assert_equal "titsep?", facets.dig("genre", "raw")
    assert_equal "epitaph", facets.dig("genre", "value")
  end

  # --- persons + annotation riders -------------------------------------------

  def test_persons_and_crosswalk_ids_ride_in_document_metadata
    persons = [{ "nomen" => "Nonia", "cognomen" => "Optata", "sex" => "W", "filiation" => "P.f." }]
    doc = parse1(csv: { "tm_nr" => "251193", "literatur" => "AE 1983, 0192. # M. Annecchino. #" },
                 persons: persons)
    assert_equal persons, doc.metadata["persons"]
    assert_equal "251193", doc.metadata["tm_nr"]
    assert_equal ["AE 1983, 0192.", "M. Annecchino."], doc.metadata["literature"]
  end

  def test_empty_metadata_layers_are_absent_not_blank
    metadata = parse1.metadata
    refute metadata.key?("persons")
    refute metadata.key?("tm_nr")
    refute metadata.key?("verse")
  end

  # --- identity + error surfaces ----------------------------------------------

  def test_urn_mismatch_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      parser.parse(HD1, urn: "urn:nabu:edh:hd999999", language: "lat")
    end
    assert_match(/urn mismatch/, error.message)
    assert_match(/hd000001/, error.message)
  end

  def test_missing_local_id_is_a_parse_error
    xml = File.read(HD1).sub('<idno type="localID">HD000001</idno>', "")
    error = assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(xml), urn: HD1_URN, language: "lat", canonical_path: "/x/HD000001.xml")
    end
    assert_match(/localID/, error.message)
  end

  def test_malformed_xml_is_a_parse_error
    assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new("<TEI><broken"), urn: HD1_URN, language: "lat", canonical_path: "/x/broken.xml")
    end
  end

  def test_io_without_path_requires_canonical_path
    assert_raises(ArgumentError) do
      parser.parse(StringIO.new("<x/>"), urn: HD1_URN, language: "lat")
    end
  end

  # --- stability ---------------------------------------------------------------

  def test_two_parses_mint_identical_urns_and_text
    first = parse82
    second = parse82
    assert_equal first.passages.map(&:urn), second.passages.map(&:urn)
    assert_equal first.passages.map(&:text), second.passages.map(&:text)
  end

  # The family's structural streaming contract (DdbdpParser sibling rule).
  def test_implementation_streams_and_never_builds_a_full_document_dom
    source = File.read(File.expand_path("../../lib/nabu/adapters/edh_epidoc_parser.rb", __dir__))
    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end
end
