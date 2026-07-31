# frozen_string_literal: true

require "test_helper"
require "json"

module Adapters
  # Nabu::Adapters::OchreJsonParser (P55-2): the `ochre-json` family's shape
  # normalizers, exercised on REAL fixture bytes — the OCHRE JSON is a
  # mechanical XML transliteration, so singular/plural and scalar/wrapped
  # content instability is EVERYWHERE and both shapes must parse.
  class OchreJsonParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("rsti")

    def parser = Nabu::Adapters::OchreJsonParser

    def season01
      @season01 ||= JSON.parse(
        File.read(File.join(FIXTURES, "sets", "2a414954-e077-496b-8b06-a9d0cd417eba.json"))
      )
    end

    def rs1001_text
      @rs1001_text ||= JSON.parse(
        File.read(File.join(FIXTURES, "texts", "de32293f-9b4b-435e-bf02-c4894863035b.json"))
      ).dig("ochre", "text")
    end

    # -- wrap: the singular/plural instability -------------------------------

    def test_wrap_normalizes_nil_scalar_and_list
      assert_empty parser.wrap(nil)
      assert_equal [1], parser.wrap(1)
      assert_equal [1, 2], parser.wrap([1, 2])
    end

    def test_wrap_on_the_real_singular_property_nesting
      # RS 1.004's text item nests properties.property.property as a DICT
      # where RS 1.001's is a LIST — the witnessed instability, real bytes.
      shell = JSON.parse(
        File.read(File.join(FIXTURES, "texts", "3e80daf3-a394-4a0e-9f00-dd76392b3834.json"))
      ).dig("ochre", "text")
      singular = shell.dig("properties", "property", "property")
      assert_kind_of Hash, singular, "fixture must witness the singular shape"
      assert_equal [singular], parser.wrap(singular)
      plural = season01.dig("ochre", "set", "items", "spatialUnit")
      assert_kind_of Array, plural
      assert_same plural, parser.wrap(plural)
    end

    # -- contents_of / content_of: the scalar/wrapped content instability ----

    def test_content_of_handles_scalar_language_dict_and_empty_dict
      # Scalar (a set record's label) …
      record = season01.dig("ochre", "set", "items", "spatialUnit", 0)
      assert_equal "RS 1.001", parser.content_of(record.dig("identification", "label"))
      # … the {languages,string,lang} dict (the menu's label shape) …
      menu = JSON.parse(File.read(File.join(FIXTURES, "menu.json")))
      assert_equal "New TEO Menu of Sets",
                   parser.content_of(menu.dig("ochre", "set", "identification", "label"))
      # … and the empty dict {} (RIH 77/01's description) → nil, never "".
      rih = JSON.parse(
        File.read(File.join(FIXTURES, "sets", "a7a3a86e-8cdb-4ea9-92fe-6dc31d07dcbc.json"))
      ).dig("ochre", "set", "items", "spatialUnit", 0)
      assert_equal "RIH 77/01", parser.content_of(rih.dig("identification", "label"))
      assert_nil parser.content_of(rih["description"])
    end

    def test_contents_of_flattens_the_alias_list
      aliases = rs1001_text.dig("identification", "alias")
      assert_equal ["CTA 34", "KTU 1.39", "RSO XII 1", "UT 1"], parser.contents_of(aliases)
    end

    def test_content_of_stringifies_integer_line_labels
      assert_equal "1", parser.content_of(1)
    end

    # -- entity decode: graphemic &#x103xx; → real U+10380-block codepoints --

    def test_decode_entities_turns_literal_hex_entities_into_cuneiform
      # The exact first bytes of RS 1.001's graphemic Recto line 1.
      first = rs1001_text.dig("sections", "graphemic", "section", 0, "section", 0,
                              "value", "supplementary")
      assert_equal "&#x10384;", first.fetch(0), "fixture must carry the literal entity string"
      assert_equal "\u{10384}", parser.decode_entities(first.fetch(0))
      assert_equal "\u{10384}\u{10396}\u{1039A}",
                   parser.decode_entities(first.take(3).join)
    end

    def test_decode_entities_handles_decimal_and_leaves_plain_text_alone
      assert_equal "\u{10384}", parser.decode_entities("&#66436;")
      assert_equal "dqt . ṯʿ", parser.decode_entities("dqt . ṯʿ")
    end

    # -- sections: the four parallel renderings ------------------------------

    def test_sections_extracts_per_surface_per_line_renderings
      renderings = parser.sections(rs1001_text)
      assert_equal %w[graphemic phonemic translation transliteration], renderings.keys.sort
      surfaces = renderings.fetch("transliteration")
      labels = surfaces.map { |s| s.fetch("surface") }
      assert_equal ["Recto", "Lower edge", "Verso"], labels
      recto = surfaces.fetch(0)
      assert_equal 17, recto.fetch("lines").size
      line1 = recto.fetch("lines").fetch(0)
      assert_equal "1", line1.fetch("label")
      assert_equal "dqt . ṯʿ . ynt . ṯʿm . dqt . ṯʿm", line1.fetch("value")
      assert_empty renderings.fetch("translation"), "RS 1.001's translation rendering is {}"
    end

    def test_sections_of_the_shell_text_item_are_empty
      shell = JSON.parse(
        File.read(File.join(FIXTURES, "texts", "3e80daf3-a394-4a0e-9f00-dd76392b3834.json"))
      ).dig("ochre", "text")
      assert_empty parser.sections(shell)
    end

    # -- graphemic values: {supplementary, content} --------------------------

    def test_graphemic_of_decodes_signs_and_carries_marks
      renderings = parser.sections(rs1001_text)
      line1 = renderings.fetch("graphemic").fetch(0).fetch("lines").fetch(0)
      graphemic = parser.graphemic_of(line1.fetch("value"))
      assert graphemic.fetch("signs").start_with?("\u{10384}\u{10396}\u{1039A}")
      assert_equal 17, graphemic.fetch("signs").each_char.count
      assert_equal [".", ".", ".", ".", "."], graphemic.fetch("marks")
    end

    def test_graphemic_of_without_content_carries_no_marks
      # RS 1.001 Verso line 22 has supplementary only — real upstream shape.
      renderings = parser.sections(rs1001_text)
      verso = renderings.fetch("graphemic").find { |s| s.fetch("surface") == "Verso" }
      line22 = verso.fetch("lines").find { |l| l.fetch("label") == "22" }
      graphemic = parser.graphemic_of(line22.fetch("value"))
      refute graphemic.key?("marks")
      assert_equal 7, graphemic.fetch("signs").each_char.count
    end
  end
end
