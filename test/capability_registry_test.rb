# frozen_string_literal: true

require "test_helper"
require "yaml"

# The capability registry guard (config/capabilities.yml): the hand-curated
# map of every user-facing capability to the data layers it reads and how
# each layer is produced. The shelf_members.yml pattern — curation by hand,
# completeness by the suite: a CLI command or MCP tool born without a
# registry row turns the suite red, naming the offender.
class CapabilityRegistryTest < Minitest::Test
  PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "capabilities.yml")
  PRODUCERS = %w[sync rebuild enrichment tool write_through curated].freeze
  COSTS = %w[derived time_heavy paid ruled acquired log].freeze

  def registry
    @registry ||= YAML.safe_load_file(PATH)
  end

  def capabilities
    registry.fetch("capabilities")
  end

  def layers
    registry.fetch("layers")
  end

  def uncataloged
    registry.fetch("uncataloged", [])
  end

  # Thor's command names use underscores; the user types dashes.
  def dash(name)
    name.to_s.tr("_", "-")
  end

  # Every CLI command as the user types it: root commands ("search") and
  # the leaves of every subcommand family ("lect assign"). The family
  # dispatchers themselves ("lect") are not commands of their own; Thor's
  # built-ins (help, tree) ride the `uncataloged:` allowlist by own name.
  def cli_commands
    families = Nabu::CLI.subcommand_classes
    root = Nabu::CLI.all_commands.keys.reject { |name| families.key?(name) }
    leaves = families.flat_map do |family, klass|
      klass.all_commands.keys.map { |name| [family, name] }
    end
    names = root.map { |name| [nil, name] } + leaves
    names.reject { |(_, own)| uncataloged.include?(dash(own)) }
         .map { |(family, own)| [family && dash(family), dash(own)].compact.join(" ") }
  end

  def surface_entries(kind)
    capabilities.flat_map do |name, cap|
      Array(cap.fetch("surfaces", {})[kind]).map { |entry| [entry, name] }
    end
  end

  def assert_exactly_once(kind, enumerated)
    entries = surface_entries(kind)
    by_entry = entries.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

    missing = enumerated.reject { |name| by_entry.key?(name) }
    assert_empty missing, "#{kind} surfaces missing from config/capabilities.yml " \
                          "(catalog each under a capability's surfaces.#{kind}): #{missing.join(', ')}"

    doubled = by_entry.select { |_, caps| caps.size > 1 }
    assert_empty doubled, "#{kind} surfaces cataloged under more than one capability: " \
                          "#{doubled.map { |entry, caps| "#{entry} (#{caps.join(', ')})" }.join('; ')}"

    unknown = by_entry.keys - enumerated
    assert_empty unknown, "config/capabilities.yml names #{kind} surfaces that do not exist: #{unknown.join(', ')}"
  end

  def test_every_cli_command_is_cataloged_exactly_once
    assert_exactly_once("cli", cli_commands)
  end

  def test_every_mcp_tool_is_cataloged_exactly_once
    assert_exactly_once("mcp", Nabu::MCP::Tools::TOOLS.keys)
  end

  def test_uncataloged_allowlist_names_real_commands
    own_names = Nabu::CLI.all_commands.keys +
                Nabu::CLI.subcommand_classes.values.flat_map { |klass| klass.all_commands.keys }
    stale = uncataloged - own_names.map { |name| dash(name) }
    assert_empty stale, "uncataloged: names no CLI command: #{stale.join(', ')}"
  end

  def test_every_capability_has_a_description_surfaces_and_declared_layers
    capabilities.each do |name, cap|
      refute_empty cap["desc"].to_s, "capability #{name} has no desc"
      refute_empty cap.fetch("surfaces", {}).values.flatten, "capability #{name} has no surfaces"
      used = Array(cap["layers"])
      refute_empty used, "capability #{name} reads no layers"
      undeclared = used - layers.keys
      assert_empty undeclared, "capability #{name} reads undeclared layers: #{undeclared.join(', ')}"
    end
  end

  def test_every_layer_uses_the_closed_vocabularies
    layers.each do |name, layer|
      refute_empty layer["home"].to_s, "layer #{name} has no home"
      assert_includes PRODUCERS, layer["producer"], "layer #{name}: producer #{layer['producer'].inspect}"
      assert_includes COSTS, layer["cost"], "layer #{name}: cost #{layer['cost'].inspect}"
    end
  end

  def test_every_non_derived_layer_names_its_producing_command
    layers.each do |name, layer|
      next if layer["cost"] == "derived"

      refute_empty layer["command"].to_s, "layer #{name} (cost #{layer['cost']}) carries no command"
    end
  end

  def test_every_declared_layer_is_read_by_some_capability
    read = capabilities.values.flat_map { |cap| Array(cap["layers"]) }
    orphans = layers.keys - read
    assert_empty orphans, "layers no capability reads: #{orphans.join(', ')}"
  end
end
