# frozen_string_literal: true

require "test_helper"

# The Bosworth-Toller → ASPR crosswalk (P123-1): the census-validated
# Grein/Thorpe sigla resolve onto the held ASPR documents, everything else
# carries verbatim. Inputs are verbatim upstream <references> markup (the
# fixture CSV and the full-dump census strings), never invented shapes.
class BosworthAsprRefsTest < Minitest::Test
  REFS = Nabu::Adapters::BosworthAsprRefs

  def cite(markup)
    REFS.citations(Nokogiri::XML.fragment(markup))
  end

  def targets(markup)
    cite(markup).map { |c| [c.label, c.cts_work, c.citation] }
  end

  def test_validated_poem_line_resolves_at_passage_grain
    assert_equal [["Gen. 375.", "urn:nabu:aspr:A1.1", "375"]],
                 targets("<references><ref>Gen. 375.</ref></references>")
  end

  def test_line_past_the_census_boundary_falls_back_to_document_grain
    # Genesis: Grein's numbering runs +2/+3 past ~2150 — the poem, not the line.
    assert_equal [["Gen. 2486", "urn:nabu:aspr:A1.1", nil]],
                 targets("<references><ref>Gen. 2486</ref></references>")
  end

  def test_document_grain_poems_never_claim_a_line
    assert_equal [["Gú. 816", "urn:nabu:aspr:A3.2", nil]],
                 targets("<references><ref>Gú. 816</ref></references>")
  end

  def test_beowulf_resolves_beside_thorpe_and_never_after_another_siglum
    beowulf = targets("<references><ref>Beo. Th. 1555</ref>; <ref>B. 775</ref></references>")
    assert_equal [["Beo. Th. 1555", nil, nil], ["B. 775", "urn:nabu:aspr:A4.1", "775"]], beowulf

    # Upstream "Mone p. 398; B. 3231" — Mone's glosses, not Beowulf.
    mone = targets("<references><ref>Mone p. 398</ref>; <ref>B. 3231</ref>.</references>")
    assert_equal [["Mone p. 398", nil, nil], ["B. 3231", nil, nil]], mone
  end

  def test_paris_psalter_resolves_to_the_psalm_document_and_prose_psalms_stay_verbatim
    assert_equal [["Ps. Th. 103, 6.", "urn:nabu:aspr:A5.103", nil]],
                 targets("<references><ref>Ps. Th. 103, 6.</ref></references>")
    assert_equal [["Ps. Th. 35, 8", nil, nil]],
                 targets("<references><ref>Ps. Th. 35, 8</ref></references>")
  end

  def test_meters_of_boethius_resolve_meter_and_line
    assert_equal [["Met. 28, 78", "urn:nabu:aspr:A6.28", "78"]],
                 targets("<references><ref>Met. 28, 78</ref></references>")
  end

  def test_unit_resolves_on_its_first_resolvable_segment
    # Thorpe's Caedmon page then Grein's line, one <ref>.
    assert_equal [["Cd. 19; Th. 24, 10", nil, nil], ["Gen. 375.", "urn:nabu:aspr:A1.1", "375"]],
                 targets("<references><ref>Cd. 19; Th. 24, 10</ref>; <ref>Gen. 375.</ref></references>")
  end

  def test_untagged_block_mints_one_unit_per_semicolon_segment
    assert_equal [["Bt. 42", nil, nil], ["Fox 258, 21.", nil, nil]],
                 targets("<references>Bt. 42 ; Fox 258, 21.</references>")
  end

  def test_riddles_stay_verbatim_grein_numbering_is_not_krapp_dobbie
    assert_equal [["Rä. 36, 8", nil, nil]], targets("<references><ref>Rä. 36, 8</ref></references>")
  end

  def test_labels_collapse_whitespace_verbatim
    citation = cite("<references><ref>Ps. Th. 54,\n                             11.</ref></references>").first
    assert_equal "Ps. Th. 54, 11.", citation.label
    assert_equal citation.label, citation.urn_raw
    assert_equal "urn:nabu:aspr:A5.54", citation.cts_work
  end
end
