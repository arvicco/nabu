# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require "nabu/ops/reconstruction/book"

# The Reconstruction Book guard. docs/reconstruction.md is GENERATED on the
# reference instance (`rake reconstruction:book` — it reads the instance's
# grants and canonical/ attic, which public clones lack), committed, and
# byte-refreshed at the gate like site/_data. This suite therefore guards
# its SHAPE and COVERAGE from TRACKED inputs only, never a byte diff and
# never local/ or canonical/: every public registered source appears
# exactly once across the class sections (a new source turns this red
# until the book is regenerated), no blocked holding is named, every
# section stands, every non-derived capability layer has its row, and no
# internal id leaks.
class ReconstructionBookTest < Minitest::Test
  Book = Nabu::Ops::Reconstruction::Book
  SourceClass = Nabu::Ops::Reconstruction::SourceClass
  ROOT = Nabu::Config::PROJECT_ROOT
  SOURCES_PATH = File.join(ROOT, "config", "sources.yml")
  BOOK_PATH = File.join(ROOT, Book::OUTPUT_FILE)

  SECTIONS = [
    "## 1 · Prerequisites and tools",
    "## 2 · The sister repositories",
    "## 3 · The sources, by how they come back",
    "## 4 · Derivation",
    "## 5 · Enrichments",
    "## 6 · Verification"
  ].freeze

  def registry
    @registry ||= Nabu::SourceRegistry.load(SOURCES_PATH)
  end

  def committed
    @committed ||= File.read(BOOK_PATH, encoding: Encoding::UTF_8)
  end

  def capabilities
    @capabilities ||= YAML.safe_load_file(File.join(ROOT, "config", "capabilities.yml"))
  end

  def section(text, heading)
    start = text.index(heading) or flunk "missing section #{heading.inspect}"
    rest = text[(start + heading.size)..]
    stop = rest.index(/^## /) || rest.size
    rest[0, stop]
  end

  # Section 3 up to the attic paragraph: the per-class source lists.
  def class_lists(text)
    sources = section(text, SECTIONS[2])
    sources[0, sources.index(Book::ATTIC_HEADING) || sources.size]
  end

  # Headings name the class key in code (`manual`); only list lines count.
  def listed_slugs(text)
    class_lists(text).lines.reject { |line| line.start_with?("#") }.join.scan(/`([a-z0-9][a-z0-9-]*)`/).flatten
  end

  # A public-clone render: no grants, no canonical/ — tracked inputs only.
  def rendered
    @rendered ||= Dir.mktmpdir("nabu-book") do |tmp|
      classifier = SourceClass.new(sources_path: SOURCES_PATH, manual_dir: File.join(ROOT, "docs", "manual"),
                                   grants_path: File.join(tmp, "grants.yml"),
                                   canonical_dir: File.join(tmp, "canonical"))
      Book.new(registry: registry, verdicts: classifier.verdicts, capabilities: capabilities,
               tool_tasks: [["tools:embed", "Install the embed stack"], ["tools:hooks", "Install the hooks"]],
               manual_dir: File.join(ROOT, "docs", "manual"),
               census: YAML.safe_load_file(File.join(ROOT, "site", "_data", "census.yml"))).render
    end
  end

  # --- the committed book -------------------------------------------------

  def test_committed_book_carries_every_section_in_order
    positions = SECTIONS.map { |heading| committed.index(heading) }
    missing = SECTIONS.zip(positions).reject(&:last).map(&:first)
    assert positions.all?, "docs/reconstruction.md lacks a section: #{missing}"
    assert_equal positions.sort, positions, "sections out of order"
    assert_includes committed, Book::GENERATED_NOTE
  end

  def test_committed_book_lists_every_public_source_exactly_once
    listed = listed_slugs(committed)
    public = registry.each_source.select(&:public?).map(&:slug).sort
    dupes = listed.tally.select { |_slug, n| n > 1 }.keys
    assert_empty dupes, "sources listed more than once across the class sections: #{dupes}"
    missing = public - listed
    assert_empty missing, "docs/reconstruction.md is stale — sources missing from the class sections " \
                          "(run `rake reconstruction:book` on the reference instance): #{missing}"
    assert_empty listed - public, "the class sections name a source that is not a public registered one"
  end

  def test_committed_book_names_no_blocked_holding
    blocked = registry.each_source.select(&:blocked?).map(&:slug)
    refute_empty blocked, "the registry carries grant-gated blocked sources"
    named = blocked.select { |slug| committed.match?(/(?<![a-z0-9-])#{Regexp.escape(slug)}(?![a-z0-9-])/) }
    assert_empty named, "blocked holdings never appear on a public surface"
    unlisted = committed.scan(/plus (\d+) not listed/).flatten.sum(&:to_i)
    assert_equal blocked.size, unlisted, "the class sections must count every blocked holding, unnamed"
  end

  def test_committed_book_has_a_row_for_every_non_derived_layer
    rows = section(committed, SECTIONS[4]).scan(/^\| `([a-z_]+)` \|/).flatten
    expected = capabilities.fetch("layers").reject { |_name, layer| layer["cost"] == "derived" }.keys
    assert_equal expected.sort, rows.sort, "the enrichments table and config/capabilities.yml disagree"
  end

  def test_committed_book_carries_the_attic_list
    attic = section(committed, SECTIONS[2])[/#{Regexp.escape(Book::ATTIC_HEADING)}.*\z/m]
    refute_nil attic, "the attic paragraph is missing"
    assert_match(/no re-fetch restores/, attic)
  end

  def test_committed_book_names_every_sister_repository
    sisters = section(committed, SECTIONS[1])
    Book.sister_entries(registry).each do |entry|
      assert_includes sisters, "`#{entry.slug}`"
      assert_includes sisters, entry.manifest.upstream_url
    end
  end

  def test_committed_book_carries_no_internal_ids
    [committed, rendered].each do |text|
      # The numero sign, spelled as its codepoint (this file is a tracked
      # surface too); the day-part and grant screens run over the committed
      # book in test/public_hygiene_test.rb.
      refute_match(/\u2116/, text, "internal register ids never appear")
      refute_match(/\b[QRT]-?\d+\b/, text, "internal queue/register/thread ids never appear")
      refute_match(/\bP\d{2,3}\b/, text, "phase narrative never appears")
    end
  end

  # --- the generator --------------------------------------------------------

  def test_every_sister_has_its_seam
    sisters = Book.sister_entries(registry).map(&:slug).sort
    assert_equal %w[edubba-overlay nabu-data nabu-lects nabu-places], sisters
    assert_equal sisters, Book::SISTER_SEAMS.keys.sort, "every sister repository needs its seam named"
  end

  def test_public_clone_render_covers_every_public_source_and_hides_blocked_ones
    listed = listed_slugs(rendered)
    assert_equal registry.each_source.select(&:public?).map(&:slug).sort, listed.sort
    assert_includes rendered, "plus 13 not listed"
  end

  def test_render_lists_tool_tasks_and_tool_recipes_but_no_source_recipe_as_a_tool
    tools = section(rendered, SECTIONS[0])
    assert_includes tools, "`rake tools:embed` — Install the embed stack"
    assert_includes tools, "manual/embed-venv.md"
    refute_includes tools, "manual/achemenet.md", "a source recipe is not a tool recipe"
    refute_includes tools, "manual/README.md"
    refute_match(/\(P\d/, tools, "recipe titles carry no phase tags")
  end

  def test_render_states_census_figures_from_the_census_file
    census = YAML.safe_load_file(File.join(ROOT, "site", "_data", "census.yml"))
    verification = section(rendered, SECTIONS[5])
    assert_includes verification, census.fetch("documents_display")
    assert_includes verification, census.fetch("as_of")
    refute_includes rendered, "nabu reconstruct", "no command that does not exist"
  end

  def test_manual_class_links_each_recipe
    manual = rendered[/^### .*`manual`.*?(?=^### )/m]
    refute_nil manual
    assert_includes manual, "[`achemenet`](manual/achemenet.md)"
    assert_includes manual, "manual/ivdnt-corpora.md", "a multi-source acquisition recipe rides the manual class"
    refute_includes section(rendered, SECTIONS[0]), "manual/ivdnt-corpora.md"
  end
end
