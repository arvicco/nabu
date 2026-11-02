# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The local-meter shelf's sanctioned write gateway (P152, architecture
# §16): the scansion lane's machine output as append-only JSONL shards
# under local/shelves/local-meter/, written ONLY through Nabu::MeterShelf,
# plus the owner's projection ruling as shelf furniture.
class MeterShelfTest < Minitest::Test
  def with_shelf
    Dir.mktmpdir("nabu-meter-shelf") { |root| yield Nabu::MeterShelf.new(dir: File.join(root, "local-meter")) }
  end

  def scanned(urn: "urn:t:1", **over)
    Nabu::MeterShelf::Record.new(kind: "passage", urn: urn, language: "lat", content_sha256: "abc",
                                 status: "scanned", meter: "hexameter", feet: "DDSSD",
                                 quantities: "-uu-uu-----uu--", word_pattern: "-u u-u", basis: "unique",
                                 scanner: "nabu-scan", scanner_version: "nabu-scan/1", **over)
  end

  def test_the_shelf_lives_under_local_shelves
    config = Nabu::Config.new(canonical_dir: "/x/canonical", db_dir: "/x/db", local_dir: "/x/local",
                              sources_path: "/x/config/sources.yml", config_path: "/x/config/nabu.yml")
    assert_equal "/x/local/shelves/local-meter", Nabu::MeterShelf.dir(config)
  end

  def test_append_round_trips_and_a_later_record_supersedes
    with_shelf do |shelf|
      first = shelf.append_batch!(records: [scanned, scanned(urn: "urn:t:2")], now: Time.utc(2026, 11, 2))
      shelf.append_batch!(records: [scanned(feet: "SSSSD", quantities: "------------uu--")])
      assert_equal "shard-000001.jsonl", File.basename(first)
      assert_equal 2, shelf.shard_paths.size
      latest = shelf.latest_by_urn
      assert_equal "SSSSD", latest["urn:t:1"].feet
      assert_equal "2026-11-02T00:00:00Z", latest["urn:t:2"].generated_at, "stamped at landing"
    end
  end

  def test_unscanned_and_document_gate_records
    with_shelf do |shelf|
      unscanned = Nabu::MeterShelf::Record.new(kind: "passage", urn: "urn:t:3", language: "grc",
                                               content_sha256: "x", status: "unscanned", reason: "no_fit",
                                               scanner: "nabu-scan", scanner_version: "nabu-scan/1")
      gate = Nabu::MeterShelf::Record.new(kind: "document", urn: "urn:t:doc", passages: 40, scanned: 0,
                                          scanner: "nabu-scan", scanner_version: "nabu-scan/1")
      shelf.append_batch!(records: [unscanned, gate])
      kinds = []
      shelf.each_record { |r| kinds << [r.kind, r.status] }
      assert_equal [%w[passage unscanned], ["document", nil]], kinds
    end
  end

  def test_invalid_records_never_land
    with_shelf do |shelf|
      assert_raises(Nabu::MeterShelf::Error) { shelf.append_batch!(records: [scanned(feet: "XX")]) }
      assert_raises(Nabu::MeterShelf::Error) { shelf.append_batch!(records: [scanned(scanner_version: "")]) }
      assert_raises(Nabu::MeterShelf::Error) { shelf.append_batch!(records: [scanned(content_sha256: nil)]) }
      assert_raises(Nabu::MeterShelf::Error) do
        shelf.append_batch!(records: [scanned(status: "unscanned", meter: nil, feet: nil, quantities: nil)])
      end
      assert_raises(Nabu::MeterShelf::Error) { shelf.append_batch!(records: []) }
      assert_empty shelf.shard_paths
      refute Dir.exist?(shelf.dir) && !Dir.empty?(shelf.dir), "nothing staged survives a refusal"
    end
  end

  def test_a_malformed_shard_fails_loud_naming_file_and_line
    with_shelf do |shelf|
      shelf.append_batch!(records: [scanned])
      File.write(shelf.shard_paths.first, "{not json\n", mode: "a")
      error = assert_raises(Nabu::MeterShelf::FormatError) { shelf.each_record { nil } }
      assert_match(/shard-000001\.jsonl:2/, error.message)
    end
  end

  def test_the_census_names_code_staleness
    with_shelf do |shelf|
      shelf.append_batch!(records: [scanned, scanned(urn: "urn:t:2", scanner_version: "nabu-scan/0")],
                          now: Time.utc(2026, 11, 1))
      census = Nabu::MeterShelf::Census.of(shelf, current: "nabu-scan/1")
      assert_equal [2, 0, 0, 1], [census.scanned, census.unscanned, census.gates, census.old_code]
      assert_equal({ "nabu-scan/0" => 1, "nabu-scan/1" => 1 }, census.versions)
      assert_equal "2026-11-01T00:00:00Z", census.newest
    end
  end

  def test_the_arm_marker
    with_shelf do |shelf|
      refute_predicate shelf, :armed?
      shelf.arm!(now: Time.utc(2026, 11, 2))
      shelf.arm!(now: Time.utc(2027, 1, 1))
      assert_predicate shelf, :armed?
      assert_includes File.read(File.join(shelf.dir, ".projection-armed.json")), "2026-11-02"
      assert_empty shelf.shard_paths, "furniture is never a shard"
      shelf.disarm!
      refute_predicate shelf, :armed?
    end
  end
end
