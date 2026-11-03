# frozen_string_literal: true

require "test_helper"

# The Littré TEI parser family (oeuvres/littre, XMLittré lineage), run
# against the trimmed-real littre fixtures.
class LittreTeiParserTest < Minitest::Test
  def entries(letter)
    path = File.join(Nabu::TestSupport.fixtures("littre"), "xml", "#{letter}.xml")
    Nabu::Adapters::LittreTeiParser.new.entries(path, letter: letter)
  end

  def entry(letter, id) = entries(letter).find { |e| e.entry_id == id }

  def test_entry_ids_are_upstream_xml_ids_in_file_order
    assert_equal %w[b baal], entries("b").map(&:entry_id)
  end

  def test_a_repeated_id_within_a_file_is_numbered_from_its_second_occurrence
    assert_equal %w[gommeux gommeux:2], entries("g").map(&:entry_id)
    assert_match(/\AGOMMEUX \(go-meû\) s\. m\./, entry("g", "gommeux:2").body)
  end

  def test_an_entry_filed_under_another_letter_carries_its_file_letter
    assert_equal %w[salleran ignoramment@s], entries("s").map(&:entry_id)
    assert_equal "ignoramment", entry("s", "ignoramment@s").headword
    assert_equal "ignoramment", entries("i").first.entry_id
  end

  def test_headword_is_the_id_lemma_and_key_raw_the_printed_orth
    baal = entry("b", "baal")
    assert_equal "baal", baal.headword
    assert_equal "BAAL", baal.key_raw
    able = entry("a", "able.2")
    assert_equal "able", able.headword, "the homograph number is dropped from the lemma"
    assert_equal "Ce suffixe a deux significations", able.gloss, "an entryFree is an entry too"
  end

  def test_body_renders_head_senses_citations_and_etymology
    lines = entry("b", "baal").body.lines(chomp: true)
    assert_equal "BAAL (ba-al) s. m.", lines[0]
    assert_equal "Grande divinité des Assyriens, que les Grecs assimilaient à leur Jupiter.", lines[1]
    assert_match(/\A« Qui peut vous inspirer .* ni le Dieu d'Israël » \(RAC\., Ath\. III, 3\)\z/, lines[2])
    assert_equal "ÉTYM. Mot assyrien et hébreu qui signifie seigneur.", lines.last
  end

  def test_numbered_senses_and_the_historique
    assert_match(/^1° Qui jette de la gomme\./, entry("g", "gommeux").body)
    b = entry("b", "b").body
    assert_includes b, "\nHIST.\nXIIIe s.\n« Je ne puis bien nommer sans B"
  end

  def test_gloss_is_the_first_definition_to_its_first_sentence_end
    assert_equal "Grande divinité des Assyriens, que les Grecs assimilaient à leur Jupiter", entry("b", "baal").gloss
    assert_equal "Seconde lettre de l'alphabet", entry("b", "b").gloss
    assert_nil entry("g", "gommeux:2").gloss, "a citation-only article has no definition"
  end

  def test_part_of_speech_and_first_attested_century_are_mined
    assert_equal({ "pos" => "s. m.", "first_attested" => "XIIIe s." }, entry("b", "b").annotations)
    assert_equal({ "pos" => "s. m." }, entry("b", "baal").annotations)
  end

  def test_output_is_nfc_and_folded
    entries("g").each do |e|
      assert e.body.unicode_normalized?(:nfc)
      assert_equal Nabu::Normalize.search_form(e.headword, language: "fra"), e.headword_folded
    end
  end
end
