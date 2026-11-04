# frozen_string_literal: true

require "test_helper"
require "yaml"

module Site
  # The /sources/ completeness guard. The corpus table used to be a hand
  # table, and a hundred live sources went unlisted while blocked holdings
  # kept empty rows. It is now a pure projection — registry membership +
  # the hand prose in site/_data/source_notes.yml — so this test
  # regenerates it in memory and FAILS THE SUITE the day a live public
  # source is missing from the page (newly wired, renamed, un-blocked) or a
  # blocked one appears, until `rake site:sources` runs.
  class SourcesTableTest < Minitest::Test
    ROOT = Nabu::Config::PROJECT_ROOT
    SITE = File.join(ROOT, "site")

    def registry
      @registry ||= Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
    end

    def generator = Nabu::Ops::SourcesTable.load(registry: registry, site_dir: SITE)
    def committed = File.read(File.join(SITE, Nabu::Ops::SourcesTable::INCLUDE_FILE))

    def test_committed_table_matches_the_registry_projection
      assert_equal generator.render, committed,
                   "site/_includes/sources_table.md is stale against config/sources.yml + " \
                   "site/_data/source_notes.yml — run `rake site:sources` (a live source is missing " \
                   "from /sources/, or prose was hand-edited into the generated table)"
    end

    def test_every_live_public_source_has_exactly_one_anchor_and_no_blocked_one_does
      anchors = committed.scan(/id="src-([^"]+)"/).flatten
      live = Nabu::Ops::SiteData.live_public_slugs(registry)
      assert_equal live, anchors.sort, "every live public source needs exactly one /sources/ anchor"
      blocked = registry.each_source.select(&:blocked?).map(&:slug)
      refute_empty blocked, "the registry carries grant-gated blocked sources"
      assert_empty anchors & blocked, "blocked holdings never appear on a public census surface"
    end

    def test_the_table_lists_what_the_holdings_data_lists
      data = YAML.safe_load_file(File.join(SITE, "_data", "sources.yml")).fetch("sources")
      assert_equal data.keys.sort, generator.slugs,
                   "site/_data/sources.yml and the /sources/ table disagree on membership — " \
                   "run `rake site:refresh`"
    end

    def test_every_source_note_names_a_live_public_source
      assert_empty generator.orphans,
                   "site/_data/source_notes.yml carries prose for sources that are not live and public " \
                   "(retired, renamed or blocked) — move or drop the note"
    end

    def test_the_sources_page_includes_the_generated_table_and_carries_no_hand_rows
      page = File.read(File.join(SITE, "sources.md"))
      assert_includes page, "{% include sources_table.md %}"
      refute_match(/^\| <span id="src-/, page, "no hand-maintained source row may return to sources.md")
    end
  end
end
