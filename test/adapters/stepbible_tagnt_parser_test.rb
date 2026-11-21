# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# StepbibleTagntParser: one TAGNT word-per-row file → one Document per book,
# verse-grain passages, every word row a token carrying the cross-edition
# apparatus. Runs against the checked-in real excerpts (README.md there).
class StepbibleTagntParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("stepbible-tagnt")
  MAT_JHN = File.join(FIXTURES, "Mat-Jhn",
                      "TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt")
  ACT_REV = File.join(FIXTURES, "Act-Rev",
                      "TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt")

  def parser = Nabu::Adapters::StepbibleTagntParser.new

  def parse(path, book)
    parser.parse(path, book: book, urn: "urn:nabu:test:#{book.downcase}", title: book)
  end

  def passage(document, key)
    document.find { |p| p.urn.end_with?(":#{key}") } || flunk("no passage #{key}")
  end

  def token(document, id)
    document.each { |p| p.annotations["tokens"].each { |t| return t if t["id"] == id } }
    flunk "no token #{id}"
  end

  def test_books_lists_the_files_books_in_order
    assert_equal %w[Mat Jhn], parser.books(MAT_JHN)
    assert_equal %w[Act Jas 3Jn Rev], parser.books(ACT_REV)
  end

  def test_verse_grain_passages_with_verbatim_amalgamated_text
    matt = parse(MAT_JHN, "Mat")
    assert_equal(%w[1.1 1.2 6.13 15.6 17.20 17.21], matt.map { |p| p.urn.split(":").last })
    assert_equal "Βίβλος γενέσεως Ἰησοῦ Χριστοῦ υἱοῦ Δαυὶδ υἱοῦ Ἀβραάμ.", matt.first.text
    assert_equal "Mat.1.1", matt.first.annotations["citation"]
    assert_equal({ "book" => "Mat" }, matt.metadata)
    # The amalgam is the union of the editions: the TR doxology rides the text.
    assert passage(matt, "6.13").text.end_with?("εἰς τοῦς αἰῶνας ἀμήν.")
    # ¶ (upstream's paragraph mark) is kept verbatim in the text.
    assert passage(matt, "17.21").text.end_with?("καὶ νηστείᾳ.¶")
  end

  def test_every_word_row_is_a_token
    matt = parse(MAT_JHN, "Mat")
    # Row counts cross-checked by grep against the fixture ("^Mat.1.2#" → 18).
    assert_equal([8, 18, 27, 21, 32, 12], matt.map { |p| p.annotations["tokens"].size })
    assert_equal passage(matt, "1.1").text.split.size, passage(matt, "1.1").annotations["tokens"].size
  end

  def test_token_carries_the_edition_apparatus
    matt = parse(MAT_JHN, "Mat")
    assert_equal({ "id" => "Mat.1.1#01", "form" => "Βίβλος", "translit" => "Biblos", "type" => "NKO",
                   "editions" => "NA28+NA27+Tyn+SBL+WH+Treg+TR+Byz", "strong" => "G0976",
                   "morph" => "N-NSF", "lemma" => "βίβλος", "lemma_gloss" => "book",
                   "gloss" => "[The] book" }, token(matt, "Mat.1.1#01"))
    # TR-only words of the doxology; the extra-text note rides the last one.
    doxology = passage(matt, "6.13").annotations["tokens"][12..]
    assert(doxology.all? { |t| t["editions"] == "TR+Byz" && %w[K KO].include?(t["type"]) })
    assert doxology.last["note"].start_with?("^ ὅτι")
    # A whole verse absent from NA: no token names NA28.
    assert(passage(matt, "17.21").annotations["tokens"].none? { |t| t["editions"].include?("NA28") })
  end

  def test_meaning_and_spelling_variants_ride_verbatim
    matt = parse(MAT_JHN, "Mat")
    variant = token(matt, "Mat.17.20#08")
    assert_equal "N(K)O", variant["type"]
    assert_equal "NA28+NA27+Tyn+SBL+WH+Treg", variant["editions"]
    assert_equal "ἀπιστίαν (T=apistian) unbelief - G0570=N-ASF in: TR+Byz", variant["meaning_variants"]
    assert variant["note"].start_with?("v ἀπιστίαν")
    david = token(matt, "Mat.1.1#06")
    assert_equal "Tyn+WH: Δαυεὶδ ; +TR: Δαβὶδ ;", david["spelling_variants"]
    assert_equal "Δαυείδ", david["lemma"], "the first headword of 'Δαυείδ, Δαυίδ, Δαβίδ'"
  end

  def test_versification_bracket_stays_in_the_nrsv_verse
    matt = parse(MAT_JHN, "Mat")
    ids = passage(matt, "15.6").annotations["tokens"].map { |t| t["id"] }
    assert_equal "Mat.15.6{15.5}#01", ids.first
    assert_equal "Mat.15.6#12", ids[11]
  end

  def test_form_strips_punctuation_the_text_keeps
    matt = parse(MAT_JHN, "Mat")
    assert_equal "Ἀβραάμ", token(matt, "Mat.1.1#08")["form"]
    assert_equal "νηστείᾳ", token(matt, "Mat.17.21#12")["form"]
  end

  def test_joined_words_and_homograph_marks
    acts = parse(ACT_REV, "Act")
    joined = token(acts, "Act.5.39#10")
    assert_equal "G3361 + G4218", joined["strong"]
    assert_equal "PRT-N + PRT", joined["morph"]
    # Upstream's dictionary field "μήποτε=lest + πότε=when" names two
    # lexemes: no single lemma key is minted.
    refute joined.key?("lemma")
    assert_equal %w[μήποτε πότε], joined["lemma_parts"]
    assert_equal "lest + when", joined["lemma_gloss"]
    james = parse(ACT_REV, "Jas")
    assert_equal "ἰός", token(james, "Jas.5.3#10")["lemma"], "the homograph mark (2) is dropped"
  end

  def test_book_absent_from_the_file_is_a_parse_error
    assert_raises(Nabu::ParseError) { parse(MAT_JHN, "Mrk") }
  end

  def test_drifted_word_ref_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.txt")
      File.write(path, File.read(MAT_JHN, encoding: "UTF-8").sub("Mat.1.1#01=NKO", "Mat.1.1-01=NKO"))
      assert_raises(Nabu::ParseError) { parse(path, "Mat") }
    end
  end
end
