# frozen_string_literal: true

require "test_helper"

# The registry-drift guard for docs/nabu-data.md (P50-W1) — the axes-page
# pattern: the doc's feature census is written FROM Nabu::DataBuild::REGISTRY,
# never hand-duplicated, so this test parses the page's "## The features"
# section and pins every rendered fact to the live registry. The deterministic
# page format the page commits to:
#
#   | `<slug>` | <status> | <tier> | <license> | <language> | <inputs> |   — the table
#   ### `<slug>` — <title>                                     — one H3 per feature
#   **Status**: s · **Tier**: t · **Anchoring**: a · **Inputs**: i
#   <rationale paragraph, VERBATIM>
#   **Maintenance**: <maintenance, VERBATIM>
class NabuDataPageTest < Minitest::Test
  PAGE = File.join(Nabu::Config::PROJECT_ROOT, "docs", "nabu-data.md")

  # The SHIPPED registry (the constant, not the test seam).
  def features
    Nabu::DataBuild::REGISTRY
  end

  # The "## The features" section body — from that heading to the next H2.
  def features_section
    md = File.read(PAGE)
    body = md[/^## The features\n(.*?)(?=^## )/m, 1]
    refute_nil body, "docs/nabu-data.md must carry a '## The features' section closed by a following '## ' heading"
    body
  end

  def test_the_feature_table_matches_the_registry_in_order
    rows = features_section.scan(/^\| `([^`]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$/)
                           .map { |cells| cells.map(&:strip) }
    assert_equal features.map(&:slug), rows.map(&:first),
                 "the table must list exactly the registered slugs, in registry order"
    features.zip(rows).each do |feature, (_slug, status, tier, license, language, inputs)|
      assert_equal feature.status.to_s, status, "#{feature.slug}: table status must match the registry"
      assert_equal feature.tier, tier, "#{feature.slug}: table tier must match the registry"
      assert_equal feature.license, license,
                   "#{feature.slug}: table license must match the registry (mixed-license repo, D51-a)"
      assert_equal feature.language_code, language, "#{feature.slug}: table language must match the registry"
      expected_inputs = feature.inputs.empty? ? "—" : feature.inputs.join(", ")
      assert_equal expected_inputs, inputs, "#{feature.slug}: table inputs must match the registry"
    end
  end

  def test_each_feature_block_pins_title_status_rationale_and_maintenance
    blocks = features_section.scan(/^### `([^`]+)` — (.+?)\n(.*?)(?=^### |\z)/m)
    assert_equal features.map(&:slug), blocks.map(&:first),
                 "one '### `<slug>` — <title>' block per registered feature, in registry order"

    features.zip(blocks).each do |feature, (_slug, title, body)|
      assert_equal feature.title, title.strip, "#{feature.slug}: the heading title must be VERBATIM"

      status_line = body[/^\*\*Status\*\*: (.+)$/, 1]
      refute_nil status_line, "#{feature.slug}: expected a '**Status**: ...' line"
      expected_inputs = feature.inputs.empty? ? "—" : feature.inputs.join(", ")
      assert_equal "#{feature.status} · **Tier**: #{feature.tier} · **Anchoring**: #{feature.anchoring} · " \
                   "**Inputs**: #{expected_inputs}",
                   status_line, "#{feature.slug}: the status line must render the registry facts"

      maintenance = body[/^\*\*Maintenance\*\*: (.+)$/, 1]
      assert_equal feature.maintenance, maintenance,
                   "#{feature.slug}: the maintenance line must be VERBATIM from the registry"

      # The rationale: the block's one plain paragraph — every content line
      # that is neither the status nor the maintenance line.
      rationale = body.lines.map(&:chomp).reject do |line|
        line.strip.empty? || line.start_with?("**Status**") || line.start_with?("**Maintenance**")
      end
      assert_equal [feature.rationale], rationale,
                   "#{feature.slug}: the rationale paragraph must be VERBATIM from the registry (one line)"
    end
  end
end
