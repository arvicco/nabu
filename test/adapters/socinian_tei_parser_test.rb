# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The socinian-tei parser family over the real fixture letters (no policy:
  # every component and witness comes back; the adapter chooses).
  class SocinianTeiParserTest < Minitest::Test
    LETTERS = File.join(Nabu::TestSupport.fixtures("socinian-letters"), "data", "xml", "letters")
    PARSER = Nabu::Adapters::SocinianTeiParser

    def parse(name) = PARSER.new.parse(File.join(LETTERS, "LETTER_#{name}.xml"))

    def test_components_and_witnesses_come_back_in_document_order
      result = parse("MAIN_lfw_qlm_zdb")
      assert_equal %w[cover_letter attachment], result.components.map(&:role)
      assert_equal %w[MAIN_lfw_qlm_zdb MAIN_ckw_qlm_zdb], result.components.map(&:id)
      assert_equal ["reference_witness"], result.components.first.witnesses.map(&:designation)
    end

    def test_every_witness_header_is_read
      anw = parse("MAIN_anw_qlm_zdb").components.first
      reference, second = anw.witnesses
      assert_equal ["reference_witness", nil], [reference.designation, second.designation]
      refute reference.transcribed?, "the base print's <p/> body"
      assert second.transcribed?
      assert_equal "Druck", second.medium
      assert_equal ["lat"], second.languages
      ydw = parse("MAIN_ydw_qlm_zdb").components.first.witnesses.first
      assert_equal "https://creativecommons.org/licenses/by-sa/3.0/", ydw.licence_target
      assert_includes ydw.licence_text, "CC BY-SA 3.0"
    end

    def test_correspdesc_actions
      sent, received = parse("MAIN_ckw_qlm_zdb").components.first.actions
      assert_equal "sent", sent.type
      assert_equal [{ "name" => "Rautenstein, Johann Ernst von", "key" => "Rautenstein" }], sent.persons
      assert_equal [{ "name" => "Regensburg", "key" => "Regensburg" }], sent.places
      assert_equal({ "when" => "1665-10-15" }, sent.date)
      assert_equal "received", received.type
    end

    def test_reading_text_rules
      blocks = parse("MAIN_dq3_2dc_b2b").components.first.witnesses.first.blocks
      text = blocks.map(&:text).join("\n")
      assert_includes text, "salutem plurimam dicit", "choice → expan"
      refute_includes text, "S. P. D."
      assert_includes text, "et de illius […] inquiretur", "gap → the house mark"
      refute_includes text, "pontif. pontificem"
      assert_equal %w[opener p p p p p p postscript closer], blocks.map(&:tag)
    end

    def test_a_metadata_only_letter_has_no_blocks
      result = parse("MAIN_ed_nnl_xb5_r5b")
      assert(result.components.flat_map(&:witnesses).none?(&:transcribed?))
    end

    def test_a_non_corpus_root_is_a_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "x.xml")
        xml = File.read(File.join(LETTERS, "LETTER_MAIN_ckw_qlm_zdb.xml"))
        File.write(path, xml.sub(/\A<teiCorpus/, "<tei").sub(%r{</teiCorpus>\s*\z}, "</tei>\n"))
        assert_raises(Nabu::ParseError) { PARSER.new.parse(path) }
      end
    end
  end
end
