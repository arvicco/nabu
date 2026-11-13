# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexibank-cldf parser family: one reader for every lexibank CLDF
# Wordlist (forms/languages/parameters/cognates + optional cognatesets/
# borrowings/etyma), one dictionary entry per cognate set. Exercised here
# against the real trimmed upstream fixtures of the wave-1 datasets, one
# family behavior per fixture that carries it (README per fixture dir).
class LexibankCldfParserTest < Minitest::Test
  def fixture(slug) = File.join(Nabu::TestSupport.fixtures(slug), "cldf")

  def read(slug, dir: fixture(slug), **)
    parser = Nabu::Adapters::LexibankCldfParser.new(slug: slug, label: slug.upcase, **)
    parser.read(dir)
  end

  def nfc(pairs) = pairs.map { |pair| pair.map { |text| text && Nabu::Normalize.nfc(text) } }

  def entry(result, id) = result.entries.find { |e| e.entry_id == id } || flunk("set #{id} missing")

  # --- headwords: the reconstruction, else the concept --------------------------

  def test_the_cognatesets_form_id_reconstruction_heads_the_set_and_leaves_the_members
    result = read("acd", language: "map")
    assert_equal %w[24748_1 25118_1 30578_1], result.entries.map(&:entry_id), "cognatesets.csv order"
    set = entry(result, "25118_1")
    assert_equal "baNaw", set.headword, "the proto form verbatim (acd writes it without the asterisk)"
    assert_equal "map", set.language
    assert_equal "a thorny vine: Smilax spp.", set.gloss, "the head form's concept when the set has no Description"
    refute_includes set.reflexes.map(&:word), "baNaw", "the head row is the headword, never its own reflex"
    assert_equal %w[banaw vaɭau vaɭau banau], set.reflexes.map(&:word)
  end

  def test_the_body_carries_reconstruction_set_name_and_etymon
    body = entry(read("acd", language: "map"), "25118_1").body
    assert_includes body, "ACD cognate set 25118_1 — concept: a thorny vine: Smilax spp."
    assert_includes body, "reconstruction: Proto-Austronesian baNaw"
    assert_includes body, "set: PAN *baNaw 'a thorny vine: Smilax spp.'"
    assert_includes body, "etymon 25118: *baNaw — a thorny vine: Smilax spp."
  end

  def test_a_declared_proto_variety_heads_its_set_when_upstream_has_no_is_proto_column
    result = read("uralex", language: "urj", proto_varieties: ["0"])
    set = entry(result, "100-f")
    assert_equal "*kämä ?", set.headword, "uralex writes the asterisk and the doubt mark itself — verbatim"
    assert_equal Nabu::Normalize.search_form("kämä", language: "urj"), set.headword_folded,
                 "the doubt mark is upstream prose, not a key character — folds drop it"
    assert_equal %w[keme kemény], set.reflexes.map(&:word)
    undeclared = entry(read("uralex", language: "urj"), "100-f")
    assert_equal "hard", undeclared.headword, "undeclared, the asterisk is never sniffed: the concept heads"
  end

  def test_a_dataset_without_reconstructions_heads_each_set_with_its_concept
    result = read("dyenindoeuropean", language: "ine")
    set = entry(result, "001-004")
    assert_equal "ALL", set.headword
    assert_equal "ALL", set.gloss
    assert_includes set.body, "no reconstruction in this dataset — the concept heads the set"
    assert_equal 11, set.reflexes.size, "every judged member is a reflex"
  end

  def test_a_set_without_form_id_falls_back_to_its_proto_member_or_concept
    result = read("csd", language: "sio")
    assert_equal "*xi", entry(result, "13").headword, "Form_ID resolves the Proto-Siouan row"
    vermin = entry(result, "73")
    assert_equal "vermin (6)", vermin.headword, "no reconstruction: the set Description stands in (members gloss ant)"
    assert_equal "vermin (6)", vermin.gloss
    assert_equal %w[nactítka kátcĭdĭktĕ´], vermin.reflexes.map(&:word)
  end

  def test_a_set_name_that_repeats_the_id_or_the_headword_earns_no_line
    refute_match(/^set: /, entry(read("csd", language: "sio"), "113").body, "csd names its sets by number")
    refute_match(/^set: /, entry(read("mcd", language: "poz-mic"), "3005").body, "*amʷii repeats amʷii")
    assert_includes entry(read("tlopo", language: "poz-oce"), "1-3-3-4-55-POc-sajaq-a").body, "(level PMP)"
  end

  # --- languages ------------------------------------------------------------------

  def test_iso_codes_pass_through_and_iso_less_varieties_wear_their_glottocode
    set = entry(read("dyenindoeuropean", language: "ine"), "001-004")
    swedish = set.reflexes.find { |r| r.lang_name == "Swedish Up" }
    assert_equal "svea1239", swedish.lang_code
    assert_nil swedish.language, "no ISO code: display-only, never a join candidate"
    german = set.reflexes.find { |r| r.lang_name == "German ST" }
    assert_equal %w[deu deu], [german.lang_code, german.language]
  end

  def test_declared_varieties_map_reconstructions_and_undeclared_protos_stay_namespaced
    set = entry(read("mcd", language: "poz-mic", varieties: { "protooceanic" => "poz-oce-pro" }), "2979")
    poc = set.reflexes.find { |r| r.lang_name == "Proto-Oceanic" }
    assert_equal %w[poz-oce-pro poz-oce-pro], [poc.lang_code, poc.language]
    bare = entry(read("mcd", language: "poz-mic"), "2979").reflexes.find { |r| r.lang_name == "Proto-Oceanic" }
    assert_equal "mcd-protooceanic", bare.lang_code, "a proto never wears its family's Glottocode (ocea1241)"
    assert_nil bare.language
  end

  def test_csd_varieties_carry_no_codes_at_all_so_every_member_is_namespaced
    set = entry(read("csd", language: "sio"), "13")
    assert_equal %w[csd-da csd-bi csd-la], set.reflexes.map(&:lang_code)
    assert(set.reflexes.all? { |r| r.language.nil? })
  end

  # --- flags ------------------------------------------------------------------------

  def test_borrowings_targets_and_loan_columns_flag_borrowed_with_a_body_line
    village = entry(read("acd", language: "map"), "30578_1")
    assert(village.reflexes.all?(&:borrowed), "both members are borrowings targets (and Loan true)")
    assert_equal ["loan: Saisiyat asaŋ", "loan: Bunun asaŋ"], village.body.lines.grep(/\Aloan: /).map(&:chomp),
                 "Bunun's two source-less events render once"
    paha = entry(read("uralex", language: "urj"), "106-x")
    assert(paha.reflexes.all?(&:borrowed))
    assert_includes paha.body, "loan: Ingrian paha ← Germanic (probable)"
    thunder = entry(read("sagartst", language: "sit", word_from: :value), "2526-thethunder")
    assert_equal [false, true], thunder.reflexes.map(&:borrowed), "forms.Loan alone flags Japhug"
  end

  def test_a_doubtful_judgment_marks_the_reflex_uncertain
    set = entry(read("mcd", language: "poz-mic"), "2979")
    assert_equal({ "Gilbertese" => false, "Proto-Oceanic" => true, "Lakalai" => false, "Fijian" => false },
                 set.reflexes.to_h { |r| [r.lang_name, r.uncertain] })
    assert_includes entry(read("mcd", language: "poz-mic"), "2978").body, "(doubtful set)"
  end

  # --- word strategies ----------------------------------------------------------------

  def test_value_strategy_reads_the_source_form_not_the_segmentation_artifact
    set = entry(read("sagartst", language: "sit", word_from: :value), "20-above")
    old_chinese = set.reflexes.find { |r| r.language == "och" }
    assert_equal "*daŋʔ-s", old_chinese.word, "Baxter-Sagart OC rides verbatim as a member"
    assert_equal "steŋ", set.reflexes.first.word
    form = entry(read("sagartst", language: "sit"), "20-above")
    assert_equal "s.t.e.ŋ", form.reflexes.first.word, "the default strategy reads Form"
  end

  def test_value_braces_strategy_splits_variants_and_pairs_orthography_with_transcription
    set = entry(read("saenkoromance", language: "roa", word_from: :value_braces), "23")
    aromanian = set.reflexes.select { |r| r.language == "rup" }
    # upstream writes a Private Use Area character (U+EDC1) inside the
    # Aromanian orthography — carried verbatim, canonical stays canonical
    assert_equal(nfc([["mî \u{EDC1}șcu", "mˈɨšk-u"], ["mușcu", "mˈušk-u"]]), aromanian.map { |r| [r.word, r.roman] })
    breast = entry(read("saenkoromance", language: "roa", word_from: :value_braces), "34")
    assert_equal nfc([%w[stòmi stˈɔmi], ["stˈɔːmik", nil], %w[stòmegh stˈɔmeg]]),
                 breast.reflexes.map { |r| [r.word, r.roman] }, "a bare transcription stays the word"
  end

  def test_unknown_strategy_is_refused
    assert_raises(ArgumentError) { read("acd", language: "map", word_from: :segments) }
  end

  # --- skips, census, errors ------------------------------------------------------------

  def test_the_census_counts_minted_sets_and_unjudged_forms
    census = read("dyenindoeuropean", language: "ine").census
    assert_equal 2, census[:sets_minted]
    assert_equal 1, census[:forms_unjudged], "the Ossetic form outside the CognateTable mints nothing"
  end

  def test_placeholder_only_sets_mint_nothing_and_are_counted
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(fixture("dyenindoeuropean"), dir)
      forms = File.join(dir, "cldf", "forms.csv")
      File.write(forms, File.read(forms).sub(",pawb,pawb,", ",---,---,"))
      result = read("dyenindoeuropean", dir: File.join(dir, "cldf"), language: "ine")
      assert_equal %w[001-004], result.entries.map(&:entry_id), "ielexfinal's '---' grain mints nothing"
      assert_equal 1, result.census[:sets_without_forms]
    end
  end

  def test_a_dangling_form_id_is_a_parse_error_never_a_silent_drop
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(fixture("csd"), dir)
      forms = File.join(dir, "cldf", "forms.csv")
      File.write(forms, File.readlines(forms).reject { |line| line.start_with?("pma-") }.join)
      error = assert_raises(Nabu::ParseError) { read("csd", dir: File.join(dir, "cldf"), language: "sio") }
      assert_match(/cognate set 113 names unknown form pma-/, error.message)
    end
  end

  def test_a_missing_spine_table_is_a_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(fixture("uralex"), dir)
      File.delete(File.join(dir, "cldf", "cognates.csv"))
      error = assert_raises(Nabu::ParseError) { read("uralex", dir: File.join(dir, "cldf"), language: "urj") }
      assert_match(/missing cognates\.csv/, error.message)
    end
  end

  def test_folds_strip_the_length_dot_and_the_doubt_mark
    # csd writes vowel length as a raised dot and doubt as "(?)" INSIDE the
    # form ("*sitó• (?)"); neither is typeable at the define prompt, so the
    # fold key drops them while the headword keeps upstream's spelling.
    set = entry(read("csd", language: "sio"), "2")
    assert_equal "*sitó• (?)", set.headword
    assert_equal Nabu::Normalize.search_form("sitó", language: "sio"), set.headword_folded
    tutelo = set.reflexes.find { |r| r.lang_code == "csd-tu" }
    assert_equal Nabu::Normalize.search_form("šitóre", language: nil), tutelo.word_folded
  end

  def test_folds_are_the_house_search_forms_with_the_member_hyphen_strip
    set = entry(read("tlopo", language: "poz-oce"), "1-4-2-2-76-POc-burua-a")
    assert_equal Nabu::Normalize.search_form("buruŋ", language: "poz-oce"), set.headword_folded
    set.reflexes.each do |reflex|
      expected = Nabu::Normalize.search_form(reflex.word.delete("()").sub(/-\z/, ""),
                                             language: reflex.language || "poz-oce")
      assert_equal expected, reflex.word_folded
    end
  end
end
