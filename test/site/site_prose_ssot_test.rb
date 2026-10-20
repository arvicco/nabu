# frozen_string_literal: true

require "test_helper"
require "yaml"

module Site
  # The prose single-source-of-truth guard (owner commission 2026-08-28 —
  # "all the numbers/dates need to refer to a single source of truth; the
  # prose must use it, not hardcode"). site/_data/census.yml is the SSOT,
  # regenerated from the live catalog by `rake site:data`; every site page
  # that states a library-wide headline figure must READ it through Liquid
  # (`{{ site.data.census.* }}`), never copy the number into prose where it
  # rots. This test turns that rule into a red/green gate: it fails the day
  # a page hardcodes a headline total or lets a known-stale figure return.
  #
  # SCOPE: the shared, drifting HEADLINE figures — library-wide document /
  # passage / code / source / dictionary / lemma totals and the desk count,
  # plus their as-of date. Per-source and per-section detail numbers (a
  # single corpus's counts in a table row, one dictionary's entry count, the
  # place-program's own census) are page-local facts, out of this guard's
  # scope; the news archive (site/news/_posts) is a dated historical record
  # and is exempt from the FIGURE guards — but NOT from the two
  # rendering-layer guards below (front-matter Liquid, relative_url),
  # which scan every page including posts.
  class SiteProseSsotTest < Minitest::Test
    ROOT = Nabu::Config::PROJECT_ROOT
    SITE = File.join(ROOT, "site")

    # Every page that states a library-wide headline figure must read the
    # census SSOT rather than carry the number in prose.
    SSOT_PAGES = %w[
      index languages library faq tools sources examples about quickstart layers
    ].freeze

    # The pre-SSOT values (and the spelled-out desk phrasings) this migration
    # removed. Their return means a page was hand-edited with a stale copy
    # instead of the Liquid field — exactly the drift the SSOT ends.
    STALE_LITERALS = [
      "975,074",          # old document total
      "68,408,109",       # old passage total
      "68.4 million",     # old passage total, prose form
      "1,407,706",        # old dictionary-entry total
      "1,407,280",        # old dictionary-entry total (variant)
      "122 language codes", # old code count
      "thirty-seven languages", # old gold-lemma language count
      "twenty-three [research desks]",
      "twenty-three [research axes]",
      "twenty-three scholarly hats",
      "all twenty-three",
      # The 2026-09-26 drift sweep (the ko/cmn lesson): literals retired
      # when the September wave outgrew them.
      "803 Wiktionary etymology codes", # → census.etym_codes (1,131 at retirement)
      "the five StarLing bases",        # 15 bases since the September expansion
      "Six etymological databases",     # the starling row's old scope line
      "28,707",                         # old starling entry total
      "27,397",                         # old starling entry total (library.md variant)
      # The 2026-10-11 prose-staleness audit (P118-R5): literals that had
      # outlived three growth waves. The 803-codes line had slipped the
      # guard above by breaking across two lines.
      "the 803 Wiktionary",             # → census.etym_codes
      "fifteen StarLing",               # 56 StarLing shelves by October 2026
      "fifteen bases",                  # the starling scope line, library.md variant
      "Roughly 99%",                    # → census.redistributable_pct (96% at retirement)
      "roughly 99%",
      "45 GB canonical",                # the July 2026 full-library size
      "eldest of four siblings",        # five with Edubba
      "Eighteen further registry rows", # → census.feature_modules
      "Four further registered sources" # → census.local_shelves
    ].freeze

    # Pure-headline pages whose only million-scale totals ARE the SSOT
    # figures — so a comma-grouped 7-plus-digit literal outside a fenced
    # code block means a total was hardcoded instead of rendered.
    STRICT_PAGES = %w[index languages about quickstart].freeze
    MILLION_LITERAL = /\b\d{1,3}(?:,\d{3}){2,}\b/

    def page(name) = File.read(File.join(SITE, "#{name}.md"))

    # The rendered-output guard the 2026-09-18 leak demanded (owner: "even
    # one leak should have been caught — and it wasn't"): Jekyll does NOT
    # run Liquid on front matter, so a {{ ... }} in a title/description
    # renders as literal braces on the live site (the classification news
    # post shipped exactly that). Front matter must be Liquid-free —
    # EVERYWHERE, news posts included.
    def test_front_matter_never_carries_liquid
      Dir.glob(File.join(SITE, "**", "*.md")).each do |path|
        next if path.include?("/vendor/") || path.include?("/_site/")

        lines = File.read(path).lines
        next unless lines.first&.strip == "---"

        front = lines.drop(1).take_while { |line| line.strip != "---" }
        offenders = front.grep(/\{\{|\{%/)
        assert_empty offenders,
                     "#{path.delete_prefix(SITE)} carries Liquid in its FRONT MATTER — Jekyll " \
                     "never renders it there, so the braces ship as literal text on the live " \
                     "page. Move the figure into the body, or state it Liquid-free."
      end
    end

    # Companion rendered-output guard (same 2026-09-18 sweep): the site
    # lives under a baseurl (/nabu), so an internal markdown link written
    # as a bare root path — `](/dates/)` — renders as a BROKEN link on
    # the live site. Internal links must ride `relative_url`. (The
    # v1.5.0 news post shipped exactly that, live-broken for weeks.)
    def test_internal_links_ride_relative_url
      Dir.glob(File.join(SITE, "**", "*.md")).each do |path|
        next if path.include?("/vendor/") || path.include?("/_site/")

        offenders = File.read(path).lines.grep(%r{\]\(/(?!/)})
        assert_empty offenders,
                     "#{path.delete_prefix(SITE)} links an internal path without relative_url — " \
                     "under the /nabu baseurl that renders as a broken link on the live site; " \
                     "write it as ]({{ '/path/' | relative_url }})."
      end
    end

    def test_headline_pages_read_the_census_ssot
      SSOT_PAGES.each do |name|
        assert_includes page(name), "site.data.census",
                        "site/#{name}.md states a headline figure but does not read it from the census " \
                        "SSOT — render it via {{ site.data.census.* }} (regenerated by `rake site:data`), " \
                        "never hardcode."
      end
    end

    def test_no_page_carries_a_known_stale_headline_literal
      Dir.glob(File.join(SITE, "*.md")).each do |path|
        body = File.read(path)
        STALE_LITERALS.each do |literal|
          refute_includes body, literal,
                          "#{File.basename(path)} carries the pre-SSOT literal #{literal.inspect} — " \
                          "the headline figures now come from site/_data/census.yml through Liquid; " \
                          "replace the hardcoded value with its {{ site.data.census.* }} field."
        end
      end
    end

    # site/llms.txt is generated (Nabu::Ops::LlmsTxt), so the place a
    # headline figure could be typed in by hand is the TEMPLATE — the
    # regeneration guard in site_data_test would bless a number baked into
    # it. The template must carry no million-scale literal, no current
    # census headline value, and no known-stale literal; the rendered file
    # carries only million-scale figures the census states.
    LLMS_TEMPLATE = File.join(ROOT, "lib", "nabu", "ops", "llms_txt.rb")
    LLMS_HEADLINE_KEYS = %w[documents passages language_codes live_sources dictionary_entries
                            gold_lemmas gold_lemmas_m gold_languages silver_lemmas_m desks
                            redistributable_pct].freeze

    def test_the_llms_txt_template_hardcodes_no_headline_figure
      template = File.read(LLMS_TEMPLATE)
      assert_empty template.scan(MILLION_LITERAL),
                   "lib/nabu/ops/llms_txt.rb carries a million-scale literal — read the census field instead"
      census = YAML.safe_load_file(File.join(SITE, "_data", "census.yml"))
      LLMS_HEADLINE_KEYS.each do |key|
        value = census.fetch(key).to_s
        next if value.size < 2 # a one-digit value collides with list numbering

        refute_match(/(?<![\d.])#{Regexp.escape(value)}(?![\d.])/, template,
                     "lib/nabu/ops/llms_txt.rb hardcodes census.#{key} (#{value}) — render the field")
      end
      STALE_LITERALS.each { |literal| refute_includes template, literal }
    end

    def test_rendered_llms_txt_states_only_census_totals
      census = YAML.safe_load_file(File.join(SITE, "_data", "census.yml"))
      stated = census.select { |key, _| key.end_with?("_display") }.values
      File.read(File.join(SITE, "llms.txt")).scan(MILLION_LITERAL).each do |literal|
        assert_includes stated, literal, "site/llms.txt states #{literal}, which no census field carries"
      end
    end

    def test_pure_headline_pages_do_not_hardcode_million_scale_totals
      STRICT_PAGES.each do |name|
        prose = page(name).gsub(/```.*?```/m, "") # code blocks show illustrative CLI output
        hits = prose.scan(MILLION_LITERAL)
        assert_empty hits,
                     "site/#{name}.md hardcodes a million-scale total #{hits.inspect} outside a code block — " \
                     "on a pure-headline page every such figure must render from the census SSOT."
      end
    end
  end
end
