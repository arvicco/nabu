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
  end
end
