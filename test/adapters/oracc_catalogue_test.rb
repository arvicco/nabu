# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::OraccCatalogue — one ORACC catalogue member → the
  # document metadata the catalogue holds beyond designation/period/genre:
  # persons with their roles, works identity, archive/findspot context,
  # sub/supergenre, regnal context and the SAA sender place, plus the
  # composite Q edges. Every member below is a REAL catalogue entry, cut
  # verbatim from the held ORACC build into
  # test/fixtures/oracc/catalogue-members/members.json (README there).
  class OraccCatalogueTest < Minitest::Test
    MEMBERS = JSON.parse(File.read(File.join(Nabu::TestSupport.fixtures("oracc"),
                                             "catalogue-members", "members.json")))

    def metadata_for(key) = Nabu::Adapters::OraccCatalogue.document_metadata(MEMBERS.fetch(key))
    def related_for(key) = Nabu::Adapters::OraccCatalogue.related(MEMBERS.fetch(key))

    # -- persons ----------------------------------------------------------

    def test_letter_persons_ride_with_their_roles
      metadata = metadata_for("saao/saa01:P313416")
      assert_equal "Sargon II", metadata["ruler"]
      assert_equal "Sin-a[šared?]", metadata["ancient_author"], "the restored name rides verbatim"
      assert_equal "the king", metadata["ancient_recipient"]
      assert_equal "sin-ashared", metadata["dossier_list"]
    end

    def test_legal_parties_are_lists
      sale = metadata_for("atae/mallanate:P522850")
      assert_equal "Mitūnu", sale["eponym"]
      assert_equal ["Handî"], sale["ancient_buyer"]
      assert_equal ["Ateqanni"], sale["ancient_seller"]
      assert_equal ["Ateqanni"], sale["seal_owner"]

      loan = metadata_for("atae/imgurenlil:P522820")
      assert_equal ["Tikasu"], loan["ancient_creditor"]
      assert_equal ["Dādî"], loan["ancient_debtor"]
    end

    def test_semicolon_lists_split_into_their_parties
      member = { "ancient_seller" => "Wandî; Ṭūrī-rāme" } # censused verbatim value
      assert_equal %w[Wandî Ṭūrī-rāme], Nabu::Adapters::OraccCatalogue.document_metadata(member)["ancient_seller"]
    end

    def test_unknown_author_is_a_claim_kept_verbatim
      assert_equal "(unknown)", metadata_for("saao/saa15:P238649")["ancient_author"]
    end

    # -- works identity ---------------------------------------------------

    def test_royal_inscription_works_identity
      metadata = metadata_for("riao:Q006482")
      assert_equal "Q006482", metadata["id_composite"]
      assert_equal "Annals of Room II", metadata["popular_name"]
      assert_equal "Sargon II 001", metadata["Q_designation"]
      assert_equal "Assyria", metadata["dynastic_seat"]
      assert_equal "721-705", metadata["regnal_dates"]
      assert_equal "LIT", metadata["supergenre"]
      assert_equal "Sargon II", metadata["subgenre"]
    end

    def test_letter_title_rides_as_the_work_title
      assert_equal "Gold and Silver Objects Sent to the King", metadata_for("saao/saa01:P313416")["work_title"]
      assert_nil Nabu::Adapters::OraccCatalogue.document_metadata("title" => "(no title)")["work_title"],
                 "upstream's no-title placeholder is not a title"
    end

    def test_lexical_series_identity
      list = metadata_for("dcclt/signlists:Q000055")
      assert_equal "Ea", list["series"]
      assert_equal ["Proto-Ea"], list["other_names"]
      assert_equal "Antagal 3", metadata_for("dcclt/nineveh:P235300")["series_tablet_no"]
    end

    def test_qcat_other_names_join_the_other_names
      assert_equal ["Dreaming of Witchcraft"], metadata_for("cmawro/cmawr1:P236997")["other_names"]
    end

    # -- archive / findspot context ---------------------------------------

    def test_archive_and_excavation_context
      metadata = metadata_for("atae/burmarina:P522614")
      assert_equal "001 - Area F, Private Archive", metadata["archive"]
      assert_equal "TSF 97 F 200/126 + 209 + 220", metadata["excavation_no"]
      assert_equal "Area F", metadata["findspot_square"]
      assert_equal "sales document (person)", metadata["subgenre"]
    end

    # -- the SAA sender place ---------------------------------------------

    def test_sender_place_fields_ride_verbatim
      metadata = metadata_for("saao/saa01:P313416")
      assert_equal "Assyria", metadata["sender_loc"]
      assert_equal "29492", metadata["pleiades_sender_loc"]
      assert_equal "43.2,36.2", metadata["sender_loc_coordinates"]
    end

    def test_sender_placeholders_are_not_values
      metadata = metadata_for("saao/saa15:P238649")
      assert_equal "(unknown)", metadata["sender_loc"], "upstream's unknown-sender claim"
      refute metadata.key?("pleiades_sender_loc"), "\"not assigned\" is no Pleiades id"
      refute metadata.key?("sender_loc_coordinates"), "\"N/A\" is no coordinate pair"
    end

    # -- edges ------------------------------------------------------------

    # The composite Q-numbers mint the SAME hub targets CDLI's
    # composite_id mints (urn:nabu:cdli:q…), so ORACC witnesses, CDLI
    # witnesses and the composite meet at one hub.
    def test_composite_q_numbers_mint_the_cdli_q_hubs
      assert_equal ["urn:nabu:cdli:q006482"], related_for("riao:Q006482")
      assert_equal ["urn:nabu:cdli:q005112"], related_for("cmawro/cmawr1:P236997"),
                   "cmawro's qcat_2__id_composite is the same claim under another key"
      assert_empty related_for("saao/saa01:P313416")
    end

    def test_composites_lists_contribute_every_q
      member = { "composites" => "Q003294; Q003295" } # the censused list shape
      assert_equal %w[urn:nabu:cdli:q003294 urn:nabu:cdli:q003295],
                   Nabu::Adapters::OraccCatalogue.related(member)
    end

    def test_a_member_with_none_of_the_fields_yields_empty_metadata
      assert_empty Nabu::Adapters::OraccCatalogue.document_metadata("designation" => "X 1", "period" => "Ur III")
    end
  end
end
