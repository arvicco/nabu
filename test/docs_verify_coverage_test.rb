# frozen_string_literal: true

require "test_helper"
require "nabu/ops/docs_verify"

# The drift guard of `rake docs:verify`: every command the walkthrough pages
# teach (fenced blocks, inline `bin/nabu …` spans, content blocks) is either
# verified by a step of config/docs_verify.yml or ignored there with a
# reason; every claim quote still appears in its page; no plan entry names a
# command the pages no longer document. A newly documented command therefore
# cannot silently escape the verifier — it fails here until it is placed.
class DocsVerifyCoverageTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def plan = Nabu::Ops::DocsVerify::Plan.load(File.join(ROOT, Nabu::Ops::DocsVerify::PLAN))

  def test_every_documented_command_is_verified_or_ignored
    gaps = Nabu::Ops::DocsVerify.new(plan: plan, root: ROOT).coverage_gaps

    assert_empty gaps, "docs:verify plan out of step with the pages (#{Nabu::Ops::DocsVerify::PLAN}):\n" \
                       "#{gaps.join("\n")}"
  end

  # Both quickstart walkthroughs are in scope — the two pages share claims.
  def test_both_quickstart_pages_are_in_scope
    paths = plan.pages.map(&:path)

    assert_includes paths, "site/quickstart.md"
    assert_includes paths, "docs/quickstart.md"
  end

  # The guard must have teeth: the scoped pages really yield commands.
  def test_the_scoped_pages_yield_commands
    plan.pages.each do |ref|
      text = File.read(File.join(ROOT, ref.path), encoding: Encoding::UTF_8)
      parsed = Nabu::Ops::DocCommands.parse(text, path: ref.path, sections: ref.sections)

      refute_empty parsed.blocks, "#{ref.path} yielded no fenced blocks — a section heading renamed?"
    end
  end
end
