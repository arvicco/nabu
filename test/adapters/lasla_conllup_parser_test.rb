# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::LaslaConllupParser — the `lasla-conllup` parser family:
# the CoNLL-U Plus dialect CIRCSE ships in github.com/CIRCSE/LASLA/conllup
# (the LASLA hand-verified Latin corpus, LiLa-linked). Fixture bytes are
# real upstream lines (test/fixtures/lasla/README.md): CicQuaest whole,
# Catullus poem 1 (the first 3 sentence blocks), Tacitus Hist. 4 trimmed to
# the ambiguous-link sentence and the repeated-sent_id run.
class LaslaConllupParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("lasla")
  CICERO = File.join(FIXTURES, "conllup", "Cicero_CumQuaestorLilybaeoDecederetFragmenta_CicQuaest.conllup")
  CATULLUS = File.join(FIXTURES, "conllup", "Catullus_Catullus_Catul.conllup")
  TACITUS = File.join(FIXTURES, "conllup", "Tacitus_TacHistoriae_TacHist4.conllup")
  LIVY = File.join(FIXTURES, "conllup", "Livius_AbVrbeCondita_TLiv08.conllup")
  URN = "urn:nabu:lasla:test"

  def parse(path, **)
    Nabu::Adapters::LaslaConllupParser.new.parse(path, urn: URN, language: "lat", **)
  end

  # -- passages ----------------------------------------------------------------

  def test_one_passage_per_sentence_block_cited_by_the_upstream_sent_id
    document = parse(CATULLUS)
    assert_equal %W[#{URN}:Catul-C-00-1 #{URN}:Catul-C-00-2 #{URN}:Catul-C-00-3],
                 document.passages.map(&:urn)
    assert_equal [0, 1, 2], document.passages.map(&:sequence)
    assert_equal "cui dono lepidum nouum libellum arida modo pumice expolitum",
                 document.passages.first.text, "the `# text` comment verbatim (LASLA's u-spelling)"
  end

  def test_the_global_columns_header_is_a_comment_of_the_first_block_not_a_sentence
    document = parse(CICERO)
    assert_equal 1, document.passages.size
    assert_equal "quod non detrectare militiam sed defendere prouinciam iudicata est", document.passages.first.text
  end

  def test_citation_hoists_from_the_first_token_with_the_closing_unit_when_it_moves
    first = parse(CATULLUS).passages.first
    assert_equal "Liber_1,Versus_1", first.annotations["citation"]
    assert_equal "Liber_1,Versus_2", first.annotations["citation_end"], "the sentence runs over two verses"
    single = parse(CICERO).passages.first
    assert_equal "Fragmentum_1,Linea_1", single.annotations["citation"]
    assert_equal "Fragmentum_1,Linea_2", single.annotations["citation_end"]
  end

  # -- a repeated sent_id (an interleaved sentence resumed) -----------------------

  def test_a_repeated_sent_id_mints_an_occurrence_suffix_never_a_collision
    document = parse(TACITUS)
    assert_equal %W[#{URN}:TacHist4-Q-05-1672 #{URN}:TacHist4-Q-05-1791 #{URN}:TacHist4-Q-05-1792
                    #{URN}:TacHist4-Q-05-1791.2 #{URN}:TacHist4-Q-05-1792.2],
                 document.passages.map(&:urn)
    resumed = document.passages[3]
    assert_equal "prohibebantur", resumed.text
    assert_equal "TacHist4-Q-05-1791", resumed.annotations["sent_id"], "the upstream id rides verbatim"
    assert_equal 2, resumed.annotations["sent_id_occurrence"]
    refute document.passages[1].annotations.key?("sent_id_occurrence"), "a first occurrence carries no mark"
  end

  # -- tokens --------------------------------------------------------------------

  def test_tokens_keep_the_gold_lemma_and_ud_morphology_with_the_lila_columns
    token = parse(CICERO).passages.first.annotations["tokens"][2]
    assert_equal({ "id" => "3", "form" => "detrectare", "lemma" => "detrecto", "upos" => "VERB", "xpos" => "B1",
                   "feats" => "Aspect=Imp|InflClass=LatA|InflClass[nominal]=Ind|VerbForm=Inf|Voice=Act",
                   "flcat" => "v1", "lasla_line" => "3", "lila" => ["lilaLemma:99051"] }, token)
  end

  def test_misc_lasla_variant_and_the_implied_word_ride_the_token
    tokens = parse(CICERO).passages.first.annotations["tokens"]
    assert_equal "2", tokens.first["lasla_variant"]
    implied = parse(TACITUS).passages.first.annotations["tokens"].find { |t| t["form"] == "testatum" }
    assert_equal "est", implied["tac"], "MISC Tac= — the word upstream marks as understood"
  end

  def test_an_ambiguous_lila_link_keeps_every_candidate_lemma
    an = parse(TACITUS).passages.first.annotations["tokens"].find { |t| t["form"] == "an" }
    assert_equal %w[lilaLemma:88828 lilaLemma:88829 lilaLemma:90944], an["lila"]
    assert_equal "an", an["lemma"], "the LASLA lemma itself is single — only the LiLa link is ambiguous"
  end

  def test_multiword_token_ranges_carry_only_their_surface
    tokens = parse(TACITUS).passages[1].annotations["tokens"]
    range = tokens.find { |t| t["id"] == "5-6" }
    assert_equal({ "id" => "5-6", "form" => "magnisque" }, range)
    assert_equal(%w[magnis que], tokens.select { |t| %w[5 6].include?(t["id"]) }.map { |t| t["form"] })
  end

  def test_the_token_uri_folds_into_one_document_base_plus_each_token_line
    document = parse(CICERO)
    assert_equal "http://lila-erc.eu/data/corpora/Lasla/id/corpus/CiceroCum%20Quaestor%20Lilybaeo%20Decederet" \
                 "%20Fragmenta/Cicero_CumQuaestorLilybaeoDecederetFragmenta_CicQuaest.BPN_t_",
                 document.metadata["lila_token_base"]
    document.passages.first.annotations["tokens"].each do |token|
      refute token.key?("token_uri"), "every URI is base + the 7-digit line — none rides the token"
    end
  end

  def test_a_token_uri_off_the_base_rides_its_token_verbatim
    lines = File.readlines(CICERO)
    lines[4] = lines[4].sub("BPN_t_0000002", "BPN_t_0009999")
    document = parse(StringIO.new(lines.join), canonical_path: CICERO)
    second = document.passages.first.annotations["tokens"][1]
    assert_match(/BPN_t_0009999\z/, second["token_uri"])
  end

  def test_an_unlinked_file_parses_without_lila_or_citation
    document = parse(LIVY)
    passage = document.passages.first
    assert_equal "#{URN}:TLiv08-T-LI-4771", passage.urn
    refute passage.annotations.key?("citation"), "the six unlinked files carry no CitationHierarchy upstream"
    tokens = passage.annotations["tokens"]
    assert(tokens.none? { |t| t.key?("lila") || t.key?("token_uri") })
    assert_equal({ "id" => "4", "form" => "C.", "lemma" => "gaius", "upos" => "PROPN", "xpos" => "A2",
                   "feats" => "Abbr=Yes|InflClass=Ind", "flcat" => "n2", "lasla_line" => "4",
                   "lasla_variant" => "N" }, tokens[3])
    refute document.metadata.key?("lila_token_base")
  end

  # -- damage fails loudly ---------------------------------------------------------

  def test_a_short_token_line_is_a_parse_error
    bad = "# sent_id = X-1\n# text = quod\n1\tquod\tquod\tSCONJ\tT\t_\t_\t_\t_\t_\n"
    error = assert_raises(Nabu::ParseError) { parse(StringIO.new(bad), canonical_path: "bad.conllup") }
    assert_match(/columns/, error.message)
  end

  def test_a_block_without_text_is_a_parse_error
    bad = "# sent_id = X-1\n1-2\tquodque\t_\t_\t_\t_\t_\t_\t_\t_\t_\t_\t_\n"
    assert_raises(Nabu::ParseError) { parse(StringIO.new(bad), canonical_path: "bad.conllup") }
  end
end
