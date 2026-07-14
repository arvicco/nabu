# frozen_string_literal: true

require "test_helper"

# The lila-ttl parser family (P18-6): a minimal Turtle-subset triple reader
# for the two CIRCSE/LiLa lexical-resource files (LIV.ttl, BrillEDL.ttl).
# NOT a general Turtle parser — the subset was censused first-hand against
# both upstream files (docs/pie-survey.md §2; fixture READMEs) and anything
# outside it fails LOUDLY as Nabu::ParseError, never a silent skip.
class LilaTtlParserTest < Minitest::Test
  def statements(text)
    Nabu::Adapters::LilaTtlParser.new.statements(text)
  end

  def test_named_blank_nodes_parse_as_terms_in_both_positions
    # The real LIV.ttl carries 70 NAMED blank nodes (_:node1hh00i44bx1) —
    # object position AND subject position — which the fixture-slice
    # census missed; the whole-file document quarantined and the liv
    # sync "succeeded" with an empty shelf (owner-hit, 2026-07-14).
    ttl = <<~TTL
      @prefix vartrans: <http://www.w3.org/ns/lemon/vartrans#> .
      @prefix ontolex: <http://www.w3.org/ns/lemon/ontolex#> .
      @prefix liv_forms: <http://example.org/liv/forms/> .
      <http://example.org/liv/lex_1> vartrans:lexicalRel _:node1hh00i44bx1 .
      _:node1hh00i44bx1 ontolex:lexicalForm liv_forms:form_78 .
    TTL
    stmts = statements(ttl)
    rel = stmts.select { |s| s.predicate == "http://www.w3.org/ns/lemon/vartrans#lexicalRel" }
    assert_equal ["_:node1hh00i44bx1"], rel.map(&:object)
    assert_equal [:blank], rel.map(&:kind)
    form = stmts.select { |s| s.subject == "_:node1hh00i44bx1" }
    assert_equal ["http://example.org/liv/forms/form_78"], form.map(&:object)
  end

  def test_prefixed_names_expand_through_the_prefix_map
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
      ex:thing rdfs:label "a label" .
    TTL
    assert_equal 1, triples.size
    statement = triples.first
    assert_equal "http://example.org/thing", statement.subject
    assert_equal "http://www.w3.org/2000/01/rdf-schema#label", statement.predicate
    assert_equal "a label", statement.object
    assert_equal :literal, statement.kind
  end

  def test_a_expands_to_rdf_type_and_iri_objects_are_kind_iri
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      ex:s a ex:Klass .
    TTL
    assert_equal ["http://example.org/s",
                  "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
                  "http://example.org/Klass", :iri],
                 triples.first.deconstruct
  end

  def test_semicolon_and_comma_lists_fan_out_in_document_order
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      ex:s a ex:K1, ex:K2;
        ex:p "one", "two";
        ex:q ex:o .
    TTL
    assert_equal 5, triples.size
    assert_equal(%w[K1 K2], triples.first(2).map { |t| t.object.split("/").last })
    assert_equal %w[one two], triples[2, 2].map(&:object)
    assert_equal "http://example.org/q", triples.last.predicate
  end

  # The LIV serialization revisits subjects (liv_base:Lexicon accretes its
  # lime:entry list across several statements) — statements just accumulate.
  def test_repeated_subjects_accumulate
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      ex:s ex:p ex:a .
      ex:s ex:p ex:b .
    TTL
    assert_equal(%w[a b], triples.map { |t| t.object.split("/").last })
  end

  # BrillEDL wraps canonicalForm in a blank-node property list, sometimes
  # with a multi-valued writtenRep inside; the reader mints a stable node id
  # and emits the inner triples against it.
  def test_blank_node_property_lists_mint_node_ids_and_inner_triples
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      @prefix ontolex: <http://www.w3.org/ns/lemon/ontolex#> .
      ex:s ontolex:canonicalForm [ ontolex:writtenRep
        "*ureh₃d‑e/o‑" , "*Hreh₃d‑e/o‑" ] .
    TTL
    outer = triples.find { |t| t.predicate.end_with?("canonicalForm") }
    assert_equal :blank, outer.kind
    inner = triples.select { |t| t.subject == outer.object }
    assert_equal ["*ureh₃d‑e/o‑", "*Hreh₃d‑e/o‑"], inner.map(&:object)
  end

  def test_datatype_and_language_annotations_yield_the_lexical_value
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
      ex:s ex:n "NaN"^^xsd:double;
        ex:d "a description"@en .
    TTL
    assert_equal %w[NaN], [triples.first.object]
    assert_equal "a description", triples.last.object
    assert_equal :literal, triples.last.kind
  end

  def test_string_escapes_unescape
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      ex:s ex:p "say \\"hi\\"\\n\\u0041" .
    TTL
    assert_equal "say \"hi\"\nA", triples.first.object
  end

  def test_comments_and_blank_lines_are_skipped_but_hash_inside_iris_is_not
    triples = statements(<<~TTL)
      @prefix ex: <http://example.org/> .
      # a comment line
      ex:s ex:p <https://dictionaries.brillonline.com/search#dictionary=latin&id=la1405> .
    TTL
    assert_equal 1, triples.size
    assert_includes triples.first.object, "#dictionary=latin"
  end

  # Real LIV shapes: numeric local names, an IRI whose local name is "-",
  # unicode inside <>-wrapped IRIs.
  def test_liv_shaped_names_parse
    triples = statements(<<~TTL)
      @prefix liv_themes: <http://lila-erc.eu/data/lexicalResources/LIV/id/Themes/> .
      @prefix morph: <https://ontolex.github.io/morph/> .
      liv_themes:1039490935661763527509341827371069474528331284855222600237 a morph:Morph .
      <http://lila-erc.eu/data/lexicalResources/LIV/id/Themes/-> a morph:Morph .
      <http://lila-erc.eu/data/lexicalResources/LIV/id/LexicalEntry/id/Stems/éi̯e-causative_stem–iterative_stem>
        a morph:Morph .
    TTL
    assert_equal 3, triples.size
    assert triples[0].subject.end_with?("222600237")
    assert triples[1].subject.end_with?("Themes/-")
    assert_includes triples[2].subject, "éi̯e-causative"
  end

  def test_malformed_input_raises_parse_error_with_line_number
    error = assert_raises(Nabu::ParseError) do
      statements(<<~TTL)
        @prefix ex: <http://example.org/> .
        ex:s ex:p "unterminated statement"
      TTL
    end
    assert_match(/line/, error.message)
  end

  def test_unknown_prefix_raises_parse_error
    assert_raises(Nabu::ParseError) { statements("nope:s nope:p nope:o .") }
  end
end
