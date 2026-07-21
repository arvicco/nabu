# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Display (P27-0): the display-time policy module. Everything here is
# render-only — the canonical store, the search index, and MCP never see it.
#
# The fixture lines are REAL stored-passage bytes, produced by the shipping
# parsers over the checked-in fixtures (OSHB Gen/Ruth, TOROT zogr, DCS
# conllu) — the byte pins below were computed from those parses, so a parser
# change that shifts the stored bytes will fail these pins honestly.
class DisplayTest < Minitest::Test
  # OSHB Gen 1:1 exactly as OshbOsisParser stores it (hbo, NFC-exempt,
  # byte-verbatim): cantillation ×6 (U+0591/0596/05A3/05A5), points incl.
  # meteg U+05BD, sof pasuq U+05C3.
  GEN_1_1 = "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃"
  # The same verse with the cantillation class (U+0591–05AF) removed and
  # NOTHING else: points, meteg, shin dot, sof pasuq all intact.
  GEN_1_1_NO_CANTILLATION = "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָֽרֶץ׃"
  # Consonantal: cantillation + points (incl. meteg, shin/sin dots) gone;
  # sof pasuq (punctuation, unclassified) stays.
  GEN_1_1_CONSONANTAL = "בראשית ברא אלהים את השמים ואת הארץ׃"

  # OSHB Gen 1:2 — carries maqaf (עַל־פְּנֵי ×2).
  GEN_1_2 = "וְהָאָ֗רֶץ הָיְתָ֥ה תֹ֨הוּ֙ וָבֹ֔הוּ וְחֹ֖שֶׁךְ עַל־פְּנֵ֣י תְה֑וֹם " \
            "וְר֣וּחַ אֱלֹהִ֔ים מְרַחֶ֖פֶת עַל־פְּנֵ֥י הַמָּֽיִם׃"

  # TOROT zogr sentence 75108 (chu): titlo U+0483 ×2 (дх҃омь ст҃ъꙇмь) and
  # palatalization U+0484 ×1 (огн҄емь) — the titla class strips ONLY the
  # titlo; palatalization is not a titlo and stays.
  ZOGR = "тъ васъ крьститъ дх҃омь ст҃ъꙇмь ꙇ огн҄емь·"
  ZOGR_NO_TITLA = "тъ васъ крьститъ дхомь стъꙇмь ꙇ огн҄емь·"

  # DCS Aitareyopaniṣad 1.1 sentence 1 (san, IAST romanization): the DCS shelf
  # carries NO Devanagari and no Vedic accents — the vedic-accents policy must
  # be a byte no-op on it.
  DCS_IAST = "ātmā vai idam ekaḥ eva agre āsīt na anyat kiṃcana miṣat"

  RLI = "⁧"
  PDI = "⁩"

  def policies
    @policies ||= Nabu::Display.load_policies(File.join(Nabu::Config::PROJECT_ROOT, "config", "display.yml"))
  end

  def render(text, language, mode: "default")
    Nabu::Display.render(text, language: language, mode: Nabu::Display.mode(mode), policies: policies)
  end

  def unwrap(text)
    text.delete(RLI + PDI)
  end

  # -- mark-class stripping on real fixture lines (before/after byte pins) --

  def test_default_mode_strips_hebrew_cantillation_only
    rendered = render(GEN_1_1, "hbo")
    assert_equal GEN_1_1_NO_CANTILLATION, unwrap(rendered.text)
    assert_includes rendered.applied, "cantillation"
  end

  def test_default_mode_keeps_points_meteg_and_maqaf
    rendered = render(GEN_1_2, "hbo")
    text = unwrap(rendered.text)
    assert_includes text, "־", "maqaf is in the keep list — default mode must not touch it"
    assert_includes unwrap(render(GEN_1_1, "hbo").text), "ֽ",
                    "meteg (HEBREW POINT METEG) is a point — kept by default"
    assert_includes text, "ְ", "points survive default mode"
  end

  def test_plain_mode_yields_consonantal_hebrew
    rendered = render(GEN_1_1, "hbo", mode: "plain")
    assert_equal GEN_1_1_CONSONANTAL, unwrap(rendered.text)
    assert_includes rendered.applied, "points"
  end

  def test_plain_mode_replaces_maqaf_with_a_space_never_fusing_words
    rendered = render(GEN_1_2, "hbo", mode: "plain")
    text = unwrap(rendered.text)
    refute_includes text, "־"
    assert_includes text, "על פני", "maqaf-joined words must stay two words"
  end

  def test_full_mode_is_byte_identical_everywhere
    [[GEN_1_1, "hbo"], [GEN_1_2, "hbo"], [ZOGR, "chu"], [DCS_IAST, "san"]].each do |text, lang|
      rendered = render(text, lang, mode: "full")
      assert_equal text, rendered.text, "--display full must be the byte-honest escape hatch (#{lang})"
      assert_empty rendered.applied
    end
  end

  def test_default_mode_strips_titla_but_not_palatalization
    rendered = render(ZOGR, "chu")
    assert_equal ZOGR_NO_TITLA, rendered.text
    assert_includes rendered.applied, "titla"
    assert_includes rendered.text, "҄", "U+0484 palatalization is not a titlo"
  end

  def test_vedic_accent_policy_is_a_byte_noop_on_the_iast_shelf
    rendered = render(DCS_IAST, "san")
    assert_equal DCS_IAST, rendered.text
    assert_empty rendered.applied, "nothing stripped → nothing to hint"
  end

  def test_vedic_accent_class_strips_udatta_and_anudatta_codepoints
    # Mechanics pin for the class set {U+0951, U+0952}: no fixture carries
    # them (DCS is IAST, SARIT's fixtures are unaccented) — censused 0 —
    # so this minimal Devanagari string exercises the machinery only.
    rendered = render("अ॑ग्नि॒", "san-Deva")
    assert_equal "अग्नि", rendered.text
    assert_includes rendered.applied, "vedic-accents"
  end

  def test_language_with_no_policy_passes_through
    text = "μῆνιν ἄειδε θεὰ"
    rendered = render(text, "grc")
    assert_equal text, rendered.text
    assert_empty rendered.applied
  end

  def test_hebrew_stripping_never_normalizes_the_exempt_bytes
    # hbo is NFC-exempt (P26-3): stripping must delete codepoints in place,
    # never round-trip through NFD/NFC (which would reorder Masoretic marks).
    # Dagesh (ccc 21) before vowel (ccc 10–19) is NOT NFC-stable; the
    # non-cantillation part of the sequence must come back byte-identical.
    text = "בְּ֑" # bet + dagesh + sheva + etnahta
    rendered = render(text, "hbo")
    assert_equal "בְּ", unwrap(rendered.text)
  end

  def test_stripping_is_grapheme_safe_over_nfc_text
    # chu strips run NFD→strip→NFC; a precomposed neighbor (й U+0439) must
    # come back precomposed, and the titlo must not orphan its base.
    rendered = render("й дх҃омь", "chu")
    assert_equal "й дхомь", rendered.text
  end

  # -- isolates ------------------------------------------------------------

  def test_hbo_runs_are_wrapped_in_rtl_isolates
    rendered = render(GEN_1_1, "hbo")
    assert rendered.text.start_with?(RLI), "hbo policy sets isolates: true"
    assert rendered.text.end_with?(PDI)
    assert_includes rendered.applied, Nabu::Display::ISOLATES
  end

  def test_full_mode_never_wraps_isolates
    rendered = render(GEN_1_1, "hbo", mode: "full")
    refute_includes rendered.text, RLI
  end

  def test_chu_policy_has_no_isolates
    refute_includes render(ZOGR, "chu").text, RLI
  end

  # -- East-Asian display width (P35-7) — the one column-math seam ----------
  #
  # Real Han from the kanripo fixture (KR1h0004 Lunyu): 其為人也 etc. Fullwidth
  # forms and kana come from the ojp/lzh reality the Sino wave landed.
  LZH_HAN = "其為人也孝弟" # 6 CJK Unified Ideographs (U+4E00–9FFF)
  CJK_PUNCT = "「，」"              # U+300C wide bracket, U+FF0C fullwidth comma, U+300D
  KANA = "あア"                    # hiragana A (U+3042) + katakana A (U+30A2)
  FULLWIDTH_A = "Ａ" # U+FF21 fullwidth latin capital A

  def width(text) = Nabu::Display.width(text)

  def test_width_of_ascii_and_greek_is_one_cell_per_char
    assert_equal 3, width("abc")
    assert_equal 5, width("μῆνιν"), "grc is narrow — precomposed circumflex included"
  end

  def test_width_of_han_ideographs_is_two_cells_each
    assert_equal 12, width(LZH_HAN)
    assert_equal 2, width("人")
  end

  def test_width_of_kana_is_two_cells_each
    assert_equal 4, width(KANA)
  end

  def test_width_of_fullwidth_and_wide_punctuation_is_two_cells
    assert_equal 6, width(CJK_PUNCT), "「 ， 」 each render two cells"
    assert_equal 2, width(FULLWIDTH_A)
  end

  def test_combining_marks_take_the_base_grapheme_width
    assert_equal 1, width("é"), "e + combining acute is one narrow cluster"
    assert_equal 1, width("μ͂"), "mu + combining perispomeni is one narrow cluster"
    assert_equal 2, width("人́"), "a wide base plus a combining mark stays two cells"
  end

  def test_isolates_are_zero_width
    assert_equal 2, width("#{RLI}人#{PDI}"), "RTL isolates U+2066–2069 draw nothing"
    assert_equal 0, width(RLI + PDI)
  end

  def test_ansi_escape_sequences_are_zero_width
    assert_equal 2, width("\e[36m人\e[0m"), "SGR color codes draw nothing"
    assert_equal 3, width("\e[33mabc\e[0m")
  end

  def test_mixed_string_sums_display_cells
    assert_equal 3, width("a人"), "1 + 2"
    assert_equal 5, width("其b，"), "2 + 1 + 2"
    assert_equal 0, width("")
  end

  def test_width_ignores_isolates_on_rendered_hebrew
    rendered = render(GEN_1_1_CONSONANTAL, "hbo", mode: "plain")
    assert_equal GEN_1_1_CONSONANTAL.length, Nabu::Display.width(rendered.text),
                 "consonantal Hebrew is narrow; the isolate wrap adds no cells"
  end

  # -- the mode registry (the sibling-packet seam) -------------------------

  def test_builtin_modes_are_registered
    assert_equal %w[default full plain], Nabu::Display.mode_names.sort & %w[default full plain]
  end

  def test_unknown_mode_is_a_named_error_listing_the_registry
    error = assert_raises(Nabu::Display::UnknownModeError) { Nabu::Display.mode("sideways") }
    assert_match(/sideways/, error.message)
    assert_match(/default/, error.message, "the error must name the valid modes")
  end

  def test_sibling_packets_can_register_a_mode_without_reshaping
    mode = Class.new do
      def name = "upcase-test"

      def description = "test mode"

      def render(text, language:, policy:) # rubocop:disable Lint/UnusedMethodArgument
        Nabu::Display::Rendered.new(text: text.upcase, applied: ["upcase-test"])
      end

      def isolates?(policy) = policy.isolates
    end.new
    Nabu::Display.register_mode(mode) unless Nabu::Display.mode_names.include?("upcase-test")
    rendered = Nabu::Display.render("shalom", language: "hbo", mode: Nabu::Display.mode("upcase-test"),
                                              policies: policies)
    assert_equal "#{RLI}SHALOM#{PDI}", rendered.text
    assert_includes rendered.applied, "upcase-test"
  end

  def test_registering_a_duplicate_mode_name_raises
    error = assert_raises(Nabu::Display::Error) do
      Nabu::Display.register_mode(Nabu::Display.mode("default"))
    end
    assert_match(/default/, error.message)
  end

  # -- config parsing & validation -----------------------------------------

  def test_shipped_config_defines_the_owner_gated_policies
    assert_equal %w[cantillation], policies["hbo"].strip
    assert_equal %w[points maqaf], policies["hbo"].keep
    assert policies["hbo"].isolates
    assert_equal %w[cantillation], policies["arc"].strip
    assert policies["arc"].isolates
    assert_equal %w[vedic-accents], policies["san"].strip
    assert_equal %w[titla], policies["chu"].strip
    refute policies.key?("grc"), "monotonic is definable but never defaulted"
  end

  def test_missing_config_file_means_no_policies
    assert_empty Nabu::Display.load_policies("/nonexistent/display.yml")
  end

  def test_unknown_mark_class_is_a_named_error
    with_yaml("languages:\n  hbo: { strip: [sparkles] }\n") do |path|
      error = assert_raises(Nabu::Display::ConfigError) { Nabu::Display.load_policies(path) }
      assert_match(/sparkles/, error.message)
      assert_match(/cantillation/, error.message, "the error must name the valid classes")
    end
  end

  def test_unknown_language_key_is_a_named_error
    with_yaml("languages:\n  Hebrew!: { strip: [cantillation] }\n") do |path|
      error = assert_raises(Nabu::Display::ConfigError) { Nabu::Display.load_policies(path) }
      assert_match(/Hebrew!/, error.message)
    end
  end

  def test_non_boolean_isolates_is_a_named_error
    with_yaml("languages:\n  hbo: { isolates: sideways }\n") do |path|
      error = assert_raises(Nabu::Display::ConfigError) { Nabu::Display.load_policies(path) }
      assert_match(/isolates/, error.message)
    end
  end

  def test_monotonic_is_a_defined_class_available_to_config
    # Definable but never defaulted: an owner opting in strips breathings,
    # perispomeni, varia, and iota subscript; the acute survives (μῆνιν
    # ἄειδε → μηνιν άειδε). This is a strip, not a polytonic→monotonic
    # conversion — conversion is a display MODE for a later packet.
    with_yaml("languages:\n  grc: { strip: [monotonic] }\n") do |path|
      custom = Nabu::Display.load_policies(path)
      rendered = Nabu::Display.render("μῆνιν ἄειδε", language: "grc", mode: Nabu::Display.mode("default"),
                                                     policies: custom)
      assert_equal "μηνιν άειδε", rendered.text
      assert_includes rendered.applied, "monotonic"
    end
  end

  # -- translit mode (P27-2) -------------------------------------------------

  # Real i-may-010 ogham line (test/fixtures/ogham) and a real GRETIL
  # Mahabharata opening (the deva_test sample).
  OGHAM_LINE = "ᚇᚑᚈᚐᚌᚅᚔ"
  MBH_DEVA = "नारायणं नमस्कृत्य नरं चैव नरोत्तमम् ।"

  def test_translit_is_registered_with_mono
    assert_equal %w[mono translit], Nabu::Display.mode_names.sort & %w[mono translit]
  end

  def test_translit_romanizes_hebrew_sbl_style_without_isolates
    rendered = render(GEN_1_1, "hbo", mode: "translit")
    assert_equal "bəreʾshiyt baraʾ ʾelohiym ʾet hashamayim wəʾet haʾarets.", rendered.text
    assert_includes rendered.applied, "translit"
    refute_includes rendered.text, RLI, "romanized output is LTR — isolates would be wrong"
  end

  def test_translit_transcodes_devanagari_to_iast
    rendered = render(MBH_DEVA, "san-Deva", mode: "translit")
    assert_equal "nārāyaṇaṃ namaskṛtya naraṃ caiva narottamam |", rendered.text
    assert_includes rendered.applied, "translit"
  end

  def test_translit_renders_cyrillic_scholarly_latin_marks_preserved
    rendered = render(ZOGR, "chu", mode: "translit")
    assert_equal "tъ vasъ krьstitъ dx҃omь st҃ъimь i ogn҄emь·", rendered.text,
                 "the transcoder romanizes letters; mark stripping stays default mode's business"
  end

  def test_translit_is_a_noop_on_already_romanized_shelves
    rendered = render(DCS_IAST, "san", mode: "translit")
    assert_equal DCS_IAST, rendered.text
    assert_empty rendered.applied, "nothing changed → nothing to hint"
  end

  def test_translit_passes_untranscoded_languages_through
    text = "μῆνιν ἄειδε"
    with_yaml("languages:\n  grc: { strip: [monotonic] }\n") do |path|
      custom = Nabu::Display.load_policies(path)
      rendered = Nabu::Display.render(text, language: "grc", mode: Nabu::Display.mode("translit"),
                                            policies: custom)
      assert_equal text, rendered.text, "no grc transcoder — pass through, never guess"
      assert_empty rendered.applied
    end
  end

  def test_orv_and_bul_have_policies_so_translit_reaches_them
    assert policies.key?("orv"), "config/display.yml carries orv (empty policy — translit seam)"
    assert policies.key?("bul"), "config/display.yml carries bul (empty policy — translit seam)"
    rendered = render("и оуби", "orv", mode: "translit")
    assert_equal "i ubi", rendered.text
  end

  def test_full_mode_still_byte_identical_with_the_new_modes
    [[GEN_1_1, "hbo"], [ZOGR, "chu"], [MBH_DEVA, "san-Deva"], [OGHAM_LINE, "pgl-Ogam"]].each do |text, lang|
      rendered = render(text, lang, mode: "full")
      assert_equal text, rendered.text
      assert_empty rendered.applied
    end
  end

  # -- mono mode (P27-2): default strips, no colors --------------------------

  def test_mono_strips_like_default
    rendered = render(ZOGR, "chu", mode: "mono")
    assert_equal ZOGR_NO_TITLA, rendered.text
    assert_includes rendered.applied, "titla"
  end

  def test_mode_color_contract
    assert Nabu::Display.mode("default").colors?
    assert Nabu::Display.mode("translit").colors?
    refute Nabu::Display.mode("mono").colors?, "--display mono disables token coloring"
    refute Nabu::Display.mode("full").colors?, "full is the byte-honest escape hatch"
  end

  # -- grapheme spacing (P27-2) ----------------------------------------------

  def test_pgl_spacing_inserts_ogham_space_marks_between_letters
    rendered = render(OGHAM_LINE, "pgl-Ogam")
    # seven letters joined by U+1680 OGHAM SPACE MARK — the script's own
    # stemline-continuing separator, never ASCII space between letters
    assert_equal OGHAM_LINE.chars.join("\u1680"), rendered.text
    assert_includes rendered.applied, "spacing"
  end

  def test_spacing_skips_existing_separators_and_full_mode
    rendered = render("ᚇᚑ ᚈᚐ", "pgl-Ogam")
    assert_equal "ᚇ ᚑ ᚈ ᚐ", rendered.text, "existing spaces never double up"
    assert_equal OGHAM_LINE, render(OGHAM_LINE, "pgl-Ogam", mode: "full").text
  end

  def test_spacing_config_validates_booleans
    with_yaml("languages:\n  pgl: { spacing: sideways }\n") do |path|
      error = assert_raises(Nabu::Display::ConfigError) { Nabu::Display.load_policies(path) }
      assert_match(/spacing/, error.message)
    end
  end

  def test_spacing_in_a_non_ogham_script_uses_plain_spaces
    with_yaml("languages:\n  got: { spacing: true }\n") do |path|
      custom = Nabu::Display.load_policies(path)
      rendered = Nabu::Display.render("𐌲𐌿𐌸", language: "got", mode: Nabu::Display.mode("default"),
                                             policies: custom)
      assert_equal "𐌲 𐌿 𐌸", rendered.text
    end
  end

  # -- per-token language coloring (P27-2) -----------------------------------

  # Real corph shape: sga passage with a code-switched Latin token; the token
  # "lang" contract is the P7-5 tokens annotation (corph/oshb census).
  def test_paint_colors_only_tokens_tagged_with_another_language
    text = "amail rongab grammatica"
    tokens = [
      { "form" => "amail", "lang" => "sga" },
      { "form" => "rongab" }, # untagged — must stay uncolored
      { "form" => "grammatica", "lang" => "lat" }
    ]
    painted, legend = Nabu::Display::TokenColors.paint(text, tokens: tokens, language: "sga")
    assert_includes painted, "\e[36mgrammatica\e[0m", "the lat token wears the first palette color"
    refute_includes painted, "\e[36mamail", "base-language tokens stay uncolored"
    refute_match(/\e\[\d+mrongab/, painted, "untagged tokens stay uncolored — color only what is honestly tagged")
    assert_equal({ "lat" => "cyan" }, legend)
  end

  def test_paint_locates_tokens_sequentially_and_skips_honest_misses
    text = "ab ab"
    tokens = [{ "form" => "ab", "lang" => "lat" }, { "form" => "zz", "lang" => "lat" }]
    painted, = Nabu::Display::TokenColors.paint(text, tokens: tokens, language: "sga")
    assert painted.start_with?("\e[36mab\e[0m"), "first occurrence painted"
    assert painted.end_with?(" ab"), "the unlocatable zz paints nothing — never a fabricated span"
  end

  def test_paint_composes_with_snippet_brackets
    text = "dixit [grammatica] est"
    tokens = [{ "form" => "grammatica", "lang" => "lat" }]
    painted, = Nabu::Display::TokenColors.paint(text, tokens: tokens, language: "sga")
    assert_includes painted, "[\e[36mgrammatica\e[0m]", "existing highlight brackets survive around the color"
  end

  def test_paint_with_no_cross_language_tokens_is_a_noop
    text = "בְּרֵאשִׁית"
    tokens = [{ "form" => "בְּרֵאשִׁית", "lang" => "hbo" }]
    painted, legend = Nabu::Display::TokenColors.paint(text, tokens: tokens, language: "hbo")
    assert_equal text, painted
    assert_empty legend
  end

  def test_color_gate_honors_no_color_and_nabu_color
    with_env("NO_COLOR" => "1", "NABU_COLOR" => nil) do
      refute Nabu::Display.color?(tty: true), "NO_COLOR wins over everything"
    end
    with_env("NO_COLOR" => nil, "NABU_COLOR" => "1") do
      assert Nabu::Display.color?(tty: false), "NABU_COLOR forces color for captured output"
    end
    with_env("NO_COLOR" => nil, "NABU_COLOR" => nil) do
      assert Nabu::Display.color?(tty: true)
      refute Nabu::Display.color?(tty: false), "piped output stays clean by default"
    end
  end

  private

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_yaml(content)
    Dir.mktmpdir("nabu-display") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, content)
      yield path
    end
  end
