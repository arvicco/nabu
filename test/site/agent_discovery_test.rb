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
      assert_match(/^Sitemap: \{\{ '\/sitemap\.xml' \| absolute_url \}\}$/, robots)
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

    def test_the_site_concept_doi_is_the_citation_cff_doi
      citation = YAML.safe_load_file(File.join(ROOT, "CITATION.cff"))
      assert_equal citation.fetch("doi"), config.fetch("concept_doi")
      author = citation.fetch("authors").first.values_at("given-names", "family-names").join(" ")
      assert_equal author, config.fetch("author_name")
    end
  end
end
