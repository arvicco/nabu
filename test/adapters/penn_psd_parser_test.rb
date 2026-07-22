# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# PennPsdParser unit tests against the real HeliPaD fixture (P40-3) — the
# first 2 whole tree blocks of heliand.psd (OSHeliandC.1.1-5, OSHeliandC.2.5-9).
# Covers the balanced-parenthesis tree reader, sentence=passage minting from
# the (ID …) nodes, surface-text reconstruction with punctuation attachment,
# form-lemma splitting (last hyphen), tag^morphology splitting (first caret),
# CODE marker + empty-category retention in the tokens lane, the serialized
# tree annotation, and the malformed-input error paths.
class PennPsdParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("helipad"), "heliand-head.psd")
  URN = "urn:nabu:helipad:OSHeliandC"

  # The full reconstructed surface of the two fixture sentences —
  # byte-pinned NFC Old Saxon (Heliand C, lines 1-5 and 5-9).
  TEXT_1 = "Manega uuaron the sia iro mod gespon, that sia uuord godes uuisean " \
           "bigunnun, reckean that giruni, that thie riceo Crist undar mancunnea " \
           "maritha gifrumida mid uuordun endi mid uuercun."
  TEXT_2 = "That uuolda tho uuisara filo liudo barno loƀon, lera Cristes, " \
           "helag uuord godas, endi mid iro handon scriƀan berethlico an buok, " \
           "huo sia is gibodscip scoldin frummian firiho barn."

  def parser
    Nabu::Adapters::PennPsdParser.new
  end

  def parse
    parser.parse(FIXTURE, urn: URN, language: "osx", title: "Heliand", id_prefix: "OSHeliandC")
  end

  # --- document + passage minting -----------------------------------------

  def test_document_fields
    document = parse
    assert_equal URN, document.urn
    assert_equal "osx", document.language
    assert_equal "Heliand", document.title
    assert_equal FIXTURE, document.canonical_path
  end

  def test_two_tree_blocks_become_two_passages
    assert_equal 2, parse.size
  end

  def test_passage_urns_are_the_id_tails_after_the_stripped_prefix
    passages = parse.to_a
    assert_equal ["#{URN}:1.1-5", "#{URN}:2.5-9"], passages.map(&:urn)
    assert_equal [0, 1], passages.map(&:sequence)
  end

  def test_without_an_id_prefix_the_full_upstream_id_is_the_urn_tail
    document = parser.parse(FIXTURE, urn: URN, language: "osx", title: "Heliand")
    assert_equal "#{URN}:OSHeliandC.1.1-5", document.first.urn
  end

  def test_the_verbatim_upstream_id_rides_the_annotations
    assert_equal "OSHeliandC.1.1-5", parse.first.annotations.fetch("id")
  end

  # --- surface text reconstruction ----------------------------------------

  def test_first_sentence_text_is_the_pinned_old_saxon_opening
    assert_equal TEXT_1, parse.first.text
  end

  def test_second_sentence_text_keeps_the_crossed_b_nfc
    text = parse.to_a.last.text
    assert_equal TEXT_2, text
    assert_includes text, "loƀon", "ƀ (U+0180) survives verbatim"
    assert text.unicode_normalized?(:nfc)
  end

  def test_punctuation_attaches_to_the_preceding_token
    text = parse.first.text
    assert_includes text, "gespon, that", "no space before the comma"
    assert text.end_with?("uuercun."), "the final period attaches"
  end

  def test_text_normalized_is_the_minted_search_form
    first = parse.first
    assert_equal Nabu::Normalize.search_form(first.text, language: "osx"), first.text_normalized
  end

  # --- the tokens lane ------------------------------------------------------

  def test_token_counts_census_both_trees
    first_tokens, second_tokens = parse.map { |passage| passage.annotations.fetch("tokens") }
    assert_equal 49, first_tokens.size, "tree 1: 33 surface tokens + 3 empties + 13 CODE markers"
    assert_equal 44, second_tokens.size, "tree 2: 34 surface tokens + 2 empties + 8 CODE markers"
    assert_equal(13, first_tokens.count { |entry| entry.key?("code") })
    assert_equal(3, first_tokens.count { |entry| entry.key?("empty") })
    assert_equal(8, second_tokens.count { |entry| entry.key?("code") })
    assert_equal(2, second_tokens.count { |entry| entry.key?("empty") })
  end

  def test_form_lemma_split_on_the_last_hyphen
    tokens = parse.first.annotations.fetch("tokens")
    manega = tokens.find { |entry| entry["form"] == "Manega" }
    assert_equal "manag", manega["lemma"]
    uuaron = tokens.find { |entry| entry["form"] == "uuaron" }
    assert_equal "wesan", uuaron["lemma"]
  end

  def test_pos_and_morphology_split_on_the_first_caret
    tokens = parse.first.annotations.fetch("tokens")
    manega = tokens.find { |entry| entry["form"] == "Manega" }
    assert_equal "Q", manega["pos"]
    assert_equal "N^PL", manega["morph"]
    gespon = tokens.find { |entry| entry["form"] == "gespon" }
    assert_equal "GE+VBDI", gespon["pos"]
    assert_equal "3^SG", gespon["morph"]
    assert_equal "spanan", gespon["lemma"]
    iro = tokens.find { |entry| entry["form"] == "iro" }
    assert_equal "PRO$", iro["pos"], "the $ of possessive-pronoun tags survives the caret split"
    assert_equal "N^3^SG", iro["morph"]
  end

  def test_a_morphology_less_tag_mints_no_morph_key
    tokens = parse.first.annotations.fetch("tokens")
    uuisean = tokens.find { |entry| entry["form"] == "uuisean" }
    assert_equal "VB", uuisean["pos"]
    refute uuisean.key?("morph")
  end

  def test_punctuation_leaves_are_tokens_too
    comma = parse.first.annotations.fetch("tokens").find { |entry| entry["form"] == "," }
    assert_equal ",", comma["lemma"]
    assert_equal ",", comma["pos"]
  end

  def test_code_markers_ride_in_order_with_angle_brackets_stripped
    codes = parse.first.annotations.fetch("tokens").filter_map { |entry| entry["code"] }
    assert_equal %w[P_7 COM:HELIAND_C MS_5a F_1 R_1 C R_2 C R_3 C R_4 C R_5], codes,
                 "edition page, manuscript, folio, fitt, verse-line refs and caesurae, in document order"
  end

  def test_the_caesura_marker_sits_between_its_half_lines
    tokens = parse.first.annotations.fetch("tokens")
    uuaron = tokens.index { |entry| entry["form"] == "uuaron" }
    assert_equal "C", tokens[uuaron + 1]["code"], "the <C> caesura follows uuaron (line 1's a-verse ends)"
  end

  def test_empty_categories_keep_their_tag_and_contribute_no_text
    tokens = parse.first.annotations.fetch("tokens")
    assert_equal({ "tag" => "NP-SBJ", "empty" => "*exp*" }, tokens.find { |e| e["empty"] == "*exp*" })
    assert_equal({ "tag" => "CP-REL", "empty" => "*ICH*-1" }, tokens.find { |e| e["empty"] == "*ICH*-1" })
    zero = parse.first.annotations.fetch("tokens").find { |e| e["empty"] == "0" }
    assert_equal "WNP-SBJ-2", zero["tag"]
    refute_includes parse.first.text, "*"
    trace = parse.to_a.last.annotations.fetch("tokens").find { |e| e["empty"] == "*T*-1" }
    assert_equal "ADVP", trace["tag"]
  end

  # --- the syntax lane ------------------------------------------------------

  def test_the_serialized_tree_round_trips_the_block
    tree = parse.first.annotations.fetch("tree")
    assert tree.start_with?("((IP-MAT (CODE <P_7>) (CODE <COM:HELIAND_C>)"),
           "unexpected tree head: #{tree[0, 60].inspect}"
    assert tree.end_with?("(ID OSHeliandC.1.1-5))")
    assert_equal tree.count("("), tree.count(")")
    assert_includes tree, "(GE+VBDI^3^SG gespon-spanan)"
  end

  # --- error paths ----------------------------------------------------------

  def test_unbalanced_parentheses_raise_parse_error
    with_psd("( (IP-MAT (Q^N^PL Manega-manag)\n") do |path|
      error = assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
      assert_match(/unbalanced/, error.message)
    end
  end

  def test_a_stray_atom_between_blocks_raises_parse_error
    with_psd("( (IP-MAT (Q^N^PL a-b)) (ID X.1))\n\nstray\n") do |path|
      assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
    end
  end

  def test_a_block_without_an_id_node_raises_parse_error
    with_psd("( (IP-MAT (Q^N^PL Manega-manag)))\n") do |path|
      error = assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
      assert_match(/\(ID/, error.message)
    end
  end

  def test_a_preterminal_with_multiple_atoms_raises_parse_error
    with_psd("( (IP-MAT (Q^N^PL Manega-manag stray-atom)) (ID X.1))\n") do |path|
      assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
    end
  end

  def test_an_empty_file_raises_parse_error
    with_psd("") do |path|
      assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
    end
  end

  def test_duplicate_ids_raise_parse_error
    block = "( (IP-MAT (Q^N^PL a-b)) (ID X.1))\n"
    with_psd("#{block}\n#{block}") do |path|
      assert_raises(Nabu::ParseError) { parser.parse(path, urn: URN, language: "osx") }
    end
  end

  def test_a_form_only_leaf_mints_a_token_without_a_lemma_claim
    # YCOE-shaped .psd carries NO lemmas (its .pos siblings do): an
    # unhyphenated leaf is a form-only token, never an invented lemma.
    with_psd("( (IP-MAT (NP-SBJ (N Sum))) (ID X.1))\n") do |path|
      document = parser.parse(path, urn: URN, language: "osx")
      token = document.first.annotations.fetch("tokens").first
      assert_equal "Sum", token["form"]
      refute token.key?("lemma")
    end
  end

  private

  def with_psd(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.psd")
      File.write(path, content)
      yield path
    end
  end
end
