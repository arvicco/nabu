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
#
# Internal identifiers are workflow state too, wherever they sit — a
# runtime string, a code comment, a config note, a doc. No tolerance:
# rewrite the id into the content it stood for (a date, "owner ruling",
# the grantor and date of a reply, or one plain clause).
class PublicHygieneTest < Minitest::Test
  # Each entry: [pattern, plain-language reason]. Scanned over every
  # tracked file except SELF, GRANDFATHERED, ALLOWLIST and upstream
  # fixture bytes (see #scanned?).
  FORBIDDEN = [
    [/№/, "the numero sign only ever marks an internal register/thread id — " \
          "use the ruling date or grantor+date provenance instead"],
    # Short Wikidata QIDs collide with the queue-id shape (London IS
    # Q84, live in the tree since the imprint-towns mint) — a Q-token
    # in an explicit wikidata context is an identifier, not workflow.
    [/(?<!wikidata:)(?<!wikidata )\bQ\d{2,3}\b/,
     "internal work-queue ids — state the content (or the date) instead"],
    [/\bT-\d+\b/, "internal thread ids — use grantor+date provenance instead"],
    [/OWNER\s+ACTIONS/, "owner-action lists live in chat and untracked docs only"],
    [/email-register/, "the correspondence register is private machinery"],
    [/external-communications\.md/, "the correspondence protocol is private machinery"],
    [/\b(?:your|the)\s+Drafts\b|Drafts folder|thank-you draft|mailbox draft/i,
     "correspondence workflow state never appears on a public surface"],
    # The ogham manifest leak (found 2026-10-20): a pending-ask note had
    # been phrased as our workflow ("clarification email drafted, unlock
    # registry #14"). State the FACT (unresolved, pending upstream
    # clarification), never the machinery.
    [/unlock registry/i, "internal unlock-registry ids are workflow state"],
    [/\b(?:email|ask|letter)\s+(?:already\s+)?drafted\b/i,
     "correspondence workflow state never appears on a public surface"]
  ].freeze

  # Living HISTORY files written before the rule, awaiting the owner's
  # call (scrub-in-place vs untrack) — grandfathered, NOT license to add
  # more.
  GRANDFATHERED = %w[docs/history/worklog.md docs/history/backlog.md].freeze

  # Per-path exemptions, each with its reason. NOT license to add more:
  # a new entry needs a file that genuinely cannot be rewritten.
  ALLOWLIST = {
    # The owner-authored agent instructions: their wording is the owner's
    # to change, never a sweep's.
    "CLAUDE.md" => "owner-authored agent instructions"
  }.freeze

  # Under test/fixtures/ only our own provenance notes are prose we
  # write (each set's README.md and manifest.yml); every other fixture
  # file is upstream bytes kept verbatim, whatever they contain.
  FIXTURE_PROSE = %r{\Atest/fixtures/(?:.+/)?(?:README\.md|manifest\.yml)\z}

  # This guard names its own patterns; the untracked-import pointer in
  # CLAUDE.md names this file.
  SELF = "test/public_hygiene_test.rb"

  # A grant-gated source whose license class forbids redistribution
  # (the personal TITUS / ACLT grants) must ship NO fixture bytes in the
  # public tree — its samples live in the gitignored local/fixtures/<slug>/
  # and its tests skip-when-absent. Grant-gated sources under an open class
  # (starling: attribution, any use) may keep public fixtures.
  RESTRICTED_GRANT_CLASSES = %w[nc research_private].freeze

  # Pre-rule public fixture sets still awaiting the same migration — NOT
  # license to add more. The guard asserts this list EXACTLY, so a
  # migration must also strike its entry here. Empty since 2026-10-10
  # (aclt, the last pre-rule set, migrated): every restricted source now
  # keeps its samples in local/fixtures/ only.
  LEGACY_PUBLIC_GRANT_FIXTURES = %w[].freeze

  ROOT = File.expand_path("..", __dir__)

  def test_tracked_files_carry_no_internal_workflow_markers
    offenders = []
    tracked_files.each do |rel|
      next unless scanned?(rel)

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

  # The exemptions stay honest: every allowlisted or grandfathered path
  # must still be tracked (a stale entry would silently exempt a future
  # file of the same name), and the id patterns must bite on the shapes
  # they exist for.
  def test_exemptions_name_tracked_files_and_the_patterns_bite
    tracked = tracked_files
    (ALLOWLIST.keys + GRANDFATHERED).each do |rel|
      assert_includes tracked, rel, "stale hygiene exemption: #{rel} is no longer tracked"
    end
    ["(№R-51-B, 2026-08-29)", "grant №23", "the Q83 drain", "(P104-1, Q77)", "thread T-12"].each do |leak|
      assert FORBIDDEN.any? { |pattern, _| leak.match?(pattern) }, "the guard must catch #{leak.inspect}"
    end
    refute scanned?("test/fixtures/perseus/data/tlg0012.xml"), "upstream fixture bytes stay verbatim"
    assert scanned?("test/fixtures/perseus/README.md"), "our fixture provenance notes are prose"
  end

  private

  def scanned?(rel)
    return false if rel == SELF || GRANDFATHERED.include?(rel) || ALLOWLIST.key?(rel)
    return rel.match?(FIXTURE_PROSE) if rel.start_with?("test/fixtures/")

    true
  end

  def tracked_files
    Nabu::Shell.run("git", "-C", ROOT, "ls-files").split("\n")
  rescue Nabu::Shell::Error
    skip "no git checkout — the guard runs where the tree is tracked"
  end
end