end

# Edition-level display transforms (P27-1): per-SOURCE convention rules
# (config/display.yml `sources:`) executed by the `reading` mode, with
# `diplomatic` as the byte-honest edition-marks view. Every before/after pin
# below is REAL stored-passage bytes from the shipping parsers over the
# checked-in fixtures (census 2026-07-18, counts in backlog P27-1).
class DisplayEditionTest < Minitest::Test
  # DDbDP bgu.1.102 lines 6-7 (grc): the parse-time Leiden policy already
  # reads through supplied/expan/unclear markerless — the stored surface
  # carries ONLY the "[…]" gap marker (censused ×2 in 32 passages).
  DDBDP_LINE_6 = "καὶ Οὐήρου τῶν κυρίων Σεβαστῶν Ἐπεὶφ η […]"
  DDBDP_LINE_7 = "Αἴλιος […]θως ἐπηκολούθησα ταῖς τοῦ ἀργυρίου"

  # EDH HD000082 lines 1:1-2 (lat): del rend="erasure" kept in ⟦…⟧ (the
  # damnatio-memoriae divergence, censused ×2), gaps "[…]" ×4.
  EDH_ERASED = "Lucius Licinius Luci ⟦filius Crassu⟧s"
  EDH_LOST = "[…] […]"

  # RIIG all-01-01 PLT-a:2 (xtg-Latn): surplus {…} kept from <surplus>
  # (censused ×2); ahp-01-01 HRD-a:1 (xtg-Grek): mid-word gap.
  RIIG_SURPLUS = "nanton{t}icnos"
  RIIG_GAP = "καρε[…]μ"

  # SBLGNT 3John 1:4 and John 1:15 (grc): the upstream apparatus sigla
  # ⸀ (×69) and ⸂…⸃ (×30 pairs) ride the verse text verbatim; John 1:15's
  # parentheses are the edition's own punctuation, never apparatus.
  SBLGNT_WORD = "μειζοτέραν τούτων οὐκ ἔχω ⸀χαράν, ἵνα ἀκούω τὰ ἐμὰ τέκνα ἐν ⸀τῇ ἀληθείᾳ περιπατοῦντα."
  SBLGNT_WORD_READING = "μειζοτέραν τούτων οὐκ ἔχω χαράν, ἵνα ἀκούω τὰ ἐμὰ τέκνα ἐν τῇ ἀληθείᾳ περιπατοῦντα."
  SBLGNT_PHRASE = "(Ἰωάννης μαρτυρεῖ περὶ αὐτοῦ καὶ κέκραγεν λέγων· Οὗτος ἦν ⸂ὃν εἶπον⸃· " \
                  "Ὁ ὀπίσω μου ἐρχόμενος ἔμπροσθέν μου γέγονεν, ὅτι πρῶτός μου ἦν·)"

  # OSHB Ruth 1:8 (hbo, NFC-exempt): the ketiv יעשה rides the verse text;
  # the qere reading attaches to that token as a "qere" word hash. Tokens
  # below are the fixture's REAL token bytes trimmed to the qere-relevant
  # neighborhood (the CLI test exercises the full parsed annotations).
  RUTH_1_8 = "וַתֹּ֤אמֶר נָעֳמִי֙ לִשְׁתֵּ֣י כַלֹּתֶ֔יהָ לֵ֣כְנָה שֹּׁ֔בְנָה אִשָּׁ֖ה לְבֵ֣ית אִמָּ֑הּ יעשה יְהוָ֤ה " \
             "עִמָּכֶם֙ חֶ֔סֶד כַּאֲשֶׁ֧ר עֲשִׂיתֶ֛ם עִם־הַמֵּתִ֖ים וְעִמָּדִֽי׃"
  RUTH_1_8_TOKENS = [
    { "form" => "אִמָּ֑הּ", "lemma" => "517", "morph" => "HNcfsc/Sp3fs", "id" => "08dns", "lang" => "hbo" },
    { "form" => "יעשה", "lemma" => "6213 a", "morph" => "HVqi3ms", "id" => "08GK3",
      "type" => "x-ketiv", "lang" => "hbo",
      "qere" => [{ "form" => "יַ֣עַשׂ", "lemma" => "6213 a", "morph" => "HVqj3ms", "id" => "08nRZ",
                   "lang" => "hbo" }] },
    { "form" => "יְהוָ֤ה", "lemma" => "3068", "morph" => "HNp", "id" => "08cpb", "lang" => "hbo" }
  ].freeze
  RUTH_ANNOTATIONS = { "tokens" => RUTH_1_8_TOKENS }.freeze

  RLI = "⁧"
  PDI = "⁩"

  def policies
    @policies ||= Nabu::Display.load_policies(shipped_config)
  end

  def source_policies
    @source_policies ||= Nabu::Display.load_source_policies(shipped_config)
  end

  def shipped_config
    File.join(Nabu::Config::PROJECT_ROOT, "config", "display.yml")
  end

  def render(text, language, mode: "reading", source: nil, annotations: nil)
    Nabu::Display.render(text, language: language, mode: Nabu::Display.mode(mode),
                               policies: policies, source: source, annotations: annotations,
                               source_policies: source_policies)
  end

  def unwrap(text)
    text.delete(RLI + PDI)
  end

  # -- the two new modes on the P27-0 registry -----------------------------

  def test_reading_and_diplomatic_are_registered
    assert_includes Nabu::Display.mode_names, "reading"
    assert_includes Nabu::Display.mode_names, "diplomatic"
  end

  def test_diplomatic_is_byte_identical_on_every_shelf_pin
    [[DDBDP_LINE_6, "grc", "papyri-ddbdp", nil],
     [EDH_ERASED, "lat", "edh", nil],
     [RIIG_SURPLUS, "xtg-Latn", "riig", nil],
     [SBLGNT_WORD, "grc", "sblgnt", nil],
     [RUTH_1_8, "hbo", "oshb", RUTH_ANNOTATIONS]].each do |text, lang, source, annotations|
      rendered = render(text, lang, mode: "diplomatic", source: source, annotations: annotations)
      assert_equal text, rendered.text, "diplomatic must show the stored edition marks (#{source})"
      assert_empty rendered.applied
    end
  end

  # -- lacuna normalization (papyri-ddbdp, edh, riig) ----------------------

  def test_reading_normalizes_the_gap_marker_to_one_ellipsis
    rendered = render(DDBDP_LINE_6, "grc", source: "papyri-ddbdp")
    assert_equal "καὶ Οὐήρου τῶν κυρίων Σεβαστῶν Ἐπεὶφ η …", rendered.text
    assert_includes rendered.applied, "lacuna"
  end

  def test_reading_keeps_a_mid_word_gap_mid_word
    assert_equal "Αἴλιος …θως ἐπηκολούθησα ταῖς τοῦ ἀργυρίου",
                 render(DDBDP_LINE_7, "grc", source: "papyri-ddbdp").text
    assert_equal "καρε…μ", render(RIIG_GAP, "xtg-Grek", source: "riig").text
  end

  def test_reading_normalizes_edh_whole_inscription_lacunae
    assert_equal "… …", render(EDH_LOST, "lat", source: "edh").text
  end

  # -- erasures and surplus: content, kept by default ----------------------

  def test_reading_keeps_erasures_bracketed_by_default
    rendered = render(EDH_ERASED, "lat", source: "edh")
    assert_equal EDH_ERASED, rendered.text, "an erasure is content — default keeps the ⟦…⟧"
    assert_empty rendered.applied
  end

  def test_erasures_unwrap_is_configurable
    with_sources_yaml("sources:\n  edh: { reading: { erasures: unwrap } }\n") do |sp|
      rendered = Nabu::Display.render(EDH_ERASED, language: "lat", mode: Nabu::Display.mode("reading"),
                                                  policies: policies, source: "edh", source_policies: sp)
      assert_equal "Lucius Licinius Luci filius Crassus", rendered.text
      assert_includes rendered.applied, "erasures"
    end
  end

  def test_reading_keeps_riig_surplus_braces_by_default
    rendered = render(RIIG_SURPLUS, "xtg-Latn", source: "riig")
    assert_equal RIIG_SURPLUS, rendered.text, "surplus letters are on the stone — default keeps the {…}"
  end

  def test_surplus_unwrap_is_configurable
    with_sources_yaml("sources:\n  riig: { reading: { surplus: unwrap } }\n") do |sp|
      rendered = Nabu::Display.render(RIIG_SURPLUS, language: "xtg-Latn",
                                                    mode: Nabu::Display.mode("reading"),
                                                    policies: policies, source: "riig", source_policies: sp)
      assert_equal "nantonticnos", rendered.text
      assert_includes rendered.applied, "surplus"
    end
  end

  # -- sblgnt apparatus sigla ----------------------------------------------

  def test_reading_strips_the_sblgnt_apparatus_sigla
    rendered = render(SBLGNT_WORD, "grc", source: "sblgnt")
    assert_equal SBLGNT_WORD_READING, rendered.text
    assert_includes rendered.applied, "sigla"
  end

  def test_reading_keeps_sblgnt_punctuation_parentheses
    rendered = render(SBLGNT_PHRASE, "grc", source: "sblgnt")
    assert rendered.text.start_with?("("), "parentheses are the edition's punctuation, not apparatus"
    refute_includes rendered.text, "⸂"
    refute_includes rendered.text, "⸃"
  end

  def test_default_mode_never_applies_edition_rules
    rendered = render(SBLGNT_WORD, "grc", mode: "default", source: "sblgnt")
    assert_equal SBLGNT_WORD, rendered.text, "edition rules belong to reading mode only"
    assert_empty rendered.applied
  end

  # -- ketiv/qere (oshb) ---------------------------------------------------

  def test_reading_substitutes_qere_and_composes_with_cantillation_strip
    rendered = render(RUTH_1_8, "hbo", source: "oshb", annotations: RUTH_ANNOTATIONS)
    text = unwrap(rendered.text)
    assert_includes text, "יַעַשׂ", "the qere reading, its cantillation stripped by the hbo policy"
    refute_includes text, "יעשה", "the ketiv must be substituted away under qere display"
    assert_includes rendered.applied, "qere"
    assert_includes rendered.applied, "cantillation"
    assert_includes rendered.applied, Nabu::Display::ISOLATES, "hbo isolates still wrap reading mode"
  end

  def test_qere_display_ketiv_leaves_the_written_form
    with_sources_yaml("sources:\n  oshb: { qere_display: ketiv }\n") do |sp|
      rendered = Nabu::Display.render(RUTH_1_8, language: "hbo", mode: Nabu::Display.mode("reading"),
                                                policies: policies, source: "oshb",
                                                annotations: RUTH_ANNOTATIONS, source_policies: sp)
      assert_includes unwrap(rendered.text), "יעשה"
      refute_includes rendered.applied, "qere"
    end
  end

  def test_qere_display_both_renders_ketiv_then_qere_bracketed
    with_sources_yaml("sources:\n  oshb: { qere_display: both }\n") do |sp|
      rendered = Nabu::Display.render(RUTH_1_8, language: "hbo", mode: Nabu::Display.mode("reading"),
                                                policies: policies, source: "oshb",
                                                annotations: RUTH_ANNOTATIONS, source_policies: sp)
      assert_includes unwrap(rendered.text), "יעשה [יַעַשׂ]", "both = ketiv [qere]"
      assert_includes rendered.applied, "ketiv+qere"
    end
  end

  def test_qere_substitution_without_annotations_is_a_noop
    rendered = render(RUTH_1_8, "hbo", source: "oshb")
    assert_includes unwrap(rendered.text), "יעשה", "no annotations → the stored ketiv stands"
    refute_includes rendered.applied, "qere"
  end

  # -- config parsing & validation -----------------------------------------

  def test_shipped_sources_config_carries_the_censused_conventions
    assert_equal({ "lacuna" => "ellipsis" }, source_policies["papyri-ddbdp"].reading)
    assert_equal "ellipsis", source_policies["edh"].reading["lacuna"]
    assert_equal "keep", source_policies["edh"].reading["erasures"]
    assert_equal "keep", source_policies["riig"].reading["surplus"]
    assert_equal({ "sigla" => "strip" }, source_policies["sblgnt"].reading)
    assert_equal "qere", source_policies["oshb"].qere_display
    refute source_policies.key?("ogham"), "ogham censused zero edition marks — no rules invented"
    refute source_policies.key?("oracc"), "oracc braces/x are content — deliberately left (backlog P27-1)"
  end

  def test_missing_sources_section_means_no_source_policies
    with_sources_yaml("languages:\n  hbo: { strip: [cantillation] }\n") do |sp|
      assert_empty sp
    end
  end

  def test_unknown_edition_rule_is_a_named_error
    error = assert_raises(Nabu::Display::ConfigError) do
      with_sources_yaml("sources:\n  edh: { reading: { sparkles: strip } }\n") { |_sp| flunk "must raise" }
    end
    assert_match(/sparkles/, error.message)
    assert_match(/lacuna/, error.message, "the error must name the valid rules")
  end

  def test_unknown_rule_setting_is_a_named_error
    error = assert_raises(Nabu::Display::ConfigError) do
      with_sources_yaml("sources:\n  edh: { reading: { lacuna: sideways } }\n") { |_sp| flunk "must raise" }
    end
    assert_match(/sideways/, error.message)
  end

  def test_bad_qere_display_value_is_a_named_error
    error = assert_raises(Nabu::Display::ConfigError) do
      with_sources_yaml("sources:\n  oshb: { qere_display: loud }\n") { |_sp| flunk "must raise" }
    end
    assert_match(/qere_display/, error.message)
    assert_match(/loud/, error.message)
  end

  def test_reading_without_source_context_is_language_strips_only
    rendered = render(RUTH_1_8, "hbo")
    text = unwrap(rendered.text)
    assert_includes text, "יעשה", "no source context → no qere substitution"
    refute_includes rendered.applied, "qere"
    assert_includes rendered.applied, "cantillation", "language-level default strips still compose"
  end

  private

  def with_sources_yaml(content)
    Dir.mktmpdir("nabu-display-sources") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, content)
      yield Nabu::Display.load_source_policies(path)
    end
  end
