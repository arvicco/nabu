# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::HieroCard (P65-2): the Egyptian sign desk card — one sign
  # in (glyph or Gardiner-style code), the Unikemet identity out (catalog
  # code, description, function, phonetic value, the JSesh/Hieroglyphica/
  # IFAO concordances, core-vs-legacy), plus an "in the wild" panel counting
  # the sign's Gardiner code across held aes hiero_inventar annotations —
  # semicolon-bounded (N35 must never count N35A). The honesty rule binds:
  # absent upstream fields are absent sections; no catalog → no panel.
  class HieroCardTest < Minitest::Test
    include StoreTestDB

    SIGNS = Nabu::Hieroglyphs.load(File.join(Nabu::TestSupport.fixtures("unikemet"), "Unikemet.txt"))

    OVERLAY = Nabu::EdubbaOverlay.new(Nabu::TestSupport.fixtures("edubba-overlay"))

    def card_for(input, catalog: nil, overlay: nil)
      Nabu::Query::HieroCard.new(hieroglyphs: SIGNS, catalog: catalog, overlay: overlay).run(input)
    end

    # P72-6: the Edubba didactic overlay joins on the JSESH Gardiner code
    # (their contract said `cat`, but our cat is the Gardiner-PLUS
    # G-12-002 shape — the correction is relayed); the section carries
    # the attribution line and rides the JSON contract additively.
    def test_didactic_overlay_joins_on_the_jsesh_code_with_attribution
      result = card_for("G43", overlay: OVERLAY)
      didactic = result.card.didactic
      assert_equal "chick", didactic["keyword"]
      assert_equal "sound", didactic["voice_kind"]
      assert_equal ["Z7"], didactic["confusables"]
      assert_equal Nabu::EdubbaOverlay::ATTRIBUTION, didactic["attribution"]
      assert_match(%r{edubba\.ac/hieroglyphs/addenda/signs/g43/}, didactic["link"])

      payload = Nabu::Query::HieroCard.json_payload(result)
      assert_equal "chick", payload.dig("card", "didactic", "keyword"),
                   "the overlay rides the frozen JSON contract as an additive key"
    end

    def test_no_overlay_module_means_no_didactic_section_never_an_error
      assert_nil card_for("G43").card.didactic
    end

    def test_a_glyph_resolves_to_its_card
      card = card_for("𓅃").card
      assert_equal "𓅃", card.glyph
      assert_equal "U+13143", card.codepoint
      assert_equal "G-12-002", card.cat
      assert_equal "G5", card.jsesh
      assert_equal "A falcon.", card.desc
      assert_equal "Logogram (Horus)", card.func
      assert_equal "ḥr", card.fval
      assert_equal({}, card.corpus, "no catalog handle → the corpus panel is absent")
    end

    def test_a_gardiner_code_resolves_to_the_same_card
      assert_equal "U+13143", card_for("G5").card.codepoint
      assert_equal "U+13216", card_for("N35").card.codepoint
    end

    def test_unknown_input_is_an_empty_result
      assert_nil card_for("Z99").card
      assert_nil card_for("𓀁").card, "a hieroglyph outside the held file resolves to nothing"
    end

    def test_the_corpus_panel_counts_aes_hiero_inventar_semicolon_bounded
      db = store_test_db
      load_aes_fixture(db)
      corpus = card_for("N35", catalog: db).card.corpus
      assert_equal 18, corpus["signs"],
                   "N35 tokens across the aes fixture (12 tuebingerstelen + 6 sawlit, " \
                   "counted from the raw JSON 2026-08-09 — and never N35A)"
      assert_operator corpus["passages"], :>, 0
      assert_operator corpus["signs"], :>=, corpus["passages"]
    ensure
      db&.disconnect
    end

    def test_the_json_payload_carries_the_card_and_absent_fields_as_null
      payload = Nabu::Query::HieroCard.json_payload(card_for("𓅃"))
      card = payload["card"]
      assert_equal "U+13143", card["codepoint"]
      assert_equal "G5", card["jsesh"]
      assert_equal "ḥr", card["fval"]
      assert_nil card["alt_seq"]
      empty = Nabu::Query::HieroCard.json_payload(card_for("Z99"))
      assert_nil empty["card"]
    end

    private

    def load_aes_fixture(catalog)
      source = Nabu::Store::Source.create(
        slug: "aes", name: "AES", adapter_class: "Nabu::Adapters::Aes",
        license_class: "attribution"
      )
      adapter = Nabu::Adapters::Aes.new
      loader = Nabu::Store::Loader.new(db: catalog, source: source)
      adapter.discover(Nabu::TestSupport.fixtures("aes")).each do |ref|
        loader.load([adapter.parse(ref)], full: false)
      end
    end
  end
end
