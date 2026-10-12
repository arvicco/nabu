# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Store::SilverDates (P122-1): the local-dates shelf projected into
# document_axes as silver-grade rows — flagged twice (lane + class),
# wholesale supersede, live documents only, and only once the owner has
# armed the shelf (the replay rail).
class SilverDatesTest < Minitest::Test
  def with_world
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    src = catalog[:sources].insert(slug: "s", name: "S", adapter_class: "X", license_class: "open")
    ids = %w[a b gone].to_h do |name|
      [name, catalog[:documents].insert(source_id: src, urn: "urn:t:#{name}", language: "grc",
                                        content_sha256: "x", withdrawn: name == "gone")]
    end
    catalog[:document_axes].insert(document_id: ids["a"], not_before: 100, not_after: 200, axis_source: "hgv")
    Dir.mktmpdir("nabu-silver-dates") do |root|
      yield catalog, Nabu::DateShelf.new(dir: File.join(root, "local-dates")), ids
    end
  ensure
    catalog&.disconnect
  end

  def estimate(urn, not_before, not_after, **over)
    Nabu::DateShelf::Record.new(urn: urn, not_before: not_before, not_after: not_after, basis: "model",
                                estimator: "chronos", estimator_version: "0.3", confidence: 0.8,
                                note: nil, generated_at: nil, **over)
  end

  def silver_rows(catalog)
    catalog[:document_axes].where(axis_source: Nabu::Store::SilverDates::AXIS_SOURCE)
                           .order(:document_id).all
  end

  def test_projects_the_latest_estimate_per_live_document_flagged_silver
    with_world do |catalog, shelf, ids|
      shelf.append_batch!(records: [estimate("urn:t:b", -300, -200), estimate("urn:t:gone", 1, 2),
                                    estimate("urn:t:nowhere", 5, 6)])
      shelf.append_batch!(records: [estimate("urn:t:b", -250, -220, note: "second pass")])
      report = Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)

      assert_equal 1, report.projected
      assert_equal 2, report.unresolved, "a withdrawn document and an unheld urn never project"
      assert_equal 1, report.superseded
      row = silver_rows(catalog).first
      assert_equal ids["b"], row[:document_id]
      assert_equal [-250, -220], [row[:not_before], row[:not_after]], "the later estimate supersedes"
      assert_equal "silver", row[:date_class]
      assert_equal "estimate", row[:precision]
      assert_equal "model estimate — chronos 0.3, confidence 0.8: second pass", row[:date_raw]
      assert_equal 1, catalog[:document_axes].where(axis_source: "hgv").count, "upstream lanes untouched"
    end
  end

  def test_projecting_twice_is_the_same_rows
    with_world do |catalog, shelf, _ids|
      shelf.append_batch!(records: [estimate("urn:t:a", -300, -200), estimate("urn:t:b", 5, 9)])
      Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
      first = silver_rows(catalog).map { |row| row.except(:id) }
      Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
      assert_equal(first, silver_rows(catalog).map { |row| row.except(:id) })
      assert_equal 3, catalog[:document_axes].count
    end
  end

  def test_replay_projects_only_an_armed_shelf
    with_world do |catalog, shelf, _ids|
      assert_nil Nabu::Store::SilverDates.replay!(catalog: catalog, shelf: nil), "no shelf, no lane"
      shelf.append_batch!(records: [estimate("urn:t:b", -300, -200)])
      assert_nil Nabu::Store::SilverDates.replay!(catalog: catalog, shelf: shelf)
      assert_empty silver_rows(catalog), "silver never reaches db/ before the owner's ruling"

      shelf.arm!
      assert_equal 1, Nabu::Store::SilverDates.replay!(catalog: catalog, shelf: shelf).projected
      assert_equal 1, silver_rows(catalog).size
    end
  end

  def test_retract_drops_only_the_lane
    with_world do |catalog, shelf, _ids|
      shelf.append_batch!(records: [estimate("urn:t:b", -300, -200)])
      Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
      assert_equal 1, Nabu::Store::SilverDates.retract!(catalog: catalog)
      assert_empty silver_rows(catalog)
      assert_equal 1, catalog[:document_axes].count
    end
  end

  def test_upstream_excludes_the_lane
    with_world do |catalog, shelf, _ids|
      shelf.append_batch!(records: [estimate("urn:t:b", -300, -200)])
      Nabu::Store::SilverDates.project!(catalog: catalog, shelf: shelf)
      assert_equal %w[hgv], Nabu::Store::SilverDates.upstream(catalog[:document_axes]).select_map(:axis_source)
    end
  end
end
