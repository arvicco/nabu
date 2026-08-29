# frozen_string_literal: true

require "test_helper"

# Nabu::ScriptCheck — the surface-script byte checker (P61) and, since P86-2,
# the DRIFT GUARD binding it to the registry's global scripts table: the five
# script vocabularies converge on two authorities (registry = naming,
# Unicode property = bytes), and this suite makes silent divergence
# impossible — a script minted into nabu-lects without a checker row (or a
# documented unmirrored reason) turns the suite red, and so does a checker
# row the registry does not know.
class ScriptCheckTest < Minitest::Test
  REGISTRY_DIR = File.expand_path("fixtures/nabu-lects", __dir__)

  def registry_script_tags
    Nabu::Lects.load(REGISTRY_DIR).script_tags
  end

  # -- the drift guard ------------------------------------------------------

  def test_every_registry_script_is_checkable_or_documented_unmirrored
    covered = (Nabu::ScriptCheck::PROPERTIES.keys + Nabu::ScriptCheck::UNMIRRORED.keys).sort
    missing = registry_script_tags - covered
    assert_empty missing,
                 "registry scripts with neither a byte-check property nor a documented " \
                 "unmirrored reason (extend ScriptCheck with the mint): #{missing.join(', ')}"
  end

  def test_the_checker_carries_no_ghost_tags
    ghosts = (Nabu::ScriptCheck::PROPERTIES.keys + Nabu::ScriptCheck::UNMIRRORED.keys) -
             registry_script_tags
    assert_empty ghosts, "checker tags the registry does not know: #{ghosts.join(', ')}"
  end

  def test_unmirrored_reasons_are_stated
    Nabu::ScriptCheck::UNMIRRORED.each do |tag, reason|
      refute_empty reason.to_s, "#{tag}: an unmirrored script must say why"
    end
  end

  # Collation's witness-cell grouping must name every byte-checkable registry
  # script (it may carry display extras beyond the registry — Georgian, the
  # kana pair — but never lag it): compared by regex source, the one identity
  # both tables share.
  def test_collation_covers_every_checkable_registry_script
    collation_sources = Nabu::Query::Collation.const_get(:SCRIPTS).values.map(&:source)
    lagging = Nabu::ScriptCheck::PROPERTIES.reject do |_, property|
      collation_sources.include?(property.source)
    end.keys
    assert_empty lagging, "collation cannot name these checkable scripts: #{lagging.join(', ')}"
  end

  # -- classification over the six P86-2 scripts ----------------------------

  SIX = {
    "tibt" => "ཀ",  # TIBETAN LETTER KA
    "ethi" => "ሀ",  # ETHIOPIC SYLLABLE HA
    "hang" => "한",  # a Hangul syllable
    "avst" => "𐬀",  # AVESTAN LETTER A
    "ugar" => "𐎀",  # UGARITIC LETTER ALPA
    "xpeo" => "𐎠"   # OLD PERSIAN SIGN A
  }.freeze

  def test_the_six_minted_scripts_classify
    SIX.each do |tag, char|
      tally = Nabu::ScriptCheck.classify(char)
      assert_equal({ tag => 1 }, tally, "#{char} must classify as #{tag}")
    end
  end

  def test_dominant_names_the_majority_script
    tag, share = Nabu::ScriptCheck.dominant(%w[ཀཁག ka])
    assert_equal "tibt", tag
    assert_in_delta 0.6, share, 0.01
  end

  def test_scriptless_text_stays_nil
    assert_equal [nil, 0.0], Nabu::ScriptCheck.dominant(["123 …!"])
  end
end
