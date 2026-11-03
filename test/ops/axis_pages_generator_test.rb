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
          poly:
            adapter: TestAdapter
            wired: true
            sync_policy: manual
            multilingual: true
            axes: [alpha]
          local-notes:
            adapter: Nabu::Adapters::LocalNotes
            wired: true
            sync_policy: manual
            axes: [alpha]
          local-lemmas:
            adapter: Nabu::Adapters::LocalLemmas
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
          output_dir: File.join(root, "out"), catalog_path: catalog_path,
          fulltext_path: File.join(root, "fulltext.sqlite3"), as_of: AS_OF
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
      seed_pack(catalog)
      seed_local_shelves(catalog, path)
      Nabu::Store::SourceStats.derive!(catalog, note: "test seed")
      catalog.disconnect
    end

    # The multilingual pack (`multilingual: true`, whole-source member):
    # five zho documents — more than any desk-proper code holds, the
    # Celtic-desk shape — plus one l01 document, a code the desk's own
    # shelf also holds.
    def seed_pack(catalog)
      src = catalog[:sources].insert(slug: "poly", name: "Poly", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      ((["zho"] * 5) + ["l01"]).each_with_index do |code, i|
        catalog[:documents].insert(
          source_id: src, urn: "urn:nabu:poly:#{code}:#{i}", title: code, language: code,
          content_sha256: "x", revision: 1, withdrawn: false
        )
      end
    end

    # P105-5a: the owner-notes and lemma shelves hold their content
    # outside documents — urn_notes rows and tier-silver fulltext rows.
    def seed_local_shelves(catalog, catalog_path)
      catalog[:sources].insert(slug: "local-notes", name: "Notes",
                               adapter_class: "Nabu::Adapters::LocalNotes",
                               license_class: "open", enabled: true)
      catalog[:sources].insert(slug: "local-lemmas", name: "Lemmas",
                               adapter_class: "Nabu::Adapters::LocalLemmas",
                               license_class: "open", enabled: true)
      2.times do |i|
        catalog[:urn_notes].insert(urn: "urn:nabu:pack:big:#{i}", note: "n#{i}",
                                   topic: "reading", added: "2026-07-28", provenance: "owner")
      end
      fulltext = Nabu::Store.connect_fulltext(File.join(File.dirname(catalog_path), "fulltext.sqlite3"))
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      3.times do |i|
        fulltext[:passage_lemmas].insert(passage_id: i,
                                         language: "got", lemma_raw: "w#{i}", lemma_folded: "w#{i}",
                                         surface_forms: "w#{i}", tier: i.zero? ? "gold" : "silver")
      end
      fulltext.disconnect
    end

    def test_holdings_cells_census_the_notes_and_lemma_shelves
      with_generator_env do |out|
        page = File.read(File.join(out, "alpha.md"))
        notes_row = page.lines.find { |l| l.start_with?("| `local-notes` |") }
        refute_nil notes_row, "the notes shelf rides the alpha desk table"
        assert_includes notes_row, "2 notes", "live owner notes must never read as nothing held"
        lemma_row = page.lines.find { |l| l.start_with?("| `local-lemmas` |") }
        refute_nil lemma_row
        assert_includes lemma_row, "2 lemma rows", "tier-silver rows are the shelf's holdings"
      end
    end

    def test_languages_line_is_dated_counted_descending_and_capped
      with_generator_env do |out|
        page = File.read(File.join(out, "alpha.md"))
        line = page[/^\*\*Languages on this desk\*\* (.+)$/, 1]
        refute_nil line, "the alpha page must carry the languages line"
        assert_includes line, "as of 28 July 2026", "the list is dated (the holdings-cell rule)"
        assert line.include?("`big` 3 · `l01` 2 · `l02` 1"),
               "holdings descending, ties by code, a shared code merging both members — got: #{line}"
        assert_match(/… and 2 more \(`nabu axis alpha` lists all\)/, line)
        refute_includes line, "l11", "codes past the cap elide"
        # The line sits inside the shelves section, above the instruments.
        assert_operator page.index("**Languages on this desk**"), :>, page.index("## The shelves")
        assert_operator page.index("**Languages on this desk**"), :<, page.index("## The desk's instruments")
      end
    end

    # The Celtic-desk lesson (November 2026 site review): whole-source
    # membership let a multilingual pack's languages outrank the desk's
    # own ("`zho` 327,296 · `cy` 89,386"). Desk-proper codes — held by a
    # non-pack member — lead; codes reachable ONLY through a pack ride a
    # separate, labelled tail naming the packs, still counted.
    def test_pack_spillover_rides_a_labelled_tail_after_the_desk_proper_languages
      with_generator_env do |out|
        page = File.read(File.join(out, "alpha.md"))
        line = page[/^\*\*Languages on this desk\*\* (.+)$/, 1]
        refute_includes line, "zho", "a pack-only code never ranks among the desk's own languages"
        assert_includes line, "`l01` 2", "a code the desk's own shelf holds stays desk-proper, pack docs merged"
        tail = page[/^\*\*Carried in by multilingual packs\*\* (.+)$/, 1]
        refute_nil tail, "pack-only languages render as a labelled tail"
        assert_includes tail, "`poly`", "the tail names the whole-source packs it comes from"
        assert_includes tail, "`zho` 5", "spillover stays counted — honest, just not leading"
        refute_includes tail, "l01", "a desk-proper code is never repeated in the tail"
        assert_operator page.index("**Carried in by"), :>, page.index("**Languages on this desk**")
        assert_operator page.index("**Carried in by"), :<, page.index("## The desk's instruments")
      end
    end

    def test_a_desk_without_packs_carries_no_spillover_tail
      with_generator_env do |out|
        refute_includes File.read(File.join(out, "empty.md")), "Carried in by"
      end
    end

    # The /axis/ index opens its desk list with a jump line: one in-page
    # anchor per desk, in registry order, matching kramdown's ids for the
    # `### <name>` headings below it.
    def test_index_opens_the_desk_list_with_a_jump_line
      with_generator_env do |out|
        index = File.read(File.join(out, "index.md"))
        jump = index[/^Jump to a desk: (.+)$/, 1]
        refute_nil jump, "the /axis/ index must carry a jump line"
        assert_equal ["[alpha](#alpha)", "[empty](#empty)"], jump.split(" · ")
        assert_operator index.index("Jump to a desk:"), :>, index.index("## The two desks")
        assert_operator index.index("Jump to a desk:"), :<, index.index("### alpha")
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
