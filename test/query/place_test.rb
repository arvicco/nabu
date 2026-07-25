# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Place (P44-2): the place desk — a Pleiades resolver card plus
  # the library's holdings at that place, joined ONLY on the upstream-asserted
  # ids the parsers captured (documents.metadata_json $.place.pleiades). Input
  # is a numeric id or an EXACT case-insensitive title — never fuzzy. The
  # unlinked tail is an exact-substring text match over the captured findspot
  # text fields of id-less documents, labelled apart, never merged.
  #
  # Catalog: fresh in-memory SQLite (house pattern); resolver: the two-place
  # fixture dump (462492 Sicilia (island), 570685 Sparta) — injected, so no
  # test ever touches a real canonical tree.
  class PlaceTest < Minitest::Test
    include StoreTestDB

    PLEIADES_DUMP = File.join(Nabu::TestSupport.fixtures("pleiades"), "dump.json")

    def setup
      @catalog = store_test_db
      @loaders = {}
    end

    def loader(slug)
      @loaders[slug] ||= begin
        source = Nabu::Store::Source.create(
          slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open"
        )
        Nabu::Store::Loader.new(db: @catalog, source: source)
      end
    end

    def load_document(source:, slug:, place: nil)
      document = Nabu::Document.new(
        urn: "urn:t:#{source}:#{slug}", language: "grc", title: slug,
        canonical_path: "/canonical/#{source}/#{slug}.xml",
        metadata: place ? { "place" => place } : {}
      )
      document << Nabu::Passage.new(
        urn: "urn:t:#{source}:#{slug}:1", language: "grc", text: "χαῖρε",
        text_normalized: "χαιρε", sequence: 0
      )
      loader(source).load([document], full: false)
    end

    def resolver
      @resolver ||= Nabu::Pleiades.load(PLEIADES_DUMP)
    end

    def place_query(pleiades: resolver)
      Nabu::Query::Place.new(catalog: @catalog, pleiades: pleiades)
    end

    # -- id lookup + holdings -------------------------------------------------

    def test_numeric_id_yields_the_card_and_holdings_grouped_by_source
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      load_document(source: "isicily", slug: "b", place: { "pleiades" => "570685" })
      load_document(source: "edh", slug: "c", place: { "pleiades" => "570685" })
      load_document(source: "edh", slug: "d", place: { "pleiades" => "462492" })

      result = place_query.run("570685")
      assert result.dump_loaded
      assert_equal 1, result.cards.size
      card = result.cards.first
      assert_equal "570685", card.pleiades_id
      assert_equal "Sparta", card.place.title
      assert_equal [["isicily", 2], ["edh", 1]], card.holdings,
                   "descending by count — the other-place edh document never counts here"
    end

    def test_a_full_pleiades_url_is_accepted_as_the_id_form
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      card = place_query.run("https://pleiades.stoa.org/places/570685").cards.first
      assert_equal "Sparta", card.place.title
    end

    def test_exact_title_lookup_is_case_insensitive_never_fuzzy
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })

      result = place_query.run("sparta")
      assert_equal ["570685"], result.cards.map(&:pleiades_id)
      assert_equal [["isicily", 1]], result.cards.first.holdings

      error = assert_raises(Nabu::Query::Place::Error) { place_query.run("Spart") }
      assert_match(/no place titled/, error.message)
    end

    def test_an_id_the_dump_lacks_still_counts_holdings_card_less
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "999999" })
      result = place_query.run("999999")
      card = result.cards.first
      assert_nil card.place, "no gazetteer entry — the card degrades, the counts stay honest"
      assert_equal [["isicily", 1]], card.holdings
    end

    def test_withdrawn_documents_do_not_count
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      load_document(source: "isicily", slug: "b", place: { "pleiades" => "570685" })
      Nabu::Store::Document.first(urn: "urn:t:isicily:b").update(withdrawn: true)

      assert_equal [["isicily", 1]], place_query.run("570685").cards.first.holdings
    end

    # -- the dump-absent degradation -------------------------------------------

    def test_without_the_dump_an_id_still_counts_holdings
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      result = place_query(pleiades: nil).run("570685")
      refute result.dump_loaded
      card = result.cards.first
      assert_nil card.place
      assert_equal [["isicily", 1]], card.holdings
    end

    def test_without_the_dump_a_title_lookup_is_a_clear_error
      error = assert_raises(Nabu::Query::Place::Error) { place_query(pleiades: nil).run("Sparta") }
      assert_match(/nabu sync pleiades/, error.message)
    end

    # -- the unlinked tail (labelled, never merged) ----------------------------

    def test_unlinked_tail_counts_idless_documents_whose_findspot_text_mentions_the_name
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685", "ancient" => "Sparta" })
      load_document(source: "edh", slug: "b", place: { "ancient" => "Sparta?" })
      load_document(source: "iip", slug: "c", place: { "settlement" => "sparta region" })
      load_document(source: "edh", slug: "d", place: { "ancient" => "Corduba" })

      result = place_query.run("570685")
      assert_equal [["isicily", 1]], result.cards.first.holdings,
                   "id-matched counts never absorb text matches"
      assert_equal "Sparta", result.unlinked_term
      assert_equal [["edh", 1], ["iip", 1]], result.unlinked,
                   "exact substring, case-insensitive, id-less documents only"
    end

    def test_unlinked_tail_uses_the_queried_name_when_input_was_a_title
      load_document(source: "edh", slug: "a", place: { "ancient" => "Sparta?" })
      result = place_query.run("SPARTA")
      assert_equal "SPARTA", result.unlinked_term
      assert_equal [["edh", 1]], result.unlinked
    end

    # -- input edges -----------------------------------------------------------

    def test_blank_input_is_an_error
      assert_raises(Nabu::Query::Place::Error) { place_query.run("  ") }
    end
  end
end
