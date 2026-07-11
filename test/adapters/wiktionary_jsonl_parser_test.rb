# frozen_string_literal: true

require "test_helper"
require "tempfile"

# The wiktionary-jsonl parser family (P13-10): kaikki.org's wiktextract
# JSONL — one JSON object per line, one record per WORD x POS x etymology
# section, no top-level record id. All assertions run against the real
# trimmed kaikki OCS extract in test/fixtures/wiktionary-cu/.
class WiktionaryJsonlParserTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("wiktionary-cu"),
                      "kaikki.org-dictionary-OldChurchSlavonic.jsonl")

  def entries
    @entries ||= Nabu::Adapters::WiktionaryJsonlParser.new.entries(FIXTURE)
  end

  def entry(id)
    entries.find { |e| e.entry_id == id } || flunk("fixture entry #{id} not parsed")
  end

  def test_parses_every_fixture_line_into_a_dictionary_entry
    assert_equal 278, entries.size
    assert(entries.all?(Nabu::DictionaryEntry))
  end

  # --- entry ids: word:pos[:ety][:n] -----------------------------------------

  def test_entry_ids_compose_word_pos_and_etymology_number
    assert_includes entries.map(&:entry_id), "богъ:noun"
    # homograph о: a letter entry (etymology 1) and a preposition (etymology 2)
    assert_includes entries.map(&:entry_id), "о:character:1"
    assert_includes entries.map(&:entry_id), "о:prep:2"
    # triple homograph и: letter / conjunction / pronoun
    %w[и:character:1 и:conj:2 и:pron:3].each { |id| assert_includes entries.map(&:entry_id), id }
  end

  def test_residual_collisions_get_a_positional_suffix_in_file_order
    ids = entries.map(&:entry_id)
    assert_equal ids.uniq, ids, "entry ids must be unique within the file"
    # боль appears twice as noun with no etymology_number ("sick man" / "pain")
    assert_includes ids, "боль:noun"
    assert_includes ids, "боль:noun:2"
    assert_equal "sick man", entry("боль:noun").gloss
    assert_equal "pain", entry("боль:noun:2").gloss
    # видимъ collides even WITH an etymology number (both are etymology 2)
    assert_includes ids, "видимъ:verb:2"
    assert_includes ids, "видимъ:verb:2:2"
    # the Glagolitic headword collides too
    assert_includes ids, "ⰿⰾⱑⰽⱁ:noun"
    assert_includes ids, "ⰿⰾⱑⰽⱁ:noun:2"
  end

  # --- headword / fold ---------------------------------------------------------

  def test_headword_is_the_word_field_nfc_and_key_raw_verbatim
    bog = entry("богъ:noun")
    assert_equal "богъ", bog.headword
    assert_equal "богъ", bog.key_raw
    entries.each do |e|
      assert e.headword.unicode_normalized?(:nfc)
      assert e.body.unicode_normalized?(:nfc)
      assert_equal "chu", e.language
    end
  end

  def test_headwords_fold_with_the_generic_chu_fold
    assert_equal "богъ", entry("богъ:noun").headword_folded # jers are letters, kept
    # ан҃г carries the Cyrillic titlo U+0483 — a combining mark, stripped
    ang = entries.find { |e| e.headword == "ан҃г" } || flunk("titlo fixture word missing")
    assert_equal "анг", ang.headword_folded
    # uppercase downcases (proper names)
    isus = entries.find { |e| e.headword == "Исоусъ" } || flunk("Исоусъ missing")
    assert_equal "исоусъ", isus.headword_folded
  end

  def test_homographs_stay_separate_entries_sharing_a_folded_headword
    group = entries.select { |e| e.headword == "и" }
    assert_equal 3, group.size
    assert_equal ["и"], group.map(&:headword_folded).uniq
  end

  # --- gloss --------------------------------------------------------------------

  def test_gloss_is_the_first_gloss_of_the_first_glossed_sense
    assert_equal "god", entry("богъ:noun").gloss
    assert_equal "say, speak", entry("глаголати:verb").gloss
    assert_equal "word, speech, utterance", entry("слово:noun").gloss # parent gloss, not the leaf
  end

  def test_gloss_trims_a_trailing_colon
    assert_equal "inflection of видѣти (viděti)", entry("видимъ:verb:2").gloss
  end

  def test_gloss_is_nil_for_no_gloss_records
    assert_nil entry("котерꙑи:pron").gloss
    assert_nil entry("-мо:suffix").gloss
  end

  # --- body: etymology KEPT + sense lines ---------------------------------------

  def test_body_keeps_the_etymology_text_the_reconstruction_seed
    assert_includes entry("богъ:noun").body, "Inherited from Proto-Slavic *bogъ."
    # the PIE chain survives verbatim
    assert_includes entry("о:prep:2").body,
                    "From Proto-Slavic *o(b), from Proto-Indo-European *h₃ebʰi."
  end

  def test_body_numbers_senses_only_when_there_are_several
    slovo = entry("слово:noun") # 18 senses
    assert_match(/^1\. /, slovo.body.lines[1])
    assert_match(/^18\. /, slovo.body.lines.last)
    refute_match(/^1\. /, entry("богъ:noun").body) # single sense, no numbering
    assert_equal "Inherited from Proto-Slavic *bogъ.\ngod", entry("богъ:noun").body
  end

  def test_body_joins_nested_gloss_paths
    assert_includes entry("слово:noun").body, "word, speech, utterance — word"
  end

  def test_body_prefers_raw_glosses_with_their_context_labels
    oko = entry("око:noun")
    assert_includes oko.body, "(anatomy) eye"
  end

  def test_no_gloss_senses_render_their_upstream_tags
    assert_includes entry("-мо:suffix").body, "(Old-East-Church-Slavonic, morpheme, no-gloss)"
    # gloss-less but etymology-bearing: the body is still non-empty prose
    assert_includes entry("котерꙑи:pron").body, "Proto-Balto-Slavic"
  end

  def test_every_body_is_non_empty
    entries.each do |e|
      refute e.body.strip.empty?, "entry #{e.entry_id} rendered an empty body"
    end
  end

  def test_citations_start_empty_wiktionary_quotes_are_unanchored
    assert(entries.all? { |e| e.citations.empty? })
  end

  # --- malformed input ------------------------------------------------------------

  def test_malformed_json_line_raises_parse_error_with_line_number
    Tempfile.create(["kaikki", ".jsonl"]) do |f|
      f.write(%({"word":"а","pos":"noun","lang_code":"cu","senses":[{"glosses":["x"]}]}\n{"word": broken\n))
      f.flush
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::WiktionaryJsonlParser.new.entries(f.path)
      end
      assert_match(/line 2/, error.message)
    end
  end

  def test_record_without_a_word_raises_parse_error
    Tempfile.create(["kaikki", ".jsonl"]) do |f|
      f.write(%({"pos":"noun","lang_code":"cu","senses":[]}\n))
      f.flush
      assert_raises(Nabu::ParseError) { Nabu::Adapters::WiktionaryJsonlParser.new.entries(f.path) }
    end
  end
end
