# frozen_string_literal: true

require "test_helper"

module Adapters
  # The 84000 glossary lane (P106-4 — the P48 follow-up finally executed):
  # the back-matter <div type="glossary"> entity records — bo / Wylie /
  # Sanskrit / English term entries with definitions — ride the P104-4
  # secondary dictionary lane into ONE bo-headed shelf beside mvp. Both
  # upstream gloss shapes are real (the fixtures document them): the bare
  # <term> + <term type="definition"> shape (toh846a) and the
  # translationMain + <note type="definition"> shape (toh3156).
  class E84000GlossaryLaneTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("e84000")

    def lane
      Nabu::Adapters::E84000GlossaryLane.new
    end

    def documents
      lane.discover(FIXTURES).map { |ref| lane.parse(ref) }
    end

    def entries
      documents.flat_map { |document| document.entries.to_a }
    end

    def test_discovery_follows_the_primary_cone_filtered_to_gloss_bearers
      ids = lane.discover(FIXTURES).map(&:id)
      assert(ids.all? { |id| id.start_with?("e84000-gloss:") })
      # Placeholders are never discovered (the primary's rule), and a
      # publication without a single <gloss (toh761, toh1-6) is not a lane
      # ref — every discovered ref parses to a non-empty shelf document.
      assert_equal %w[e84000-gloss:toh3156 e84000-gloss:toh539e e84000-gloss:toh846a], ids.sort
    end

    def test_every_document_lands_on_the_one_shared_shelf
      documents.each do |document|
        assert_equal "e84000-glossary", document.slug
        assert_equal "xct", document.language
      end
    end

    def test_parses_the_bare_term_shape
      garuda = entries.find { |entry| entry.entry_id == "UT22084-100-002-20" }
      refute_nil garuda
      assert_equal "གསེར་འདབ", garuda.headword, "bo headword, trailing shad stripped"
      assert_equal "གསེར་འདབ།", garuda.key_raw, "the verbatim upstream term"
      assert_equal "gser 'dab", garuda.headword_folded, "folds to Wylie so EWTS queries hit"
      assert_equal "garuḍa", garuda.gloss, "the English display term is the short gloss"
      assert_includes garuda.body, "A class of bird deities."
      assert_includes garuda.body, "gser ’dab", "the Wylie lane rides the body"
      assert_includes garuda.body, "garuḍa"
    end

    def test_parses_the_translation_main_shape_with_note_definition
      five_deeds = entries.find { |entry| entry.entry_id == "UT23703-075-017-94" }
      refute_nil five_deeds
      assert_equal "མཚམས་མེད་པ་ལྔ", five_deeds.headword
      assert_equal "five deeds of immediate retribution", five_deeds.gloss
      assert_includes five_deeds.body, "immediate and unavoidable birth"
      assert_includes five_deeds.body, "pañcānantarya"
    end

    def test_entity_type_is_recorded_in_the_body
      person = entries.find { |entry| entry.entry_id == "UT23703-075-017-95" }
      refute_nil person
      assert_includes person.body, "type: person"
    end

    def test_an_entry_without_a_bo_term_falls_back_and_stays_honest
      # Every fixture gloss carries a bo term today; the fallback ladder
      # (bo → Wylie → English) is pinned at unit grain instead.
      entry = Nabu::Adapters::E84000GlossaryLane.build_entry_from(
        { id: "X-1", type: "term", en: "test being", wylie: "test w", bo: nil,
          skt: nil, definition: "d" }
      )
      assert_equal "test w", entry.headword
    end

    def test_fixture_census
      assert_equal 14, entries.size, "6 (toh846a) + 1 (toh539e) + 7 (toh3156)"
      assert_equal entries.map(&:entry_id).uniq.size, entries.size, "entry ids unique"
    end
  end
end
