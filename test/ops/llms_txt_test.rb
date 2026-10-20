# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "yaml"

# The site's llms.txt is a pure projection of the census SSOT (+ the desk
# list): every figure it states is a census field, rendered at
# `rake site:refresh`. These tests pin the shape against a seeded census;
# the committed copy's freshness is guarded in test/site/.
class LlmsTxtTest < Minitest::Test
  BASE = "https://example.org/nabu"

  def census
    { "as_of" => "1 January 2030", "documents_display" => "1,234,567",
      "passages_display" => "98,765,432", "language_codes" => 321, "live_sources" => 210,
      "dictionary_entries_display" => "3,000,001", "gold_lemmas_m" => "23.5",
      "gold_languages" => 50, "silver_lemmas_m" => "31.0", "desks" => 2,
      "redistributable_pct" => 94 }
  end

  def desks
    [{ "slug" => "classical", "persona" => "The Classicist", "blurb" => "Greek and Latin", "members" => 18 },
     { "slug" => "cuneiform", "persona" => "The Assyriologist", "blurb" => "Clay", "members" => 9 }]
  end

  def render = Nabu::Ops::LlmsTxt.render(census: census, desks: desks, base_url: BASE)

  def test_opens_with_the_h1_and_a_blockquote_census_summary
    lines = render.lines
    assert_equal "# Nabu\n", lines.first
    quote = render[/^> .*$/]
    refute_nil quote, "the census summary is a blockquote"
    %w[1,234,567 98,765,432 321 210 3,000,001 23.5 94%].each do |figure|
      assert_includes quote, figure, "the summary cites #{figure} from the census"
    end
    assert_includes quote, "1 January 2030", "the summary is dated by the census stamp"
  end

  def test_carries_the_do_not_crawl_line_and_a_numbered_agent_flow
    text = render
    assert_match(/do not crawl/i, text)
    assert_match(/use the lookup files/i, text)
    steps = text.scan(/^(\d+)\. /).flatten.map(&:to_i)
    assert_operator steps.size, :>=, 4
    assert_equal (1..steps.size).to_a, steps, "the agent flow is one numbered list"
  end

  def test_link_sections_name_the_indexes_and_every_desk_dossier
    text = render
    sections = text.scan(/^## (.+)$/).flatten
    assert_equal "Optional", sections.last, "the heavyweight dumps close the file under ## Optional"
    assert_operator sections.size, :>=, 3
    assert_includes text, "](#{BASE}/sources/)"
    assert_includes text, "](#{BASE}/languages/)"
    assert_includes text, "](#{BASE}/axis/)"
    desks.each do |desk|
      assert_includes text, "- [#{desk['persona']}](#{BASE}/axis/#{desk['slug']}/): #{desk['blurb']}"
    end
  end

  def test_every_link_is_absolute
    links = render.scan(/\]\(([^)]+)\)/).flatten
    refute_empty links
    links.each { |link| assert_match(%r{\Ahttps://}, link, "llms.txt links must be absolute") }
  end

  def test_the_optional_section_holds_the_heavyweight_dumps
    optional = render.split(/^## Optional$/).last
    assert_includes optional, "github.com/arvicco/nabu-data"
  end

  def test_write_renders_from_the_committed_ssot_files
    Dir.mktmpdir do |dir|
      data = File.join(dir, "_data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "census.yml"), YAML.dump(census))
      File.write(File.join(data, "desks.yml"), YAML.dump(desks))
      File.write(File.join(dir, "_config.yml"), YAML.dump("url" => "https://example.org", "baseurl" => "/nabu"))

      path = Nabu::Ops::LlmsTxt.write!(site_dir: dir)
      assert_equal File.join(dir, "llms.txt"), path
      assert_equal render, File.read(path)
    end
  end
end
