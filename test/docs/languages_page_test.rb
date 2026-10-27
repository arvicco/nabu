# frozen_string_literal: true

require "test_helper"
require "yaml"

# The figure-drift guard for docs/languages.md (the P96 assumption audit's
# invariant; the site-prose SSOT pattern carried over to docs/). docs/ is
# plain Markdown — no Liquid — so the page keeps its hand-written figures,
# and this test holds them to site/_data/census.yml, the single source of
# truth `rake site:refresh` regenerates from the live catalog at every gate:
#
# - every passage figure the page attributes to a backticked language code
#   (the headline paragraph's `code` … N.NNM mentions, and the largest
#   figure in each single-code table row) must sit within TOLERANCE of that
#   code's census count, for every code census.top_languages carries
#   (codes below its top-16 cut have no census field and stay unchecked);
# - the dated header's passage total, registry-row count, document
#   language-code count and etymology-universe count must sit within
#   TOLERANCE of their census fields.
#
# The tolerance absorbs ordinary growth between gates; a figure that lags
# a growth wave (the 2026-10 jpn 4.16M → 5.59M, cmn 0.97M → 1.30M lesson)
# fails until the prose is refreshed from the census.
class LanguagesPageTest < Minitest::Test
  PAGE = File.join(Nabu::Config::PROJECT_ROOT, "docs", "languages.md")
  CENSUS = File.join(Nabu::Config::PROJECT_ROOT, "site", "_data", "census.yml")
  TOLERANCE = 0.15

  def census = @census ||= YAML.safe_load_file(CENSUS)
  def page = @page ||= File.read(PAGE)

  def top_languages
    census.fetch("top_languages").to_h { |row| [row.fetch("code"), row.fetch("passages")] }
  end

  # "19.0M" → 19_000_000; "33,294,039" → 33_294_039.
  def self.figure(text)
    text.end_with?("M") ? (Float(text.delete_suffix("M")) * 1_000_000).round : Integer(text.delete(","), 10)
  end

  def assert_near(expected, actual, label)
    drift = (actual - expected).abs.fdiv(expected)
    assert_operator drift, :<=, TOLERANCE,
                    "docs/languages.md #{label}: page says #{actual}, census.yml says #{expected} " \
                    "(#{(drift * 100).round}% drift) — refresh the figure from site/_data/census.yml"
  end

  def headline_paragraph
    page[/^\*\*The headline pair is.*?(?=\n\n)/m] || flunk("docs/languages.md lost its headline paragraph")
  end

  def test_headline_paragraph_figures_match_the_census
    checked = 0
    headline_paragraph.scan(/`([^`]+)`([^`]*)/).each do |code, tail|
      next unless top_languages.key?(code)

      tail.scan(/(\d+(?:\.\d+)?M)\b/).flatten.first(1).each do |figure|
        assert_near top_languages.fetch(code), self.class.figure(figure), "headline `#{code}`"
        checked += 1
      end
    end
    assert_operator checked, :>=, 8, "the headline paragraph must name its top languages by `code` with figures"
  end

  def test_table_row_totals_match_the_census
    checked = 0
    page.scan(/^\| `([^`]+)` \|(.*)\|\s*$/).each do |code, rest|
      next unless top_languages.key?(code)

      figures = rest.scan(/(\d+(?:\.\d+)?M)\b|(\d{1,3}(?:,\d{3}){2,}) passages/).flatten.compact
      next if figures.empty?

      assert_near top_languages.fetch(code), figures.map { |text| self.class.figure(text) }.max, "row `#{code}`"
      checked += 1
    end
    assert_operator checked, :>=, 8, "the corpus-languages table must carry dated totals for its top codes"
  end

  def test_dated_header_counts_match_the_census
    total = page[/~(\d+(?:\.\d+)?M) live passages/, 1] || flunk("header passage total missing")
    assert_near census.fetch("passages"), self.class.figure(total), "header passage total"
    rows = page[/(\d+)-row\s+registry/, 1] || flunk("header registry-row count missing")
    assert_near census.fetch("registry_rows"), Integer(rows, 10), "registry rows"
    codes = page[/(\d+) document\s+language codes/, 1] || flunk("header language-code count missing")
    assert_near census.fetch("language_codes"), Integer(codes, 10), "document language codes"
    etym = page[/\*\*([\d,]+)-code\*\* etymology universe/, 1] || flunk("etymology-universe count missing")
    assert_near census.fetch("etym_codes"), Integer(etym.delete(","), 10), "etymology universe"
  end
end
