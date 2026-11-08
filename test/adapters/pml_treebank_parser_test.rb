# frozen_string_literal: true

require "test_helper"
require "stringio"

module Adapters
  # The aldt-pml parser family (P164) over the real LLCT1 fixture trim: the
  # lexical tree-span scan, fragment reading, nesting → head edges, and the
  # surface/lemma rules. No adapter policy here (charter grouping, identity
  # and metadata are Adapters::Llct1's).
  class PmlTreebankParserTest < Minitest::Test
    FIXTURE = File.join(Nabu::TestSupport.fixtures("llct1"), "llct1-1.2.xml")
    PARSER = Nabu::Adapters::PmlTreebankParser

    def bytes = PARSER.read(FIXTURE)
    def spans = PARSER.tree_spans(bytes)

    def test_tree_spans_find_every_top_level_tree_with_its_root_attributes
      all = spans
      assert_equal 29, all.size, "the trim holds 29 sentence trees (5 + 2 + 11 + 11)"
      first = all.first
      assert_equal "2935509", first.id
      assert_equal({ "document_id" => "CDL", "subdoc" => "115", "date" => "754",
                     "place" => "S. Cassiano (di Moriano o a Vico?, Lucca)", "scribe" => "Osprand",
                     "type" => "charta dotis", "redaction" => "copy" }, first.attributes)
      assert_equal %w[CDL CDT MED], all.map { |s| s.attributes["document_id"] }.uniq
    end

    def test_a_span_is_exactly_one_balanced_tree
      span = spans.find { |s| s.id == "2936672" }
      slice = bytes.byteslice(span.offset, span.length)
      assert_equal Encoding::BINARY, bytes.encoding, "#read hands back a byte-offset buffer"
      assert slice.start_with?('<LM id="2936672" document_id="CDL" subdoc="208"')
      assert slice.end_with?("</LM>")
      assert_equal slice.scan("<LM ").size, slice.scan("</LM>").size
    end

    def test_trees_read_a_fragment_cut_from_spans
      chosen = spans.select { |s| s.attributes["subdoc"] == "208" }
      fragment = PARSER.fragment(bytes, chosen.map { |s| [s.offset, s.length] }, path: FIXTURE)
      assert_equal Encoding::UTF_8, fragment.encoding
      assert fragment.valid_encoding?
      trees = PARSER.new.trees(StringIO.new(fragment), path: FIXTURE)
      assert_equal %w[2936672 2936673], trees.map(&:id)
      assert_equal "breve", trees.first.attributes["type"]
      assert_equal 27, trees.first.tokens.size
    end

    def test_tokens_come_back_in_word_order_with_heads_from_the_nesting
      tree = whole_trees.find { |t| t.id == "2936672" }
      assert_equal((1..27).map(&:to_s), tree.tokens.map { |t| t["id"] })
      breue = tree.tokens.find { |t| t["form"] == "breue" }
      assert_equal "0", breue["head"], "a child of the sentence root heads to 0"
      scriptum = tree.tokens.find { |t| t["form"] == "scriptum" }
      assert_equal "3", scriptum["head"], "nested under breue (id 3)"
      assert_equal({ "id" => "4", "relation" => "ATR", "seg" => "free", "status" => "normal",
                     "declension" => "2", "animacy" => "-", "iobj" => "-", "form" => "scriptum",
                     "lemma" => "scribo1", "pos" => "participle", "number" => "singular",
                     "tense" => "perfect", "mood" => "participial", "voice" => "passive",
                     "gender" => "masculine", "case" => "accusative", "head" => "3" }, scriptum,
                   "upstream attributes verbatim, in upstream order, plus the derived head")
    end

    def test_parse_builds_sentence_passages_with_glued_punctuation
      document = parse_whole
      assert_equal 29, document.size
      passage = document.find { |p| p.urn.end_with?(":2936672") }
      assert_equal "Et ecce breue scriptum, quam dictauit Barbenti presbiter, de casis et pertinentia " \
                   "et hominibus sancti Quirici, quam Osprandus diaconus scripsit per eius dictatum.",
                   passage.text
      assert_equal "urn:test:llct1:2936672", passage.urn
      assert_equal "lat", passage.language
    end

    def test_lacuna_markers_stay_spaced_words
      passage = parse_whole.find { |p| p.urn.end_with?(":2935511") }
      assert_includes passage.text, "ego Austripert ..... o in hoc seculo"
    end

    def test_placeholder_and_punctuation_lemmas_are_dropped
      tokens = parse_whole.flat_map { |p| p.annotations.fetch("tokens") }
      period = tokens.find { |t| t["form"] == "." }
      refute period.key?("lemma"), "unknown1 on punctuation is not a dictionary form"
      assert_equal "unknown1", period["lemma_placeholder"], "the placeholder survives under its own key"
      lacuna = tokens.find { |t| t["form"] == "....." }
      refute lacuna.key?("lemma")
      refute(tokens.any? { |t| %w[unknown1 other].include?(t["lemma"]) })
      nomine = tokens.find { |t| t["form"] == "nomine" }
      assert_equal %w[nomen 1], nomine.values_at("lemma", "lemma_homograph"),
                   "the LDT homograph index splits off the dictionary form, kept beside it"
    end

    def test_trees_stay_raw_upstream_values
      tokens = whole_trees.flat_map(&:tokens)
      assert_equal "nomen1", tokens.find { |t| t["form"] == "nomine" }["lemma"]
      assert_equal "unknown1", tokens.find { |t| t["form"] == "." }["lemma"]
    end

    def test_a_range_past_the_buffer_is_a_parse_error
      error = assert_raises(Nabu::ParseError) do
        PARSER.fragment(bytes, [[bytes.bytesize - 10, 50]], path: FIXTURE)
      end
      assert_match(/reaches past the end/, error.message)
    end

    def test_malformed_xml_is_a_parse_error
      assert_raises(Nabu::ParseError) do
        PARSER.new.trees(StringIO.new('<aldt_trees><LM id="1" document_id="X"><LM id="1"'), path: "x.xml")
      end
    end

    private

    def whole_trees = PARSER.new.trees(FIXTURE, path: FIXTURE)

    def parse_whole
      PARSER.new.parse(FIXTURE, urn: "urn:test:llct1", language: "lat", title: "t", canonical_path: FIXTURE)
    end
  end
end
