# frozen_string_literal: true

require "test_helper"

# Public-surface hygiene (owner rule 2026-08-30): every git-tracked file is
# a PUBLIC surface. It may carry technical content and license-provenance
# facts (grantor, date, terms) — NEVER internal workflow state: outreach
# thread identifiers, correspondence status (drafts, sends, nudges,
# mailbox mechanics), owner-action lists, or the private register paths.
# The cleanup of 2026-08-30 converted every legacy thread id to
# grantor+date provenance; this guard keeps the tree that way. PR bodies
# and commit messages are the other half of the surface — checked at
# authoring time, not testable here.
class PublicHygieneTest < Minitest::Test
  # Each entry: [pattern, plain-language reason].
  FORBIDDEN = [
    [/№\d+-\d/, "internal thread/report ids — use grantor+date provenance instead"],
    [/thread\s+T-\d/i, "internal thread ids — use grantor+date provenance instead"],
    [/OWNER\s+ACTIONS/, "owner-action lists live in chat and untracked docs only"],
    [/email-register/, "the correspondence register is private machinery"],
    [/external-communications\.md/, "the correspondence protocol is private machinery"],
    [/\b(?:your|the)\s+Drafts\b|Drafts folder|thank-you draft|mailbox draft/i,
     "correspondence workflow state never appears on a public surface"]
  ].freeze

  # Living HISTORY files written before the rule, awaiting the owner's
  # call (scrub-in-place vs untrack) — grandfathered, NOT license to add
  # more. №R-n ruling ids in code comments are tolerated decision
  # provenance (dated), deliberately not matched above.
  GRANDFATHERED = %w[docs/worklog.md docs/backlog.md].freeze

  # This guard names its own patterns; the untracked-import pointer in
  # CLAUDE.md names this file.
  SELF = "test/public_hygiene_test.rb"

  def test_tracked_files_carry_no_internal_workflow_markers
    root = File.expand_path("..", __dir__)
    listing = begin
      Nabu::Shell.run("git", "-C", root, "ls-files")
    rescue Nabu::Shell::Error
      skip "no git checkout — the guard runs where the tree is tracked"
    end

    offenders = []
    listing.split("\n").each do |rel|
      next if rel == SELF || GRANDFATHERED.include?(rel)

      path = File.join(root, rel)
      next unless File.file?(path)

      content = File.read(path, encoding: Encoding::UTF_8)
      next unless content.valid_encoding? # binary fixtures are not prose

      FORBIDDEN.each do |pattern, reason|
        content.scan(pattern).first(1).each do |hit|
          offenders << "#{rel}: #{Array(hit).first.to_s.strip[0, 40].inspect} — #{reason}"
        end
      end
    end

    assert_empty offenders,
                 "internal workflow leaked into the public tree:\n  #{offenders.join("\n  ")}"
  end
end
