# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"
require "json"
require "yaml"

# `nabu export` (P121-1): the research exporter's CLI — `documents` and
# `links` write a data file + license manifest into exports/ (or --out),
# and the passage stream stays the family's default command, so
# `nabu export --format jsonl` is byte-unchanged. Every case runs against a
# throwaway root with a migrated catalog and links journal.
class ExportCommandTest < Minitest::Test
  def test_documents_lands_in_exports_with_its_manifest
    with_export_env do |config|
      out, err, status = with_config(config) { run_cli(%w[export documents --with-axes]) }
      assert_nil status, err
      data = File.join(config.exports_dir, "documents.csv")
      manifest = File.join(config.exports_dir, "documents.manifest.yml")
      assert_match(/3 rows .*documents\.csv/, out)
      assert_match(/manifest .*documents\.manifest\.yml/, out)
      assert_match(/in \d/, out, "the summary carries elapsed time")
      table = CSV.read(data, headers: true)
      assert_equal(%w[urn:a:1 urn:a:2 urn:b:1], table.map { |row| row["urn"] })
      assert_includes table.headers, "not_before", "--with-axes widens the table"
      sources = YAML.safe_load_file(manifest).fetch("sources")
      assert_equal [{ "source" => "alpha", "license_class" => "open", "rows" => 2 },
                    { "source" => "beta", "license_class" => "nc", "rows" => 1 }], sources
    end
  end

  def test_documents_filters_and_license_class_list_and_out_dir
    with_export_env do |config|
      Dir.mktmpdir do |out_dir|
        argv = %W[export documents --license-class open,attribution --lang lat --from -200 --to 100
                  --out #{out_dir} --format jsonl]
        _out, err, status = with_config(config) { run_cli(argv) }
        assert_nil status, err
        lines = File.readlines(File.join(out_dir, "documents.jsonl")).map { |line| JSON.parse(line) }
        assert_equal(%w[urn:a:1], lines.map { |line| line["urn"] })
        filters = YAML.safe_load_file(File.join(out_dir, "documents.manifest.yml")).fetch("filters")
        assert_equal %w[open attribution], filters.fetch("license_class")
        assert_equal [-200, 100], filters.values_at("from", "to")
        refute File.exist?(config.exports_dir), "--out overrides the default home"
      end
    end
  end

  def test_links_dump_with_kind_and_dated
    with_export_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[export links --kind parallel --dated]) }
      assert_nil status, err
      table = CSV.read(File.join(config.exports_dir, "links.csv"), headers: true)
      assert_equal([["urn:a:1:1", "urn:b:1:1", "-100"]], table.map do |row|
        row.values_at("from_urn", "to_urn", "from_not_before")
      end)
      manifest = YAML.safe_load_file(File.join(config.exports_dir, "links.manifest.yml"))
      assert_equal({ "kind" => %w[parallel], "dated" => true, "license_class" => nil }, manifest.fetch("filters"))
    end
  end

  def test_refusals_are_clean_errors
    with_export_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[export documents --license-class bogus]) }
      assert_equal 1, status
      assert_match(/bogus/, err)
      _out, err, status = with_config(config) { run_cli(%w[export documents --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
      _out, err, status = with_config(config) { run_cli(%w[export documents --format xml]) }
      assert_equal 1, status
      assert_match(/csv, jsonl/, err)
    end
  end

  def test_links_without_a_journal_says_so
    with_export_env(links: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[export links]) }
      assert_equal 1, status
      assert_match(/no links journal/, err)
    end
  end

  def test_help_names_every_table_and_the_passage_stream
    out, _err, _status = run_cli(%w[help export])
    %w[documents links passages].each { |name| assert_match(/export #{name}/, out) }
    assert_match(/manifest/, out)
    out, _err, _status = run_cli(%w[export documents --help])
    assert_match(/--with-axes/, out)
    assert_match(/--license-class/, out)
  end

  def test_the_passage_stream_stays_the_default_command
    with_export_env do |config|
      out, err, status = with_config(config) { run_cli(%w[export --format plain --source alpha]) }
      assert_nil status, err
      assert_equal %w[t t], out.split("\n")
      out, err, status = with_config(config) { run_cli(%w[export passages --format plain --source beta]) }
      assert_nil status, err
      assert_equal %w[t], out.split("\n")
    end
  end

  private

  def with_export_env(links: true)
    Dir.mktmpdir("nabu-export") do |root|
      sources = File.join(root, "config", "sources.yml")
      FileUtils.mkdir_p(File.dirname(sources))
      File.write(sources, "# none\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: File.join(root, "config", "nabu.yml"))
      FileUtils.mkdir_p(config.db_dir)
      seed_catalog(config)
      seed_links(config) if links
      yield config
    end
  end

  def seed_catalog(config)
    catalog = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(catalog)
    Nabu::Store.setup!(catalog)
    alpha = Nabu::Store::Source.create(slug: "alpha", name: "Alpha", adapter_class: "TestAdapter",
                                       license_class: "open")
    beta = Nabu::Store::Source.create(slug: "beta", name: "Beta", adapter_class: "TestAdapter", license_class: "nc")
    a1 = seed_document(alpha, "urn:a:1", "lat")
    catalog[:document_axes].insert(document_id: a1.id, axis_source: "test", not_before: -100, not_after: -50)
    seed_document(alpha, "urn:a:2", "grc")
    seed_document(beta, "urn:b:1", "lat")
    catalog.disconnect
  end

  def seed_document(source, urn, language)
    doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: language,
                                       content_sha256: "x", revision: 1, withdrawn: false)
    Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1", sequence: 1, language: language, text: "t",
                                text_normalized: "t", content_sha256: "x", revision: 1, withdrawn: false)
    doc
  end

  def seed_links(config)
    journal = Nabu::Store::LinksJournal.open!(config.links_path)
    run = Nabu::Store::LinksJournal.record_run!(journal, producer: "parallels", scope: "alpha", params: {},
                                                         code_version: "test/1")
    Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:a:1:1", to_urn: "urn:b:1:1", kind: "parallel",
                                                   score: 0.9, run_id: run)
    Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:a:2:1", to_urn: "urn:b:1:1", kind: "formula",
                                                   score: 0.4, run_id: run)
    journal.disconnect
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