end

# Gaiji resolution + placeholder (P37-3): the kanripo `reading`-mode transform
# for `&KR\d+;` not-yet-encoded-character references. A ref the curated map
# resolves becomes its real glyph; every other becomes the ⬚ placeholder box —
# never a fake glyph. diplomatic/full/default keep refs verbatim.
class DisplayGaijiTest < Minitest::Test
  # A short lzh run carrying one FAITHFUL ref (KR0001 → 𫠦, in the shipped map)
  # and one IMAGE-ONLY ref (KR0809, the parser's own example — unresolvable).
  KANRIPO_LINE = "子曰&KR0001;學而&KR0809;時習之"
  FAITHFUL_MAP = { "KR0001" => "𫠦" }.freeze
  PLACEHOLDER = "\u{2B1A}" # ⬚

  def render(text, mode:, source: "kanripo", gaiji_map: FAITHFUL_MAP, gaiji: "placeholder",
             gaiji_ids: {}, gaiji_substitutes: {})
    with_kanripo_policy(gaiji) do |sp|
      Nabu::Display.render(text, language: "lzh", mode: Nabu::Display.mode(mode),
                                 policies: {}, source: source,
                                 source_policies: sp, gaiji_map: gaiji_map,
                                 gaiji_ids: gaiji_ids, gaiji_substitutes: gaiji_substitutes)
    end
  end

  def test_reading_resolves_the_faithful_ref_and_placeholds_the_rest
    rendered = render(KANRIPO_LINE, mode: "reading")
    assert_equal "子曰𫠦學而#{PLACEHOLDER}時習之", rendered.text
    refute_includes rendered.text, "&KR", "no raw ref survives reading mode"
  end

  def test_reading_tallies_resolved_and_unresolved_for_the_footer
    tally = render(KANRIPO_LINE, mode: "reading").gaiji
    assert_equal 1, tally.resolved, "KR0001 mapped to a real codepoint"
    assert_equal 1, tally.unresolved, "KR0809 is image-only → placeholder"
  end

  def test_diplomatic_keeps_the_refs_verbatim
    rendered = render(KANRIPO_LINE, mode: "diplomatic")
    assert_equal KANRIPO_LINE, rendered.text, "the byte-honest view shows the refs as stored"
    assert_nil rendered.gaiji, "no gaiji transform ran → no tally"
  end

  def test_full_keeps_the_refs_verbatim
    assert_equal KANRIPO_LINE, render(KANRIPO_LINE, mode: "full").text
  end

  def test_default_mode_never_resolves_gaiji
    assert_equal KANRIPO_LINE, render(KANRIPO_LINE, mode: "default").text,
                 "gaiji resolution belongs to reading mode only"
  end

  def test_refs_setting_keeps_them_verbatim_even_in_reading
    rendered = render(KANRIPO_LINE, mode: "reading", gaiji: "refs")
    assert_equal KANRIPO_LINE, rendered.text
    assert_equal 0, rendered.gaiji.resolved
    assert_equal 0, rendered.gaiji.unresolved
  end

  def test_a_bad_gaiji_setting_is_a_named_error
    error = assert_raises(Nabu::Display::ConfigError) do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "display.yml")
        File.write(path, "sources:\n  kanripo: { gaiji: sparkle }\n")
        Nabu::Display.load_source_policies(path)
      end
    end
    assert_match(/gaiji/, error.message)
    assert_match(/placeholder/, error.message, "the error names the valid settings")
  end

  def test_shipped_display_yml_gives_kanripo_the_ladder_policy
    sp = Nabu::Display.load_source_policies(File.join(Nabu::Config::PROJECT_ROOT, "config", "display.yml"))
    assert_equal "ladder", sp["kanripo"].gaiji, "P38-2 made the four-rung ladder kanripo's shipped policy"
  end

  def test_shipped_gaiji_map_resolves_a_known_ref_and_omits_the_unresolvable
    map = Nabu::Display.load_gaiji_map(File.join(Nabu::Config::PROJECT_ROOT, "config", "gaiji", "kanripo.tsv"))
    assert_equal "𫠦", map["KR0001"], "the faithful codepoint ships"
    assert_nil map["KR0809"], "the image-only ref is deliberately not in the faithful map"
    # census recalibrated in P38-1: was 972, but 547 of those were Private-Use
    # codepoints (tofu off the mandoku font) — purged from the faithful lane. The
    # exact count + full lane invariants live in test/gaiji_tables_test.rb.
    assert_equal 427, map.size, "the curated faithful subset after the P38-1 PUA purge"
  end

  def test_missing_gaiji_map_is_an_empty_map_not_an_error
    assert_empty Nabu::Display.load_gaiji_map("/no/such/gaiji.tsv"),
                 "resolution degrades to placeholder-only, never a load error"
  end

  private

  def with_kanripo_policy(gaiji)
    Dir.mktmpdir("nabu-gaiji") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, "sources:\n  kanripo: { gaiji: #{gaiji} }\n")
      yield Nabu::Display.load_source_policies(path)
    end
  end
