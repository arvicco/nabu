# frozen_string_literal: true

require "test_helper"

# The CLI layout guard: cli.rb is the registry (root class, subcommand
# registrations, area requires) and the commands live by area under cli/.
# The budget keeps the 13k-line monolith from silently regrowing — a new
# command joins an area file (or a new one), never the registry.
class CliLayoutTest < Minitest::Test
  LIB = File.expand_path("../lib/nabu", __dir__)
  REGISTRY = File.join(LIB, "cli.rb")
  REGISTRY_LINE_BUDGET = 250

  def test_the_registry_stays_under_its_line_budget
    lines = File.foreach(REGISTRY).count
    assert_operator lines, :<=, REGISTRY_LINE_BUDGET,
                    "lib/nabu/cli.rb is #{lines} lines (budget #{REGISTRY_LINE_BUDGET}) — " \
                    "put commands and helpers in an area file under lib/nabu/cli/"
  end

  def test_every_area_file_is_loaded_by_the_registry
    required = File.read(REGISTRY).scan(%r{^require_relative "cli/([a-z_]+)"$}).flatten.sort
    on_disk = Dir[File.join(LIB, "cli", "*.rb")].map { |path| File.basename(path, ".rb") }.sort
    refute_empty on_disk
    assert_equal on_disk, required, "every lib/nabu/cli/*.rb is required by cli.rb, and only those"
  end
end
