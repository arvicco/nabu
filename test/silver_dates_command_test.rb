# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# `nabu silver-dates` (P122-1): the local-dates shelf's front door —
# --import through the DateShelf gateway (urns resolved against the
# catalog), --project as the owner's arming gate, --retract, the bare
# census — and the silver class visible on the card and to --date-basis.
class SilverDatesCommandTest < Minitest::Test
  def test_import_project_show_search_retract_round_trip
    with_corpus do |config, root|
      batch = write_batch(root, [estimate("urn:t:undated", -300, -200, note: "letter forms")])

      out, _err, status = with_config(config) { run_cli(["silver-dates", "--import", batch]) }
      assert_nil status
      assert_match(/shelved 1 estimate\(s\)/, out)
      assert_match(/silver-dates --project/, out, "an unarmed import names the gate")
      assert_equal 0, silver_rows(config), "importing never touches the timeline"

      out, _err, status = with_config(config) { run_cli(%w[silver-dates --project]) }
      assert_nil status
      assert_match(/projected 1 silver date\(s\)/, out)
      assert_match(/lemma rollups re-derived/, out)
      assert_equal 1, silver_rows(config)

      out, = with_config(config) { run_cli(%w[show urn:t:undated]) }
      assert_match(/date: 300–200 BCE \[silver — model estimate — chronos 0\.3, confidence 0\.8: letter forms\]/, out)

      out, = with_config(config) { run_cli(%w[search --date-basis silver]) }
      assert_match("urn:t:undated:1", out)
      refute_match("urn:t:dated:1", out)
      out, = with_config(config) { run_cli(%w[search --from -400 --to -100]) }
      refute_match("urn:t:undated:1", out, "a plain window never reads an estimate")

      out, = with_config(config) { run_cli(%w[silver-dates]) }
      assert_match(/1 estimate\(s\) in 1 shard\(s\), 1 document urn\(s\)/, out)
      assert_match(/ARMED/, out)
      assert_match(/1 silver date row\(s\) on the timeline/, out)

      out, _err, status = with_config(config) { run_cli(%w[silver-dates --retract]) }
      assert_nil status
      assert_match(/retracted 1 silver date\(s\)/, out)
      assert_equal 0, silver_rows(config)
      refute Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config)).armed?
      assert_equal 1, Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config)).shard_paths.size,
                   "retract keeps the shelf — estimates are permanent"
    end
  end

  def test_import_refuses_unknown_urns_unless_forced
    with_corpus do |config, root|
      batch = write_batch(root, [estimate("urn:t:ghost", -300, -200)])
      _out, err, status = with_config(config) { run_cli(["silver-dates", "--import", batch]) }
      assert_equal 1, status
      assert_match(/urn:t:ghost/, err)
      assert_empty Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config)).shard_paths

      _out, _err, status = with_config(config) { run_cli(["silver-dates", "--import", batch, "--force"]) }
      assert_nil status
      assert_equal 1, Nabu::DateShelf.new(dir: Nabu::DateShelf.dir(config)).shard_paths.size
    end
  end

  def test_invalid_estimates_and_mode_clashes_exit_one
    with_corpus do |config, root|
      batch = write_batch(root, [estimate("urn:t:undated", 0, 10)])
      _out, err, status = with_config(config) { run_cli(["silver-dates", "--import", batch]) }
      assert_equal 1, status
      assert_match(/no year 0/, err)

      _out, err, status = with_config(config) { run_cli(%w[silver-dates --project --retract]) }
      assert_equal 1, status
      assert_match(%r{one of --import/--project/--retract}, err)

      _out, err, status = with_config(config) { run_cli(%w[silver-dates --project]) }
      assert_equal 1, status
      assert_match(/shelf .* is empty/, err)
    end
  end

  private

  def estimate(urn, not_before, not_after, note: nil)
    { "urn" => urn, "not_before" => not_before, "not_after" => not_after, "basis" => "model",
      "estimator" => "chronos", "estimator_version" => "0.3", "confidence" => 0.8, "note" => note }
  end

  def write_batch(root, estimates)
    path = File.join(root, "batch.jsonl")
    File.write(path, estimates.map { |e| JSON.generate(e) }.join("\n") << "\n")
    path
  end

  def silver_rows(config)
    db = Nabu::Store.connect(config.catalog_path)
    db[:document_axes].where(axis_source: Nabu::Store::SilverDates::AXIS_SOURCE).count
  ensure
    db&.disconnect
  end

  # One dated and one undated Greek document, indexed, rollups built.
  def with_corpus
    Dir.mktmpdir("nabu-silver-dates") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = db[:sources].insert(slug: "p", name: "P", adapter_class: "TestAdapter", license_class: "open",
                                   enabled: true)
      { "urn:t:dated" => [-113, -113], "urn:t:undated" => nil }.each do |urn, bounds|
        doc = db[:documents].insert(source_id: source, urn: urn, title: urn, language: "grc",
                                    content_sha256: "x", revision: 1, withdrawn: false)
        db[:passages].insert(document_id: doc, urn: "#{urn}:1", sequence: 0, language: "grc",
                             text: "στρατηγος",
                             text_normalized: Nabu::Normalize.search_form("στρατηγος", language: "grc"),
                             content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}")
        next unless bounds

        db[:document_axes].insert(document_id: doc, not_before: bounds[0], not_after: bounds[1],
                                  precision: "low", axis_source: "hgv")
      end
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      fulltext.disconnect
      db.disconnect
      yield config, root
    end
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
