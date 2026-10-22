# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu person mine SOURCE [AUTHORITY]` — the census-only person-index
# scan, its scope explicit (which source's text × which authority's
# keys) — and `nabu person candidates SOURCE [--dry-run]`, the
# person-name candidate recipe: a links-journal producer whose scope is
# recorded for the rebuild's links stage (config/mined_layers.yml:
# cheap), its edges labelled candidates, never persons.
class PersonCommandTest < Minitest::Test
  Person = Nabu::Store::PersonIndex::Person

  LINES = ["Dis Manibus", "Dis Manibus", "Dis Manibus sacrum", "Caius Sextius Paris",
           "Caius Iulius Cai filius Optatus", "Caius filius"].freeze

  def test_person_mine_names_its_authority_and_lane_and_writes_nothing
    with_person_env do |config|
      out, err, status = with_config(config) { run_cli(%w[person mine edh edh]) }
      assert_nil status, err
      assert_match(/person mine: edh × edh \(word lane\) — 6 passages scanned against 1 name keys/, out)
      assert_match(/sextius paris\s+1 passages/, out)
      assert_match(/census only/, out)
      refute_path_exists config.links_path, "the census writes no journal"
      refute_path_exists config.link_scopes_path, "and records no scope"
    end
  end

  def test_person_mine_refuses_an_underived_authority_by_name
    with_person_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[person mine edh elephantine]) }
      assert_equal 1, status
      assert_match(/the "elephantine" person-index slice is not derived/, err)
    end
  end

  def test_person_candidates_dry_run_prints_the_census_and_writes_nothing
    with_person_env do |config|
      out, err, status = with_config(config) { run_cli(%w[person candidates edh --dry-run]) }
      assert_nil status, err
      assert_match(/person candidates: edh — 6 passages, \d+ words, 3 name candidates/, out)
      assert_match(/Caius\s+3 occurrences/, out)
      assert_match(/dry run — nothing written/, out)
      refute_path_exists config.links_path
      refute_path_exists config.link_scopes_path
    end
  end

  def test_person_candidates_mines_labelled_edges_and_records_the_scope
    with_person_env do |config|
      out, err, status = with_config(config) { run_cli(%w[person candidates edh]) }
      assert_nil status, err
      assert_match(/9 candidate edges written/, out)
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      assert_equal ["person-name-candidate"], journal[:links].select_map(:kind).uniq
      journal.disconnect
      assert_equal [{ "producer" => "person-candidates", "scope" => "edh", "params" => {} }],
                   Nabu::LinkScopes.load(config.link_scopes_path),
                   "the rebuild's links stage re-mints the scope (a cheap lane)"
    end
  end

  def test_usage_errors_name_the_scope_grammar
    with_person_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[person candidates]) }
      assert_equal 1, status
      assert_match(/usage: nabu person candidates SOURCE \[--dry-run\]/, err)
    end
  end

  # A name with no derived-authority card still answers from the
  # person-shaped document facets, each value with its sources (real
  # catalogue values: the oracc/cdli ruler facet).
  def test_person_lists_catalogue_mentions_with_their_sources
    Dir.mktmpdir("nabu-cli-person") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: File.join(root, "config", "nabu.yml"))
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      { "cdli" => 2, "oracc" => 1 }.each do |slug, docs|
        source = catalog[:sources].insert(slug: slug, name: slug, adapter_class: "T", license_class: "open",
                                          enabled: true)
        docs.times do |i|
          id = catalog[:documents].insert(source_id: source, urn: "urn:#{slug}:#{i}", title: "t", language: "akk",
                                          content_sha256: "x", revision: 1, withdrawn: false)
          catalog[:document_facets].insert(document_id: id, facet: "ruler", value: "Esarhaddon")
        end
      end
      catalog.disconnect

      out, _err, status = with_config(config) { run_cli(%w[person Esarhaddon]) }
      assert_nil status
      assert_match(/catalogue mentions \(document facets — names as catalogued, no person id\):/, out)
      assert_match(/  Esarhaddon  \[ruler\]  cdli 2 · oracc 1/, out)

      _out, err, status = with_config(config) { run_cli(%w[person Nabonidus]) }
      assert_equal 1, status
      assert_match(/no person named "Nabonidus"/, err)
    end
  end

  private

  def with_person_env
    Dir.mktmpdir("nabu-person-cli") do |root|
      sources = File.join(root, "config", "sources.yml")
      FileUtils.mkdir_p(File.dirname(sources))
      File.write(sources, "# none\n")
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: File.join(root, "config", "nabu.yml"))
      FileUtils.mkdir_p(config.db_dir)
      seed(config)
      yield config
    end
  end

  def seed(config)
    catalog = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(catalog)
    Nabu::Store.setup!(catalog)
    src = catalog[:sources].insert(slug: "edh", name: "EDH", adapter_class: "TestAdapter",
                                   license_class: "attribution", enabled: true)
    doc = catalog[:documents].insert(source_id: src, urn: "urn:nabu:edh:HD000001", title: "t", language: "lat",
                                     content_sha256: "x", revision: 1, withdrawn: false)
    LINES.each_with_index do |text, i|
      catalog[:passages].insert(document_id: doc, urn: "urn:nabu:edh:HD000001:#{i}", sequence: i, language: "lat",
                                text: text, text_normalized: text.downcase, content_sha256: "x#{i}",
                                revision: 1, withdrawn: false, annotations_json: "{}")
    end
    Nabu::Store::PersonIndex.derive!(
      catalog, authority: "edh",
               persons: [Person.new(authority: "edh", person_id: "HD000002/1", name: "C. Sextius Paris",
                                    name_han: nil, birth_year: nil, death_year: nil, index_year: nil,
                                    dynasty: nil, dynasty_han: nil, female: false,
                                    name_keys: ["sextius paris"])]
    )
    catalog.disconnect
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
