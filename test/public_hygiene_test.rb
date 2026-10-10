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

  # Q119: a grant-gated source whose license class forbids redistribution
  # (the personal TITUS / ACLT grants) must ship NO fixture bytes in the
  # public tree — its samples live in the gitignored local/fixtures/<slug>/
  # and its tests skip-when-absent. Grant-gated sources under an open class
  # (starling: attribution, any use) may keep public fixtures.
  RESTRICTED_GRANT_CLASSES = %w[nc research_private].freeze

  # Pre-rule public fixture sets still awaiting the same migration — NOT
  # license to add more. The guard asserts this list EXACTLY, so a
  # migration must also strike its entry here.
  LEGACY_PUBLIC_GRANT_FIXTURES = %w[aclt].freeze

  ROOT = File.expand_path("..", __dir__)

  def test_tracked_files_carry_no_internal_workflow_markers
    offenders = []
    tracked_files.each do |rel|
      next if rel == SELF || GRANDFATHERED.include?(rel)

      path = File.join(ROOT, rel)
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

  def test_no_redistribution_grant_sources_ship_no_public_fixture_bytes
    registry = Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
    restricted = []
    registry.each_source do |entry|
      next unless entry.grant_required?
      next unless RESTRICTED_GRANT_CLASSES.include?(entry.manifest&.license_class)

      restricted << entry.slug
    end
    assert_includes restricted, "titus-pahlavi", "the guard must see the grant-gated nc sources"

    fixture_slugs = tracked_files.filter_map { |rel| rel[%r{\Atest/fixtures/([^/]+)/}, 1] }.uniq
    shipping = (restricted & fixture_slugs).sort
    assert_equal LEGACY_PUBLIC_GRANT_FIXTURES.sort, shipping,
                 "no-redistribution grant bytes belong in gitignored local/fixtures/<slug>/ " \
                 "(README recipe + skip-when-absent tests), never in the public test/fixtures/"
  end

  private

  def tracked_files
    Nabu::Shell.run("git", "-C", ROOT, "ls-files").split("\n")
  rescue Nabu::Shell::Error
    skip "no git checkout — the guard runs where the tree is tracked"
  end
end
