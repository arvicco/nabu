# frozen_string_literal: true

require "test_helper"

# The paced-crawl index cadence guard. A source whose adapter declares a
# paced/sliced fetch schedule (a Nabu::PacedCrawl::Schedule in its adapter
# file — the same code declarations the acquisition rail reads as its
# roster) lands its documents one slice per sync. Inline, every slice pays
# an index refresh, and once the source is big each slice is a
# full-corpus shadow pass; `index_policy: deferred` instead leaves the
# index to `nabu index refresh` once per wave (several deferred sources
# in one command share ONE shadow pass).
#
# So every paced source in config/sources.yml either declares
#
#   index_policy: deferred
#
# or states WHY it stays inline, on its row, in this exact detectable form:
#
#   index_policy: inline   # inline because: <reason>
#
# (a cone-complete crawl whose slices are over, a corpus too small for a
# slice to approach the in-place row budget…). A paced source silently
# inline — no declaration, or `inline` without the reason — fails here.
class IndexPolicyConformanceTest < Minitest::Test
  SOURCES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml")
  PACED = /PacedCrawl::Schedule\.new/
  INLINE_REASON = /^\s+index_policy:\s*inline\s+#\s*inline because:\s*\S/

  def registry
    @registry ||= Nabu::SourceRegistry.load(SOURCES_PATH)
  end

  # The adapter's own file declares a paced schedule.
  def paced?(entry)
    file, = Object.const_source_location(entry.adapter_class_name)
    !file.nil? && File.read(file, encoding: Encoding::UTF_8).match?(PACED)
  rescue NameError
    false
  end

  # The source's row in sources.yml: its top-level key line through the
  # line before the next top-level key.
  def row_text(slug)
    lines = File.readlines(SOURCES_PATH, encoding: Encoding::UTF_8)
    start = lines.index { |line| line.match?(/\A#{Regexp.escape(slug)}:(\s|\z)/) }
    return "" if start.nil?

    tail = lines[(start + 1)..].take_while { |line| !line.match?(/\A[^\s#]/) }
    ([lines[start]] + tail).join
  end

  def paced_entries
    registry.each_source.select { |entry| paced?(entry) }
  end

  def test_the_sweep_finds_the_known_paced_sources
    slugs = paced_entries.map(&:slug)

    %w[ndl-kotenseki wellcome pleias-french-books].each do |slug|
      assert_includes slugs, slug, "the paced-schedule detector must see #{slug} (a broken detector passes vacuously)"
    end
  end

  def test_every_paced_source_defers_its_index_or_states_why_not
    silent = paced_entries.reject do |entry|
      entry.index_deferred? || row_text(entry.slug).match?(INLINE_REASON)
    end

    assert_empty silent.map(&:slug),
                 "paced-crawl sources silently inline — declare `index_policy: deferred`, or " \
                 "`index_policy: inline   # inline because: <reason>` on the row"
  end

  def test_the_inline_reason_form_is_detected_only_with_a_reason
    assert_match INLINE_REASON, "  index_policy: inline   # inline because: the crawl is complete\n"
    refute_match INLINE_REASON, "  index_policy: inline\n"
    refute_match INLINE_REASON, "  index_policy: inline   # inline because:\n"
    refute_match INLINE_REASON, "  index_policy: deferred   # inline because: no\n"
  end
end
