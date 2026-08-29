# frozen_string_literal: true

require "test_helper"

# Nabu::ScriptDossiers (P86-4c) — the curated per-script context layer, and
# the guard binding it to the registry: every registry script has a dossier,
# no dossier orphans, display names agree — the same drift-guard family as
# ScriptCheck's.
class ScriptDossiersTest < Minitest::Test
  def registry
    Nabu::Lects.load(File.expand_path("fixtures/nabu-lects", __dir__))
  end

  def test_dossiers_cover_the_registry_exactly
    tags = Nabu::ScriptDossiers.table.keys.sort
    assert_equal registry.script_tags, tags,
                 "dossier tags must equal the registry scripts table — a mint without a " \
                 "dossier (or a dossier orphan) is drift"
  end

  def test_every_dossier_is_well_formed
    Nabu::ScriptDossiers.table.each_key do |tag|
      dossier = Nabu::ScriptDossiers.lookup(tag)
      refute_empty dossier.name
      assert dossier.context.length > 80, "#{tag}: context is a real paragraph, not a stub"
      refute_match(/\n/, dossier.name)
    end
  end

  def test_lookup_folds_iso_spelling_and_answers_nil_off_table
    assert_equal "Runic", Nabu::ScriptDossiers.lookup("Runr").name
    assert_match(/futhark/i, Nabu::ScriptDossiers.lookup("runr").context)
    assert_nil Nabu::ScriptDossiers.lookup("zzzz")
  end

  def test_desk_lines_are_optional_and_present_where_shelf_specific
    assert Nabu::ScriptDossiers.lookup("xsux").desk, "cuneiform has desk conventions"
    assert_nil Nabu::ScriptDossiers.lookup("armn").desk, "Armenian carries none yet — honest absence"
  end
end
