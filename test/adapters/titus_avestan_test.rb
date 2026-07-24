# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TITUS Avestan adapter tests (P43-2): the frame-based Avesta edition, one
# document per text page, verses as passages keyed off the machine-generated
# <A NAME="Avest._book_chapter_paragraph_verse"> anchors. Includes the shared
# conformance suite against a two-page fixture trim (Yasna 0 + the Yasna 1
# continuation page). No network: fetch is owner-run only.
class TitusAvestanTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("titus-avestan")

  # The frauuarāne creed line (Y 0.1 a) — a known snippet, apparatus-free.
  FRAUUARANE = "frauuarāne. mazdaiiasnō. zaraϑuštriš. vīdaēuuō. ahura.t̰kaēṣ̌ō::"

  def conformance_adapter
    Nabu::Adapters::TitusAvestan.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "titus-avestan"
  end

  def setup
    @adapter = Nabu::Adapters::TitusAvestan.new
  end

  def documents_by_page
    @adapter.discover(FIXTURES).to_h do |ref|
      [ref.metadata.fetch("page"), @adapter.parse(ref)]
    end
  end

  def passages_of(page)
    documents_by_page.fetch(page).passages
  end

  def passage(urn)
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_titus_avestan_source
    manifest = Nabu::Adapters::TitusAvestan.manifest
    assert_equal "titus-avestan", manifest.id
    assert_equal "titus_avestan", manifest.parser_family
    assert_equal "ave", Nabu::Adapters::TitusAvestan::LANGUAGE
  end

  # The grant is non-commercial + credit "wherever displayed" — NOT private:
  # license_class `nc` keeps it SERVABLE (not MCP-hidden like research_private),
  # while grant_required (registry) guards the fetch right.
  def test_manifest_declares_nc_class_with_verbatim_grant_license
    manifest = Nabu::Adapters::TitusAvestan.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "non-commercial use"
    assert_includes manifest.license, "clearly indicated wherever displayed"
  end

  def test_manifest_carries_the_credit_line
    manifest = Nabu::Adapters::TitusAvestan.manifest
    refute_nil manifest.credit
    assert_includes manifest.credit, "TITUS"
    assert_includes manifest.credit, "Gippert"
    assert_includes manifest.credit, "Geldner/Westergaard"
    assert_includes manifest.credit, "Fritz"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_document_per_text_page_not_the_frameset
    pages = @adapter.discover(FIXTURES).map { |ref| ref.metadata.fetch("page") }
    assert_equal %w[avest001 avest002], pages.sort
  end

  def test_discover_ref_id_is_the_page_document_urn
    ref = @adapter.discover(FIXTURES).find { |r| r.metadata["page"] == "avest001" }
    assert_equal "urn:nabu:titus-avestan:avest001", ref.id
  end

  # --- parse: structure -------------------------------------------------------

  def test_parse_mints_verse_passages_at_the_anchor_grain
    assert_equal 39, passages_of("avest001").size
    # 11 verses + the one chapter-level ritual rubric (zōt̰. u. rāspī.).
    assert_equal 12, passages_of("avest002").size
  end

  # A chapter can carry a ritual rubric of its own, before its first verse —
  # keyed at the chapter grain (Y.1), not under any verse, and never dropped.
  def test_chapter_level_ritual_rubric_becomes_its_own_passage
    rubric = passage("urn:nabu:titus-avestan:avest002:Y.1")
    refute_nil rubric
    assert_equal "zōt̰. u. rāspī.", rubric.text
    assert_equal({ "book" => "Y", "chapter" => "1" }, rubric.annotations)
  end

  def test_passage_urns_nest_under_the_page_and_carry_the_citation
    first = passages_of("avest001").first
    assert_equal "urn:nabu:titus-avestan:avest001:Y.0.1.Q1Aa", first.urn
    assert_equal({ "book" => "Y", "chapter" => "0", "paragraph" => "1", "verse" => "Q1Aa" },
                 first.annotations)
  end

  # The verse labels the real markup shows: the Ahuna-Vairya quartet Q1Aa…Q1Dc
  # AND the plain a–e frauuarāne lines, in document order.
  def test_verse_labels_span_the_q_quartet_and_plain_letters
    labels = passages_of("avest001").select { |p| p.annotations.values_at("chapter", "paragraph") == %w[0 1] }
                                    .map { |p| p.annotations.fetch("verse") }
    assert_equal %w[Q1Aa Q1Ab Q1Ac Q1Ba Q1Bb Q1Bc Q1Ca Q1Cb Q1Cc Q1Da Q1Db Q1Dc a b c d e], labels
  end

  # --- parse: text fidelity ---------------------------------------------------

  def test_known_snippet_frauuarane_is_extracted_verbatim
    assert_equal FRAUUARANE, passage("urn:nabu:titus-avestan:avest001:Y.0.1.a").text
  end

  # The <span id=x12> Geldner line-numbers are interspersed MID-verse; they are
  # apparatus, not text — the frauuarāne line carries no stray digits.
  def test_geldner_line_number_apparatus_is_excluded
    refute_match(/\d/, passage("urn:nabu:titus-avestan:avest001:Y.0.1.a").text)
  end

  # <span id=iipzc…> parenthetical Pahlavi ritual rubrics ARE part of the
  # displayed text and are kept.
  def test_ritual_rubric_in_parentheses_is_kept
    assert_includes passage("urn:nabu:titus-avestan:avest001:Y.0.1.Q1Aa").text,
                    "(yak. u. si. bār.)"
  end

  # <SUP> wraps an in-word combining mark (mazdā̊, ā + U+030A ring above) — kept
  # and NFC-normalized, never dropped with the tag.
  def test_in_word_sup_combining_mark_is_preserved
    text = passage("urn:nabu:titus-avestan:avest001:Y.0.2.a").text
    assert_includes text, "mazdā̊."
    assert text.unicode_normalized?(:nfc)
  end

  # The continuation page carries NO "Book:" header — book context comes only
  # from the anchor. Its verses still key under book Y.
  def test_continuation_page_recovers_book_from_the_anchor
    verse = passage("urn:nabu:titus-avestan:avest002:Y.1.1.a")
    refute_nil verse
    assert_equal "Y", verse.annotations.fetch("book")
    assert_equal "niuuaēδaiiemi. haṇkāraiiemi.", verse.text
  end

  def test_document_title_names_the_book
    title = documents_by_page.fetch("avest001").title
    assert_equal "Avestan Corpus — Yasna (avest001)", title
  end

  # --- parse: quarantine discipline ------------------------------------------

  def test_a_page_with_no_verses_quarantines_loudly
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "avest999.htm"),
                 "<html><body><span id=h2>Book: Y<A NAME=\"Avest._Y\">x</A></span></body></html>")
      ref = @adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
    end
  end
end
