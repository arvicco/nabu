# frozen_string_literal: true

require "test_helper"

# The registry-drift guard for the per-axis SITE pages (P37-9 — the site
# rendition of the research desks, one committed Jekyll page each at
# /axis/<name>/, plus the /axis/ index). These pages are GENERATED from the
# live registry by `rake site:axes` (Nabu::Ops::AxisPages), never
# hand-maintained: this test pins every rendered REGISTRY fact — persona,
# desc, and the member slug list — to Nabu::AxisRegistry / SourceRegistry, so
# a config change with no page regeneration fails the gate (the
# test/docs/axes_page_test.rb precedent, now over 18 files + the index).
#
# It does NOT pin the HOLDINGS counts: those are read live from the catalog
# and carry an as-of date, so they drift by design between regenerations and
# stay honest without a gate. What is pinned is the shape of the map, not the
# census numbers inside it.
class AxisPagesTest < Minitest::Test
  ROOT = Nabu::Config::PROJECT_ROOT
  AXIS_DIR = File.join(ROOT, "site", "axis")

  def registry
    @registry ||= Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
  end

  def axes
    registry.axes
  end

  def page_path(name)
    File.join(AXIS_DIR, "#{name}.md")
  end

  # The body of one axis page below its YAML front matter.
  def body(name)
    md = File.read(page_path(name))
    md.sub(/\A---\n.*?\n---\n/m, "")
  end

  # The front-matter block of one axis page.
  def front_matter(name)
    File.read(page_path(name))[/\A---\n(.*?)\n---\n/m, 1]
  end

  # The member slugs backticked in the "## The shelves" table, in row order.
  def table_slugs(name)
    section = body(name)[/^## The shelves\n(.*?)(?=^## )/m, 1]
    refute_nil section, "#{name}: expected a '## The shelves' section closed by a following '## ' heading"
    section.lines.filter_map { |line| line[/^\|\s*`([^`]+)`\s*\|/, 1] }
  end

  def test_every_axis_has_a_page_with_the_right_permalink
    axes.each_axis do |axis|
      assert_path_exists page_path(axis.name), "expected site/axis/#{axis.name}.md — run `rake site:axes`"
      assert_includes front_matter(axis.name), "permalink: /axis/#{axis.name}/",
                      "#{axis.name}: the page must declare permalink /axis/#{axis.name}/"
    end
  end

  def test_each_page_pins_persona_and_desc_verbatim_to_the_registry
    axes.each_axis do |axis|
      body = body(axis.name)
      persona = body[/^> (.+)$/, 1]
      assert_equal axis.persona, persona&.strip,
                   "#{axis.name}: the persona blockquote must be VERBATIM from config/axes.yml (regenerate)"

      # The desc is the first content paragraph after the persona blockquote,
      # before the first '## ' section.
      lead = body[/\A(.*?)(?=^## )/m, 1]
      desc = lead.lines.map(&:chomp).reject { |l| l.strip.empty? || l.start_with?(">") }.first
      assert_equal axis.desc, desc,
                   "#{axis.name}: the membership-rationale paragraph must be VERBATIM from config/axes.yml"
    end
  end

  def test_each_page_pins_the_member_slug_list_to_the_registry
    axes.each_axis do |axis|
      assert_equal registry.axis_members(axis.name), table_slugs(axis.name),
                   "#{axis.name}: the shelves table's member slugs must equal " \
                   "SourceRegistry#axis_members, in order (regenerate with `rake site:axes`)"
    end
  end

  # No STALE pages: a site/axis/*.md file with no matching axis (a renamed or
  # removed desk left behind) fails until it is regenerated/removed.
  def test_no_orphan_axis_pages
    on_disk = Dir.glob(File.join(AXIS_DIR, "*.md")).map { |p| File.basename(p, ".md") } - %w[index]
    assert_equal axes.each_axis.map(&:name).sort, on_disk.sort,
                 "site/axis/*.md must be exactly the registry's axes plus index — run `rake site:axes`"
  end

  # ---- the /axis/ index (the site rendition of docs/axes.md) --------------

  def index_body
    File.read(File.join(AXIS_DIR, "index.md")).sub(/\A---\n.*?\n---\n/m, "")
  end

  # [[name, block-body], …] split on the ### axis headings under "## The
  # eighteen desks".
  def index_blocks
    section = index_body[/^## The eighteen desks\n(.*?)(?=^---\s*$)/m, 1]
    refute_nil section, "the /axis/ index must carry a '## The eighteen desks' section"
    section.scan(/^### (.+?)\n(.*?)(?=^### |\z)/m)
  end

  def test_index_headings_match_the_registry_names_in_order
    assert_path_exists File.join(AXIS_DIR, "index.md"), "expected site/axis/index.md — run `rake site:axes`"
    page_names = index_blocks.map { |name, _| name.strip }
    assert_equal axes.each_axis.map(&:name), page_names,
                 "the /axis/ index desk headings must be exactly the AxisRegistry names, in ratified order"
  end

  def test_index_pins_each_persona_verbatim_and_links_the_page
    blocks = index_blocks.to_h { |name, block| [name.strip, block] }
    axes.each_axis do |axis|
      block = blocks.fetch(axis.name) { flunk "the /axis/ index has no '### #{axis.name}' block" }
      persona = block[/^> (.+)$/, 1]
      assert_equal axis.persona, persona&.strip,
                   "#{axis.name}: the index persona must be VERBATIM from config/axes.yml"
      assert_includes block, "/axis/#{axis.name}/",
                      "#{axis.name}: the index block must link to /axis/#{axis.name}/"
    end
  end
end
