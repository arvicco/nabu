# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# `nabu scan-meter` (P152): the scansion lane's operator surface — the
# gold validation, the campaign onto the local-meter shelf, the owner's
# projection gate, and the census. A tiny file catalog: one Latin verse
# document carrying pedecerto gold on its first line.
class ScanMeterCommandTest < Minitest::Test
  LINES = [
    "Arma virumque cano, Troiae qui primus ab oris",
    "litora, multum ille et terris iactatus et alto",
    "Arma gravi numero violentaque bella parabam",
    "edere, materia conveniente modis."
  ].freeze

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

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def with_world
    Dir.mktmpdir("nabu-scan-meter") do |root|
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                local_dir: File.join(root, "local"), sources_path: File.join(root, "sources.yml"),
                                config_path: File.join(root, "config", "nabu.yml"))
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      src = catalog[:sources].insert(slug: "perseus-lat", name: "P", adapter_class: "X", license_class: "open")
      doc = catalog[:documents].insert(source_id: src, urn: "urn:cts:latinLit:phi0690.phi003.t", language: "lat",
                                       content_sha256: "x")
      ids = LINES.each_with_index.map do |text, i|
        catalog[:passages].insert(document_id: doc, urn: "urn:cts:latinLit:phi0690.phi003.t:1.#{i + 1}",
                                  sequence: i, language: "lat", text: text, text_normalized: text,
                                  content_sha256: "sha-#{i}")
      end
      catalog[:enrichments].insert(passage_id: ids[0], kind: "meter", model: "pedecerto", model_version: "t",
                                   payload_json: JSON.generate("meter" => "H", "pattern" => "DDSS"), at: Time.now)
      catalog.disconnect
      yield config
    end
  end

  def test_validate_scores_the_scanner_against_the_held_gold
    with_world do |config|
      out, _err, status = with_config(config) { run_cli(%w[scan-meter --validate]) }
      assert_nil status
      assert_match(%r{lat / hexameter / dev\s+1 lines\s+agree 100\.0%}, out)
      assert_match(/dev split = /, out)
    end
  end

  def test_run_project_census_and_retract
    with_world do |config|
      out, = with_config(config) { run_cli(%w[scan-meter --run]) }
      assert_match(/1 verse/, out)
      assert_match(/not yet in the meter layer/, out)

      out, = with_config(config) { run_cli(%w[scan-meter --project]) }
      assert_match(/projected 3 silver scansion\(s\) — 1 gold-covered/, out)

      out, = with_config(config) { run_cli(%w[scan-meter]) }
      assert_match(/4 scanned \+ 0 unscanned line\(s\)/, out)
      assert_match(/ARMED/, out)
      assert_match(/3 silver scansion row\(s\) in the meter layer/, out)

      out, = with_config(config) { run_cli(%w[scan-meter --retract]) }
      assert_match(/retracted 3 silver scansion\(s\)/, out)
    end
  end

  def test_modes_are_exclusive
    with_world do |config|
      _out, err, status = with_config(config) { run_cli(%w[scan-meter --run --project]) }
      refute_nil status
      assert_match(/one of/, err)
    end
  end
end
