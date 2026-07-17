# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::SourceShelf (P24-0): the third sanctioned canonical-write gateway —
# the LanguageShelf accretion contract at the source grain: idempotent
# (write only when the body differs), own-section supersession, skeleton
# dossiers for unknown slugs, everyone else's lanes untouched, malformed
# files refused as evidence.
class SourceShelfTest < Minitest::Test
  def with_shelf
    Dir.mktmpdir("nabu-source-shelf") do |dir|
      yield Nabu::SourceShelf.new(dir: dir), dir
    end
  end

  def test_accrete_creates_a_skeleton_dossier_for_an_unknown_slug
    with_shelf do |shelf, dir|
      changed = shelf.accrete!(notes: [["gretil", "witness:survey", "Survey: .docs/surveys/pie-survey.md."]],
                               source: "pie-survey", now: Time.new(2026, 7, 16))
      assert_equal %w[gretil], changed.keys
      dossier = Nabu::SourceDossier.parse(File.read(File.join(dir, "gretil.md")), slug: "gretil")
      assert_nil dossier.description, "a skeleton has no curated lanes"
      section = dossier.section("witness:survey")
      assert_equal "Survey: .docs/surveys/pie-survey.md.", section.body
      assert_equal "pie-survey", section.provenance
      assert_equal "2026-07-16", section.date
    end
  end

  def test_accrete_is_idempotent_and_supersedes_only_its_own_section
    with_shelf do |shelf, dir|
      shelf.write!(Nabu::SourceDossier.new(
                     slug: "edh", description: "Latin inscriptions.", note: "Curated prose.",
                     sections: [Nabu::SourceDossier::Section.new(
                       kind: "witness:survey", provenance: "edh-survey", date: "2026-07-01", body: "Survey lane."
                     )]
                   ))
      notes = [["edh", "witness:gate", "Gate 24 checked."]]
      assert_equal %w[edh], shelf.accrete!(notes: notes, source: "gate-24").keys

      before = File.read(File.join(dir, "edh.md"))
      assert_empty shelf.accrete!(notes: notes, source: "gate-24"),
                   "an unchanged body writes nothing — re-syncs are no-ops"
      assert_equal before, File.read(File.join(dir, "edh.md")), "byte-identical on the no-op"

      changed = shelf.accrete!(notes: [["edh", "witness:gate", "Gate 24 checked, revised."]], source: "gate-24")
      dossier = changed.fetch("edh")
      assert_equal "Gate 24 checked, revised.", dossier.section("witness:gate").body
      assert_equal "Curated prose.", dossier.note, "the owner's prose is never touched"
      assert_equal "Latin inscriptions.", dossier.description, "the curated description is never touched"
      assert_equal "Survey lane.", dossier.section("witness:survey").body,
                   "someone else's section is never touched"
    end
  end

  def test_accrete_refuses_to_clobber_a_malformed_dossier
    with_shelf do |shelf, dir|
      File.write(File.join(dir, "edh.md"), "not a dossier")
      assert_raises(Nabu::SourceDossier::FormatError) do
        shelf.accrete!(notes: [%w[edh witness:gate x]], source: "gate-24")
      end
      assert_equal "not a dossier", File.read(File.join(dir, "edh.md")), "the broken file is left as evidence"
    end
  end
end
