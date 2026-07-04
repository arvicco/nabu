# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"

# Golden-query smoke suite (docs/maintenance-and-extension.md §6). Builds ONE
# full fixture corpus — every adapter loaded into a single store and indexed —
# and asserts, per YAML entry, that a known query returns its expected passage
# urn (membership, not rank or snippet). The YAML is the data; this file only
# iterates it.
#
# Doubles as the cross-adapter integration test: six adapters, one catalog, one
# FTS index. A urn collision across adapters, or a broken indexer/search seam,
# fails here where per-adapter unit tests would not.
class GoldenTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures", __dir__)
  QUERIES = YAML.safe_load_file(File.expand_path("golden/golden_queries.yml", __dir__)).freeze

  # slug, adapter class name, fixture workdir (under test/fixtures/).
  SOURCES = [
    ["perseus-greek", "Nabu::Adapters::Perseus",              %w[perseus greekLit]],
    ["first1k",       "Nabu::Adapters::First1kGreek",         %w[first1k greekLit]],
    ["ud",            "Nabu::Adapters::UniversalDependencies", %w[ud]],
    ["proiel",        "Nabu::Adapters::Proiel",               %w[proiel]],
    ["torot",         "Nabu::Adapters::Torot",                %w[torot]],
    ["papyri",        "Nabu::Adapters::Papyri",               %w[ddbdp]]
  ].freeze

  class << self
    # Built once (the fixtures are small); cleaned up after the whole run.
    def corpus
      @corpus ||= build_corpus
    end

    def build_corpus
      dir = Dir.mktmpdir("nabu-golden")
      Minitest.after_run { FileUtils.rm_rf(dir) }
      db = Nabu::Store.connect(File.join(dir, "catalog.sqlite3"))
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      ft = Nabu::Store.connect_fulltext(File.join(dir, "fulltext.sqlite3"))
      SOURCES.each { |slug, class_name, path| load_source(db, slug, class_name, path) }
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: ft)
      { db: db, ft: ft }
    end

    def load_source(db, slug, class_name, path)
      adapter = Object.const_get(class_name).new
      source = Nabu::Store::Source.create(
        slug: slug, name: slug, adapter_class: class_name, license_class: adapter.manifest.license_class
      )
      report = Nabu::Store::Loader.new(db: db, source: source)
                                  .load_from(adapter, workdir: File.join(FIXTURES, *path), full: true)
      raise "golden corpus: #{slug} quarantined #{report.errored} document(s)" if report.errored.positive?
    end
  end

  def search
    corpus = self.class.corpus
    Nabu::Query::Search.new(catalog: corpus[:db], fulltext: corpus[:ft])
  end

  # One independent test per YAML entry, so a single failing golden query names
  # itself in the output.
  QUERIES.each_with_index do |entry, index|
    define_method(:"test_golden_query_#{format('%02d', index)}_#{entry['lang'] || 'nolang'}") do
      results = search.run(entry["query"], lang: entry["lang"])
      urns = results.map(&:urn)
      assert_includes urns, entry["expect_urn"],
                      "golden query #{entry['query'].inspect} (lang=#{entry['lang'].inspect}) " \
                      "must return #{entry['expect_urn']}; got #{urns.inspect}\nnote: #{entry['note']}"
    end
  end

  # The packet requires ≥6 queries spanning grc/lat/got/chu/orv, with one
  # diacritic-folded and one gap-adjacent case; guard that the data still does.
  def test_suite_spans_the_required_languages
    assert_operator QUERIES.size, :>=, 6, "need at least six golden queries"
    langs = QUERIES.filter_map { |entry| entry["lang"] }.uniq
    %w[chu got grc lat orv].each { |lang| assert_includes langs, lang }
  end

  def test_every_source_loaded_and_indexed_without_quarantine
    corpus = self.class.corpus
    assert_equal SOURCES.size, corpus[:db][:sources].count
    assert_operator corpus[:ft][Nabu::Store::Indexer::TABLE].count, :>, 0
  end
end
