# frozen_string_literal: true

require "test_helper"

# Nabu::LanguageNote — the language-note addressing (P85-A, №R-48-2): a bare
# language code maps to a canonical pseudo-URN so the ordinary note pipeline
# carries private per-language notes; a colon-bearing target stays a URN note.
class LanguageNoteTest < Minitest::Test
  def test_a_bare_code_is_a_language_target
    assert_equal "chu", Nabu::LanguageNote.code_for("chu")
    assert_equal "zle-ort", Nabu::LanguageNote.code_for("zle-ort")
    assert_equal "roa-opt", Nabu::LanguageNote.code_for("  roa-opt  "), "trimmed"
  end

  def test_a_colon_bearing_target_is_not_a_language_code
    assert_nil Nabu::LanguageNote.code_for("urn:nabu:perseus:1"), "a corpus URN is never a language code"
    assert_nil Nabu::LanguageNote.code_for("urn:nabu:lang:chu"), "an already-minted language URN is not bare"
    assert_nil Nabu::LanguageNote.code_for(""), "empty is nothing"
    assert_nil Nabu::LanguageNote.code_for("Chu Ci"), "spaces/caps are not a code"
  end

  def test_urn_round_trips_the_code
    urn = Nabu::LanguageNote.urn("zle-ort")
    assert_equal "urn:nabu:lang:zle-ort", urn
    assert_equal "zle-ort", Nabu::LanguageNote.code_of(urn)
  end

  def test_code_of_ignores_a_non_language_urn
    assert_nil Nabu::LanguageNote.code_of("urn:nabu:perseus:1")
    assert_nil Nabu::LanguageNote.code_of("chu")
  end
end
