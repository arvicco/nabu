# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/cuneiform-senses builder (P102-3): the BY-SA sense-lane
# sidecar the P73 sign-table deliberately deferred — Wiktionary's
# sense glosses for the cuneiform languages (sux · akk · hit),
# republished verbatim from the three kaikki shelves as one CC BY-SA
# dataset beside the CC-BY sign-table core.
class CuneiformSensesBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    %w[wiktionary-sux wiktionary-akk wiktionary-hit].to_h do |slug|
      [slug, EntryRig.new(manifest: ManifestRig.new(
        name: slug, upstream_url: "https://kaikki.org", license: "CC BY-SA 4.0"
      ))]
    end
  end

  def seed_shelf(slug, rows)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter",
                                        license_class: "attribution")
    dict = @catalog[:dictionaries].insert(source_id: source.id, slug: slug, title: slug,
                                          language: slug.split("-").last)
    rows.each_with_index do |(headword, pos, gloss), i|
      @catalog[:dictionary_entries].insert(
        dictionary_id: dict, urn: "urn:nabu:dict:#{slug}:#{headword}:#{pos}",
        entry_id: "#{headword}:#{pos}", key_raw: headword, headword: headword,
        headword_folded: headword, gloss: gloss, body: gloss,
        content_sha256: format("%064x", i), revision: 1,
        withdrawn: headword == "withdrawn-entry"
      )
    end
  end

  def setup
    @catalog = store_test_db
    seed_shelf("wiktionary-sux", [["𒊬", "noun", "orchard"], ["𒊬", "verb", "to write"]])
    seed_shelf("wiktionary-akk", [%w[šarrum noun king]])
    seed_shelf("wiktionary-hit", [
                 %w[𒉿𒀀𒋻 noun water],
                 %w[a noun x], %w[b noun y], %w[c noun z],
                 %w[withdrawn-entry noun gone]
               ])
    # A non-cuneiform wiktionary shelf must never leak in.
    seed_shelf("wiktionary-cu", [%w[слово noun word]])
  end

  def build!(out_dir)
    Nabu::DataBuild::CuneiformSensesBuilder.new(registry: registry_rig)
                                           .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_senses_per_shelf_with_pos_and_language
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "cuneiform-senses.csv"), headers: true)
      assert_equal %w[ID Headword Language_ID Part_Of_Speech Description URN Source], table.headers
      assert_equal %w[akk hit hit hit hit sux sux],
                   table.map { |row| row["Language_ID"] },
                   "the three cuneiform shelves only, language-then-headword order; " \
                   "withdrawn entries and the Slavonic shelf never appear"
      sar = table.select { |row| row["Headword"] == "𒊬" }
      assert_equal [%w[noun orchard], ["verb", "to write"]],
                   sar.map { |row| row.values_at("Part_Of_Speech", "Description") },
                   "one row per sense, POS split from the entry id"
      assert_equal "urn:nabu:dict:wiktionary-akk:šarrum:noun",
                   table.first["URN"]
      assert_equal "wiktionary-akk", table.first["Source"]
      ids = table.map { |row| row["ID"] }
      assert_equal ids.uniq, ids
      assert_equal 7, result.resources.first.rows
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal({ "akk" => 1, "hit" => 4, "sux" => 2 }, evaluation["rows_by_language"])
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:dictionary_entries].where(gloss: "king").update(gloss: "ruler")
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::CuneiformSensesBuilder.new(registry: registry_rig)
                                               .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
