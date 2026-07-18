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

  def test_visible_length_ignores_isolates
    rendered = render(GEN_1_1_CONSONANTAL, "hbo", mode: "plain")
    assert_equal GEN_1_1_CONSONANTAL.length, Nabu::Display.visible_length(rendered.text)
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

  private

  def with_yaml(content)
    Dir.mktmpdir("nabu-display") do |dir|
      path = File.join(dir, "display.yml")
      File.write(path, content)
      yield path
    end
  end
end
