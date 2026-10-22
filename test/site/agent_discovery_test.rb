# frozen_string_literal: true

require "test_helper"
require "yaml"

module Site
  # The site's machine-discovery surface: the files crawlers and AI agents
  # read before (or instead of) the prose — sitemap.xml + robots.txt. Pinned
  # at the source level; the rendered output is read back after a local
  # build (site/MAINTENANCE.md).
  class AgentDiscoveryTest < Minitest::Test
    ROOT = Nabu::Config::PROJECT_ROOT
    SITE = File.join(ROOT, "site")

    def config = YAML.safe_load_file(File.join(SITE, "_config.yml"))
    def read(path) = File.read(File.join(SITE, path))

    # jekyll-sitemap is on the github-pages plugin whitelist, so the
    # production build (actions/jekyll-build-pages) runs it; the site
    # Gemfile carries it for the local preview build.
    def test_the_sitemap_plugin_is_configured_and_bundled
      assert_includes config.fetch("plugins"), "jekyll-sitemap"
      assert_match(/^gem "jekyll-sitemap"/, read("Gemfile"))
      assert_match(/^    jekyll-sitemap \(/, read("Gemfile.lock"))
    end

    # robots.txt names the sitemap through absolute_url — under the /nabu
    # baseurl a bare "/sitemap.xml" would point at the host's root.
    def test_robots_txt_points_at_the_sitemap_through_absolute_url
      robots = read("robots.txt")
      assert_match(/^User-agent: \*$/, robots)
      assert_includes robots.lines.map(&:chomp), "Sitemap: {{ '/sitemap.xml' | absolute_url }}"
      front = robots.split(/^---\s*$/)[1]
      refute_nil front, "robots.txt carries front matter, so Jekyll renders its Liquid"
      refute_match(/\{\{|\{%/, front, "front matter is never Liquid-rendered")
    end

    # SoftwareSourceCode JSON-LD (schema.org) in the page head: the
    # repository, license and concept DOI a citation manager or agent
    # needs, stated once. It carries no corpus figures at all — headline
    # numbers live in the census SSOT and the prose that renders it.
    def test_the_layout_head_includes_the_json_ld
      layout = read("_layouts/default.html")
      head = layout[%r{<head>.*</head>}m]
      refute_nil head
      assert_includes head, "{% include jsonld.html %}"
    end

    def test_the_json_ld_declares_software_source_code_from_site_config
      jsonld = read("_includes/jsonld.html")
      assert_includes jsonld, '<script type="application/ld+json">'
      assert_includes jsonld, '"@type": "SoftwareSourceCode"'
      assert_includes jsonld, "site.repository_url | jsonify"
      assert_includes jsonld, "site.concept_doi"
      refute_match(/site\.data\.census|\d{2,}/, jsonld.gsub(%r{https?://\S+}, ""),
                   "the JSON-LD states no figures (URLs aside)")
    end

    # llms-full.txt: the prose pages as plain text, rendered by Jekyll at
    # build time from the pages' own rendered content — so every census
    # figure in it is the figure the page renders from the SSOT, and the
    # template itself states none.
    LLMS_FULL = "zz-llms-full.txt"

    def test_llms_full_txt_is_a_build_time_page_at_the_root
      template = read(LLMS_FULL)
      front = template.split(/^---\s*$/)[1]
      refute_nil front
      assert_match(%r{^permalink: /llms-full\.txt$}, front)
      assert_match(/^layout: null$/, front)
      refute_match(/\{\{|\{%/, front, "front matter is never Liquid-rendered")
      assert_includes template, "site.nav", "the page list follows the site navigation"
      assert_includes template, ".content", "each page's rendered content is the text"
    end

    def test_llms_full_txt_template_states_no_figure
      body = read(LLMS_FULL).split(/^---\s*$/, 3).last
      refute_match(/\d{3,}|\d,\d{3}/, body, "figures come from the rendered pages, never the template")
    end

    # Jekyll renders site.pages sorted by file name; a page's .content is
    # its rendered HTML only once its own turn has passed. The template's
    # name must therefore sort after every page it reads, or those pages
    # would arrive as raw, un-rendered Liquid.
    def test_llms_full_txt_renders_after_every_page_it_reads
      names = Dir.glob(File.join(SITE, "**", "*.{md,html}")).reject do |path|
        rel = path.delete_prefix("#{SITE}/")
        rel.start_with?("_", "vendor/") || rel.include?("/_")
      end
      names = names.map { |path| File.basename(path) }
      assert_operator names.size, :>, 10
      late = names.reject { |name| name < LLMS_FULL }
      assert_empty late, "#{late.inspect} sort after #{LLMS_FULL} — they would render after it"
    end

    def test_the_site_concept_doi_is_the_citation_cff_doi
      citation = YAML.safe_load_file(File.join(ROOT, "CITATION.cff"))
      assert_equal citation.fetch("doi"), config.fetch("concept_doi")
      author = citation.fetch("authors").first.values_at("given-names", "family-names").join(" ")
      assert_equal author, config.fetch("author_name")
    end
  end
end
