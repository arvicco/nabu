# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# SefariaJsonParser tests (P30-3): the `sefaria-json` family — Sefaria's
# per-version export files. One JSON object per title/version carrying its
# own metadata (title, versionTitle, license, sectionNames) plus `text`,
# a jagged array of section strings (Chapter/Verse for the Tanakh shelf,
# deeper where sectionNames says so) OR — complex titles — a dict of
# schema-node jagged arrays keyed by `schema.nodes[].enTitle`. The parser
# walks whatever nesting the file actually has: citation = the 1-based
# index path joined with ".", prefixed with the node slug for dict texts.
class SefariaJsonParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("sefaria")
  TARGUM = File.join(FIXTURES, "json/Tanakh/Targum")

  OBADIAH = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Obadiah/Hebrew/Mikraot Gedolot.json")
  JONAH_EN = File.join(TARGUM,
                       "Targum Jonathan/Prophets/Targum Jonathan on Jonah/English/Sefaria Community Translation.json")
  SHENI = File.join(TARGUM,
                    "Aramaic Targum/Writings/Targum Sheni on Esther/English/Sefaria Community Translation.json")
  JERUSALEM = File.join(TARGUM, "Targum Jerusalem/Targum Jerusalem/Hebrew/Targum Jerusalem on Torah.json")
  ONKELOS_NC = File.join(TARGUM,
                         "Onkelos/Torah/Onkelos Numbers/Hebrew/Sifsei Chachomim Chumash, Metsudah Publications, " \
                         "2009.json")

  def parse(path, urn: "urn:nabu:sefaria:test", language: "arc", **)
    Nabu::Adapters::SefariaJsonParser.new.parse(path, urn: urn, language: language, **)
  end

  # --- citation minting -------------------------------------------------------

  def test_chapter_verse_citations_are_one_based_index_paths
    document = parse(OBADIAH, urn: "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot")
    assert_equal "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot", document.urn
    assert_equal "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot:1.1", document.first.urn
    assert_equal 21, document.size, "Obadiah: one chapter, 21 verses"
    assert_equal "1.21", document.passages.last.urn.split(":").last
  end

  def test_depth_three_section_names_walk_to_paragraph_citations
    document = parse(SHENI, language: "eng")
    assert_equal 7, document.size
    assert_equal "1.2.9", document.first.urn.split(":").last,
                 "Targum Sheni's chapter 1 opens with empty verse arrays and empty paragraphs — " \
                 "the first REAL paragraph is 1.2.9 (sectionNames Chapter/Verse/Paragraph)"
  end

  def test_schema_node_dict_texts_prefix_citations_with_the_node_slug
    document = parse(JERUSALEM)
    assert_equal 39, document.size, "the fragmentary Targum Jerusalem trim: 39 non-empty verses"
    assert_equal "genesis.1.1", document.first.urn.split(":").last
    books = document.map { |p| p.urn.split(":").last[/\A[a-z]+/] }.uniq
    assert_equal %w[genesis exodus leviticus numbers deuteronomy], books,
                 "schema.nodes order IS document order"
  end

  def test_sequence_is_reading_order
    document = parse(OBADIAH)
    assert_equal (0..20).to_a, document.map(&:sequence)
  end

  # --- text discipline --------------------------------------------------------

  def test_aramaic_text_is_byte_verbatim_never_nfc_normalized
    document = parse(OBADIAH)
    verse = document.passages[1]
    upstream = JSON.parse(File.read(OBADIAH)).fetch("text")[0][1]
    assert_equal upstream, verse.text,
                 "upstream bytes verbatim (the Masoretic mark order is NOT NFC-stable — " \
                 "equality against the raw JSON string is the byte pin)"
    refute verse.text.unicode_normalized?(:nfc),
           "this verse's mark order must actually exercise the exemption"
    assert_equal "arc", verse.language
  end

  def test_english_text_is_nfc
    document = parse(JONAH_EN, language: "eng")
    assert_equal 48, document.size
    assert(document.all? { |p| p.text.unicode_normalized?(:nfc) })
  end

  def test_empty_verses_are_skipped_by_rule
    document = parse(JERUSALEM)
    genesis_one = document.select { |p| p.urn.split(":").last.start_with?("genesis.1.") }
    assert_equal 6, genesis_one.size,
                 "Targum Jerusalem Genesis 1 attests 6 of 27 verses — empties never mint passages"
  end

  def test_footnote_markup_is_extracted_to_annotations_not_verse_text
    document = parse(JONAH_EN, language: "eng")
    verse = document.find { |p| p.urn.end_with?(":3.6") }
    assert_equal "And the word reached before the king of Nineveh, and he got up from his royal throne " \
                 "and removed his valuable clothes and from him and covered himself in sackcloth and " \
                 "sat on ashes.", verse.text,
                 "the <sup footnote-marker>/<i footnote> apparatus must not corrupt the reading"
    assert_equal ["Some texts say: “before the Pharaoh who was king in those days in Nineveh,”"],
                 verse.annotations["footnotes"]
  end

  def test_inline_formatting_tags_are_unwrapped_keeping_their_text
    document = parse(ONKELOS_NC)
    verse = document.find { |p| p.urn.end_with?(":1.2") }
    upstream = JSON.parse(File.read(ONKELOS_NC)).fetch("text")[0][1]
    assert_includes upstream, "<b>", "the fixture verse must actually carry the Metsudah emphasis markup"
    assert_equal upstream.gsub(%r{</?b>}, "").strip, verse.text,
                 "the <b> emphasis unwraps — tags dropped, Aramaic bytes otherwise verbatim"
  end

  def test_unmarked_text_carries_no_footnote_annotations
    document = parse(OBADIAH)
    assert(document.all? { |p| p.annotations.empty? })
  end

  # --- document identity ------------------------------------------------------

  def test_title_joins_upstream_title_and_version_title
    document = parse(OBADIAH)
    assert_equal "Targum Jonathan on Obadiah — Mikraot Gedolot", document.title
  end

  def test_trailing_space_in_version_title_is_stripped_from_the_display_title
    taj = File.join(TARGUM, "Onkelos/Torah/Onkelos Genesis/Hebrew/Targum Onkelos, " \
                            "vocalized according to the Yemenite Taj .json")
    document = parse(taj)
    assert_equal "Onkelos Genesis — Targum Onkelos, vocalized according to the Yemenite Taj", document.title
  end

  def test_license_override_and_metadata_ride_the_document
    document = parse(ONKELOS_NC, license_override: "nc", metadata: { "license" => "CC-BY-NC" })
    assert_equal "nc", document.license_override
    assert_equal "CC-BY-NC", document.metadata["license"]
  end

  # --- damage -----------------------------------------------------------------

  def test_malformed_json_raises_parse_error
    with_file("{not json") do |path|
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end

  def test_missing_text_raises_parse_error
    with_file('{"title": "T", "versionTitle": "V"}') do |path|
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end

  def test_text_with_zero_non_empty_leaves_raises_parse_error
    with_file('{"title": "T", "versionTitle": "V", "text": [["", ""], []]}') do |path|
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end

  def test_non_string_leaf_raises_parse_error
    with_file('{"title": "T", "versionTitle": "V", "text": [[42]]}') do |path|
      assert_raises(Nabu::ParseError) { parse(path) }
    end
  end

  # --- the slug helper (shared identity fold with the adapter) ----------------

  def test_slug_folds_titles_to_urn_safe_tokens
    slug = Nabu::Adapters::SefariaJsonParser.method(:slug)
    assert_equal "mikraot-gedolot", slug.call("Mikraot Gedolot")
    assert_equal "targum-onkelos-vocalized-according-to-the-yemenite-taj",
                 slug.call("Targum Onkelos, vocalized according to the Yemenite Taj ")
    assert_equal "sifsei-chachomim-chumash-metsudah-publications-2009",
                 slug.call("Sifsei Chachomim Chumash, Metsudah Publications, 2009")
  end

  private

  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "version.json")
      File.write(path, content)
      yield path
    end
  end
end
