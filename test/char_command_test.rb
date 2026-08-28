# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu char 棄` (P37-4): the character card — the join across held shelves,
# matching Jisho synchronically where a shelf backs the glyph and exceeding
# it diachronically, with the "absent, never —" rule. Builds a catalog from
# the CJK fixtures (Unihan + BabelStone IDS + KRADFILE + TLS + a seeded
# corpus passage) and asserts the rendered sections.
class CharCommandTest < Minitest::Test
  # P72-2 (Edubba FR-2): the Han card's frozen --json contract — the
  # payload mirrors the Card shape one-to-one, so the fields Edubba
  # consumes (strokes, radical, IDS+parts, variants, readings, OC/MC,
  # TLS, desk refs, per-corpus attestation) ride as data, not prose.
  def test_char_json_emits_the_frozen_han_contract
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 棄 --json]) }
      assert_nil status
      payload = JSON.parse(out)
      assert_equal "棄", payload["glyph"]
      card = payload.fetch("card")
      assert_equal 12, card["total_strokes"]
      assert_equal 75, card.dig("radical", "number")
      assert_equal "木", card.dig("radical", "glyph")
      assert_equal "⿳亠厶⿻廿木", card.fetch("ids").first.fetch("sequence"),
                   "IDS decompositions ride as a per-source list"
      assert_includes card["components"], "木"
      assert(card["variants"].any? { |v| v["relation"] == "simplified" && v["glyph"] == "弃" })
      assert_includes card["readings_sinoxenic"], %w[Mandarin qì],
                      "sinoxenic readings are [stratum, reading] pairs"
      assert card.key?("old_chinese")
      assert card.key?("tls")
      assert_equal 1, card.dig("corpus", "lzh"),
                   "per-language corpus attestation rides as data"
      assert_equal [["kanripo", "lzh", 1]], card["corpus_by_source"],
                   "the P72-5 per-source split rides beside it"
    end
  end

  # P78-6 (the korean-desk census revisit): the hangul-script Korean
  # stratum rides beside the romanized kKorean layer on the card. 棄
  # carries no kHangul upstream, so the whole-card test above stays an
  # honest-absence witness; 一 carries both.
  def test_char_carries_the_hangul_stratum_after_the_census_revisit
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 一 --json]) }
      assert_nil status
      readings = JSON.parse(out).dig("card", "readings_sinoxenic")
      assert_includes readings, %w[Korean IL]
      assert_includes readings, ["Korean (hangul)", "일:0E"]
    end
  end

  def test_char_of_the_acceptance_glyph_renders_the_whole_card
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 棄]) }
      assert_nil status

      # header — Unihan kTotalStrokes + kRSUnicode → radical 75 木 tree
      assert_match(/棄\s+U\+68C4.*12 strokes.*radical 75 木 tree/, out)
      # decomposition — BabelStone IDS + the printed follow-up "click"
      assert_match(/decomposition \(BabelStone IDS\):/, out)
      assert_match(/⿳亠厶⿻廿木/, out)
      assert_match(/木 — nabu char 木 · nabu search --char-component 木/, out)
      # components — KRADFILE flat index
      assert_match(/components \(KRADFILE index\): 一 木 亠 凵 厶/, out)
      # variants — Unihan trad→simp
      assert_match(/simplified: 弃 \(U\+5F03\)/, out)
      # sinoxenic readings — Unihan
      assert_match(/Mandarin: qì/, out)
      assert_match(/Korean: KI/, out)
      assert_match(/Vietnamese: khí/, out)
      # the diachronic column — TLS senses + attestation counts
      assert_match(/TLS \(Thesaurus Linguae Sericae\):/, out)
      assert_match(/attestation/, out)
      # corpus attestation from the seeded passage
      assert_match(/corpus attestation: lzh 1/, out)
      # search affordances
      assert_match(/search: nabu search 棄.*--char-component 棄.*--radical 75/, out)
    end
  end

  def test_absent_fields_are_omitted_not_dashed
    with_char_catalog do |config|
      out, = with_config(config) { run_cli(%w[char 棄]) }
      # kanjidic2 / baxter-sagart / tshet-uinh / hdic do not back 棄 in the
      # fixture rig — those sections are absent, never rendered "—".
      refute_match(/—$/, out, "no bare em-dash placeholder anywhere")
      refute_match(/readings \(ja, KANJIDIC2\)/, out, "ja readings absent (kanjidic2 lacks 棄)")
      refute_match(/Old Chinese/, out, "OC absent (baxter-sagart lacks 棄)")
    end
  end

  def test_char_notes_the_japanese_reform_cross_reference_and_covers_jpn_corpus
    with_char_catalog do |config|
      # 國 is a kyūjitai — the card names its shinjitai 国, and the corpus
      # column now carries the jpn holding.
      out, = with_config(config) { run_cli(%w[char 國]) }
      assert_match(/shinjitai \(Japanese new form\): 国 \(U\+56FD\)/, out)
      assert_match(/corpus attestation:.*jpn 1/, out)

      # and the reverse: 国 names its kyūjitai 國 (the hani-fold display precedent).
      back, = with_config(config) { run_cli(%w[char 国]) }
      assert_match(/kyūjitai \(Japanese old form\): 國 \(U\+570B\)/, back)
      # The corpus panel folds both sides (P65: postings live over
      # text_normalized, where 国→國 ran) — the simplified card still
      # attests through its folded form.
      assert_match(/corpus attestation:.*jpn 1/, back)
    end
  end

  def test_char_of_a_non_reform_glyph_has_no_jpn_cross_reference_and_zero_jpn_is_graceful
    with_char_catalog do |config|
      out, = with_config(config) { run_cli(%w[char 棄]) }
      refute_match(/shinjitai|kyūjitai/, out, "棄 is not a reform pair — no jpn cross-reference")
      # 棄 has no jpn attestation in the fixture: the column shows lzh only,
      # never an empty/placeholder jpn entry.
      assert_match(/corpus attestation: lzh 1/, out)
      refute_match(/jpn/, out)
    end
  end

  def test_an_unindexed_box_says_the_corpus_panel_needs_the_index
    with_char_catalog do |config|
      FileUtils.rm_f(config.fulltext_path)
      out, = with_config(config) { run_cli(%w[char 棄]) }
      assert_match(/corpus attestation: not indexed yet/, out,
                   "no char-postings index → an honest hint, NEVER a 180-second scan")
      refute_match(/corpus attestation: lzh/, out)
    end
  end

  # --- the reduced non-Han card (P84-5, the Q46 mechanical half) ---

  # The 2026-08-26 defect: a single non-Han char rode the FULL Han card
  # path, whose define pipeline's Sanskrit stem expansion turned "a" into
  # "as" and matched the TLS concept headword "AS" — nonsense rendered
  # with a straight face. A non-Han glyph now gets a reduced honest card:
  # glyph, codepoint, script probe, search hint — never a define call.
  # (The Latin-letter reading-lane question is №R-44's — single Latin
  # stays on the reduced card for now.)
  def test_char_of_a_latin_letter_renders_the_reduced_card_never_tls
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char a]) }
      assert_nil status
      assert_match(/a\s+U\+0061\s+·\s+Latin/, out)
      assert_match(/a is a Latin letter — the char card's shelf lanes cover Han characters; /, out)
      assert_match(/no CJK shelf claims it/, out)
      assert_match(/search: nabu search a/, out)
      refute_match(/TLS|Thesaurus/, out, "the define pipeline never runs for a non-Han glyph")
      refute_match(/decomposition|radical|Mandarin/, out, "no CJK sections on the reduced card")
    end
  end

  def test_char_of_a_hangul_syllable_renders_the_reduced_card
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 입]) }
      assert_nil status
      assert_match(/입\s+U\+C785\s+·\s+Hangul/, out)
      assert_match(/입 is a Hangul syllable — the char card's shelf lanes cover Han characters; /, out)
      assert_match(/no CJK shelf claims it/, out)
    end
  end

  # The reduced card's --json: the Han payload shape stays stable
  # ({glyph, card}); non-Han is additive — card stays null (no Han card
  # exists) and the reduced identity rides its own key.
  def test_reduced_card_json_is_additive_beside_the_frozen_han_contract
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 입 --json]) }
      assert_nil status
      payload = JSON.parse(out)
      assert_equal "입", payload["glyph"]
      assert_nil payload["card"]
      assert_equal "Hangul", payload.dig("reduced", "script")
      assert_equal "U+C785", payload.dig("reduced", "codepoint")
    end
  end

  # --- the universal card (P85-B2): the UCD identity floor, when synced -----

  def test_universal_card_names_a_greek_letter_when_ucd_is_synced
    with_char_catalog do |config|
      seed_ucd(config)
      out, _err, status = with_config(config) { run_cli(%w[char α]) }
      assert_nil status
      assert_match(/α\s+U\+03B1\s+·\s+Greek/, out)
      assert_match(/GREEK SMALL LETTER ALPHA — Lowercase Letter/, out)
      refute_match(/not a Han character|no CJK shelf claims it/, out, "the universal card replaces the apology")
      assert_match(/search: nabu search α/, out)
    end
  end

  def test_universal_card_spells_out_a_decomposition
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char À]) }
      assert_match(/LATIN CAPITAL LETTER A WITH GRAVE — Uppercase Letter/, out)
      assert_match(/decomposes: A \(U\+0041 LATIN CAPITAL LETTER A\) \+ .*\(U\+0300 COMBINING GRAVE ACCENT\)/, out)
    end
  end

  def test_universal_card_shows_a_numeric_value_and_a_derived_hangul_name
    with_char_catalog do |config|
      seed_ucd(config)
      half, = with_config(config) { run_cli(%w[char ½]) }
      assert_match(/VULGAR FRACTION ONE HALF — Other Number/, half)
      assert_match(%r{numeric value: 1/2}, half)
      assert_match(/decomposes \(fraction\):/, half)

      hangul, = with_config(config) { run_cli(%w[char 입]) }
      assert_match(/HANGUL SYLLABLE IB — Other Letter/, hangul)
      assert_match(/reading: ib — Revised Romanization, letter-wise/, hangul,
                   "the head syllable states its romanization (owner request 2026-08-28)")
      assert_match(%r{decomposes \(jamo\): ᄋ \(U\+110B\) \+ ᅵ \(U\+1175 I /i/\) \+ ᆸ \(U\+11B8 B /p̚/\)},
                   hangul, "the B4 hangul fix + per-jamo IPA")

      jamo, = with_config(config) { run_cli(%w[char ᆸ]) }
      assert_match(/reading: b \(RR\) · IPA \[p̚\] — final/, jamo)
      ieung, = with_config(config) { run_cli(%w[char ᄋ]) }
      assert_match(/reading: silent — the silent initial ieung/, ieung)
    end
  end

  def test_universal_card_json_is_additive_beside_the_frozen_han_contract
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char α --json]) }
      payload = JSON.parse(out)
      assert_nil payload["card"], "no Han card exists for a Greek letter"
      assert_equal "GREEK SMALL LETTER ALPHA", payload.dig("universal", "name")
      assert_equal "Lowercase Letter", payload.dig("universal", "category")
      assert_equal "Greek", payload.dig("universal", "script")
    end
  end

  # --- the member-context tier (P86-1, №R-49a) ------------------------------

  def test_universal_card_carries_block_script_and_age
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char ᚠ]) }
      assert_match(/RUNIC LETTER FEHU FEOH FE F — Other Letter/, out)
      assert_match(/block: Runic \(U\+16A0–U\+16FF\)/, out)
      assert_match(/script: Runic \(Runr\)/, out)
      assert_match(/in Unicode since 3\.0/, out)
    end
  end

  def test_universal_card_renders_chart_annotations_and_formal_aliases
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char א]) }
      assert_match(/charts: = aleph/, out)
      assert_match(/see also: U\+2135 alef symbol/, out)
    end
  end

  def test_universal_card_without_member_files_stays_the_p85_floor
    with_char_catalog do |config|
      seed_ucd(config, members: false)
      out, = with_config(config) { run_cli(%w[char ᚠ]) }
      assert_match(/RUNIC LETTER FEHU FEOH FE F — Other Letter/, out)
      refute_match(/block:/, out, "absent member → absent line, never a guess")
      refute_match(/in Unicode since/, out)
    end
  end

  # --- the ambiguity layer (P86-5 + Q50) ------------------------------------

  def test_single_kana_gets_its_identity_card_with_a_capped_reading_panel
    with_char_catalog do |config|
      seed_ucd(config)
      out, _err, status = with_config(config) { run_cli(%w[char ア]) }
      assert_nil status
      assert_match(/KATAKANA LETTER A — Other Letter/, out, "Q50: the identity card renders FIRST")
      assert_match(/also a Japanese reading — 2 Han character/, out)
      assert_match(/亜 ア \(on\)/, out)
      refute_match(/not a Han character/, out)
    end
  end

  def test_as_reading_keeps_the_pure_reading_query
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char ア --as reading]) }
      assert_match(/2 Han character\(s\) carry this reading/, out)
      assert_match(/亜 ア \(on\)/, out)
      refute_match(/KATAKANA LETTER A/, out, "--as reading narrows to the reading lens")
    end
  end

  def test_latin_letter_card_shows_the_confusables_looks_like_panel
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char a]) }
      assert_match(/LATIN SMALL LETTER A — Lowercase Letter/, out)
      assert_match(/looks like:/, out)
      assert_match(/U\+FF41/, out, "the fullwidth confusable rides the panel")
    end
  end

  def test_as_identity_renders_the_universal_card_for_a_han_char
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char 木 --as identity]) }
      assert_match(/CJK UNIFIED IDEOGRAPH-6728/, out, "the range-derived identity, no Han card")
      refute_match(/kun|on\b|pinyin/, out, "--as identity narrows to pure identity")
    end
  end

  def test_universal_card_renders_the_letter_numeral_conventions
    with_char_catalog do |config|
      seed_ucd(config)
      alpha, = with_config(config) { run_cli(%w[char α]) }
      assert_match(/numeric \(isopsephy\): 1 — Greek alphabetic/, alpha)
      alef, = with_config(config) { run_cli(%w[char א]) }
      assert_match(/numeric \(gematria\): 1 — Hebrew letter values/, alef)
    end
  end

  def test_universal_card_composes_the_curated_script_dossier
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char ᚠ]) }
      assert_match(/script context: The Germanic angular alphabets/, out)
      assert_match(/desk: The runic shelf \(Rundata\)/, out)
    end
  end

  # Owner defect 2026-08-28 ("none of these Han readings actually CONTAIN
  # a"): the okurigana-STEM match (一 ひと.つ answering ひと — wanted) also
  # fired for single-kana queries, claiming every kun reading that merely
  # STARTS with the kana (`char a` → 153 okurigana stems sold as "carries
  # this reading"). A single kana now matches FULL readings only.
  def test_a_single_kana_matches_full_readings_never_okurigana_stems
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char つ]) }
      refute_match(/つ\.ぐ/, out, "亜's つ.ぐ stem must NOT answer the single kana つ")
      refute_match(/also a Japanese reading/, out, "no full reading つ exists in the rig")

      multi, = with_config(config) { run_cli(%w[char ひと]) }
      assert_match(/一 ひと\.つ/, multi, "multi-kana keeps the stem semantics — ひと.つ answers ひと")
    end
  end

  def test_universal_card_corpus_panel_is_era_honest
    with_char_catalog do |config|
      seed_ucd(config)
      out, = with_config(config) { run_cli(%w[char α]) }
      assert_match(/corpus attestation: no live passage carries it/, out,
                   "a current-class index answers a real zero, never a silent nothing")

      kana, = with_config(config) { run_cli(%w[char と]) }
      assert_match(/corpus attestation: jpn 1/, kana,
                   "B3: the widened postings attest the rig's jpn kana — Q50's own char")
    end
  end

  # Copy the trimmed real UCD fixtures into the instance's canonical tree, so
  # `nabu char` finds the identity floor and (by default) the member-context
  # tier, as after `nabu sync ucd`. members: false seeds the bare P85 floor.
  def seed_ucd(config, members: true)
    dir = File.join(config.canonical_dir, "ucd")
    FileUtils.mkdir_p(dir)
    fixture_dir = File.expand_path("fixtures/ucd", __dir__)
    if members
      FileUtils.cp_r(Dir[File.join(fixture_dir, "*.txt")], dir)
      FileUtils.mkdir_p(File.join(dir, "security"))
      FileUtils.mv(File.join(dir, "confusables.txt"),
                   File.join(dir, "security", "confusables.txt"))
    else
      FileUtils.cp(File.join(fixture_dir, "UnicodeData.txt"), File.join(dir, "UnicodeData.txt"))
    end
    Nabu::Ucd.reset!
  end

  # --- the empty-Han-card hint distinguishes held from missing (P84-5) ---

  # The rig holds unihan/edrdg/babelstone-ids/kradfile/tls — an unknown Han
  # glyph must name THOSE as held-but-silent and point the sync at the
  # actually-missing shelves, not claim nothing is held.
  def test_empty_han_card_names_held_shelves_apart_from_missing_ones
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char 玤]) }
      assert_nil status
      assert_match(
        /the held CJK shelves \(unihan, edrdg, babelstone-ids, kradfile, tls\) don't carry 玤/,
        out
      )
      assert_match(/sync the missing CJK shelves \(baxter-sagart, tshet-uinh, hdic\)/, out)
      refute_match(/no held shelf carries/, out)
    end
  end

  def test_empty_han_card_with_no_cjk_shelf_held_says_sync_them_all
    Dir.mktmpdir("nabu-char-bare") do |root|
      config = char_config(root)
      db, fulltext = open_dbs(config)
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      fulltext.disconnect
      db.disconnect
      out, _err, status = with_config(config) { run_cli(%w[char 玤]) }
      assert_nil status
      assert_match(
        /no held shelf carries 玤 yet — sync the CJK shelves \(unihan, edrdg, babelstone-ids, /,
        out
      )
      assert_match(/kradfile, baxter-sagart, tshet-uinh, hdic, tls\)/, out)
      refute_match(/held CJK shelves/, out)
    end
  end

  def test_bare_char_errors_helpfully
    with_char_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[char]) }
      assert_equal 1, status
      assert_match(/give a character/, err)
    end
  end

  def test_multi_char_input_errors_naming_the_single_char_grain
    with_char_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[char 棄権]) }
      assert_equal 1, status
      assert_match(/single character/, err)
      assert_match(/--char-component 棄/, err, "points at the containment search instead")
    end
  end

  # --- the reading→character lane (P65 gate feedback: `nabu char wen`) ---

  # P77-r15 (№R-33 PKG-1): the reading lane joins the frozen --json
  # family — it was the LAST char lane that refused JSON. Contract:
  # input echoed, matches as flat {glyph, reading, kind} maps.
  def test_reading_lane_json_emits_the_frozen_contract
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char qi --json]) }
      assert_nil status
      payload = JSON.parse(out)
      assert_equal "qi", payload["input"]
      match = payload.fetch("matches").find { |m| m["glyph"] == "棄" }
      refute_nil match, "the qì character rides the matches list"
      assert_equal "qì", match["reading"]
      assert_equal "pinyin", match["kind"]
    end
  end

  def test_pinyin_input_toneless_or_toned_lists_the_characters
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char qi]) }
      assert_nil status
      assert_match(/棄 qì/, out, "toneless pinyin folds against kMandarin")
      ya, = with_config(config) { run_cli(%w[char ya]) }
      %w[亚 亜 亞].each { |glyph| assert_match(/#{glyph} yà/, ya, "ya reaches every yà character") }
      toned, = with_config(config) { run_cli(%w[char qì]) }
      assert_match(/棄 qì/, toned, "toned input matches exactly")
    end
  end

  def test_kana_input_resolves_on_and_kun_readings
    with_char_catalog do |config|
      on, = with_config(config) { run_cli(%w[char タイ]) }
      assert_match(/体 タイ/, on)
      assert_match(/體 タイ/, on)
      hira, = with_config(config) { run_cli(%w[char あ]) }
      assert_match(/亜 ア/, hira, "hiragana input matches katakana on readings")
      kun, = with_config(config) { run_cli(%w[char ひと]) }
      assert_match(/人 ひと/, kun, "the exact kun reading")
      assert_match(/一 ひと/, kun, "the ひと.つ stem and the ひと- notation both answer")
    end
  end

  def test_romaji_readings_caps_are_on_and_lowercase_is_kun
    with_char_catalog do |config|
      on, = with_config(config) { run_cli(%w[char TAI]) }
      assert_match(/体 タイ \(on\)/, on, "CAPS romaji = on'yomi (the dictionary convention)")
      assert_match(/體 タイ \(on\)/, on)
      refute_match(/たい\.らか/, on, "CAPS never answers kun")
      kun, = with_config(config) { run_cli(%w[char hito]) }
      assert_match(/人 ひと \(kun\)/, kun, "lowercase romaji reaches kun readings")
      assert_match(/一 ひと\.つ \(kun\)/, kun)
    end
  end

  def test_an_unmatched_reading_says_so_plainly
    with_char_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[char zzz]) }
      assert_nil status
      assert_match(/resolved neither/, out)
    end
  end

  # --- the structure-search modes (search --radical/--strokes/--char-component) ---

  def test_radical_filter_finds_passages_carrying_a_radical_75_character
    with_search_catalog do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --radical 75]) }
      assert_nil status
      assert_match(/urn:nabu:test:qi.*棄/m, out, "the 棄 passage (radical 75 木)")
      refute_match(/urn:nabu:test:tian/, out, "天 is radical 37, excluded")
      assert_match(/character filter: \[radical 75\]/, out, "the footer names the filter distinctly")
    end
  end

  def test_strokes_range_filter
    with_search_catalog do |config|
      out, = with_config(config) { run_cli(%w[search --strokes 1-4]) }
      assert_match(/urn:nabu:test:tian/, out, "天(4)/一(1)/人(2) are in range")
      refute_match(/urn:nabu:test:qi\b/, out, "棄(12) is out of range")
      assert_match(/character filter: \[1-4 strokes\]/, out)
    end
  end

  def test_char_component_union_transitive_containment
    with_search_catalog do |config|
      out, = with_config(config) { run_cli(%w[search --char-component 木]) }
      # 棄 (KRADFILE lists 木; IDS ⿻廿木) and 林 (⿰木木) both contain 木.
      assert_match(/urn:nabu:test:qi\b/, out)
      assert_match(/urn:nabu:test:lin/, out)
      refute_match(/urn:nabu:test:tian/, out, "天 contains no 木")
      assert_match(/character filter: \[contains 木\]/, out)
    end
  end

  def test_char_filters_and_together
    with_search_catalog do |config|
      # radical 75 = {棄}; strokes 1 = {一}; the intersection is empty → an
      # honest zero-character resolution, not a silent empty page.
      out, = with_config(config) { run_cli(%w[search --radical 75 --strokes 1]) }
      assert_match(/no characters match \[radical 75 AND 1 strokes\]/, out)
    end
  end

  def test_char_filter_composes_with_a_text_query
    with_search_catalog do |config|
      # The FTS token for a Han run is the whole run (unicode61); the exact
      # run is the searchable form. The char filter then ANDs on top.
      out, = with_config(config) { run_cli(%w[search 林木森森 --char-component 木]) }
      assert_match(/urn:nabu:test:lin/, out, "林木森森 matches the text query AND contains 木")
      refute_match(/urn:nabu:test:qi\b/, out, "棄 contains 木 but does not match the text query")
      assert_match(/text query "林木森森"/, out)
    end
  end

  def test_char_filters_reject_word_level_combination
    with_search_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --radical 75 --lemma foo]) }
      assert_equal 1, status
      assert_match(/character-level structure search/, err)
    end
  end

  def test_radical_out_of_range_errors
    with_search_catalog do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --radical 999]) }
      assert_equal 1, status
      assert_match(/KangXi radical number 1-214/, err)
    end
  end

  private

  def with_search_catalog
    Dir.mktmpdir("nabu-char-search") do |root|
      config = char_config(root)
      db, fulltext = open_dbs(config)
      load_dictionary(db, "unihan", "Nabu::Adapters::Unihan", Nabu::Adapters::Unihan.new, "unihan")
      load_dictionary(db, "babelstone-ids", "Nabu::Adapters::BabelstoneIds",
                      Nabu::Adapters::BabelstoneIds.new, "babelstone-ids")
      load_dictionary(db, "kradfile", "Nabu::Adapters::Kradfile", Nabu::Adapters::Kradfile.new, "kradfile")
      source = Nabu::Store::Source.create(
        slug: "test", name: "test", adapter_class: "Nabu::Adapters::Kanripo", license_class: "open"
      )
      { "qi" => "棄而違之。", "lin" => "林木森森。", "tian" => "天下一人。" }.each do |slug, text|
        seed_passage(source, slug, text)
      end
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      db.disconnect
      fulltext.disconnect
      yield config
    end
  end

  def seed_passage(source, slug, text)
    document = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:test:#{slug}", title: slug, language: "lzh",
      content_sha256: slug, revision: 1, withdrawn: false
    )
    Nabu::Store::Passage.create(
      document_id: document.id, urn: "urn:nabu:test:#{slug}:1", sequence: 0,
      language: "lzh", text: text, text_normalized: text, content_sha256: slug, revision: 1
    )
  end

  def char_config(root)
    config = Nabu::Config.new(
      canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
      sources_path: File.join(root, "sources.yml"), config_path: "(test)"
    )
    FileUtils.mkdir_p(config.db_dir)
    config
  end

  def open_dbs(config)
    db = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(db)
    Nabu::Store.setup!(db)
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    [db, fulltext]
  end

  def with_char_catalog
    Dir.mktmpdir("nabu-char") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)

      load_dictionary(db, "unihan", "Nabu::Adapters::Unihan", Nabu::Adapters::Unihan.new, "unihan")
      load_dictionary(db, "babelstone-ids", "Nabu::Adapters::BabelstoneIds",
                      Nabu::Adapters::BabelstoneIds.new, "babelstone-ids")
      load_dictionary(db, "kradfile", "Nabu::Adapters::Kradfile", Nabu::Adapters::Kradfile.new, "kradfile")
      load_dictionary(db, "tls", "Nabu::Adapters::Tls", Nabu::Adapters::Tls.new, "tls")
      # kanjidic2 (via the edrdg fixture) — the P65 reading lane's on/kun
      # side; its sample carries none of 棄/國/国, so every absence
      # assertion above still holds.
      load_dictionary(db, "edrdg", "Nabu::Adapters::Edrdg", Nabu::Adapters::Edrdg.new, "edrdg")

      kanripo = Nabu::Store::Source.create(
        slug: "kanripo", name: "Kanseki Repository", adapter_class: "Nabu::Adapters::Kanripo",
        license_class: "attribution"
      )
      document = Nabu::Store::Document.create(
        source_id: kanripo.id, urn: "urn:nabu:kanripo:KR1h0004", title: "論語", language: "lzh",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "urn:nabu:kanripo:KR1h0004:005:22a", sequence: 0,
        language: "lzh", text: "棄而違之。", text_normalized: "棄而違之。", content_sha256: "x", revision: 1
      )
      # A jpn holding carrying both reform spellings — so the card's corpus
      # column covers jpn (P38-4) and both 國 and 国 attest.
      aozora = Nabu::Store::Source.create(
        slug: "aozora", name: "Aozora Bunko", adapter_class: "Nabu::Adapters::Aozora",
        license_class: "open"
      )
      jpn_doc = Nabu::Store::Document.create(
        source_id: aozora.id, urn: "urn:nabu:aozora:000001", title: "見本", language: "jpn",
        content_sha256: "y", revision: 1, withdrawn: false
      )
      Nabu::Store::Passage.create(
        document_id: jpn_doc.id, urn: "urn:nabu:aozora:000001:1", sequence: 0,
        language: "jpn", text: "國語と国語。", text_normalized: "國語と國語。", content_sha256: "y", revision: 1
      )
      # P65: the corpus panel reads the precompiled char-postings index (the
      # desk never scans passages) — build the derived index like the live
      # box does.
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      fulltext.disconnect
      db.disconnect
      yield config
    end
  end

  def load_dictionary(db, slug, adapter_class, adapter, fixture)
    source = Nabu::Store::Source.create(
      slug: slug, name: slug, adapter_class: adapter_class, license_class: "open"
    )
    Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                 .load_from(adapter, workdir: Nabu::TestSupport.fixtures(fixture))
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
