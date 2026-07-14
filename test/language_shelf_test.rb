# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LanguageShelf (P19-1): the sanctioned canonical-write gateway — the
# accretion contract rehomed from the ledger onto dossier sections:
# idempotent (write only when the body differs), own-section supersession,
# skeleton dossiers for unknown codes, everyone else's lanes untouched.
class LanguageShelfTest < Minitest::Test
  def with_shelf
    Dir.mktmpdir("nabu-language-shelf") do |dir|
      yield Nabu::LanguageShelf.new(dir: dir), dir
    end
  end

  def test_accrete_creates_a_skeleton_dossier_for_an_unknown_code
    with_shelf do |shelf, dir|
      changed = shelf.accrete!(notes: [["lit", "iecor", "IE-CoR variety: Lithuanian."]],
                               source: "iecor", now: Time.new(2026, 7, 14))
      assert_equal %w[lit], changed.keys
      dossier = Nabu::LanguageDossier.parse(File.read(File.join(dir, "lit.md")), code: "lit")
      assert_nil dossier.name, "a skeleton has no curated lanes"
      section = dossier.section("iecor")
      assert_equal "IE-CoR variety: Lithuanian.", section.body
      assert_equal "iecor", section.source
      assert_equal "2026-07-14", section.date
    end
  end

  def test_accrete_is_idempotent_and_supersedes_only_its_own_section
    with_shelf do |shelf, dir|
      shelf.write!(Nabu::LanguageDossier.new(
                     code: "chu", name: "Old Church Slavonic", context: "Curated prose.",
                     sections: [Nabu::LanguageDossier::Section.new(
                       kind: "witness:liv", source: "liv", date: "2026-07-01", body: "LIV lane."
                     )]
                   ))
      notes = [["chu", "iecor", "IE-CoR variety: OCS."]]
      assert_equal %w[chu], shelf.accrete!(notes: notes, source: "iecor").keys

      before = File.read(File.join(dir, "chu.md"))
      assert_empty shelf.accrete!(notes: notes, source: "iecor"),
                   "an unchanged body writes nothing — re-syncs are no-ops"
      assert_equal before, File.read(File.join(dir, "chu.md")), "byte-identical on the no-op"

      changed = shelf.accrete!(notes: [["chu", "iecor", "IE-CoR variety: OCS, revised."]], source: "iecor")
      dossier = changed.fetch("chu")
      assert_equal "IE-CoR variety: OCS, revised.", dossier.section("iecor").body
      assert_equal "Curated prose.", dossier.context, "the owner's prose is never touched"
      assert_equal "LIV lane.", dossier.section("witness:liv").body, "someone else's section is never touched"
    end
  end

  def test_accrete_accepts_note_objects_and_groups_by_code
    with_shelf do |shelf, _dir|
      notes = [
        Nabu::DictionaryLanguageNote.new(lang_code: "lit", kind: "iecor", body: "Lithuanian.", source: "iecor"),
        Nabu::DictionaryLanguageNote.new(lang_code: "lav", kind: "iecor", body: "Latvian.", source: "iecor")
      ]
      changed = shelf.accrete!(notes: notes, source: "iecor")
      assert_equal %w[lav lit], changed.keys.sort
    end
  end

  def test_accrete_refuses_to_clobber_a_malformed_dossier
    with_shelf do |shelf, dir|
      File.write(File.join(dir, "chu.md"), "not a dossier")
      assert_raises(Nabu::LanguageDossier::FormatError) do
        shelf.accrete!(notes: [%w[chu iecor x]], source: "iecor")
      end
      assert_equal "not a dossier", File.read(File.join(dir, "chu.md")), "the broken file is left as evidence"
    end
  end
end
