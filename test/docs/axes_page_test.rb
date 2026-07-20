# frozen_string_literal: true

require "test_helper"

# The registry-drift guard for docs/axes.md (P35-3, D35-e — the PUBLIC atlas
# of the research axes). docs/axes.md is written FROM the live registry, never
# hand-duplicated: this test parses the page's "## The desks" section and pins
# every rendered fact to Nabu::AxisRegistry / SourceRegistry, so the page can
# never silently drift from config/axes.yml + config/sources.yml.
#
# What it parses (the deterministic page format the page commits to):
#   ### <axis-name>        — one H3 heading per desk, in ratified file order
#   > <persona>            — the persona blockquote, VERBATIM
#   <desc>                 — the membership-rationale paragraph, VERBATIM
#   **Members** (N): `a`, `b`, …   — the backticked member slugs, in order
#
# What it pins: the axis heading list == AxisRegistry names in order; each
# persona and desc == the registry definition verbatim; each member-slug list
# and its count == SourceRegistry#axis_members. It reads the SHIPPED config
# (Nabu::Config::PROJECT_ROOT), so a config change with no page update is red.
class AxesPageTest < Minitest::Test
  ROOT = Nabu::Config::PROJECT_ROOT
  PAGE = File.join(ROOT, "docs", "axes.md")

  def registry
    @registry ||= Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
  end

  # The "## The desks" section body — from that heading to the next H2.
  def desks_section
    md = File.read(PAGE)
    body = md[/^## The desks\n(.*?)(?=^## )/m, 1]
    refute_nil body, "docs/axes.md must carry a '## The desks' section closed by a following '## ' heading"
    body
  end

  # [[name, block-body], …] in page order, split on the H3 axis headings.
  def parsed_blocks
    desks_section.scan(/^### (.+?)\n(.*?)(?=^### |\z)/m)
  end

  def test_axis_headings_match_the_registry_names_in_order
    page_names = parsed_blocks.map { |name, _| name.strip }
    assert_equal registry.axes.each_axis.map(&:name), page_names,
                 "the ### desk headings must be exactly the AxisRegistry names, in ratified (file) order"
  end

  def test_each_desk_pins_persona_desc_and_members_to_the_registry
    blocks = parsed_blocks.to_h { |name, body| [name.strip, body] }

    registry.axes.each_axis do |axis|
      body = blocks.fetch(axis.name) { flunk "docs/axes.md has no '### #{axis.name}' block" }

      persona = body[/^> (.+)$/, 1]
      assert_equal axis.persona, persona&.strip,
                   "#{axis.name}: the persona blockquote must be VERBATIM from config/axes.yml"

      members_line = body[/^\*\*Members\*\*[^:\n]*:(.+)$/, 1]
      refute_nil members_line, "#{axis.name}: expected a '**Members** (N): …' line"
      page_slugs = members_line.scan(/`([^`]+)`/).flatten
      assert_equal registry.axis_members(axis.name), page_slugs,
                   "#{axis.name}: the member slug list must equal SourceRegistry#axis_members, in order"

      count = body[/^\*\*Members\*\*\s*\((\d+)\):/, 1]
      assert_equal registry.axis_members(axis.name).size.to_s, count,
                   "#{axis.name}: the '(N)' member count must match the slug list"

      # The desc paragraph: the block's one content line that is neither the
      # persona blockquote nor the Members line — pinned verbatim.
      desc = body.lines.map(&:chomp).reject do |line|
        line.strip.empty? || line.start_with?(">") || line.start_with?("**Members**")
      end
      assert_equal [axis.desc], desc,
                   "#{axis.name}: the membership-rationale paragraph must be VERBATIM from config/axes.yml"
    end
  end
end
