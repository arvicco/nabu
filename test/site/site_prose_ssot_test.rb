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
  # plus their as-of date — and, since November 2026, the per-source grain
  # where pages TABULATE it (the /library/ collection sizes, the /sources/
  # holdings column, /quickstart/'s disk figures), all rendered from
  # site/_data/sources.yml. Narrative detail numbers in prose (a dated
  # first-sync count, one dictionary's entry count, the place-program's own
  # census) remain page-local facts, out of this guard's scope; the news
  # archive (site/news/_posts) is a dated historical record and is exempt from the FIGURE guards — but NOT from the two
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
      "Four further registered sources", # → census.local_shelves
      # The November 2026 per-source sweep: the library table's hand sizes
      # had drifted from the page's own prose (Arabic row 9,089 / 34,632,378
      # vs 9,079 / 34,631,499), and the quickstart disk figures were a
      # one-off October measurement — both now render from sources.yml.
      "9,089 / 34,632,378",
      "117 GB canonical",
      "159 GB of derived"
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

    # The landing page's recency is GENERATED, never hand-written (the
    # November 2026 site review: a hand narrative of "the newest wings"
    # lagged the real newest additions by weeks, refreshable only by a
    # rewrite). The block reads the latest news posts through Liquid, so
    # the existing per-gate news duty keeps it current with no new duty —
    # and a hand-written recency phrase may not come back beside it.
    HAND_RECENCY = [/\bnewest wings?\b/i, /\bmost recent(?:ly)? (?:wave|addition)s?\b/i,
                    /\bthe latest (?:wave|additions?)\b/i].freeze

    def test_the_landing_page_recency_renders_from_the_news_posts
      home = page("index")
      assert_match(/\{%-?\s*for post in site\.posts limit:\s*3\s*-?%\}/, home,
                   "site/index.md must render its recent-additions block from site.posts (limit: 3)")
      %w[post.date post.url post.title post.description].each do |field|
        assert_includes home, field, "the recent-additions block must render #{field}"
      end
      HAND_RECENCY.each do |phrase|
        refute_match phrase, home, "site/index.md hand-writes recency (#{phrase.source}) — the " \
                                   "generated recent-additions block is the only recency on the page"
      end
    end

    # Internal phase/packet codes on the published site (the November 2026
    # site review found "since P96", "(P41-3)", "P78-5", "the P41-g census"
    # on the deployed /axis/ pages — meaningless to a reader and exactly the
    # workflow-id class public hygiene bans). The guard bites on the
    # WORKFLOW SHAPES only, never on a bare P-number: this library's own
    # domain cites P-numbers legitimately — the New Testament papyri (P52,
    # P66, P75), CDLI/ORACC tablet ids (P224395) and TEI P5.
    PHASE_CODE_SHAPES = [
      /\b[Ss]ince P\d+\b/,                                  # "since P96"
      /\bP\d+-(?:\d|[a-z])\w*\b/,                           # "P41-3", "P41-g", "P38-r1", "P105-5a"
      /\bthe P\d+ (?:\S+ )?(?:wave|census|pack|refresh|show|survey|gate|phase|mint)\b/i # "the P46 CC0 pack"
    ].freeze

    def test_phase_code_shapes_bite_on_leaks_and_spare_scholarly_tokens
      ["since P96, the KITAB", "Since P91-1 the OKHC", "(P41-3)", "P78-5", "the P41-g census",
       "(P38-4 + P38-r1)", "the P46 CC0 pack"].each do |leak|
        assert PHASE_CODE_SHAPES.any? { |shape| leak.match?(shape) }, "the guard must catch #{leak.inspect}"
      end
      ["P52, the Rylands fragment", "Bodmer P66 and P75", "(P46)", "TEI P5", "P224395:o.1-o.3",
       "urn:nabu:oracc:saao-saa01:P224395"].each do |scholarly|
        refute PHASE_CODE_SHAPES.any? { |shape| scholarly.match?(shape) },
               "#{scholarly.inspect} is a scholarly token, not a workflow id — the guard must spare it"
      end
    end

    # Scanned: every published page (Jekyll's MAINTENANCE.md exclusion
    # and the build/vendor trees aside), the rendered VALUES of the
    # site's YAML sources (comments never reach a page), and the axis
    # registry prose the /axis/ generator projects verbatim.
    def test_published_surfaces_carry_no_internal_phase_codes
      offenders = []
      Dir.glob(File.join(SITE, "**", "*.{md,html,txt}")).each do |path|
        next if path.include?("/vendor/") || path.include?("/_site/") || path.end_with?("/MAINTENANCE.md")

        phase_code_hits(File.read(path)).each { |hit| offenders << "#{path.delete_prefix(SITE)}: #{hit}" }
      end
      Dir.glob(File.join(SITE, "{_data,axis}", "*.yml")).each do |path|
        yaml_strings(YAML.safe_load_file(path)).each do |text|
          phase_code_hits(text).each { |hit| offenders << "#{path.delete_prefix(SITE)}: #{hit}" }
        end
      end
      registry = Nabu::SourceRegistry.load(File.join(ROOT, "config", "sources.yml"))
      registry.axes.each_axis do |axis|
        phase_code_hits("#{axis.persona} #{axis.desc}").each do |hit|
          offenders << "config/axes.yml #{axis.name}: #{hit}"
        end
      end
      assert_empty offenders,
                   "internal phase codes on a published surface — state the content (or a date) " \
                   "instead:\n  #{offenders.join("\n  ")}"
    end

    def phase_code_hits(text)
      PHASE_CODE_SHAPES.flat_map { |shape| text.scan(shape) }.map { |hit| Array(hit).first.inspect }
    end

    def yaml_strings(node)
      case node
      when String then [node]
      when Hash then node.flat_map { |key, value| yaml_strings(key) + yaml_strings(value) }
      when Array then node.flat_map { |value| yaml_strings(value) }
      else []
      end
    end

    # -- the per-source grain (site/_data/sources.yml) --------------------------

    # A cell whose figures are all Liquid output: words may sit beside the
    # tags ("entries"), but no digit is ever typed by hand outside the braces.
    def liquid_figures_only?(cell) = cell.include?("{{") && !cell.gsub(/\{\{.*?\}\}/, "").match?(/\d/)

    # The markdown table rows that follow +header+ (separator line skipped),
    # each split into its trimmed cells.
    def table_rows(body, header)
      lines = body.lines.drop_while { |line| !line.start_with?(header) }
      refute_empty lines, "the table headed #{header.inspect} is gone"
      rows = lines.drop(2).take_while { |line| line.start_with?("|") }
      rows.map { |line| line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip) }
    end

    # The library's collection table: every row's size renders from the
    # generated shelf totals, and every shelf the map names is a linkable
    # row (/library/#shelf-<id>) — exactly once.
    def test_library_collection_sizes_render_from_the_sources_data
      body = page("library")
      assert_includes body, "site.data.sources", "the collection table must read site.data.sources"
      shelves = YAML.safe_load_file(File.join(SITE, "_data", "shelf_members.yml")).keys
      anchors = table_rows(body, "| Collection |").map do |cells|
        message = "library.md collection row #{cells[0].inspect} hand-types its size #{cells[3].inspect} — " \
                  "render it from site.data.sources.shelves (or the census, for the reference shelf)"
        assert liquid_figures_only?(cells[3]), message
        cells[0][/id="shelf-([a-z0-9-]+)"/, 1].tap do |id|
          refute_nil id, "library.md collection row #{cells[0].inspect} carries no shelf-<id> anchor"
        end
      end
      assert_equal shelves.sort, (anchors - ["reference"]).sort,
                   "every shelf in site/_data/shelf_members.yml needs exactly one /library/ table row"
    end

    # The sources page: every corpus row's holdings render from the
    # per-source data, and every slug in a row is an anchor (/sources/#src-<slug>).
    # The table itself is generated (Nabu::Ops::SourcesTable) into the
    # include the page pulls in.
    def test_sources_page_holdings_render_from_the_sources_data
      table = File.read(File.join(SITE, Nabu::Ops::SourcesTable::INCLUDE_FILE))
      table_rows(table, "| Source | Upstream project |").each do |cells|
        message = "sources.md row #{cells[0][/`[^`]+`/]} hand-types its holdings #{cells[3].inspect} — " \
                  "render {{ src[\"<slug>\"].holdings }} from site.data.sources"
        assert liquid_figures_only?(cells[3]), message
        cells[0].scan(/`([a-z0-9_-]+)`/).flatten.each do |slug|
          assert_includes cells[0], %(id="src-#{slug}"), "sources.md row for #{slug} needs its src-#{slug} anchor"
        end
      end
    end

    # Quickstart's disk figures are measurements, regenerated by site:data
    # (du over the canonical tree) — never a typed MB/GB literal in prose.
    def test_quickstart_disk_figures_render_from_the_sources_data
      prose = page("quickstart").gsub(/```.*?```/m, "")
      assert_includes prose, "site.data.sources", "quickstart's sizes must read site.data.sources"
      hits = prose.scan(/\b\d[\d.,]*\s*[MG]B\b/)
      assert_empty hits, "site/quickstart.md hand-types disk sizes #{hits.inspect} — render them from " \
                         "site.data.sources (canonical_display / disk.*)"
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
