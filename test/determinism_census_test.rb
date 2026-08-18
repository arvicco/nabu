# frozen_string_literal: true

require "test_helper"

# The determinism census (P77-r11 — the drill_pure lesson made standing
# law): db/ must be a PURE FUNCTION of the three permanent folders, and
# the 2026-08-14 drill failure traced to encounter-order artifacts
# (rundata's colliding slugs, the kangyur dkar chag's citation markers)
# that no test could see because the nondeterminism lived in live-corpus
# shapes. Fixtures cannot cover every shape — but the CODE can be denied
# the constructs that make order an input at all. This census greps
# lib/ for them; any new occurrence is a deliberate allowlist decision
# with a stated reason, never a drive-by.
#
# The three enforced rules:
#   1. Dir.children/Dir.entries return READDIR ORDER (filesystem-
#      dependent, machine-dependent) — every use must sort within its
#      own statement (a 4-line window is the heuristic).
#   2. Dir.glob sorts by default (Ruby >= 3.0) — `sort: false` is the
#      opt-out and is banned.
#   3. No randomness in lib/: rand/shuffle/sample make two runs two
#      programs. (Attributes NAMED sample are allowlisted by file.)
class DeterminismCensusTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # file (relative to lib/) => reason. Empty entries are never added
  # casually: name what the construct does and why order/randomness
  # cannot reach minted content.
  RANDOMNESS_ALLOWLIST = {
    "nabu/ingest.rb" => "Plan#sample is a Data ATTRIBUTE (the first-page text sample) — not Array#sample",
    "nabu/query/random.rb" => "the `nabu random` feature IS randomness — query-time display, " \
                              "seeded RNG, never reaches minted content",
    "nabu/query/search.rb" => "the random-passage sampling lane of the same feature (@rng, seeded) — " \
                              "query-time only"
  }.freeze

  UNSORTED_LISTING_ALLOWLIST = {}.freeze

  def test_directory_listings_sort_within_their_statement
    offenders = census(/Dir\.(children|entries)\b/) do |lines, index|
      window = lines[index, 4].join
      window.match?(/\.sort\b|\.sort_by\b|\.min\b|\.max\b/)
    end
    offenders.reject! { |offender| UNSORTED_LISTING_ALLOWLIST.key?(offender[:file]) }
    assert_empty offenders.map { |o| "#{o[:file]}:#{o[:line]}" },
                 "Dir.children/Dir.entries yield READDIR order — sort in the same statement, " \
                 "or allowlist here with a reason (the P77-r10 encounter-order lesson)"
  end

  def test_dir_glob_never_opts_out_of_sorting
    offenders = census(/Dir\.glob[^\n]*sort:\s*false/) { false }
    assert_empty offenders.map { |o| "#{o[:file]}:#{o[:line]}" },
                 "Dir.glob sorts by default — `sort: false` reintroduces readdir order"
  end

  def test_no_randomness_in_lib
    offenders = census(/\brand\(|\.shuffle\b|\.sample\b/) { false }
    offenders.reject! { |offender| RANDOMNESS_ALLOWLIST.key?(offender[:file]) }
    assert_empty offenders.map { |o| "#{o[:file]}:#{o[:line]}" },
                 "randomness makes two rebuilds two programs — allowlist with a reason or remove"
  end

  private

  # Every match of +pattern+ in lib/ that the block does NOT clear.
  # Comment-only lines are skipped (prose may name the constructs).
  def census(pattern)
    offenders = []
    Dir.glob(File.join(LIB, "**", "*.rb")).each do |path| # glob sorts by default — rule 2
      lines = File.readlines(path)
      lines.each_with_index do |line, index|
        next unless line.match?(pattern)
        next if line.strip.start_with?("#")
        next if yield(lines, index)

        offenders << { file: path.delete_prefix("#{LIB}/"), line: index + 1 }
      end
    end
    offenders
  end
end
