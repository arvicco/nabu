# frozen_string_literal: true

require "test_helper"

# Nabu::Places (P63-7) — the registry read seam over the pinned trimmed-real
# fixture (test/fixtures/nabu-places/, the P63-6 seed wave). Also the drift
# guard: the fixture rows validate under the same rules the upstream
# bin/validate enforces (vocabulary closure, ref shapes, alias targets).
class PlacesTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-places")

  def registry
    @registry ||= Nabu::Places.load(FIXTURES)
  end

  def test_a_matched_row_resolves_with_its_refs
    d = registry.decision("cdli", "Girsu (mod. Tello)")
    assert d.matched?
    assert_includes d.refs, "cigs:GIR"
    assert_includes d.refs, "pleiades:912855"
    assert_equal "high", d.certainty
  end

  def test_an_alias_row_follows_one_hop_and_keeps_its_own_certainty
    d = registry.decision("cdli", "Girsu (mod. Tello) ?")
    assert d.matched?, "the ?-suffix alias resolves to the base row"
    assert_includes d.refs, "cigs:GIR"
  end

  def test_an_unlisted_name_is_nil_the_identity_default
    assert_nil registry.decision("cdli", "Totally Unknown Tell")
    assert_nil registry.decision("nosuchsource", "Girsu (mod. Tello)")
  end

  def test_a_low_certainty_direct_match_carries_its_note
    d = registry.decision("cdli", "Nereb (mod. Neirab) ?")
    assert d.matched?
    assert_equal "low", d.certainty
    assert_match(/\?-qualified/, d.note)
  end

  def test_decisions_for_resolves_a_whole_section
    all = registry.decisions_for("oracc")
    assert_equal %w[Assur Girsu Nineveh Umma], all.keys.sort
    assert all.values.all?(Nabu::Places::Decision)
  end

  def test_absent_registry_is_the_lane_off_posture
    Dir.mktmpdir do |dir|
      assert_nil Nabu::Places.load_default(canonical_dir: dir)
    end
  end

  # -- the native minting lane (owner ruling 2026-08-09: not only glue) -----

  def test_minted_places_read_with_evidence_backed_shape
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "places.yml"), <<~YAML)
        KARKAR_SU:
          name: Karkar (the Umma waterway station)
          lat: 31.9
          lon: 45.7
          evidence: joined barge itineraries; see the argument note
      YAML
      rows = Nabu::Places.minted(dir)
      assert_equal 1, rows.size
      row = rows.first
      assert_equal "KARKAR_SU", row.id
      assert_in_delta 31.9, row.lat
      assert_equal ["minted"], row.place_types
      assert_includes row.name_keys, Nabu::Pleiades.name_key("Karkar (the Umma waterway station)")
    end
  end

  def test_an_empty_or_absent_minted_file_is_an_empty_lane
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Places.minted(dir)
      File.write(File.join(dir, "places.yml"), "{}\n")
      assert_empty Nabu::Places.minted(dir)
    end
  end

  def test_np_mints_parse_through_the_one_ref_reader
    assert_equal [%w[np KARKAR_SU]], Nabu::PlaceRefs.ids("np:KARKAR_SU")
  end

  # -- the drift guard (the nabu-lects pattern): fixture rows stay valid ----

  def test_every_fixture_ref_has_a_declared_namespace_and_shape
    namespaces = YAML.safe_load_file(File.join(FIXTURES, "namespaces.yml"))
    shapes = namespaces.transform_values { |d| /\A#{d.fetch('id_shape')}\z/ }
    %w[cdli oracc].each do |source|
      registry.decisions_for(source).each_value do |d|
        d.refs.each do |ref|
          ns, id = ref.split(":", 2)
          assert shapes.key?(ns), "#{ref}: undeclared namespace"
          assert_match shapes[ns], id.to_s, "#{ref}: id fails the #{ns} shape"
        end
      end
    end
  end
end
