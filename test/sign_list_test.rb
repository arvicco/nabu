# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::SignList (P53-1): the pure READ seam over the OSL sign list
# (canonical/osl/00lib/osl.asl via Nabu::Adapters::AslParser) — the
# CldfSpine/Lila feature-module posture. P53-2's `nabu signs` query surface
# builds on exactly this API: value → candidate sign records, name/alias →
# record. Values are looked up as OSL spells them (the C-ATF ASCII fold is
# the P53-2 tokenizer's concern, not this seam's).
class SignListTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")

  def list
    @list ||= Nabu::SignList.load(FIXTURE)
  end

  # --- lookup: value → candidates -------------------------------------------

  def test_lookup_is_a_deterministic_single_hit_for_an_unambiguous_value
    candidates = list.lookup("šeš")
    assert_equal 1, candidates.size
    assert_equal "ŠEŠ", candidates.first.name
    assert_equal ["U+122C0"], candidates.first.codepoints
    assert_equal "𒋀", candidates.first.ucun
    assert_equal "o0002834", candidates.first.oid
  end

  def test_lookup_resolves_the_uri5_compound_to_its_useq
    candidates = list.lookup("uri₅")
    assert_equal ["|ŠEŠ.AB|"], candidates.map(&:name)
    assert_equal %w[U+122C0 U+1200A], candidates.first.codepoints, "uri₅ → 𒋀𒀊"
    assert_equal "𒋀𒀊", candidates.first.ucun
  end

  def test_an_ambiguous_value_returns_all_candidates_never_one_silently
    candidates = list.lookup("idₓ")
    assert_equal ["|A.BARA₂|", "|UD.ŠEŠ.KI|"], candidates.map(&:name),
                 "idₓ lives on two fixture signs (six upstream) — the caller disambiguates"
  end

  def test_lookup_reaches_values_on_variant_forms
    candidates = list.lookup("nannaₓ")
    assert_equal ["|ŠEŠ.NA|"], candidates.map(&:name),
                 "the form record itself is the candidate — it has its own encoding"
    assert_equal %w[U+122C0 U+1223E], candidates.first.codepoints
  end

  def test_lookup_of_a_deprecated_value_still_resolves
    assert_equal ["AK"], list.lookup("aŋ").map(&:name),
                 "OSL deprecated the reading, but texts transliterated with it must resolve"
  end

  def test_lookup_of_an_unknown_value_is_empty
    assert_empty list.lookup("nosuchvalue₉₉")
  end

  # --- the language filter --------------------------------------------------

  def test_language_qualified_values_are_filtered_by_language
    assert_equal ["|AN.SAG@g|"], list.lookup("ṣillu").map(&:name),
                 "no language filter → every candidate"
    assert_equal ["|AN.SAG@g|"], list.lookup("ṣillu", language: "akk").map(&:name)
    assert_empty list.lookup("ṣillu", language: "sux"),
                 "an %akk-qualified value is not a Sumerian reading"
  end

  def test_unqualified_values_pass_every_language_filter
    assert_equal ["ŠEŠ"], list.lookup("šeš", language: "akk").map(&:name)
    assert_equal ["ŠEŠ"], list.lookup("šeš", language: "sux").map(&:name)
  end

  # --- sign: name / alias → record ------------------------------------------

  def test_sign_resolves_by_name
    assert_equal "o0002834", list.sign("ŠEŠ").oid
    assert_equal "U+1222B", list.sign("MIN").codepoint
  end

  def test_sign_resolves_by_aka_alias
    assert_equal "|A.BARA₂|", list.sign("|A.BARAG|").name,
                 "@aka |A.BARAG| points at |A.BARA₂|"
  end

  def test_sign_resolves_a_variant_form_name
    assert_equal "|AB.ŠEŠ|", list.sign("|AB.ŠEŠ|").name
    assert_equal %w[U+1200A U+122C0], list.sign("|AB.ŠEŠ|").codepoints
  end

  def test_sign_of_an_unknown_name_is_nil
    assert_nil list.sign("NOSUCHSIGN")
  end

  # --- honesty: unencoded signs ---------------------------------------------

  def test_a_codepoint_less_sign_reports_nil_codepoints
    record = list.sign("|A×AN|")
    refute_nil record
    assert_nil record.codepoints, "no Unicode encoding upstream — nil, not an error"
    assert_nil record.ucun
  end

  # --- census ---------------------------------------------------------------

  def test_sign_count_counts_top_level_signs
    assert_equal 13, list.sign_count
  end

  # --- load_default: the lane-off posture -----------------------------------

  def test_load_default_is_nil_when_the_canonical_asset_is_absent
    Dir.mktmpdir do |dir|
      config = Nabu::Config.load(root: dir)
      assert_nil Nabu::SignList.load_default(config: config),
                 "no canonical/osl/00lib/osl.asl → lane off, byte-identical behavior"
    end
  end

  def test_load_default_reads_the_canonical_asset_and_memoizes
    Nabu::SignList.reset!
    Dir.mktmpdir do |dir|
      asl = File.join(dir, "canonical", "osl", "00lib")
      FileUtils.mkdir_p(asl)
      FileUtils.cp(FIXTURE, File.join(asl, "osl.asl"))
      config = Nabu::Config.load(root: dir)
      loaded = Nabu::SignList.load_default(config: config)
      refute_nil loaded
      assert_equal 13, loaded.sign_count
      assert_same loaded, Nabu::SignList.load_default(config: config), "the load is memoized"
    end
  ensure
    Nabu::SignList.reset!
  end
end
