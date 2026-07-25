# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::DigilibltConlluParser (P45-3): the `digiliblt-conllu` parser
# family — digilibLT's LiLa-linked CoNLL-U dialect, censused from all 373 real
# files (2026-07-25).
#
# COMPOSE VERDICT — ConlluParser refuted from the bytes, three ways:
#   1. Token lines are 11–14 tab-separated columns (the 10 standard CoNLL-U
#      columns + 1..4 LiLa lemma-bank IRI columns from the "Bronze" linking);
#      ConlluParser hard-fails on anything but exactly 10.
#   2. Every file opens with a doc-level `# key=value` header block terminated
#      by a blank line; ConlluParser would treat it as a sentence block and
#      raise "missing mandatory `# sent_id`".
#   3. Three files wrap their docTitle onto a raw continuation line that is
#      neither a comment nor a token line (dlt000340/dlt000547/dlt000649).
#
# Fixture bytes are real: dlt000173 whole, dlt000619 whole, dlt000340 trimmed
# (header + 2 sentences), and the damaged dlt000079's real first lines under
# malformed/ (upstream ships the mangling; the parser must quarantine, never
# paper over).
class DigilibltConlluParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("digiliblt")
  EUANTIUS = File.join(FIXTURES, "texts", "part1", "dlt000173.xml_linked.conllu")
  DECRETUM = File.join(FIXTURES, "texts", "part4", "dlt000619.xml_linked.conllu")
  MACROBIUS = File.join(FIXTURES, "texts", "part2", "dlt000340.xml_linked.conllu")
  MALFORMED = File.join(FIXTURES, "malformed", "dlt000079-head.conllu")

  def parser = Nabu::Adapters::DigilibltConlluParser.new

  def parse(path, urn: "urn:nabu:digiliblt:test")
    parser.parse(path, urn: urn, language: "lat")
  end

  # -- the doc header block ---------------------------------------------------

  def test_header_mints_title_author_and_document_metadata
    document = parse(EUANTIUS)
    assert_equal "Euantius — De comoedia uel de fabula", document.title,
                 "title = docAuthor — docTitle (the glaux convention)"
    assert_equal "Euantius", document.metadata["author"]
    assert_equal "De comoedia uel de fabula", document.metadata["work"]
    assert_equal "dlt000173", document.metadata["doc_id"]
    assert_match(/Cupaiuolo/, document.metadata["source_description"],
                 "the source edition rides verbatim from the `# description` header")
  end

  def test_no_author_sentinel_surfaces_as_absent_author
    document = parse(DECRETUM)
    refute document.metadata.key?("author"),
           "upstream spells anonymity as the literal 'No author' — never journal the sentinel"
    assert_equal "Decretum provinciae Africae", document.title,
                 "an anonymous work titles by docTitle alone"
  end

  def test_wrapped_doc_title_continuation_line_folds_into_the_value
    document = parse(MACROBIUS)
    assert_equal "De uerborum Graeci et Latini differentiis vel societatibus excerpta " \
                 "[=Iohannis Scoti defloratio de Macrobio]",
                 document.metadata["work"],
                 "the raw un-prefixed continuation line (3 files upstream) folds into docTitle"
  end

  # -- sentence blocks / passages ---------------------------------------------

  def test_passage_per_sentence_with_the_sent_id_urn_tail
    document = parse(EUANTIUS)
    assert_equal 55, document.count, "dlt000173 carries 55 sentence blocks"
    first = document.first
    assert_equal "urn:nabu:digiliblt:test:1", first.urn
    assert_equal 0, first.sequence
    assert_equal "lat", first.language
  end

  def test_text_is_the_authoritative_text_comment
    first = parse(EUANTIUS).first
    assert_equal "Initium tragoediae et comoediae a rebus diuinis est incohatum, " \
                 "quibus pro fructibus uota soluentes operabantur antiqui.",
                 first.text
    assert first.text.unicode_normalized?(:nfc)
  end

  def test_citation_hierarchy_is_hoisted_to_the_passage_never_each_token
    document = parse(EUANTIUS)
    assert_equal "Paragraphus_1,Sentence_1", document.first.annotations["citation"]
    document.first.annotations.fetch("tokens").each do |token|
      refute token.key?("misc"), "CitationHierarchy repeats per token — it rides the passage only"
    end
  end

  # -- tokens: lemma / upos / the LiLa link columns ---------------------------

  def test_lemma_and_upos_ride_each_token
    tokens = parse(EUANTIUS).first.annotations.fetch("tokens")
    tragoediae = tokens.find { |t| t["form"] == "tragoediae" } || flunk("tragoediae token missing")
    assert_equal "tragoedia", tragoediae["lemma"]
    assert_equal "NOUN", tragoediae["upos"]
    assert_equal "2", tragoediae["id"]
  end

  def test_single_lila_iri_rides_as_a_one_element_array
    tokens = parse(EUANTIUS).first.annotations.fetch("tokens")
    initium = tokens.find { |t| t["form"] == "Initium" } || flunk("Initium token missing")
    assert_equal ["http://lila-erc.eu/data/id/lemma/107903"], initium["lila"]
  end

  def test_ambiguous_bronze_linking_keeps_every_candidate_iri
    tokens = parse(EUANTIUS).first.annotations.fetch("tokens")
    fructibus = tokens.find { |t| t["form"] == "fructibus" } || flunk("fructibus token missing")
    assert_equal %w[http://lila-erc.eu/data/id/lemma/103879 http://lila-erc.eu/data/id/lemma/103880],
                 fructibus["lila"],
                 "an ambiguous link (397,689 tokens corpus-wide) carries ALL candidate IRIs"
  end

  def test_unlinked_token_carries_no_lila_key
    tokens = parse(MACROBIUS).first.annotations.fetch("tokens")
    theodosius = tokens.find { |t| t["form"] == "Theodosius" } || flunk("Theodosius token missing")
    refute theodosius.key?("lila"), "an empty 11th column (25.6% of tokens) is an absent key"
    assert_equal "theodosius", theodosius["lemma"], "the UDPipe lemma still rides"
  end

  def test_punctuation_tokens_carry_no_lemma
    tokens = parse(MACROBIUS).first.annotations.fetch("tokens")
    stop = tokens.find { |t| t["form"] == "." } || flunk(". token missing")
    assert_equal "PUNCT", stop["upos"]
    refute stop.key?("lemma"), "a full stop is not a dictionary form — the silver pool stays clean"
  end

  def test_all_underscore_columns_are_absent_keys
    parse(EUANTIUS).first.annotations.fetch("tokens").each do |token|
      %w[xpos feats head deprel deps].each do |key|
        refute token.key?(key), "#{key} is `_` corpus-wide (UDPipe lemma+PoS only) — absent, not `_`"
      end
    end
  end

  # -- malformed upstream bytes quarantine (real dlt000079 damage) ------------

  def test_the_damaged_file_raises_parse_error_naming_the_file
    error = assert_raises(Nabu::ParseError) { parse(MALFORMED) }
    assert_match(/dlt000079-head\.conllu/, error.message)
  end

  def test_a_mangled_token_line_raises_parse_error_with_the_line_number
    io = StringIO.new(<<~CONLLU)
      # docId=dlt000900
      # docTitle=Test

      # sent_id = 1
      # text = Verbum est.
      1\tVerbum\tuerbum\tNOUN\t_\t_\t_\t_\t_\tCitationHierarchy=Paragraphus_1,Sentence_1\t
      2  est  sum  AUX _ _ _ _ _
    CONLLU
    error = assert_raises(Nabu::ParseError) { parser.parse(io, urn: "u", language: "lat", canonical_path: "x.conllu") }
    assert_match(/x\.conllu:7/, error.message)
    assert_match(/11/, error.message, "the error names the corpus's 11-column floor")
  end

  def test_a_block_without_sent_id_raises_parse_error
    io = StringIO.new(<<~CONLLU)
      # docId=dlt000900

      # text = Verbum est.
      1\tVerbum\tuerbum\tNOUN\t_\t_\t_\t_\t_\t_\t
    CONLLU
    error = assert_raises(Nabu::ParseError) { parser.parse(io, urn: "u", language: "lat", canonical_path: "x.conllu") }
    assert_match(/sent_id/, error.message)
  end

  def test_a_block_without_text_raises_parse_error
    io = StringIO.new(<<~CONLLU)
      # docId=dlt000900

      # sent_id = 1
      1\tVerbum\tuerbum\tNOUN\t_\t_\t_\t_\t_\t_\t
    CONLLU
    error = assert_raises(Nabu::ParseError) { parser.parse(io, urn: "u", language: "lat", canonical_path: "x.conllu") }
    assert_match(/text/, error.message)
  end

  def test_an_empty_file_raises_parse_error
    io = StringIO.new("# docId=dlt000900\n\n")
    error = assert_raises(Nabu::ParseError) { parser.parse(io, urn: "u", language: "lat", canonical_path: "x.conllu") }
    assert_match(/no sentence blocks/, error.message)
  end
end
