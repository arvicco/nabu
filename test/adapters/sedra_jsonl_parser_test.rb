# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"

# The sedra-jsonl parser family (Nabu::Adapters::SedraJsonlParser): the
# Sedra V release tables — gzip JSON Lines, one row per line — joined into
# one DictionaryEntry per lexeme. Runs over the real trimmed release in
# test/fixtures/sedra/ (seven lexeme rows with their words, glosses,
# etymologies and roots; the lookup tables whole).
class SedraJsonlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("sedra")
  PARSER = Nabu::Adapters::SedraJsonlParser

  def parser = PARSER.new(FIXTURES)

  def entries = @entries ||= parser.entries(language: "syc")

  def entry(id) = entries.find { |e| e.entry_id == id } || flunk("entry #{id} missing")

  def test_tables_read_every_gzip_row_in_file_order
    assert_equal([1, 3, 225, 607, 3469, 16_413, 28_521], parser.table("lexemes").map { |r| r["id"] })
    assert_equal 16, parser.table("languages").size, "a lookup table rides whole"
    assert_equal "English", parser.index("languages")[10]["name"]
  end

  def test_a_missing_or_broken_table_is_a_parse_error
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::ParseError) { PARSER.new(dir).table("lexemes") }
      File.binwrite(File.join(dir, "lexemes.jsonl.gz"), "not gzip")
      assert_raises(Nabu::ParseError) { PARSER.new(dir).table("lexemes") }
      Zlib::GzipWriter.open(File.join(dir, "roots.jsonl.gz")) { |gz| gz.write("{\"id\": 1}\n{broken\n") }
      error = assert_raises(Nabu::ParseError) { PARSER.new(dir).table("roots") }
      assert_match(/roots\.jsonl\.gz:2: malformed JSON row/, error.message)
    end
  end

  def test_one_entry_per_lexeme_with_a_headword
    assert_equal %w[1 3 225 607 3469 16413], entries.map(&:entry_id)
    assert_equal [28_521], parser.headwordless.map { |r| r["id"] }, "the empty Sedra III row mints nothing"
  end

  def test_the_entry_joins_root_category_glosses_etymology_and_forms
    air = entry("1")
    assert_equal "ܐܐܪ", air.headword
    assert_equal "air", air.gloss
    assert_equal "ܐܐܪ ܐܳܐܰܪ\nnoun · root ܐܐܪ\nEnglish: air; air‏.\nFrench: air; aspect\n" \
                 "Arabic: هواء; هيئة\nEtymology: Greek ἀήρ\nForms: ܐܐܪ, ܒܐܐܪ, ܕܐܐܪ, ܕܠܐܐܪ, ܘܐܐܪ, ܐܐܪܣ",
                 air.body
    assert_equal({ "id" => 1, "syriac" => "ܐܐܪ", "kind" => "semitic" }, air.annotations["root"])
    assert_equal "noun", air.annotations["pos"]
    assert_equal "Sedra III", air.annotations["source"]
    assert_equal %w[grc], air.annotations["etymon_languages"]
  end

  def test_an_etymology_is_a_derived_up_edge_in_the_catalog_language
    reflex = entry("607").reflexes.first
    assert_equal %w[grc grc γένος Greek derived],
                 [reflex.lang_code, reflex.language, reflex.word, reflex.lang_name, reflex.relation]
    assert reflex.etymon?, "derived points UP — the Greek word is the entry's own source"
    arabic = entry("16413").reflexes.first
    assert_equal %w[ara ara], [arabic.lang_code, arabic.language]
  end

  def test_gloss_markup_renders_to_text_and_blank_cells_are_absence
    genos = entry("607")
    assert_includes genos.body, "ܓܢܶܣ ܓܢܶܣ various.", "the selectableFont span renders to its Syriac text"
    refute_includes genos.body, "<span"
    asn = entry("225")
    refute_match(/^French:/, asn.body, "a French cell holding only a no-break space is no gloss")
    assert_equal ["eng"], asn.annotations["glosses"].map { |g| g["language"] }.uniq
  end

  def test_word_forms_carry_their_morphology_names
    suffixed = entry("3469").annotations["forms"].find { |f| f["syriac"] == "ܠܒܬܪܗ" }
    assert_equal({ "id" => 2212, "syriac" => "ܠܒܬܪܗ", "vocalized_west" => "ܠܒ݂ܳܬ݂ܪܶܗ", "translit_sedra3" => "LBTRH",
                   "suffix_person" => "third", "suffix_gender" => "masculine", "suffix_number" => "singular" },
                 suffixed)
    assert_nil entry("3469").gloss, "a lexeme without gloss rows carries none"
  end

  def test_output_is_nfc_and_folded_for_lookup
    entries.each do |e|
      [e.headword, e.body, e.headword_folded].each { |text| assert text.unicode_normalized?(:nfc), e.entry_id }
    end
    assert_equal Nabu::Normalize.search_form("ܓܢܣܐ", language: "syc"), entry("607").headword_folded
  end

  def test_plain_strips_markup_and_reads_format_only_values_as_absent
    assert_equal "ܕܰܐܝܟ of what kind", PARSER.plain('<span class="selectableFont">ܕܰܐܝܟ</span> of what kind')
    assert_nil PARSER.plain(" ")
    assert_nil PARSER.plain("‏ ")
    assert_equal "air‏.", PARSER.plain("air‏."), "a control inside real text stays verbatim"
  end
end
