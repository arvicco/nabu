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

  # -- the thesis-grade kinds (P145) -------------------------------------------

  def test_align_with_morph_writes_jsonl_pairs_with_a_manifest
    with_export_env do |config|
      seed_alignment(config)
      out, err, status = with_config(config) { run_cli(%w[export align MARK 2.3 --with-morph]) }
      assert_nil status, err
      assert_match(/align: 1 rows .*align\.jsonl/, out)
      line = JSON.parse(File.read(File.join(config.exports_dir, "align.jsonl")))
      assert_equal %w[gr la], line.values_at("base_witness", "witness")
      assert_equal %w[open nc], line.values_at("base_license_class", "witness_license_class")
      assert_equal({ "form" => "venerunt", "lemma" => "venio", "feats" => "number=plur", "citation" => "MARK 2.3" },
                   line.fetch("witness_tokens").first)
      manifest = YAML.safe_load_file(File.join(config.exports_dir, "align.manifest.yml"))
      assert_equal "MARK 2.3", manifest.dig("filters", "ref")
      assert_equal(%w[alpha beta], manifest.fetch("sources").map { |entry| entry["source"] })
      _out, err, status = with_config(config) { run_cli(%w[export align MARK 2.3 --with-morph --format csv]) }
      assert_equal 1, status
      assert_match(/use --format jsonl/, err)
    end
  end

  def test_collation_writes_reading_rows
    with_export_env do |config|
      seed_alignment(config)
      _out, err, status = with_config(config) { run_cli(%w[export collation --work nt]) }
      assert_nil status, err
      table = CSV.read(File.join(config.exports_dir, "collation.csv"), headers: true)
      assert_equal([%w[gr uncollated open], %w[la uncollated nc]],
                   table.map { |row| row.values_at("witness", "role", "license_class") })
      assert_equal ["urn:a:al:s0"], table.map { |row| row["urns"] }.first(1)
    end
  end

  def test_stratified_passages_write_a_sample_table_and_refuse_stray_flags
    with_export_env do |config|
      argv = %w[export passages --stratum language --per-cell 1 --format csv --exclude-ocr]
      out, err, status = with_config(config) { run_cli(argv) }
      assert_nil status, err
      assert_match(/passage_sample: 2 rows .*passage_sample\.csv/, out)
      table = CSV.read(File.join(config.exports_dir, "passage_sample.csv"), headers: true)
      assert_equal(%w[grc lat], table.map { |row| row["language"] })
      assert_equal(%w[1 1], table.map { |row| row["cell_sampled"] })
      manifest = YAML.safe_load_file(File.join(config.exports_dir, "passage_sample.manifest.yml"))
      assert_equal 0, manifest.dig("notes", "ocr_documents_excluded")
      _out, err, status = with_config(config) { run_cli(%w[export passages --format plain --per-cell 3]) }
      assert_equal 1, status
      assert_match(/--per-cell needs --stratum/, err)
      _out, err, status = with_config(config) { run_cli(%w[export passages --stratum era --format csv]) }
      assert_equal 1, status
      assert_match(/unknown stratum "era"/, err)
    end
  end

  def test_help_carries_the_new_kinds_with_examples
    out, _err, _status = run_cli(%w[help export])
    %w[align collation].each { |name| assert_match(/export #{name}/, out) }
    out, _err, _status = run_cli(%w[export align --help])
    assert_match(/nabu export align MARK 2 --with-morph/, out)
    out, _err, _status = run_cli(%w[export collation --help])
    assert_match(/nabu export collation MARK 2/, out)
    out, _err, _status = run_cli(%w[export passages --help])
    assert_match(/--stratum language,century,script/, out)
    assert_match(/--exclude-ocr/, out)
  end

  private

  # Two witnesses of MARK 2.3 (alpha open grc, beta nc lat) in the catalog,
  # a registry naming them, and the ref index built in fulltext.
  def seed_alignment(config)
    catalog = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.setup!(catalog)
    [["urn:a:al", "alpha", "grc", "καὶ ἔρχονται", [{ "form" => "καὶ" }]],
     ["urn:b:al", "beta", "lat", "venerunt",
      [{ "form" => "venerunt", "lemma" => "venio", "feats" => "Number=Plur" }]]].each do |urn, slug, lang, text, toks|
      source_id = catalog[:sources].where(slug: slug).get(:id)
      doc_id = catalog[:documents].insert(source_id: source_id, urn: urn, title: urn, language: lang,
                                          content_sha256: "x", revision: 1, withdrawn: false)
      tokens = toks.map { |token| token.merge("citation_part" => "MARK 2.3") }
      catalog[:passages].insert(document_id: doc_id, urn: "#{urn}:s0", sequence: 0, language: lang, text: text,
                                text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
                                annotations_json: JSON.generate("tokens" => tokens))
    end
    File.write(config.alignments_path, <<~YAML)
      nt:
        title: NT
        witnesses:
          - document: urn:a:al
            label: gr
          - document: urn:b:al
            label: la
    YAML
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    Nabu::Store::AlignmentIndexer.rebuild!(catalog: catalog, fulltext: fulltext,
                                           registry: Nabu::AlignmentRegistry.load(config.alignments_path))
    fulltext.disconnect
    catalog.disconnect
  end

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
