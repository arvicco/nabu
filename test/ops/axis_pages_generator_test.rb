# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Ops
  # Nabu::Ops::AxisPages, the generator itself (P48-r3 slice): the desk
  # pages' "Languages on this desk" line — the same live-derived,
  # doc-or-entry-counted, holdings-descending, capped list the `nabu axis`
  # card prints, dated like the holdings cells. Honesty degradations: a
  # catalog-less checkout says "not built in this checkout" (the
  # holdings-cell precedent); a desk holding nothing says so. The committed
  # site/axis pages stay guarded by test/site/axis_pages_test.rb — this
  # file tests the generator against its own throwaway registry + catalog.
  class AxisPagesGeneratorTest < Minitest::Test
    AS_OF = Date.new(2026, 7, 28)

    def with_generator_env(build_catalog: true)
      Dir.mktmpdir("axis-pages-gen") do |root|
        File.write(File.join(root, "axes.yml"), <<~YAML)
          alpha:
            persona: "The Alphaist — first letters, read whole."
            desc: "The alpha lane."
          empty:
            persona: "The Emptyist — a desk with nothing yet."
            desc: "The empty lane."
        YAML
        sources_path = File.join(root, "sources.yml")
        File.write(sources_path, <<~YAML)
          pack:
            adapter: TestAdapter
            wired: true
            sync_policy: manual
            axes: [alpha]
          bare:
            adapter: TestAdapter
            wired: false
            sync_policy: manual
            axes: [empty]
        YAML
        catalog_path = File.join(root, "catalog.sqlite3")
        seed_catalog(catalog_path) if build_catalog
        registry = Nabu::SourceRegistry.load(sources_path)
        generator = Nabu::Ops::AxisPages.new(
          registry: registry, fragments_path: File.join(root, "_fragments.yml"),
          output_dir: File.join(root, "out"), catalog_path: catalog_path, as_of: AS_OF
        )
        generator.generate!
        yield File.join(root, "out")
      end
    end

    # The pack source: "big" 3 docs, l01..l11 one each — 12 codes, so the
    # capped line (ten codes) carries an honest "… and 2 more" tail.
    def seed_catalog(path)
      catalog = Nabu::Store.connect(path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      src = catalog[:sources].insert(slug: "pack", name: "Pack", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      codes = (["big"] * 3) + (1..11).map { |i| format("l%02d", i) }
      codes.each_with_index do |code, i|
        catalog[:documents].insert(
          source_id: src, urn: "urn:nabu:pack:#{code}:#{i}", title: code, language: code,
          content_sha256: "x", revision: 1, withdrawn: false
        )
      end
      Nabu::Store::SourceStats.derive!(catalog, note: "test seed")
      catalog.disconnect
    end

    def test_languages_line_is_dated_counted_descending_and_capped
      with_generator_env do |out|
        page = File.read(File.join(out, "alpha.md"))
        line = page[/^\*\*Languages on this desk\*\* (.+)$/, 1]
        refute_nil line, "the alpha page must carry the languages line"
        assert_includes line, "as of 28 July 2026", "the list is dated (the holdings-cell rule)"
        assert line.include?("`big` 3 · `l01` 1"), "holdings descending, ties by code — got: #{line}"
        assert_match(/… and 2 more \(`nabu axis alpha` lists all\)/, line)
        refute_includes line, "l11", "codes past the cap elide"
        # The line sits inside the shelves section, above the instruments.
        assert_operator page.index("**Languages on this desk**"), :>, page.index("## The shelves")
        assert_operator page.index("**Languages on this desk**"), :<, page.index("## The desk's instruments")
      end
    end

    def test_languages_line_says_nothing_held_for_an_empty_desk
      with_generator_env do |out|
        page = File.read(File.join(out, "empty.md"))
        assert_includes page, "**Languages on this desk** — nothing held yet."
      end
    end

    def test_languages_line_stays_honest_without_a_catalog
      with_generator_env(build_catalog: false) do |out|
        page = File.read(File.join(out, "alpha.md"))
        assert_includes page, "**Languages on this desk** — not built in this checkout."
      end
    end

    # The committed-page drift guard parses the shelves table by its `| `slug` |`
    # rows — the languages paragraph must never read as a table row.
    def test_languages_line_is_not_a_table_row
      with_generator_env do |out|
        line = File.read(File.join(out, "alpha.md")).lines.find { |l| l.start_with?("**Languages") }
        refute_nil line
        refute line.start_with?("|"), "the languages line must not collide with the table parser"
      end
    end
  end
end
