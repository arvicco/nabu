# frozen_string_literal: true

require "test_helper"

# Nabu::PlaceRefs (P63-4) — the one place_ref reader: verbatim upstream URL
# spellings and the Dp-b namespaced mints parse through ONE seam; measured
# malformations (multi-URL fields, scheme variants, the text-URL stray)
# behave honestly.
class PlaceRefsTest < Minitest::Test
  def test_a_single_pleiades_url_in_either_scheme
    %w[https://pleiades.stoa.org/places/462281 http://pleiades.stoa.org/places/462281/].each do |ref|
      assert_equal [%w[pleiades 462281]], Nabu::PlaceRefs.ids(ref)
    end
  end

  def test_the_measured_multi_url_field_splits_into_every_claim
    ref = "https://pleiades.stoa.org/places/727105 https://www.trismegistos.org/place/2711"
    assert_equal [%w[pleiades 727105], %w[tm 2711]], Nabu::PlaceRefs.ids(ref)
  end

  def test_namespaced_mints_parse_as_their_own_tokens
    assert_equal [%w[tm 2788]], Nabu::PlaceRefs.ids("tm:2788")
    assert_equal [%w[pleiades 433078]], Nabu::PlaceRefs.ids("pleiades:433078")
  end

  def test_an_unknown_mint_namespace_yields_nothing_never_guessed
    assert_empty Nabu::PlaceRefs.ids("riig:153")
  end

  def test_the_text_url_stray_yields_nothing_for_its_token
    ref = "https://www.trismegistos.org/place/34 https://www.trismegistos.org/text/392592"
    assert_equal [%w[tm 34]], Nabu::PlaceRefs.ids(ref)
  end

  def test_geonames_urls_parse_with_and_without_sws_host
    assert_equal [%w[geonames 3180985]], Nabu::PlaceRefs.ids("https://sws.geonames.org/3180985")
    assert_equal [%w[geonames 6543607]], Nabu::PlaceRefs.ids("https://www.geonames.org/6543607")
  end

  def test_the_measured_doubled_geonames_malformation_still_yields_the_id_once
    ref = "https://sws.geonames.org/https://sws.geonames.org/6543607"
    assert_equal [%w[geonames 6543607]], Nabu::PlaceRefs.ids(ref)
  end

  def test_nil_and_junk_are_empty
    assert_empty Nabu::PlaceRefs.ids(nil)
    assert_empty Nabu::PlaceRefs.ids("Segesta")
  end

  def test_ids_in_filters_one_namespace
    ref = "https://pleiades.stoa.org/places/991398 https://www.trismegistos.org/place/2983 " \
          "https://www.trismegistos.org/place/1281"
    assert_equal %w[2983 1281], Nabu::PlaceRefs.ids_in(ref, "tm")
    assert_equal %w[991398], Nabu::PlaceRefs.ids_in(ref, "pleiades")
  end
end
