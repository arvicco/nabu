# frozen_string_literal: true

require "test_helper"
require "yaml"

# The conventions scan for the encoding/bounds belt
# (Nabu::Adapters::SourceRead). Adapters read canonical files in hundreds
# of places; each bare read is a seam where invalid bytes can raise an
# encoding exception the loader's ParseError net does not catch, and each
# hand-rolled UTF-8 guard or byte slice is a copy of a check the belt owns.
#
# This is a RATCHET over three idioms per adapter file, against the
# baseline in test/adapters/source_read_baseline.yml:
#   reads        bare File/IO/CSV/GzipReader reads of a path
#   utf8_guards  hand-rolled `valid_encoding?` checks
#   byteslices   unbounded `byteslice` calls on a read buffer
# A count ABOVE the baseline fails (new code reads around the belt — use
# SourceRead.utf8_file / .utf8 / .slice); a count BELOW it fails too, so a
# migration onto the belt lowers the baseline in the same change and the
# allowance can never silently regrow. Comment lines are not counted.
class SourceReadConventionsTest < Minitest::Test
  ADAPTERS_DIR = File.expand_path("../../lib/nabu/adapters", __dir__)
  BASELINE_PATH = File.expand_path("source_read_baseline.yml", __dir__)
  BELT = "source_read.rb"

  IDIOMS = {
    "reads" => /\b(?:File|IO)\.(?:read|binread|readlines|foreach|open)\b|
                \bZlib::GzipReader\.open\b|\bCSV\.(?:foreach|read)\b/x,
    "utf8_guards" => /\.valid_encoding\?/,
    "byteslices" => /\.byteslice\(/
  }.freeze

  def self.census
    Dir[File.join(ADAPTERS_DIR, "*.rb")].each_with_object({}) do |path, out|
      name = File.basename(path)
      next if name == BELT

      code = File.readlines(path).reject { |line| line.lstrip.start_with?("#") }
      counts = IDIOMS.transform_values { |pattern| code.sum { |line| line.scan(pattern).size } }
      counts.reject! { |_, count| count.zero? }
      out[name] = counts unless counts.empty?
    end
  end

  def test_adapters_read_through_the_belt
    baseline = YAML.safe_load_file(BASELINE_PATH)
    census = self.class.census
    problems = []
    (census.keys | baseline.keys).sort.each do |file|
      now = census.fetch(file, {})
      allowed = baseline.fetch(file, {})
      IDIOMS.each_key do |idiom|
        have = now.fetch(idiom, 0)
        may = allowed.fetch(idiom, 0)
        if have > may
          problems << "#{file}: #{have} #{idiom} (baseline #{may}) — read through Nabu::Adapters::SourceRead"
        elsif have < may
          problems << "#{file}: #{have} #{idiom} now, baseline says #{may} — lower the baseline (the ratchet)"
        end
      end
    end
    assert_empty problems, "encoding/bounds belt conventions (#{BASELINE_PATH}):\n#{problems.join("\n")}"
  end

  # The belt's own read path is the only exemption, and it must exist.
  def test_the_belt_is_where_the_scan_says
    assert File.file?(File.join(ADAPTERS_DIR, BELT))
  end
end
