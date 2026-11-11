# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::SourceScope — the ONE resolution of the --source/--axis
  # scoping pair, shared by the CLI search family and the MCP nabu_search
  # tool (the MCP surface must never grow a parallel implementation). An
  # unknown slug or axis is refused naming the valid set — never an empty
  # page.
  class SourceScopeTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      %w[perseus papyri].each do |slug|
        Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter",
                                   license_class: "open", enabled: true)
      end
    end

    def registry
      axes = Nabu::AxisRegistry.new([
                                      Nabu::AxisRegistry::Axis.new(name: "classical", persona: "p", desc: "d",
                                                                   order: 0),
                                      Nabu::AxisRegistry::Axis.new(name: "documentary", persona: "p", desc: "d",
                                                                   order: 1)
                                    ])
      entries = [
        Nabu::SourceRegistry::Entry.new(slug: "perseus", adapter_class_name: "TestAdapter", wired: true,
                                        sync_policy: "manual", axes: ["classical"]),
        Nabu::SourceRegistry::Entry.new(slug: "papyri", adapter_class_name: "TestAdapter", wired: true,
                                        sync_policy: "manual", axes: ["documentary"])
      ]
      Nabu::SourceRegistry.new(entries, axes: axes)
    end

    def test_a_held_slug_passes_and_nil_is_no_filter
      assert_nil Nabu::Query::SourceScope.validate_source!(@catalog, "perseus")
      assert_nil Nabu::Query::SourceScope.validate_source!(@catalog, nil)
    end

    def test_an_unknown_slug_is_refused_naming_the_held_ones
      error = assert_raises(Nabu::Query::SourceScope::Error) do
        Nabu::Query::SourceScope.validate_source!(@catalog, "nope")
      end
      assert_equal 'unknown source "nope" — the catalog holds: papyri, perseus', error.message
    end

    def test_axis_names_resolve_to_the_union_of_their_members
      names, slugs = Nabu::Query::SourceScope.axis_membership(registry, "classical, documentary,classical",
                                                              command: "search")
      assert_equal %w[classical documentary], names
      assert_equal %w[perseus papyri], slugs
    end

    def test_a_blank_axis_spec_is_no_filter
      assert_nil Nabu::Query::SourceScope.axis_membership(registry, nil, command: "search")
      assert_nil Nabu::Query::SourceScope.axis_membership(registry, "  ", command: "search")
    end

    def test_an_unknown_axis_is_refused_naming_the_known_set
      error = assert_raises(Nabu::Query::SourceScope::Error) do
        Nabu::Query::SourceScope.axis_membership(registry, "nope", command: "search")
      end
      assert_match(/\Asearch: unknown axis "nope" — known axes: classical, documentary · functional sets: /,
                   error.message)
    end

    def test_an_axis_less_registry_says_so
      error = assert_raises(Nabu::Query::SourceScope::Error) do
        Nabu::Query::SourceScope.axis_membership(Nabu::SourceRegistry.new([]), "classical", command: "export")
      end
      assert_equal "export: no research axes are defined (config/axes.yml)", error.message
    end

    def test_a_functional_set_is_accepted_beside_the_desks
      names, slugs = Nabu::Query::SourceScope.axis_membership(registry, "core", command: "search")
      assert_equal %w[core], names
      assert_equal [], slugs
    end
  end
end
