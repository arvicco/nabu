# frozen_string_literal: true

require "test_helper"
require "nabu/ops/doc_commands"

# The extraction half of `rake docs:verify`: runnable commands and their
# documented claims pulled out of the walkthrough markdown. Fixtures are
# trimmed real excerpts of site/quickstart.md, docs/quickstart.md and
# docs/mcp.md, so the parser is held to the pages' actual shapes (plain
# command blocks with trailing comments, `$ ` transcripts, backtick spans
# broken across lines, bash continuations, JSON/Python content blocks).
class DocCommandsTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/docs_verify", __dir__)

  def parse(name, **)
    Nabu::Ops::DocCommands.parse(File.read(File.join(FIXTURES, name), encoding: Encoding::UTF_8),
                                 path: name, **)
  end

  def test_plain_blocks_yield_one_command_per_line_with_trailing_comments_split
    page = parse("site_quickstart_excerpt.md")
    texts = page.fenced_commands.map(&:text)

    assert_equal ["git clone https://github.com/arvicco/nabu", "cd nabu", "bundle install",
                  "bin/nabu enable perseus-greek", "bin/nabu sync perseus-greek",
                  "bin/nabu list --axis", "bin/nabu axis celtic", "bin/nabu enable celtic",
                  "bin/nabu sync celtic"], texts
    enable = page.fenced_commands.find { |c| c.text == "bin/nabu enable perseus-greek" }
    assert_equal "add the shelf to your profile", enable.comment
    assert_empty enable.output
  end

  def test_line_numbers_point_at_the_command_in_the_page
    page = parse("site_quickstart_excerpt.md")
    clone = page.fenced_commands.first
    lines = File.readlines(File.join(FIXTURES, "site_quickstart_excerpt.md"))

    assert_equal "git clone https://github.com/arvicco/nabu", lines[clone.line - 1].strip
  end

  def test_inline_spans_join_line_breaks_and_keep_only_bin_nabu_commands
    page = parse("site_quickstart_excerpt.md")
    inline = page.inline_commands.map(&:text)

    assert_includes inline, "bin/nabu quickstart --dry-run"
    assert_includes inline, "bin/nabu define virtus" # broken across two source lines
    assert_includes inline, "bin/nabu enable celtic && bin/nabu sync celtic"
    assert_includes inline, "bin/nabu sync papyri-ddbdp" # a table cell
    refute_includes inline, "config/sources.yml"
    refute_includes inline, "nabu show <urn>" # not a bin/nabu invocation
    refute(page.inline_commands.any?(&:fenced))
  end

  def test_transcript_blocks_carry_their_documented_output
    page = parse("docs_quickstart_excerpt.md")
    show = page.fenced_commands.find { |c| c.text.start_with?("bin/nabu show") }

    assert_equal "bin/nabu show urn:nabu:sblgnt:john:1.1-1.3", show.text
    assert_equal "urn:nabu:sblgnt:john — ΚΑΤΑ ΙΩΑΝΝΗΝ [grc]", show.output.first
    assert_equal 6, show.output.size
    status = page.fenced_commands.find { |c| c.text == "bin/nabu status" }
    assert_equal "…", status.output.first
  end

  def test_bash_continuations_join_into_one_command_and_content_blocks_carry_no_commands
    page = parse("mcp_excerpt.md")
    bash = page.fenced_commands.map(&:text)

    assert_equal ["claude mcp add --scope user nabu --env BUNDLE_GEMFILE=/Users/vb/Dev/nabu/Gemfile " \
                  "-- bundle exec /Users/vb/Dev/nabu/bin/nabu mcp"], bash
    langs = page.blocks.map(&:lang)
    assert_equal %w[json bash json python], langs
    assert_empty page.blocks.first.commands
    assert_includes page.blocks.first.body, %("args": ["exec", "bin/nabu", "mcp"])
  end

  def test_sections_scope_extraction_to_the_named_headings
    page = parse("mcp_excerpt.md", sections: ["4. Registration — Claude Desktop"])

    # The LangChain block sits under a ### heading inside §4, so it rides along.
    assert_equal %w[json python], page.blocks.map(&:lang)
    assert_empty page.fenced_commands
  end

  def test_subsections_ride_inside_their_parent_section
    page = parse("mcp_excerpt.md", sections: ["3. Registration — Claude Code"])

    assert_equal %w[json bash], page.blocks.map(&:lang)
  end

  def test_key_squeezes_whitespace
    assert_equal "bin/nabu enable celtic", Nabu::Ops::DocCommands.key("  bin/nabu   enable\n celtic ")
  end

  def test_unquoted_hash_only_starts_a_comment
    page = Nabu::Ops::DocCommands.parse(%(```\nbin/nabu search "a # b"   # find it\n```\n), path: "x.md")
    command = page.fenced_commands.first

    assert_equal %(bin/nabu search "a # b"), command.text
    assert_equal "find it", command.comment
  end

  def test_normalized_text_squeezes_the_page_for_quote_lookup
    page = parse("site_quickstart_excerpt.md")

    assert page.quotes?("`bin/nabu quickstart --dry-run` prints the set without syncing anything.")
    refute page.quotes?("prints the set while syncing everything")
  end
end
