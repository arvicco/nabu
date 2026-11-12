# frozen_string_literal: true

require "test_helper"
require "stringio"

# The cllg-tei parser family: the Inria CLLG corpora (Freed Corpus, Sources
# Chrétiennes) declare citation through TEI <citeStructure> trees (the
# DTS/Dapytains mechanism), never a CTS cRefPattern, so the EpiDoc family
# cannot read them. Fixtures are trimmed real upstream files
# (test/fixtures/cllg-freed/, test/fixtures/cllg-sc/ — READMEs there).
class CllgTeiParserTest < Minitest::Test
  FREED = File.join(Nabu::TestSupport.fixtures("cllg-freed"), "data")
  SC = File.join(Nabu::TestSupport.fixtures("cllg-sc"), "data")

  ILIAD = File.join(FREED, "tlg0012", "tlg001", "tlg0012.tlg001.cllg-grc1.xml")
  REPUBLIC = File.join(FREED, "tlg0059", "tlg030", "tlg0059.tlg030.cllg-grc1.xml")
  CHRONICLE = File.join(FREED, "tlg2738", "tlg002", "tlg2738.tlg002.cllg-grc1.xml")
  MNASEAS = File.join(FREED, "tlg1514", "tlg002", "tlg1514.tlg002.cllg-grc1.xml")
  AELIAN = File.join(FREED, "tlg0545", "tlg005", "tlg0545.tlg005.cllg-grc1.xml")
  AESCHYLUS = File.join(FREED, "tlg0085", "tlg011", "tlg0085.tlg011.cllg-grc1.xml")
  CELSUM = File.join(SC, "tlg2042", "contra_celsum.xml")
  DEMETRIANUM = File.join(SC, "stoa0104a", "ad_demetrianum.xml")
  PROVERBS = File.join(SC, "tlg4110", "commentaire_proverbes_numeriques.xml")
  HOMILY = File.join(SC, "cllg0010", "homilia_in_resurrectionem_salvatoris.xml")

  Parser = Nabu::Adapters::CllgTeiParser

  def parse(path, urn: "urn:test:doc", language: "grc")
    Parser.new.parse(path, urn: urn, language: language)
  end

  def passages(path, **options)
    parse(path, **options).to_h { |passage| [passage.urn.delete_prefix("urn:test:doc:"), passage] }
  end

  def text(path, ref, **)
    passages(path, **).fetch(ref).text
  end

  # -- verse: div[@type='book'] > l (freed, no edition wrapper) ---------------

  def test_verse_book_line_tree_cites_book_dot_line
    assert_equal %w[1.1 1.2 1.3 2.1 2.2], passages(ILIAD).keys
    assert_equal "Μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος", text(ILIAD, "1.1")
  end

  def test_marginalia_seg_leaves_the_text_and_rides_an_annotation
    line = passages(ILIAD).fetch("1.2")
    assert_equal "οὐλομένην, ἣ μυρί' Ἀχαιοῖς ἄλγε' ἔθηκε,", line.text
    assert_equal [">"], line.annotations["marginalia"]
  end

  def test_text_outside_every_leaf_unit_is_not_cited
    refute(passages(ILIAD).values.any? { |passage| passage.text.include?("ΙΛΙΑΔΟΣ") },
           "the book heads sit beside the l units, outside every citation leaf")
  end

  # -- prose by milestone: the unit runs to the next milestone, across <p> -------

  def test_milestone_units_span_from_marker_to_marker_across_paragraphs
    sections = passages(REPUBLIC)
    assert_equal %w[327a 327b 327c], sections.keys
    assert sections.fetch("327a").text.start_with?("Κατέβην χθὲς εἰς Πειραιᾶ")
    assert sections.fetch("327a").text.end_with?("ἣν οἱ Θρᾷκες ἔπεμπον.")
    assert sections.fetch("327b").text.start_with?("προσευξάμενοι δὲ καὶ θεωρήσαντες")
    assert_includes sections.fetch("327c").text, "Πῶς γὰρ οὔ;"
    assert sections.fetch("327c").text.end_with?("οὕτω διανοεῖσθε.")
  end

  # Upstream is not NFC only by U+0387 GREEK ANO TELEIA / U+037E GREEK
  # QUESTION MARK (survey §4); NFC at the boundary folds them.
  def test_text_is_nfc_at_the_boundary
    raw = File.read(REPUBLIC, encoding: "UTF-8")
    assert_includes raw, "·", "the fixture carries the non-NFC ano teleia"
    text = text(REPUBLIC, "327c")
    assert text.unicode_normalized?(:nfc)
    refute_includes text, "·"
    assert_includes text, "ἔφη· Ὦ Σώκρατες"
  end

  # -- page-cited: the pb stream alone is the citation -------------------------

  def test_page_stream_cites_by_pb_and_keeps_heads_inside_the_page
    pages = passages(CHRONICLE)
    assert_equal %w[218 219 220], pages.keys
    assert pages.fetch("218").text.start_with?("ΣΥΝΑΓΩΓΗ ΧΡΟΝΩΝ κατὰ τὸν ἀκριβῆ ψῆφον")
    assert pages.fetch("218").text.end_with?("Καϊνὰν ἔτη ἑκατὸν τριάκοντα.")
    assert pages.fetch("219").text.start_with?("Σάλα ἔτη ἑκατὸν τριάκοντα.")
    assert_includes pages.fetch("219").text, "Ἡ πυργοποιΐα."
    assert_equal "Ἰαὴρ ἔτη εἴκοσι.", pages.fetch("220").text
  end

  # -- fragments + the Leiden sigla ---------------------------------------------

  def test_fragment_divs_cite_by_their_verbatim_n
    assert_equal ["25 bis a", "25bisb", "34bis", "51"], passages(MNASEAS).keys
  end

  def test_fragment_source_bibl_leaves_the_text_and_rides_an_annotation
    fragment = passages(MNASEAS).fetch("34bis")
    refute_includes fragment.text, "JOSEPHOS"
    assert fragment.text.start_with?(": (112) rursumque tamquam piissimus")
    assert_equal ["JOSEPHOS Contra Apionem 2, 112—117 p. 67, 35 Niese"], fragment.annotations["fragment_source"]
  end

  def test_notes_leave_the_text_and_ride_an_annotation
    fragment = passages(MNASEAS).fetch("25bisb")
    refute_includes fragment.text, "vgl."
    assert_equal [{ "text" => "(vgl. ‘Herodian.’ I 127, 26 Lentz)" }], fragment.annotations["notes"]
  end

  def test_supplied_and_surplus_keep_their_text
    fragment = passages(MNASEAS).fetch("34bis").text
    assert_includes fragment, "τῆς Ἰουδουμαίας ἀφέστηκεν", "surplus ου + supplied ουμ both stay"
    assert_includes fragment, "I{u}dumaeos", "supplied um stays in place"
  end

  def test_del_drops_gap_spaces_unclear_keeps
    fragment = passages(MNASEAS).fetch("51")
    assert_includes fragment.text, "ἄνεται δ' ὁδός", "the deleted ι leaves the text"
    assert_equal ["ι"], fragment.annotations["deleted"]
    assert_includes fragment.text, "Ἴωνος Ὀμφάˈληι κατ'", "supplied + unclear letters keep their text"
    assert fragment.text.start_with?(": ὁ ἐν τῆι"), "a leading gap is a space, never text"
    assert_includes fragment.text, "(19 F 17 a Sn.)", "an inline locator bibl is the printed text — kept"
  end

  # -- Sources Chrétiennes: edition wrapper + textpart subtypes, lb-heavy ---------

  def test_sc_textpart_tree_cites_book_dot_section_under_the_volume
    sections = passages(CELSUM)
    assert_equal %w[proem.1 proem.2 1.1], sections.keys, "the volume div is structural, never a citation level"
    assert sections.fetch("proem.1").text.start_with?("Ὁ μὲν σωτὴρ καὶ κύριος ἡμῶν Ἰησοῦς Χριστὸς")
    assert sections.fetch("1.1").text.start_with?("Πρῶτον τῷ Κέλσῳ κεφάλαιόν ἐστι")
  end

  def test_lb_break_no_joins_the_word_and_plain_lb_spaces
    section = text(CELSUM, "proem.1")
    assert_includes section, "πολλῶν προσελθόντων ψευδομαρτύρων"
    assert_includes section, "Χριστὸς ψευδομαρτυρούμενος"
  end

  def test_sc_milestone_sections_under_chapter_divs
    sections = passages(DEMETRIANUM, language: "lat")
    assert_equal %w[1.1 1.2 2.1 2.2], sections.keys
    assert sections.fetch("1.1").text.start_with?("Oblatrantem te et aduersus Deum")
    assert_includes sections.fetch("1.1").text, "melius existimans errantis"
    assert_equal "lat", sections.fetch("1.1").language
  end

  def test_a_parent_unit_text_outside_its_children_is_not_cited
    items = passages(PROVERBS)
    assert_equal "1.1", items.keys.first
    refute(items.values.any? { |item| item.text.include?("Ad Prov.") }, "chunk heads sit outside the items")
  end

  # Aeschylus fr. 451s**,50 (Radt; a papyrus): line 2 is a lacuna alone (no
  # text at all) and line 3 a lone U+035C metrical sign — text, but nothing a
  # search form keeps, which the Passage model refuses. Neither is a passage;
  # the document still parses (the full freed run quarantined it before).
  def test_units_with_no_searchable_text_are_not_passages
    lines = passages(AESCHYLUS)
    assert_equal ["451s**,50.1", "451s**,50.4", "451s**,50.5"], lines.keys
    assert_equal "ας", lines.fetch("451s**,50.1").text
  end

  # -- the rejected grain: no citation tree declared -----------------------------

  def test_a_file_declaring_no_citation_tree_is_skipped_by_rule
    error = assert_raises(Parser::NoCitationTree) { parse(AELIAN) }
    assert_kind_of Nabu::DocumentSkipped, error
    assert_equal "no citeStructure declared", error.reason
  end

  # Jean de Béryte's homily declares /TEI/text/body/div[@type='edition']/p
  # cited by @n, but no <p> in the body carries an @n: the tree matches no
  # citable node (one of the two such files in SC, 2026-11-12 census).
  def test_a_declared_tree_matching_no_citable_node_is_skipped_by_rule
    error = assert_raises(Parser::ZeroMatchTree) { parse(HOMILY) }
    assert_kind_of Nabu::DocumentSkipped, error
    assert_equal "declared citeStructure matches nothing", error.reason
    assert Parser.header(HOMILY).cited?, "the tree IS declared — the verdict is distinct from no tree"
  end

  # -- the header reader ---------------------------------------------------------

  def test_header_reads_the_freed_bibl_struct_edition
    header = Parser.header(ILIAD)
    assert_equal "Ilias", header.title
    assert_equal "Homerus Epic. Homer", header.author
    assert_equal [], header.languages
    edition = header.editions.first
    assert_equal ["Allen, T.W."], edition.editors
    assert_equal "Homeri Ilias, vols. 2–3", edition.title
    assert_equal "1931", edition.date
    assert_equal "Oxford", edition.place
    assert_equal "Clarendon Press", edition.publisher
    assert header.cited?
  end

  def test_header_reads_every_sc_volume_bibl
    header = Parser.header(CELSUM)
    assert_equal ["grc"], header.languages
    assert_equal %w[SC132 SC136 SC147 SC150], header.editions.map(&:n)
    assert_equal %w[1967 1968 1969 1969], header.editions.map(&:date)
    assert_equal %w[132 136 147 150], header.editions.map(&:volume)
    assert_equal ["Sources chrétiennes"], header.editions.map(&:series).uniq
    assert_equal ["Marcel Borret"], header.editions.first.editors
    assert_equal({ "ISBN" => "978-2-204-07872-6" }, header.editions.first.identifiers)
  end

  def test_header_of_an_uncited_file_says_so
    refute Parser.header(AELIAN).cited?
  end

  # -- the declared tree: default first, the physical tree never cites -----------

  def test_the_default_tree_wins_over_the_physical_one
    refute(passages(CELSUM).keys.any? { |ref| ref.match?(/\A\d+\.\d+\.\d+\z/) }, "no volume.page.line refs")
  end

  # -- the XPath subset ------------------------------------------------------------

  def test_predicates_or_not_and_self_axis
    xpath = Parser::CiteXPath
    either = xpath.compile("./div[@subtype='book' or @subtype='proem']")
    assert either.matches?([frame("div", "subtype" => "proem")])
    refute either.matches?([frame("div", "subtype" => "section")])
    bare = xpath.compile(".//milestone[@unit='section'][not(@ed)]")
    assert bare.matches?([frame("p"), frame("milestone", "unit" => "section")])
    refute bare.matches?([frame("milestone", "unit" => "section", "ed" => "PG")])
    any = xpath.compile(".//*[self::div or self::lg][@n]")
    assert any.matches?([frame("lg", "n" => "3")])
    refute any.matches?([frame("l", "n" => "3")])
  end

  def test_child_and_descendant_axes_are_strict
    child = Parser::CiteXPath.compile("/TEI/text/body/div[@type='book']")
    assert child.matches?(%w[TEI text body].map { |name| frame(name) } + [frame("div", "type" => "book")])
    refute child.matches?(%w[TEI text body div].map { |name| frame(name) } + [frame("div", "type" => "book")])
    descendant = Parser::CiteXPath.compile("/TEI/text/body//pb[@ed='Boor']")
    assert descendant.matches?(%w[TEI text body div p].map { |name| frame(name) } + [frame("pb", "ed" => "Boor")])
  end

  def test_an_unsupported_xpath_is_a_parse_error_naming_it
    error = assert_raises(Nabu::ParseError) { Parser::CiteXPath.compile("./div[position() > 2]") }
    assert_match(/unsupported citeStructure match/, error.message)
  end

  private

  def frame(name, attributes = {})
    Parser::Frame.new(name: name, attributes: attributes)
  end
end
