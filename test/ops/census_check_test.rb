# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::CensusCheck (P35-6, dev-loop §6b rule 3): the gate scan that
  # keeps era-bound literals carrying their justification. PRESENCE check
  # only — a `# census: <n>, <date>[, basis]` or `# const: <reason>` line in
  # the comment block immediately above the constant assignment; the scan
  # never judges the values.
  class CensusCheckTest < Minitest::Test
    def check(source, name: "sample.rb")
      Dir.mktmpdir("census-check") do |root|
        dir = File.join(root, "lib/nabu/query")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, name), source)
        return Nabu::Ops::CensusCheck.new(root: root).findings
      end
    end

    def test_a_bare_numeric_constant_in_the_region_is_a_finding
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        # Pull more hits than the caller's limit.
        INNER_LIMIT_FACTOR = 10
      RUBY
      assert_equal 1, findings.size
      assert_equal "INNER_LIMIT_FACTOR", findings.first.constant
      assert_match(/census|const/, findings.first.message)
    end

    def test_census_and_const_markers_satisfy_the_scan
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        # census: 5505159, 2026-07-20, live passages
        COMMON_GRAM_DF = 500
        # A true constant:
        # const: SQLite bound-parameter comfort
        URN_BATCH = 500
      RUBY
      assert_empty findings
    end

    def test_the_marker_must_sit_in_the_adjacent_comment_block
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        # census: 100, 2026-07-20
        SOMETHING_ELSE = "not scanned"

        FLOOR = 50
      RUBY
      assert_equal %w[FLOOR], findings.map(&:constant),
                   "a marker above a DIFFERENT constant must not satisfy FLOOR"
    end

    def test_default_prefixed_knobs_are_exempt
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        DEFAULT_WINDOW = 10
        DEFAULT_LIMIT = 20
      RUBY
      assert_empty findings, "DEFAULT_* knobs are the conventions-§10 exemption"
    end

    def test_a_marker_covers_a_contiguous_sibling_run_but_not_across_a_gap
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        # const: JSON-RPC 2.0 spec codes
        PARSE_ERROR = -32_700
        INVALID_REQUEST = -32_600

        ORPHAN = 7
      RUBY
      assert_equal %w[ORPHAN], findings.map(&:constant),
                   "one marker stamps a tight sibling group; a blank line ends its reach"
    end

    def test_hand_enumerated_word_lists_are_scanned
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        LANGS = %w[grc lat ang].freeze
      RUBY
      assert_equal %w[LANGS], findings.map(&:constant),
                   "a frozen enumeration is a census claim exactly like a number"
    end

    def test_strings_and_derived_constants_are_not_scanned
      findings = check(<<~RUBY)
        # frozen_string_literal: true

        NOTE = "an honest message"
        MAX_REFS = Query::Align::MAX_REFS
        SNIPPET_SQL = "snippet(passages_fts, 0)"
      RUBY
      assert_empty findings, "only bare numerics and %w enumerations encode census claims"
    end

    def test_the_real_repo_region_is_fully_stamped
      root = File.expand_path("../..", __dir__)
      findings = Nabu::Ops::CensusCheck.new(root: root).findings
      messages = findings.map { |f| "#{f.path}:#{f.line} #{f.constant}" }
      assert_empty findings,
                   "era-bound literals missing their # census:/# const: marker:\n#{messages.join("\n")}"
    end
  end
end
