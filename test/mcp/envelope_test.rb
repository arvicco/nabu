# frozen_string_literal: true

require "test_helper"

module MCP
  # The reference-data license envelope: licenses read from the adapters'
  # own manifests (one source of truth), never a hand-copied list.
  class EnvelopeTest < Minitest::Test
    def test_reference_reads_the_adapter_manifest_verbatim
      envelope = Nabu::MCP::Envelope.reference("pleiades")
      manifest = Nabu::Adapters::Pleiades.manifest
      assert_equal({ source: "pleiades", license_class: manifest.license_class,
                     license: manifest.license, upstream_url: manifest.upstream_url }, envelope)
      assert_match(/CC BY 3\.0/, envelope.fetch(:license))
    end

    def test_every_reference_slug_resolves_to_a_licensed_manifest
      Nabu::MCP::Envelope::REFERENCE_ADAPTERS.each_key do |slug|
        envelope = Nabu::MCP::Envelope.reference(slug)
        refute_nil envelope, "#{slug} resolves"
        assert_includes Nabu::Model::Validation::LICENSE_CLASSES, envelope.fetch(:license_class)
        refute_empty envelope.fetch(:license).to_s
      end
    end

    def test_unknown_slug_is_nil_never_a_placeholder
      assert_nil Nabu::MCP::Envelope.reference("no-such-dataset")
    end

    def test_place_attribution_carries_the_upstream_place_uri
      pleiades = Nabu::MCP::Envelope.place_attribution("pleiades", "462281")
      assert_equal "https://pleiades.stoa.org/places/462281", pleiades.fetch(:uri)
      tm = Nabu::MCP::Envelope.place_attribution("tm", "2810")
      assert_equal "trismegistos-geo", tm.fetch(:source)
      assert_equal "https://www.trismegistos.org/place/2810", tm.fetch(:uri)
      # The URI shapes are exactly the ones PlaceRefs recognises.
      assert_equal ["462281"], Nabu::PlaceRefs.ids_in(pleiades.fetch(:uri), "pleiades")
      assert_equal ["2810"], Nabu::PlaceRefs.ids_in(tm.fetch(:uri), "tm")
      cigs = Nabu::MCP::Envelope.place_attribution("cigs", "GIR")
      assert_equal "cigs", cigs.fetch(:source)
      refute cigs.key?(:uri), "cigs has no per-place URL — no uri key"
      assert_nil Nabu::MCP::Envelope.place_attribution("np", "1"), "np has no gazetteer"
    end
  end
end
