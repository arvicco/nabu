# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  module Ops
    # The site's llms.txt (https://llmstxt.org): the one file an AI agent
    # should read before touching the site. A pure projection of the census
    # SSOT (site/_data/census.yml) and the desk list (desks.yml), written by
    # `rake site:data` right after SiteData regenerates them — so every
    # figure it states is a census field, never a typed number. The suite
    # regenerates it from the committed SSOT files and fails on any
    # difference (test/site/site_data_test.rb), and refuses a headline
    # literal in this template (test/site/site_prose_ssot_test.rb).
    #
    # Shape: H1, a blockquote census summary, a "do not crawl — use the
    # lookup files" line, a numbered agent flow, H2 link sections for the
    # lookup indexes and the per-desk dossier pages, and "## Optional" (the
    # llms.txt convention for skippable material) for the heavyweight dumps.
    # Links are absolute (url + baseurl from site/_config.yml): an agent
    # reads this file out of context.
    class LlmsTxt
      FILE = "llms.txt"
      REPOSITORY = "https://github.com/arvicco/nabu"
      DATA_REPOSITORY = "https://github.com/arvicco/nabu-data"
      LECTS_SITE = "https://arvicco.github.io/nabu-lects"
      PLACES_SITE = "https://arvicco.github.io/nabu-places"
      CONCEPT_DOI = "https://doi.org/10.5281/zenodo.21361956"

      def self.render(census:, desks:, base_url:)
        new(census: census, desks: desks, base_url: base_url).render
      end

      # Render from the committed SSOT files under +site_dir+ — the drift
      # guard and the writer share this one path.
      def self.from_site(site_dir)
        data = File.join(site_dir, "_data")
        config = YAML.safe_load_file(File.join(site_dir, "_config.yml"))
        render(census: YAML.safe_load_file(File.join(data, "census.yml")),
               desks: YAML.safe_load_file(File.join(data, "desks.yml")),
               base_url: "#{config.fetch('url').chomp('/')}#{config.fetch('baseurl', '')}")
      end

      def self.write!(site_dir:)
        path = File.join(site_dir, FILE)
        File.write(path, from_site(site_dir))
        path
      end

      def initialize(census:, desks:, base_url:)
        @census = census
        @desks = desks
        @base = base_url.chomp("/")
      end

      def render
        [header, flow, indexes, dossiers, optional].join("\n")
      end

      private

      def page(path) = "#{@base}#{path}"

      def header
        c = @census
        <<~TEXT
          # Nabu

          > Nabu is a local, license-honest library of the ancient world: #{c.fetch('documents_display')} documents and #{c.fetch('passages_display')} citable passages in #{c.fetch('language_codes')} language codes from #{c.fetch('live_sources')} live public sources, with #{c.fetch('dictionary_entries_display')} dictionary entries, #{c.fetch('gold_lemmas_m')} million gold-standard lemma annotations in #{c.fetch('gold_languages')} languages (#{c.fetch('silver_lemmas_m')} million more machine-suggested), and #{c.fetch('desks')} research desks; #{c.fetch('redistributable_pct')}% of documents are public-domain or attribution-class (census of #{c.fetch('as_of')}). It is a pipeline and SQLite store that runs on the researcher's own disk — this site describes it; it does not serve the texts.

          Do not crawl this site page by page to inventory the library — use the lookup files below: the source and language indexes and the desk dossiers answer what is held, and the source registry answers it machine-readably.
        TEXT
      end

      def flow
        <<~TEXT
          ## Agent flow

          1. Read this file for the census and the map; every figure above is regenerated from the live catalog at each release gate.
          2. To learn what is held, read the [Sources](#{page('/sources/')}) index (every corpus, its upstream and its license class) and the [Languages](#{page('/languages/')}) index — or the machine-readable [source registry](#{REPOSITORY}/blob/main/config/sources.yml).
          3. To work one field, open its desk dossier below: the shelves, instruments and commands of that scholarly hat.
          4. To search, read or cite the texts themselves, install Nabu locally ([Quickstart](#{page('/quickstart/')})) and connect the read-only MCP server ([Tools](#{page('/tools/')})); citations resolve to stable URNs at verse or tablet-line grain.
          5. Respect each text's license class as the Sources page states it; derived datasets carry their own terms in nabu-data.
          6. Cite Nabu by its [concept DOI](#{CONCEPT_DOI}), which resolves to the latest release.
        TEXT
      end

      def indexes
        <<~TEXT
          ## Lookup indexes

          - [Sources](#{page('/sources/')}): every corpus and dictionary, with upstream attribution and license terms
          - [Languages](#{page('/languages/')}): the language-code census and the headline languages
          - [Library](#{page('/library/')}): the shelf map, corpus by corpus
          - [Research desks](#{page('/axis/')}): the desk index — tags over the source list
          - [Layers](#{page('/layers/')}): when each document was written, where it comes from, and what kind of text it is
          - [Tools](#{page('/tools/')}): the command line and the MCP server
          - [FAQ](#{page('/faq/')}): scope, licensing and citation
          - [Lect registry](#{LECTS_SITE}): the language-stage registry the library's lect claims resolve against
          - [Place registry](#{PLACES_SITE}): the place-matching decisions registry
        TEXT
      end

      def dossiers
        rows = @desks.map do |desk|
          "- [#{desk.fetch('persona')}](#{page("/axis/#{desk.fetch('slug')}/")}): #{desk.fetch('blurb')}"
        end
        "## Desk dossiers\n\n#{rows.join("\n")}\n"
      end

      def optional
        <<~TEXT
          ## Optional

          - [nabu-data](#{DATA_REPOSITORY}): the derived datasets (CLDF + Frictionless), versioned with DOIs — bulk downloads, not lookups
          - [Source repository](#{REPOSITORY}): the full pipeline, registry and documentation
          - [News](#{page('/news/')}): dated release notes, with an Atom feed at #{page('/feed.xml')}
          - [Full site text](#{page('/llms-full.txt')}): every navigation page as plain text in one file, rendered at site build
        TEXT
      end
    end
  end
end
