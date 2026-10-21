# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu list` / `nabu status` rows for the two non-document grains: a
# kind: module row holds zero catalog rows BY INVARIANT, so "empty" was a
# document-grain lie — it renders its seam census (nabu-lects, read from
# canonical/) or, census-less, the pin it is held at; a dictionary row
# counts its dictionaries beside the entries (dicts/entries, docs/pass's
# twin). Every other row is byte-identical — pinned here.
class ListModuleRowsTest < Minitest::Test
  def run_cli(argv)
    status = nil
    out, err = capture_io do
      Nabu::CLI.start(argv)
    rescue SystemExit => e
      status = e.status
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

  def with_rig
    Dir.mktmpdir("nabu-list-modules") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, <<~YAML)
        nabu-lects:
          adapter: Nabu::Adapters::NabuLects
          kind: module
          wired: true
          sync_policy: manual
        nabu-places:
          adapter: Nabu::Adapters::NabuPlaces
          kind: module
          wired: true
          sync_policy: manual
        lex:
          adapter: TestAdapter
          wired: true
          sync_policy: frozen
        plain:
          adapter: TestAdapter
          wired: true
          sync_policy: manual
        bare:
          adapter: TestAdapter
          wired: true
          sync_policy: manual
      YAML
      config = Nabu::Config.new(canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
                                sources_path: sources, config_path: File.join(root, "config", "nabu.yml"))
      lects_dir = File.join(config.canonical_dir, "nabu-lects")
      FileUtils.mkdir_p(lects_dir)
      %w[lects.yml codemap.yml].each do |name|
        FileUtils.cp(File.join(Nabu::TestSupport.fixtures("nabu-lects"), name), lects_dir)
      end
      FileUtils.mkdir_p(config.db_dir)
      seed(config)
      yield config
    end
  end

  def seed(config)
    catalog = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(catalog)
    Nabu::Store.setup!(catalog)
    catalog[:sources].insert(slug: "nabu-lects", name: "nabu-lects", adapter_class: "Nabu::Adapters::NabuLects",
                             license_class: "attribution", enabled: true, last_sync_sha: "a" * 40)
    catalog[:sources].insert(slug: "nabu-places", name: "nabu-places", adapter_class: "Nabu::Adapters::NabuPlaces",
                             license_class: "attribution", enabled: true, last_sync_sha: "0123456789abcdef" * 2)
    lex = catalog[:sources].insert(slug: "lex", name: "Lexica", adapter_class: "TestAdapter",
                                   license_class: "attribution", enabled: true)
    %w[sla-pro ine-pro].each_with_index do |slug, d|
      dict = catalog[:dictionaries].insert(source_id: lex, slug: slug, title: slug, language: slug)
      catalog[:dictionary_entries].insert(
        dictionary_id: dict, urn: "urn:nabu:dict:#{slug}:n", entry_id: "n#{d}", key_raw: "h",
        headword: "h", headword_folded: "h", gloss: "g", body: "b", content_sha256: "x", revision: 1,
        withdrawn: false
      )
    end
    plain = catalog[:sources].insert(slug: "plain", name: "Plain", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
    doc = catalog[:documents].insert(source_id: plain, urn: "urn:nabu:plain:d", title: "d", language: "grc",
                                     content_sha256: "x", revision: 1)
    catalog[:passages].insert(document_id: doc, urn: "urn:nabu:plain:d:1", sequence: 0, language: "grc",
                              text: "α", text_normalized: "α", content_sha256: "x", revision: 1)
    catalog[:sources].insert(slug: "bare", name: "Bare", adapter_class: "TestAdapter",
                             license_class: "open", enabled: true)
    Nabu::Store::SourceStats.derive!(catalog, note: "test seed")
    catalog.disconnect
  end

  def test_list_census_rows_per_kind
    with_rig do |config|
      out, _err, status = with_config(config) { run_cli(["list"]) }
      assert_nil status
      assert_match(/^nabu-lects\s+249 anchors · 130 stages · 27 varieties · 158 codemap rows  license=attribution$/,
                   out)
      assert_match(/^nabu-places\s+module @ 0123456789ab  license=attribution$/, out)
      assert_match(/^lex\s+dicts=2 entries=2  langs=ine-pro,sla-pro  license=attribution$/, out)
      # Byte-identical non-module, non-dictionary rows.
      assert_match(/^plain        docs=1 pass=1  langs=grc  license=open$/, out)
      assert_match(/^bare         empty  license=open$/, out, "a genuinely empty SOURCE still says so")
      refute_match(/^nabu-(lects|places)\s+empty/, out)
    end
  end

  def test_list_cards_per_kind
    with_rig do |config|
      out, = with_config(config) { run_cli(%w[list nabu-lects]) }
      assert_match(/^  249 anchors · 130 stages · 27 varieties · 158 codemap rows$/, out)
      out, = with_config(config) { run_cli(%w[list nabu-places]) }
      assert_match(/^  module @ 0123456789ab$/, out)
      out, = with_config(config) { run_cli(%w[list lex]) }
      assert_match(/^  dicts=2 entries=2$/, out)
      out, = with_config(config) { run_cli(%w[list plain]) }
      assert_match(/^  docs=1 pass=1$/, out)
    end
  end

  def test_status_detail_and_long_carry_the_module_census
    with_rig do |config|
      out, = with_config(config) { run_cli(%w[status nabu-lects]) }
      assert_match(/holds:\s+249 anchors · 130 stages · 27 varieties · 158 codemap rows/, out)
      out, = with_config(config) { run_cli(%w[status --long]) }
      assert_match(/nabu-lects\s+-\s+module\s+up=module\s+249 anchors/, out)
      assert_match(/nabu-places\s+-\s+module\s+up=module\s+module @ 0123456789ab/, out)
    end
  end
end
