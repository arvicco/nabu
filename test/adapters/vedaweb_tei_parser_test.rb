# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::VedawebTeiParser — the `vedaweb-tei` parser family: the
# VedaWeb Rigveda book files (github.com/VedaWebProject/vedaweb-data,
# rigveda/TEI/rv_book_NN.tei), streamed hymn by hymn. Fixture bytes are real
# upstream lines (test/fixtures/vedaweb/README.md).
class VedawebTeiParserTest < Minitest::Test
  TEI = File.join(Nabu::TestSupport.fixtures("vedaweb"), "rigveda", "TEI")
  BOOK1 = File.join(TEI, "rv_book_01.tei")
  BOOK2 = File.join(TEI, "rv_book_02.tei")
  BOOK8 = File.join(TEI, "rv_book_08.tei")

  def hymns(path) = Nabu::Adapters::VedawebTeiParser.new.each_hymn(path).to_a

  def test_hymns_stream_in_book_order_with_upstream_numbering
    book1 = hymns(BOOK1)
    assert_equal %w[b01_h001 b01_h002], book1.map(&:id)
    first = book1.first
    assert_equal [1, 1, 1], [first.book, first.number, first.grassmann]
    assert_equal({ "deu" => "An Agni", "eng" => "Agni" }, first.addressee)
    assert_equal({ "n" => "1", "deu" => "Lieder des Madhucchandas", "eng" => "Hymns of Madhucchandas" }, first.group)
  end

  def test_grassmann_numbers_the_valakhilya_after_the_tenth_book
    hymn = hymns(BOOK8).first
    assert_equal "b08_h049", hymn.id
    assert_equal 1018, hymn.grassmann, "8.49 is Grassmann's 1018 (the Vālakhilya counted last)"
    assert_equal "Valakhilya-Hymns", hymn.group["eng"]
  end

  def test_a_stanza_carries_the_zurich_padas_in_order
    stanza = hymns(BOOK1).first.stanzas.first
    assert_equal 1, stanza.number
    assert_equal({ "a" => "agním īḷe puróhitaṃ", "b" => "yajñásya devám r̥tvíjam", "c" => "hótāraṃ ratnadhā́tamam" },
                 stanza.padas)
  end

  def test_four_pada_stanzas_and_stanza_properties
    stanza = hymns(BOOK2).first.stanzas.first
    assert_equal 16, stanza.number
    assert_equal %w[a b c d], stanza.padas.keys
    assert_equal({ "grassmann" => "G" }, stanza.properties)
  end

  def test_strata_ride_per_pada
    stanza = hymns(BOOK1).first.stanzas.first
    assert_equal({ "label" => "MO", "strata" => "N" }, stanza.strata["a"])
    assert_equal %w[a b c], stanza.strata.keys
  end

  def test_tokens_carry_lemma_grammar_and_leipzig_morphology
    token = hymns(BOOK1).first.stanzas.first.tokens.first
    assert_equal "a_01", token.id
    assert_equal "a", token.pada
    assert_equal "agním", token.surface
    assert_equal "agní-", token.lemma
    assert_equal "lemma_agni_79", token.lemma_ref
    assert_equal "nominal stem", token.gramm
    assert_equal({ "case" => ["ACC"], "gender" => ["M"], "number" => ["SG"] }, token.morphosyntax)
  end

  def test_valt_alternatives_keep_every_reading
    token = hymns(BOOK2).last.stanzas.first.tokens.find { |t| t.surface == "pātháḥ" }
    assert_equal "pánthā- ~ path-", token.lemma
    assert_equal({ "case" => %w[ACC GEN], "gender" => ["M"], "number" => %w[SG PL] }, token.morphosyntax)
  end

  def test_only_the_cc_by_layers_are_read
    stanza = hymns(BOOK1).first.stanzas.first
    assert_equal 8, stanza.tokens.size, "the zurich layer's 3 + 3 + 2 tokens"
    refute(stanza.padas.values.any? { |text| text.include?("_") }, "the Lubotsky layer never leaks in")
  end
end
