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

    # -- the derived index resolver (P45-6) ------------------------------------

    # The place desk takes whatever resolver load_default hands it — the
    # in-memory dump load or the SQLite-backed index. Same query, same
    # result, either way (the index resolver duck-types place/titled/size).
    def test_index_backed_resolver_answers_identically_to_the_dump_path
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      Nabu::Store::PlaceIndex.derive!(@catalog, places: resolver.each_place)
      indexed = Nabu::Store::PlaceIndex.resolver(@catalog) || flunk("derive left no resolver")

      from_dump = place_query.run("sparta")
      from_index = place_query(pleiades: indexed).run("sparta")
      assert_equal from_dump.cards.map(&:pleiades_id), from_index.cards.map(&:pleiades_id)
      assert_equal(from_dump.cards.map { |card| card.place.title },
                   from_index.cards.map { |card| card.place.title })
      assert_equal from_dump.cards.map(&:holdings), from_index.cards.map(&:holdings)
      assert_equal from_dump.unlinked, from_index.unlinked
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

    # -- axis holdings (P66-2: the P64-4 booked gap closes) --------------------
    #
    # document_axes.place_ref carries adapter-asserted AND registry-projected
    # refs (both mint and URL spellings — Nabu::PlaceRefs is the one reader).
    # The desk counts them as a SEPARATE labeled lane, doc-deduped, bounded
    # (an id must parse out, never substring-match).

    def axis_row(source:, slug:, place_ref:)
      doc_id = @catalog[:documents].where(urn: "urn:t:#{source}:#{slug}").get(:id)
      @catalog[:document_axes].insert(document_id: doc_id, place_ref: place_ref,
                                      axis_source: "test")
    end

    def test_axis_holdings_count_place_ref_rows_in_both_spellings
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      load_document(source: "cdli", slug: "b")
      load_document(source: "cdli", slug: "c")
      axis_row(source: "cdli", slug: "b", place_ref: "pleiades:570685 tm:2810")
      axis_row(source: "cdli", slug: "c", place_ref: "https://pleiades.stoa.org/places/570685")

      card = place_query.run("570685").cards.first
      assert_equal [["isicily", 1]], card.holdings, "the metadata lane is unchanged"
      assert_equal [["cdli", 2]], card.axis_holdings, "mint AND url spellings both count"
    end

    def test_axis_holdings_are_bounded_and_doc_deduped
      load_document(source: "cdli", slug: "b")
      axis_row(source: "cdli", slug: "b", place_ref: "pleiades:5706850")
      axis_row(source: "cdli", slug: "b", place_ref: "pleiades:570685")
      axis_row(source: "cdli", slug: "b", place_ref: "pleiades:570685")

      card = place_query.run("570685").cards.first
      assert_equal [["cdli", 1]], card.axis_holdings,
                   "5706850 never counts for 570685; two rows on one doc count once"
    end

    # -- namespaced-id input (P66-2: the desk's third dimension goes multi-gazetteer)

    def test_a_namespaced_ref_queries_its_own_axis_lane
      load_document(source: "ceipom", slug: "b")
      axis_row(source: "ceipom", slug: "b", place_ref: "tm:2810 pleiades:570685")

      result = place_query.run("tm:2810")
      card = result.cards.first
      assert_equal "tm:2810", card.ref
      assert_nil card.pleiades_id
      assert_equal [["ceipom", 1]], card.axis_holdings
      assert_empty card.holdings, "the metadata lane is pleiades-only — honest empty"
    end

    def test_a_pleiades_mint_ref_routes_to_the_full_pleiades_card
      load_document(source: "isicily", slug: "a", place: { "pleiades" => "570685" })
      card = place_query.run("pleiades:570685").cards.first
      assert_equal "570685", card.pleiades_id
      assert_equal "Sparta", card.place.title
      assert_equal "pleiades:570685", card.ref
    end

    def test_an_unknown_namespace_stays_a_title_lookup
      assert_raises(Nabu::Query::Place::Error) { place_query.run("zz:1") }
    end

    # -- the namespaced-card unlinked tail (P75 C-5, the P66-2 asymmetry) ------

    def test_a_ref_card_with_a_resolved_title_counts_the_unlinked_tail
      # A tm slice carrying the queried id: the card resolves its title, so
      # the findspot-text tail must ride exactly as it does for pleiades.
      Nabu::Store::PlaceIndex.derive!(
        @catalog,
        places: [Nabu::Pleiades::Place.new(id: "2810", title: "Girsu", lat: nil, lon: nil,
                                           place_types: [], time_periods: [])],
        gazetteer: "tm"
      )
      load_document(source: "ceipom", slug: "idless", place: { "ancient" => "near Girsu" })

      result = place_query.run("tm:2810")
      assert_equal "Girsu", result.unlinked_term
      assert_equal [["ceipom", 1]], result.unlinked,
                   "id-less findspot mentions count for a resolved ref card"
    end

    def test_a_ref_card_without_a_title_keeps_the_honest_empty_tail
      load_document(source: "ceipom", slug: "idless", place: { "ancient" => "near Girsu" })
      result = place_query.run("tm:2810")
      assert_nil result.unlinked_term, "no derived slice → no title → no text to count"
      assert_empty result.unlinked
    end

    # -- crosswalk equivalences (P75 C-3) --------------------------------------

    def test_the_card_carries_its_crosswalk_equivalences_both_directions
      @catalog[:place_crosswalk].insert(source: "t", gazetteer_a: "pleiades", id_a: "570685",
                                        gazetteer_b: "tm", id_b: "2810")
      @catalog[:place_crosswalk].insert(source: "t", gazetteer_a: "cigs", id_a: "SPA",
                                        gazetteer_b: "pleiades", id_b: "570685")
      card = place_query.run("570685").cards.first
      assert_equal [%w[cigs SPA], %w[tm 2810]], card.equivalences.sort
    end

    def test_a_ref_card_carries_equivalences_too
      @catalog[:place_crosswalk].insert(source: "t", gazetteer_a: "cigs", id_a: "GIR",
                                        gazetteer_b: "tm", id_b: "2810")
      card = place_query.run("cigs:GIR").cards.first
      assert_equal [%w[tm 2810]], card.equivalences
    end

    def test_no_crosswalk_rows_is_an_honest_empty_list
      card = place_query.run("570685").cards.first
      assert_empty card.equivalences
    end

    # -- input edges -----------------------------------------------------------

    def test_blank_input_is_an_error
      assert_raises(Nabu::Query::Place::Error) { place_query.run("  ") }
    end
  end
end
