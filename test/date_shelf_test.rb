# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The local-dates shelf's sanctioned write gateway (P122-1, architecture
# §16): model/tool date estimates as append-only JSONL shards under
# local/shelves/local-dates/, written ONLY through Nabu::DateShelf, plus
# the owner's projection ruling as shelf furniture.
class DateShelfTest < Minitest::Test
  def with_shelf(resolver: nil)
    Dir.mktmpdir("nabu-date-shelf") do |root|
      yield Nabu::DateShelf.new(dir: File.join(root, "local-dates"), resolver: resolver)
    end
  end

  def estimate(urn: "urn:nabu:test:a", not_before: -200, not_after: -100, **over)
    Nabu::DateShelf::Record.new(urn: urn, not_before: not_before, not_after: not_after,
                                basis: "model", estimator: "chronos", estimator_version: "0.3",
                                confidence: 0.8, note: nil, generated_at: nil, **over)
  end

  def test_the_shelf_lives_under_local_shelves
    config = Nabu::Config.new(canonical_dir: "/x/canonical", db_dir: "/x/db", local_dir: "/x/local",
                              sources_path: "/x/config/sources.yml", config_path: "/x/config/nabu.yml")
    assert_equal "/x/local/shelves/local-dates", Nabu::DateShelf.dir(config)
  end

  def test_append_round_trips_through_numbered_shards
    with_shelf do |shelf|
      first = shelf.append_batch!(records: [estimate, estimate(urn: "urn:nabu:test:b", not_before: nil)],
                                  now: Time.utc(2026, 10, 12))
      second = shelf.append_batch!(records: [estimate(not_before: -150, not_after: -120)])
      assert_equal(%w[shard-000001.jsonl shard-000002.jsonl], [first, second].map { |p| File.basename(p) })
      records = []
      shelf.each_record { |record| records << record }
      assert_equal 3, records.size
      assert_equal "2026-10-12T00:00:00Z", records.first.generated_at, "the gateway stamps generation time"
      assert_nil records[1].not_before, "an open bound survives the round trip"
      assert_empty Dir[File.join(shelf.dir, "*.tmp")], "no staging debris"
    end
  end

  def test_a_later_estimate_supersedes_an_earlier_one_for_the_same_urn
    with_shelf do |shelf|
      shelf.append_batch!(records: [estimate])
      shelf.append_batch!(records: [estimate(not_before: -150, not_after: -120, estimator_version: "0.4")])
      latest = shelf.latest_by_urn
      assert_equal 1, latest.size
      assert_equal([-150, -120, "0.4"], latest.fetch("urn:nabu:test:a")
                                              .then { |r| [r.not_before, r.not_after, r.estimator_version] })
    end
  end

  def test_invalid_records_are_refused_before_any_byte_lands
    with_shelf do |shelf|
      bad = [
        [estimate(urn: " "), /needs a urn/],
        [estimate(not_before: nil, not_after: nil), /carries no bound/],
        [estimate(not_before: 0), /no year 0/],
        [estimate(not_before: "-200"), /signed integer years/],
        [estimate(not_before: -100, not_after: -200), /is after not_after/],
        [estimate(basis: "Model Output"), /basis label/],
        [estimate(estimator: ""), /estimator provenance/],
        [estimate(confidence: 1.5), /confidence must be a number in \[0, 1\]/]
      ]
      bad.each do |record, message|
        error = assert_raises(Nabu::DateShelf::Error) { shelf.append_batch!(records: [estimate(urn: "ok"), record]) }
        assert_match message, error.message
      end
      assert_empty shelf.shard_paths, "a refused batch writes nothing — not even its valid records"
      assert_raises(Nabu::DateShelf::Error) { shelf.append_batch!(records: []) }
    end
  end

  def test_the_resolver_refuses_unknown_urns_unless_forced
    with_shelf(resolver: ->(urn) { urn == "urn:nabu:test:a" }) do |shelf|
      error = assert_raises(Nabu::DateShelf::Error) do
        shelf.append_batch!(records: [estimate, estimate(urn: "urn:nabu:test:ghost")])
      end
      assert_match(/urn:nabu:test:ghost/, error.message)
      assert_match(/--force/, error.message)
      assert_empty shelf.shard_paths
      shelf.append_batch!(records: [estimate(urn: "urn:nabu:test:ghost")], force: true)
      assert_equal 1, shelf.shard_paths.size, "force shelves material not yet held"
    end
  end

  def test_a_malformed_shard_raises_naming_file_and_line
    with_shelf do |shelf|
      shelf.append_batch!(records: [estimate])
      File.write(File.join(shelf.dir, "shard-000002.jsonl"), "{\"urn\":\"x\"}\n")
      error = assert_raises(Nabu::DateShelf::FormatError) { shelf.latest_by_urn }
      assert_match(/shard-000002\.jsonl:1/, error.message)
    end
  end

  def test_the_arm_marker_is_furniture_never_a_shard
    with_shelf do |shelf|
      refute shelf.armed?
      shelf.arm!(now: Time.utc(2026, 10, 12))
      assert shelf.armed?
      stamp = File.read(File.join(shelf.dir, Nabu::DateShelf::ARM_FILE))
      shelf.arm!(now: Time.utc(2027, 1, 1))
      assert_equal stamp, File.read(File.join(shelf.dir, Nabu::DateShelf::ARM_FILE)), "re-arm keeps the first ruling"
      assert_empty shelf.shard_paths
      shelf.disarm!
      refute shelf.armed?
    end
  end

  def test_read_import_parses_jsonl_and_names_a_bad_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, "batch.jsonl")
      File.write(path, "#{JSON.generate(estimate.to_h)}\n\n#{JSON.generate(estimate(urn: 'b').to_h)}\n")
      assert_equal %w[urn:nabu:test:a b], Nabu::DateShelf.read_import(path).map(&:urn)
      File.write(path, "#{JSON.generate(estimate.to_h)}\n[1]\n")
      error = assert_raises(Nabu::DateShelf::FormatError) { Nabu::DateShelf.read_import(path) }
      assert_match(/batch\.jsonl:2/, error.message)
    end
  end
end