end

# The four-rung gaiji display LADDER (P38-2; `gaiji: ladder`). Each `&KR\d+;`
# ref resolves at the first rung that holds it: FAITHFUL glyph (unmarked) → IDS
# composition (inline) → SUBSTITUTE (marked ⌈…⌉) → ⬚ placeholder. Rungs 1/3/4
# are exercised with real refs from the shipped tables; rung 2 (empty for
# kanripo) with a test-scoped IDS table injected through the same seam.
class DisplayGaijiLadderTest < Minitest::Test
  PLACEHOLDER = "\u{2B1A}"                 # ⬚
  MARK_OPEN = "\u{2308}"                   # ⌈
  MARK_CLOSE = "\u{2309}"                  # ⌉

  # Real data: KR0001 faithful (𫠦), KR4710 a PUA-rescued substitute-only ref
  # (脊, per test/gaiji_tables_test.rb), KR0809 an image-only tail ref (no lane).
  FAITHFUL = { "KR0001" => "𫠦" }.freeze
  SUBSTITUTES = { "KR4710" => "脊" }.freeze
  # Rung 2 is empty for kanripo today — a test-scoped table (our config shape,
  # not upstream data) in the ref→IDS-sequence form Aozora (P38-3) will populate.
  IDS = { "KR9001" => "⿰氵丐" }.freeze

  def ladder(text, gaiji_map: FAITHFUL, gaiji_ids: IDS, gaiji_substitutes: SUBSTITUTES)
    Dir.mktmpdir("nabu-ladder") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, "sources:\n  kanripo: { gaiji: ladder }\n")
      sp = Nabu::Display.load_source_policies(path)
      Nabu::Display.render(text, language: "lzh", mode: Nabu::Display.mode("reading"),
                                 policies: {}, source: "kanripo", source_policies: sp,
                                 gaiji_map: gaiji_map, gaiji_ids: gaiji_ids,
                                 gaiji_substitutes: gaiji_substitutes)
    end
  end

  def test_rung1_faithful_glyph_is_rendered_unmarked
    rendered = ladder("子曰&KR0001;學")
    assert_equal "子曰𫠦學", rendered.text, "the faithful codepoint is the character — no mark"
    assert_equal 1, rendered.gaiji.faithful
  end

  def test_rung2_ids_composition_is_rendered_inline
    rendered = ladder("氵&KR9001;水")
    assert_equal "氵⿰氵丐水", rendered.text, "the IDS sequence renders inline (Aozora's live lane)"
    assert_equal 1, rendered.gaiji.ids
  end

  def test_rung3_substitute_is_rendered_visibly_marked
    rendered = ladder("&KR4710;椎")
    assert_equal "#{MARK_OPEN}脊#{MARK_CLOSE}椎", rendered.text,
                 "a lossy substitute is wrapped in ⌈…⌉ so it is never quoted unaware"
    assert_equal 1, rendered.gaiji.substitute
  end

  def test_rung4_unmapped_ref_falls_to_the_placeholder
    rendered = ladder("學&KR0809;時")
    assert_equal "學#{PLACEHOLDER}時", rendered.text, "an image-only ref is the ⬚ box — never a fake glyph"
    assert_equal 1, rendered.gaiji.placeholder
  end

  def test_all_four_rungs_in_one_line_tally_per_rung
    rendered = ladder("子&KR0001;曰&KR9001;學&KR4710;而&KR0809;之")
    assert_equal "子𫠦曰⿰氵丐學#{MARK_OPEN}脊#{MARK_CLOSE}而#{PLACEHOLDER}之", rendered.text
    refute_includes rendered.text, "&KR", "no raw ref survives the ladder"
    tally = rendered.gaiji
    assert_equal 1, tally.faithful
    assert_equal 1, tally.ids
    assert_equal 1, tally.substitute
    assert_equal 1, tally.placeholder
  end

  def test_faithful_wins_over_a_ref_present_in_a_lower_lane
    # Lanes are disjoint by construction, but the ladder must still resolve at
    # the HIGHEST rung: a ref in both faithful and substitute renders faithful,
    # unmarked, and never touches the substitute counter.
    rendered = ladder("&KR0001;", gaiji_substitutes: { "KR0001" => "X" })
    assert_equal "𫠦", rendered.text
    assert_equal 1, rendered.gaiji.faithful
    assert_equal 0, rendered.gaiji.substitute
  end

  def test_placeholder_mode_never_consults_the_lower_lanes
    # `gaiji: placeholder` is rungs 1 + 4 ONLY (P37-3, preserved): even with the
    # IDS and substitute tables in hand, an unfaithful ref is the ⬚ box.
    Dir.mktmpdir("nabu-ladder") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, "sources:\n  kanripo: { gaiji: placeholder }\n")
      sp = Nabu::Display.load_source_policies(path)
      rendered = Nabu::Display.render("&KR4710;&KR9001;", language: "lzh",
                                                          mode: Nabu::Display.mode("reading"), policies: {},
                                                          source: "kanripo", source_policies: sp,
                                                          gaiji_map: FAITHFUL, gaiji_ids: IDS,
                                                          gaiji_substitutes: SUBSTITUTES)
      assert_equal "#{PLACEHOLDER}#{PLACEHOLDER}", rendered.text
      assert_equal 2, rendered.gaiji.placeholder
      assert_equal 0, rendered.gaiji.substitute
      assert_equal 0, rendered.gaiji.ids
    end
  end

  def test_diplomatic_keeps_refs_verbatim_under_ladder_policy
    Dir.mktmpdir("nabu-ladder") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, "sources:\n  kanripo: { gaiji: ladder }\n")
      sp = Nabu::Display.load_source_policies(path)
      rendered = Nabu::Display.render("&KR4710;", language: "lzh",
                                                  mode: Nabu::Display.mode("diplomatic"), policies: {},
                                                  source: "kanripo", source_policies: sp,
                                                  gaiji_substitutes: SUBSTITUTES)
      assert_equal "&KR4710;", rendered.text, "the byte-honest view keeps the ref as stored"
      assert_nil rendered.gaiji, "no gaiji transform ran → no tally"
    end
  end

  def test_shipped_substitute_lane_marks_a_pua_rescued_ref
    # End-to-end against the SHIPPED tables (KR4710 → 脊, the P38-1 rescue).
    root = Nabu::Config::PROJECT_ROOT
    faithful = Nabu::Display.load_gaiji_map(File.join(root, "config", "gaiji", "kanripo.tsv"))
    subs = Nabu::Display.load_gaiji_map(File.join(root, "config", "gaiji", "kanripo-substitutes.tsv"))
    rendered = ladder("&KR4710;", gaiji_map: faithful, gaiji_ids: {}, gaiji_substitutes: subs)
    assert_equal "#{MARK_OPEN}脊#{MARK_CLOSE}", rendered.text
    assert_nil faithful["KR4710"], "the rescued ref is NOT in the faithful lane"
  end
end
