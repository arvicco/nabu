# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"

# Regression (P11-4 review blocker): a LIVE catalog is only migrated on the
# WRITE paths (sync's open_or_create_catalog, rebuild) — every read surface
# (status/search/show/define, and the MCP server, which opens READONLY and
# can never migrate) opens it as-is. Sequel::Model(:dictionaries) introspects
# its table at class-definition time, so on a pre-006 catalog Store.setup!
# itself raised "no such table: dictionaries" before any table_exists? guard
# could run — crashing every CLI command. The fix
# (Sequel::Model.require_valid_table = false in Store.setup!) defers the
# introspection; the runtime protection stays the table_exists? guard idiom.
#
# Test stores are always freshly migrated, which is exactly why the original
# suite missed this: these tests pin the real condition by migrating only to
# version 5 (the last pre-dictionary schema).
class PreMigrationCatalogTest < Minitest::Test
  PRE_DICTIONARY_VERSION = 5

  def pre006_db
    db = Sequel.sqlite
    require "sequel/extensions/migration"
    Sequel::Migrator.run(db, Nabu::Store::MIGRATIONS_DIR, target: PRE_DICTIONARY_VERSION,
                                                          allow_missing_migration_files: true)
    db
  end

  # The rebind path: models are already loaded in this process, so setup!
  # re-points every model's dataset at the old catalog — the dictionary
  # models must tolerate their missing tables.
  def test_setup_rebinds_onto_a_pre_dictionary_catalog_without_raising
    db = pre006_db
    Nabu::Store.setup!(db)

    # The pre-006 tables still work end to end…
    source = Nabu::Store::Source.create(
      slug: "perseus", name: "Perseus", adapter_class: "TestAdapter", license_class: "open"
    )
    assert_equal "perseus", Nabu::Store::Source.first.slug

    # …and the guarded read surfaces degrade honestly, never a stack trace.
    assert_empty Nabu::Query::Define.new(catalog: db).run("μῆνις")
    assert_empty Nabu::Query::Define.new(catalog: db).glosses([%w[officium lat]])

    tools = Nabu::MCP::Tools.new(catalog: db, fulltext: nil)
    result = tools.call("nabu_define", { "lemma" => "μῆνις" })
    refute result[:isError]
    assert_equal Nabu::MCP::Tools::NO_SHELF_NOTE, result[:content][0][:text]

    status = tools.call("nabu_status", {})
    refute status[:isError]
    assert_includes JSON.parse(status[:content][0][:text]).fetch("sources").map { |s| s["slug"] }, source.slug
  end

  # The definition path — the one that crashed live: a FRESH process whose
  # very first Store.setup! runs against the pre-006 catalog, so the model
  # files' class definitions themselves must tolerate the missing tables.
  # Only a child process can exercise this (the suite's own models are
  # already defined), the entrypoint-test pattern.
  def test_model_definition_tolerates_a_pre_dictionary_catalog_in_a_fresh_process
    Dir.mktmpdir("nabu-pre006") do |dir|
      db_path = File.join(dir, "catalog.sqlite3")
      script = <<~RUBY
        require "sequel"
        require "sequel/extensions/migration"
        db = Sequel.connect("sqlite://#{db_path}")
        Sequel::Migrator.run(db, #{Nabu::Store::MIGRATIONS_DIR.inspect}, target: #{PRE_DICTIONARY_VERSION},
                             allow_missing_migration_files: true)
        db.disconnect
        require "nabu"
        catalog = Nabu::Store.connect("#{db_path}", readonly: true) # the MCP condition: can never migrate
        Nabu::Store.setup!(catalog)
        result = Nabu::MCP::Tools.new(catalog: catalog, fulltext: nil)
                                 .call("nabu_define", { "lemma" => "officium" })
        raise "unexpected isError" if result[:isError]
        raise "expected the no-shelf note" unless result[:content][0][:text].include?("dictionary shelf")
        puts "PRE006-OK"
      RUBY
      out, err, status = Open3.capture3(
        RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-e", script
      )
      assert status.success?, "fresh-process setup! against a pre-006 catalog failed:\n#{err}"
      assert_includes out, "PRE006-OK"
    end
  end
end
