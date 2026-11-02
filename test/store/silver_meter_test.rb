# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Store::SilverMeter (P152): the local-meter shelf projected into the
# enrichments table as silver meter rows — flagged (model nabu-scan +
# grade silver), never over gold, never over a moved text, wholesale
# supersede, and only once the owner armed the shelf (the replay rail).
class SilverMeterTest < Minitest::Test
  SilverMeter = Nabu::Store::SilverMeter

  def with_world
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    src = catalog[:sources].insert(slug: "perseus", name: "P", adapter_class: "X", license_class: "open")
    doc = catalog[:documents].insert(source_id: src, urn: "urn:t:doc", language: "lat", content_sha256: "x")
    ids = %w[a b gold moved gone].each_with_index.to_h do |name, i|
      [name, catalog[:passages].insert(document_id: doc, urn: "urn:t:#{name}", sequence: i, language: "lat",
                                       text: name, text_normalized: name, content_sha256: "sha-#{name}",
                                       withdrawn: name == "gone")]
    end
    catalog[:enrichments].insert(passage_id: ids["gold"], kind: "meter", model: "pedecerto", model_version: "p",
                                 payload_json: JSON.generate("meter" => "H", "pattern" => "DSSS"), at: Time.now)
    Dir.mktmpdir("nabu-silver-meter") do |root|
      yield catalog, Nabu::MeterShelf.new(dir: File.join(root, "local-meter")), ids
    end
  ensure
    catalog&.disconnect
  end

  def record(name, sha: "sha-#{name}", language: "lat", **over)
    Nabu::MeterShelf::Record.new(kind: "passage", urn: "urn:t:#{name}", language: language, content_sha256: sha,
                                 status: "scanned", meter: "hexameter", feet: "DDSSD",
                                 quantities: "-uu-uu-----uu--", word_pattern: "-u u-u- -- -", basis: "unique",
                                 scanner: "nabu-scan", scanner_version: "nabu-scan/1", **over)
  end

  def silver(catalog)
    catalog[:enrichments].where(model: SilverMeter::MODEL).order(:passage_id).all
  end

  def test_projects_scanned_records_flagged_silver_never_over_gold_or_a_moved_text
    with_world do |catalog, shelf, ids|
      unscanned = Nabu::MeterShelf::Record.new(kind: "passage", urn: "urn:t:b", language: "lat",
                                               content_sha256: "sha-b", status: "unscanned", reason: "no_fit",
                                               scanner: "nabu-scan", scanner_version: "nabu-scan/1")
      shelf.append_batch!(records: [record("a"), unscanned, record("gold"), record("moved", sha: "old"),
                                    record("gone"), record("nowhere")])
      report = SilverMeter.project!(catalog: catalog, shelf: shelf)

      assert_equal [1, 1, 1, 2, 1], [report.projected, report.gold_covered, report.stale, report.unresolved,
                                     report.unscanned]
      row = silver(catalog).first
      assert_equal ids["a"], row[:passage_id]
      payload = JSON.parse(row[:payload_json])
      assert_equal "silver", payload["grade"]
      assert_equal %w[H DDSS], [payload["meter"], payload["pattern"]], "Latin speaks pedecerto's vocabulary"
      assert_equal "unique", payload["basis"]
      assert_equal 1, catalog[:enrichments].where(model: "pedecerto").count, "gold untouched"
    end
  end

  def test_greek_speaks_hypotactic_vocabulary_and_pentameters_pedecerto_shape
    payload = SilverMeter.payload(record("a", language: "grc"))
    assert_equal ["dactylic hexameter", "-u u-u- -- -"], [payload["meter"], payload["pattern"]]
    pent = SilverMeter.payload(record("a", meter: "pentameter", feet: "DS"))
    assert_equal %w[P DS-|DD-], [pent["meter"], pent["pattern"]]
    spondaic = SilverMeter.payload(record("a", feet: "DSSDS"))
    assert_equal "DSSDS", spondaic["pattern"], "a spondeiazon spells out its fifth foot"
  end

  def test_projecting_twice_is_the_same_rows_and_retract_drops_the_lane
    with_world do |catalog, shelf, _ids|
      shelf.append_batch!(records: [record("a"), record("b")])
      SilverMeter.project!(catalog: catalog, shelf: shelf)
      first = silver(catalog).map { |r| [r[:passage_id], r[:payload_json]] }
      report = SilverMeter.project!(catalog: catalog, shelf: shelf)
      assert_equal(first, silver(catalog).map { |r| [r[:passage_id], r[:payload_json]] })
      assert_equal 2, report.projected
      assert_equal 2, SilverMeter.retract!(catalog: catalog)
      assert_empty silver(catalog)
    end
  end

  def test_replay_projects_only_an_armed_shelf
    with_world do |catalog, shelf, _ids|
      shelf.append_batch!(records: [record("a")])
      assert_nil SilverMeter.replay!(catalog: catalog, shelf: shelf)
      assert_nil SilverMeter.replay!(catalog: catalog, shelf: nil)
      assert_empty silver(catalog)
      shelf.arm!
      assert_equal 1, SilverMeter.replay!(catalog: catalog, shelf: shelf).projected
    end
  end

  def test_drop_stale_removes_rows_whose_text_moved_after_projection
    with_world do |catalog, shelf, ids|
      shelf.append_batch!(records: [record("a"), record("b")])
      SilverMeter.project!(catalog: catalog, shelf: shelf)
      catalog[:passages].where(id: ids["a"]).update(content_sha256: "re-parsed")
      assert_equal 1, SilverMeter.drop_stale!(catalog: catalog, slug: "perseus")
      assert_equal([ids["b"]], silver(catalog).map { |r| r[:passage_id] })
      assert_equal 0, SilverMeter.drop_stale!(catalog: catalog, slug: "other")
    end
  end
end
