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
    assert_equal 279, entries.size
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

  def test_headwords_fold_with_the_neutralized_chu_fold
    # P27-2: the chu fold neutralizes script (Cyrl skeleton) before the
    # generic mark strip — jers stay letters, on the Latin-diplomatic side.
    assert_equal "bogъ", entry("богъ:noun").headword_folded
    # ан҃г carries the Cyrillic titlo U+0483 — a combining mark, stripped
    ang = entries.find { |e| e.headword == "ан҃г" } || flunk("titlo fixture word missing")
    assert_equal "ang", ang.headword_folded
    # uppercase downcases (proper names); оу collapses to the u skeleton
    isus = entries.find { |e| e.headword == "Исоусъ" } || flunk("Исоусъ missing")
    assert_equal "isusъ", isus.headword_folded
  end

  def test_homographs_stay_separate_entries_sharing_a_folded_headword
    group = entries.select { |e| e.headword == "и" }
    assert_equal 3, group.size
    assert_equal ["i"], group.map(&:headword_folded).uniq
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

  # --- reflexes (P14-1, the reconstruction crosswalk edges) ----------------------

  RECON = Nabu::TestSupport.fixtures("wiktionary-recon")

  def recon_entries(file, language)
    Nabu::Adapters::WiktionaryJsonlParser
      .new(language: language, reflexes: true)
      .entries(File.join(RECON, file))
  end

  def sla_entries
    @sla_entries ||= recon_entries("kaikki.org-dictionary-ProtoSlavic.jsonl", "sla-pro")
  end

  def sla_entry(id)
    sla_entries.find { |e| e.entry_id == id } || flunk("fixture entry #{id} not parsed")
  end

  def test_reflexes_default_off_the_cu_shelf_is_untouched
    assert(entries.all? { |e| e.reflexes.empty? })
  end

  def test_reflexes_flatten_worded_nodes_depth_first
    bog = sla_entry("bogъ:noun:2")
    # parent before child, siblings in upstream order: orv богъ leads its
    # Old Ruthenian child
    assert_equal %w[orv zle-ort], bog.reflexes.first(2).map(&:lang_code)
    assert_equal %w[богъ богъ], bog.reflexes.first(2).map(&:word)
    # branch-grouping nodes (East Slavic…) mint no rows: every reflex has a word
    assert(sla_entries.flat_map(&:reflexes).none? { |r| r.word.strip.empty? })
  end

  def test_ocs_reflexes_surface_from_the_script_children
    cu = sla_entry("bogъ:noun:2").reflexes.select { |r| r.lang_code == "cu" }
    assert_equal %w[chu], cu.map(&:language).uniq, "cu maps to the catalog's chu"
    cyrillic = cu.find { |r| r.word == "богъ" } || flunk("Old Cyrillic богъ reflex missing")
    assert_equal "bogъ", cyrillic.word_folded, "P27-2: the chu skeleton crosses the script"
    assert_equal "bogŭ", cyrillic.roman
    glagolitic = cu.find { |r| r.word == "ⰱⱁⰳⱏ" } || flunk("Glagolitic богъ reflex missing")
    assert_equal "ⰱⱁⰳⱏ", glagolitic.word_folded, "script twins fold as themselves, honestly"
  end

  # P18-4: every worded node's human `lang` name rides the reflex VERBATIM
  # (NFC) — the raw material of the language_names census. Script wrapper
  # names ("Old Cyrillic script") and misfiled names ("Middle Ukrainian"
  # under zle-ort in this fixture) stay: canonical means canonical, the
  # census read side filters and takes the mode.
  def test_reflexes_carry_the_upstream_language_name_verbatim
    bog = sla_entry("bogъ:noun:2")
    assert_equal ["Old East Slavic", "Old Ruthenian"], bog.reflexes.first(2).map(&:lang_name)
    cu_names = bog.reflexes.select { |r| r.lang_code == "cu" }.map(&:lang_name)
    assert_includes cu_names, "Old Cyrillic script", "wrapper-node names parse raw"
  end

  def test_reconstructed_reflexes_keep_the_asterisk_but_fold_without_it
    novgorod = sla_entry("bogъ:noun:2").reflexes.find { |r| r.lang_code == "zle-ono" } ||
               flunk("Old Novgorodian *боге reflex missing")
    assert_equal "*боге", novgorod.word
    assert_equal "боге", novgorod.word_folded
    assert_equal "*boge", novgorod.roman
    assert_equal "boge", novgorod.roman_folded
  end

  def test_proto_to_proto_edges_carry_the_other_extracts_language
    pie = recon_entries("kaikki.org-dictionary-ProtoIndoEuropean.jsonl", "ine-pro")
    bhag = pie.find { |e| e.entry_id == "bʰeh₂g-:root" } || flunk("bʰeh₂g- not parsed")
    slavic = bhag.reflexes.find { |r| r.lang_code == "sla-pro" && r.word == "*bogъ" } ||
             flunk("the PIE→Proto-Slavic *bogъ edge is the demo chain — missing")
    assert_equal "sla-pro", slavic.language
    assert_equal "bogъ", slavic.word_folded, "joins the sla-pro shelf's asterisk-less headword_folded"
    # attested Greek reflexes fold with the mapped catalog language
    greek = bhag.reflexes.find { |r| r.lang_code == "grc" } || flunk("grc reflex missing")
    assert_equal "grc", greek.language
    assert_equal "ἔφᾰγον", greek.word
    assert_equal "εφαγον", greek.word_folded
  end

  # P17-3: the borrowed predicate — /borrow/i over raw_tags ∪ tags. The
  # iir-pro adᶻdʰáH record carries all three shapes in one tree: a flagged
  # xcl loan (raw_tags ["borrowed"]), plain inherited nodes (false), and a
  # "reshaped by analogy or addition of morphemes" raw_tag that must NOT
  # read as a loan.
  def test_borrowed_parses_from_raw_tags_and_ignores_the_analogy_tag
    iir = recon_entries("kaikki.org-dictionary-ProtoIndoIranian.jsonl", "iir-pro")
    azd = iir.find { |e| e.entry_id == "adᶻdʰáH:adj" } || flunk("adᶻdʰáH not parsed")
    xcl = azd.reflexes.find { |r| r.lang_code == "xcl" } || flunk("xcl ազդ reflex missing")
    assert xcl.borrowed, "xcl ազդ carries raw_tags [\"borrowed\"]"
    sa = azd.reflexes.find { |r| r.lang_code == "sa" } || flunk("sa अद्धा reflex missing")
    refute sa.borrowed, "inherited nodes parse false, never NULL"
    reshaped = azd.reflexes.find { |r| r.word == "ʾzdʾqryʾ" } ||
               flunk("the reshaped-by-analogy sog node missing")
    refute reshaped.borrowed, "'reshaped by analogy…' is not a loan marker"
  end

  def test_la_maps_to_lat_and_folds_by_the_catalog_language
    pie = recon_entries("kaikki.org-dictionary-ProtoIndoEuropean.jsonl", "ine-pro")
    nu = pie.find { |e| e.entry_id == "nu:adv" } || flunk("nu:adv not parsed")
    nuper = nu.reflexes.find { |r| r.word == "nūper" } || flunk("la nūper reflex missing")
    assert_equal "la", nuper.lang_code, "upstream code verbatim"
    assert_equal "lat", nuper.language, "catalog code for the join"
    assert_equal "nuper", nuper.word_folded
  end

  def test_gothic_script_reflexes_carry_their_roman_fold_the_gold_join_key
    gem = recon_entries("kaikki.org-dictionary-ProtoGermanic.jsonl", "gem-pro")
    gud = gem.find { |e| e.entry_id == "gudą:noun" } || flunk("gudą not parsed")
    got = gud.reflexes.find { |r| r.lang_code == "got" } || flunk("got reflex missing")
    assert_equal "𐌲𐌿𐌸", got.word
    assert_equal "guþ", got.roman
    assert_equal "guþ", got.roman_folded
  end

  def test_the_malformed_ml_code_stores_verbatim_with_nil_language
    gem = recon_entries("kaikki.org-dictionary-ProtoGermanic.jsonl", "gem-pro")
    hrunk = gem.find { |e| e.entry_id == "hrunkwǭ:noun" } || flunk("hrunkwǭ not parsed")
    ml = hrunk.reflexes.find { |r| r.lang_code == "ML." } ||
         flunk("the lone malformed lang_code record is the fixture's point")
    assert_nil ml.language, "no valid tag — display-only, never a join candidate"
    assert_equal "fruncāre", ml.word
    assert_equal "fruncare", ml.word_folded, "generic fold still applies"
  end

  def test_grouping_only_descendants_yield_zero_reflexes
    assert_empty sla_entry("kosatъ:noun:2").reflexes
    assert_empty sla_entry("aby:particle").reflexes, "no descendants at all"
  end

  def test_recon_headwords_fold_generically_for_the_pro_languages
    assert_equal "bogъ", sla_entry("bogъ:noun:2").headword_folded, "jer kept — a letter, not a mark"
    cesar = sla_entry("cěsařь:noun")
    assert_equal "cesarь", cesar.headword_folded, "hačeks strip under NFD (ě→e, ř→r); the jer stays"
    assert cesar.headword.unicode_normalized?(:nfc), "upstream ships decomposed — parser NFCs"
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
