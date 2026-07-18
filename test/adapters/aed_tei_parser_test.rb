# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The aed-tei parser family (P28-1): the TLA/BBAW Ägyptische Wortliste —
# TEI P5 (default namespace), one flat <entry xml:id="tla…"> per lemma with
# exactly one form/orth, one gramGrp/term, one sense (censused over all
# 35,052 upstream entries). The fixture is a byte-verbatim 31-entry slice of
# the real files/dictionary.xml (see test/fixtures/aed/README.md).
class AedTeiParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("aed"), "files", "dictionary.xml")

  def entries
    @entries ||= Nabu::Adapters::AedTeiParser.new.entries(FIXTURE)
  end

  def entry(id) = entries.find { |e| e.entry_id == id }

  # --- stream + identity --------------------------------------------------------

  def test_streams_every_entry_in_file_order
    assert_equal 31, entries.size
    assert_equal %w[tla1 tla10 tla100], entries.first(3).map(&:entry_id)
  end

  def test_entry_id_is_the_upstream_xml_id_verbatim
    # THE JOIN CONTRACT (P28-1): the xml:id IS the TLA lemmaID the AES
    # corpus mints as gold lemmas — kept verbatim, never renumbered, so
    # urn:nabu:dict:aed:<lemmaID> is exactly what an AES annotation predicts.
    assert entry("tla550034"), "the TLA lemmaID tla550034 must be the entry id"
    assert(entries.all? { |e| e.entry_id.match?(/\Atla\d+\z/) })
  end

  # --- headword + fold ----------------------------------------------------------

  def test_headword_is_the_orth_verbatim_nfc_and_key_raw_matches
    vulture = entry("tla1")
    assert_equal "ꜣ", vulture.headword
    assert_equal "ꜣ", vulture.key_raw
    assert_equal "egy", vulture.language
  end

  def test_headword_folded_is_the_egy_search_form
    assert_equal "a", entry("tla1").headword_folded
    assert_equal "aj.wj", entry("tla10").headword_folded
    assert_equal "abd", entry("tla100").headword_folded, "Ꜣbḏ downcases then folds"
    assert_equal "hap-r", entry("tla101340").headword_folded, "ḥꜣp-rʾ — the ʾ drops"
    assert_equal "hai", entry("tla100650").headword_folded, "ḥꜣi̯ — the breve strips"
    assert_equal "nfr", entry("tla550034").headword_folded
  end

  # --- glosses ------------------------------------------------------------------

  def test_gloss_is_the_german_quote_the_complete_lane
    assert_equal "Geier; Vogel (allg.)", entry("tla1").gloss
    assert_equal "[gut; schön]", entry("tla866216").gloss, "root entries gloss too"
    assert_equal "das Hinten (in Präpositionen)", entry("tla100150").gloss,
                 "entries without an English quote keep their German gloss"
  end

  def test_body_carries_grammar_and_every_translation_lane_verbatim
    lines = entry("tla1").body.split("\n")
    assert_equal ["substantive/substantive_masc",
                  "de: Geier; Vogel (allg.)",
                  "bibl: Wb 1, 1.1",
                  "en: vulture; bird (gen.)",
                  "root: tla863246"], lines
  end

  def test_body_carries_the_odd_translation_lanes_by_their_own_code
    assert_includes entry("tla863564").body, "fr: banquet"
    assert_includes entry("tla875429").body, "it: Benevento"
  end

  def test_body_omits_the_bibl_line_when_upstream_bibl_is_empty
    refute_includes entry("tla863246").body, "bibl:"
  end

  # --- Wb print citations (the BDB-pages pattern) -------------------------------

  def test_wb_segments_mint_print_citations_label_verbatim_resolution_deferred
    citation = entry("tla1").citations.fetch(0)
    assert_equal "Wb 1, 1.1", citation.label
    assert_equal "Wb 1, 1.1", citation.urn_raw
    assert_nil citation.cts_work, "Wb is a PRINT dictionary — nothing resolves until a local scan exists"
    assert_equal "1.1", citation.citation, "volume.page — the future deep-link key"
  end

  def test_only_wb_segments_mint_other_print_references_stay_in_the_body
    mansion = entry("tla100000") # bibl: Wb 4, 503.6; GDG IV, 134
    assert_equal ["Wb 4, 503.6"], mansion.citations.map(&:label)
    assert_includes mansion.body, "bibl: Wb 4, 503.6; GDG IV, 134"
    assert_empty entry("tla100").citations, "Meeks, AL 78.0031 is not a Wb citation"
    assert_empty entry("tla851379").citations, "vgl. LGG III, 671c is not a Wb citation"
  end

  def test_wb_citation_shapes_page_only_and_dot_after_volume
    assert_equal "1.270", entry("tla10010").citations.fetch(0).citation, "Wb 1, 270 — page-only"
    smell = entry("tla118230").citations.fetch(0) # upstream quirk: "Wb 3. 293.2-6"
    assert_equal "Wb 3. 293.2-6", smell.label
    assert_equal "3.293", smell.citation
  end

  def test_root_entries_with_empty_bibl_mint_no_citations
    assert_empty entry("tla866216").citations
  end

  # --- cross-references (censused verdict: body lines, not reflex rows) ---------

  def test_xr_lines_carry_type_verbatim_and_every_target
    lines = entry("tla83470").body.split("\n")
    assert_includes lines, "contains: tla550034, tla853734"
    assert_includes lines, "partOf: tla854519"
    assert_includes lines, "root: tla866216"
  end

  def test_root_entries_list_their_derivatives_and_successions
    assert_includes entry("tla872102").body, "rootOf: tla83460"
    assert_includes entry("tla866258").body, "successor: tla128690"
    assert_includes entry("tla106670").body, "predecessor: tla873407"
    assert_includes entry("tla10130").body, "referencedBy: tla172370"
    assert_includes entry("tla101810").body, "referencing: tla101800"
  end

  # --- hygiene ------------------------------------------------------------------

  def test_output_is_nfc
    entries.each do |e|
      assert e.headword.unicode_normalized?(:nfc)
      assert e.body.unicode_normalized?(:nfc)
    end
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dictionary.xml")
      File.write(path, "<TEI><body><entry xml:id=\"tla1\"><form>")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::AedTeiParser.new.entries(path) }
    end
  end

  def test_entry_without_orth_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "dictionary.xml")
      File.write(path, <<~XML)
        <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
        <entry xml:id="tla9"><gramGrp><term>verb/</term></gramGrp></entry>
        </body></text></TEI>
      XML
      assert_raises(Nabu::ParseError) { Nabu::Adapters::AedTeiParser.new.entries(path) }
    end
  end
end
