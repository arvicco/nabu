# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# Nabu::PlaceApply (P63-7) — registry decisions projected into
# document_axes.place_ref. The structural precedence: NULL-only updates
# (adapter-asserted refs always win), idempotent, censused. Runs against the
# pinned trimmed-real registry fixture copied under a canonical dir.
class PlaceApplyTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("nabu-places")

  def setup
    @db = store_test_db
    @source = Nabu::Store::Source.create(slug: "cdli", name: "CDLI", adapter_class: "T",
                                         license_class: "open")
  end

  def seed_axis(urn, place_name:, place_ref: nil)
    doc = Nabu::Store::Document.create(
      source_id: @source.id, urn: urn, title: urn, language: "sux",
      content_sha256: urn, revision: 1, withdrawn: false
    )
    @db[:document_axes].insert(document_id: doc.id, axis_source: "cdli",
                               place_name: place_name, place_ref: place_ref)
    doc.id
  end

  def with_canonical
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "nabu-places"))
      FileUtils.cp(File.join(FIXTURES, "names.yml"), File.join(dir, "nabu-places"))
      yield dir
    end
  end

  def test_matched_names_gain_space_joined_namespaced_refs
    seed_axis("urn:nabu:cdli:p1", place_name: "Girsu (mod. Tello)")
    with_canonical do |dir|
      census = Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
      assert_equal 1, census.dig("cdli", :rows_updated)
      ref = @db[:document_axes].first[:place_ref]
      assert_equal [%w[cigs GIR], %w[pleiades 912855]], Nabu::PlaceRefs.ids(ref),
                   "the decision's refs, space-joined, readable by the ONE reader"
    end
  end

  def test_adapter_asserted_refs_are_never_overwritten
    seed_axis("urn:nabu:cdli:p2", place_name: "Girsu (mod. Tello)",
                                  place_ref: "https://pleiades.stoa.org/places/912855")
    with_canonical do |dir|
      census = Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
      assert_equal 0, census.dig("cdli", :rows_updated)
      assert_equal "https://pleiades.stoa.org/places/912855", @db[:document_axes].first[:place_ref]
    end
  end

  def test_aliases_apply_and_unlisted_names_stay_null
    seed_axis("urn:nabu:cdli:p3", place_name: "Girsu (mod. Tello) ?")
    seed_axis("urn:nabu:cdli:p4", place_name: "Some Unlisted Tell")
    with_canonical do |dir|
      Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
      rows = @db[:document_axes].order(:document_id).select_map(:place_ref)
      assert_includes Nabu::PlaceRefs.ids(rows[0]), %w[cigs GIR], "the ?-alias resolves to the base"
      assert_nil rows[1], "identity-default: unlisted stays visibly unmatched"
    end
  end

  def test_apply_is_idempotent
    seed_axis("urn:nabu:cdli:p5", place_name: "Umma (mod. Tell Jokha)")
    with_canonical do |dir|
      first = Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
      assert_equal 1, first[:total]
      second = Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
      assert_equal 0, second[:total], "a registry mint is never stacked onto itself"
    end
  end

  def test_no_registry_is_the_lane_off_posture
    Dir.mktmpdir do |dir|
      assert_nil Nabu::PlaceApply.run(catalog: @db, canonical_dir: dir)
    end
  end
end
