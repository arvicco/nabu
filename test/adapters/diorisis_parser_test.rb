# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::DiorisisParser (P26-4): streaming parser for one Diorisis
# corpus XML file — TEI.2-shaped (P4-era, no namespace, no XML declaration),
# body → <sentence id location> → <word form id> → <lemma id entry POS
# TreeTagger disambiguated> → <analysis morph>, plus <punct mark>. Word forms
# are TLG Beta Code (decoded through the existing Nabu::Betacode inventory —
# the corpus-wide census found NO character outside it); lemma entries are
# already Unicode Greek (429 of 10.05M are non-NFC upstream → NFC at this
# boundary).
#
# Streaming is a house rule, not a preference: 76 of the 820 corpus files
# exceed 5 MB (Polybius' Histories is 76.1 MB), so the only Nokogiri entry
# point is Nokogiri::XML::Reader — pinned structurally below, as for
# ProielParser.
class DiorisisParserTest < Minitest::Test
  HYMN = File.join(Nabu::TestSupport.fixtures("diorisis"),
                   "Hymns (0013) - Hymn 13 To Demeter (013).xml")
  URN = "urn:nabu:diorisis:0013:013"

  def parse(path = HYMN, urn: URN)
    Nabu::Adapters::DiorisisParser.new.parse(path, urn: urn, language: "grc",
                                                   title: "Hymns — Hymn 13 To Demeter")
  end

  # -- passage minting --------------------------------------------------------

  def test_one_passage_per_sentence_with_upstream_ids_in_urns
    document = parse
    assert_equal URN, document.urn
    assert_equal "grc", document.language
    assert_equal 3, document.count, "the fixture hymn has 3 sentence elements"
    assert_equal ["#{URN}:1", "#{URN}:2", "#{URN}:3"], document.map(&:urn),
                 "passage urns ride the upstream sentence ids (unique per file — censused)"
    assert_equal [0, 1, 2], document.map(&:sequence)
  end

  def test_text_is_beta_code_decoded_with_punct_glued_left
    document = parse
    assert_equal "Δημήτηρ' ἠύκομον, σεμνὴν θεάν, ἄρχομ' ἀείδειν, " \
                 "αὐτὴν καὶ κούρην, περικαλλέα Περσεφόνειαν.",
                 document.first.text,
                 "words decode from Beta Code; punct marks stay verbatim, attached to the left"
    assert_equal "χαῖρε, θεά, καὶ τήνδε σάου πόλιν:", document.passages[1].text,
                 "the upstream ':' punct mark is kept verbatim, never reinterpreted"
  end

  def test_location_is_the_verbatim_citation_and_may_repeat
    document = parse
    assert_equal %w[1 3 3], document.map { |p| p.annotations["location"] },
                 "location is the corpus's own citation string, verbatim — it may repeat " \
                 "(both hymn lines 2-3 cite line 3), which is why urns ride sentence ids instead"
  end

  # -- token annotations ------------------------------------------------------

  def test_tokens_carry_decoded_form_and_nfc_lemma_entry
    tokens = parse.first.annotations.fetch("tokens")
    assert_equal 11, tokens.size, "one token per word element; punct is not a token"
    second = tokens[1]
    assert_equal "ἠύκομον", second.fetch("form"), "forms are Beta Code, decoded at this boundary"
    assert_equal "εὔκομος", second.fetch("lemma")
    assert second.fetch("lemma").unicode_normalized?(:nfc), "lemma entries are NFC'd (429 upstream are not)"
    assert_equal "44281", second.fetch("lemma_id")
    assert_equal "adjective", second.fetch("pos")
    assert_equal ["masc/fem acc sg (epic ionic)", "neut nom/voc/acc sg (epic ionic)"],
                 second.fetch("analyses"), "every candidate analysis rides along, in file order"
  end

  def test_a_lemma_without_an_entry_yields_a_lemma_less_token
    first = parse.first.annotations.fetch("tokens").first
    assert_equal "Δημήτηρ'", first.fetch("form"),
                 "the word still contributes its surface form to text and token"
    refute first.key?("lemma"),
           '<lemma id="unknown"> with no entry attribute is an unlemmatized word (153,593 ' \
           "corpus-wide) — honest absence, so the Indexer mints no lemma row for it"
    refute first.key?("analyses"), "no analyses on an unlemmatized word"
  end

  def test_tree_tagger_disambiguation_is_kept_only_where_it_happened
    tokens = parse.passages[1].annotations.fetch("tokens")
    saou = tokens.find { |t| t["form"] == "σάου" } || flunk("σάου token missing")
    assert_equal true, saou.fetch("tree_tagger"),
                 "TreeTagger=true marks an automatically disambiguated lemma choice"
    assert_equal "0.5", saou.fetch("disambiguated"),
                 "the upstream 1/n confidence fraction rides verbatim"
    undisambiguated = tokens.find { |t| t["form"] == "χαῖρε" }
    refute undisambiguated.key?("tree_tagger"),
           'TreeTagger="false" / disambiguated="n/a" (the 8.2M-word majority) stays absent — lean keys'
    refute undisambiguated.key?("disambiguated")
  end

  # -- errors -----------------------------------------------------------------

  def test_a_sentence_without_an_id_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.xml")
      File.write(path, File.read(HYMN).sub('<sentence id="2" location="3">', "<sentence>"))
      error = assert_raises(Nabu::ParseError) { parse(path) }
      assert_match(/missing its @id/, error.message)
    end
  end

  def test_a_file_without_sentences_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "empty.xml")
      File.write(path, "<TEI.2><text><body></body></text></TEI.2>")
      error = assert_raises(Nabu::ParseError) { parse(path) }
      assert_match(/no <sentence> elements/, error.message)
    end
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "malformed.xml")
      File.write(path, "<TEI.2><text><body><sentence id=\"1\"")
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end

  # -- streaming discipline ---------------------------------------------------

  def test_parser_streams_via_xml_reader_and_never_builds_a_dom
    source = File.read(File.expand_path("../../lib/nabu/adapters/diorisis_parser.rb", __dir__))
    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    refute_match(/Nokogiri::XML::Document/, source, "must not build a full XML document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end
end
