# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/char-postings builder (P73-8 + the Edubba P-1 rider): the Han
# character × source doc-frequency census published — license slicing
# (nc out) censused, codepoint-minted IDs, deterministic order.
class CharPostingsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "kanripo" => EntryRig.new(manifest: ManifestRig.new(
      name: "Kanseki Repository", upstream_url: "https://kanripo.example", license: "CC BY-SA 4.0"
    )) }
  end

  def setup
    @catalog = store_test_db
    @kanripo = Nabu::Store::Source.create(slug: "kanripo", name: "Kanripo",
                                          adapter_class: "TestAdapter", license_class: "attribution")
    @cbeta = Nabu::Store::Source.create(slug: "cbeta", name: "CBETA",
                                        adapter_class: "TestAdapter", license_class: "nc")
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @fulltext.create_table(:char_postings) do
      Integer :source_id
      String :char
      String :language
      Integer :docs
    end
    [[@kanripo.id, "顏", "lzh", 135], [@kanripo.id, "子", "lzh", 2900],
     [@cbeta.id, "顏", "lzh", 77]].each do |source_id, char, language, docs|
      @fulltext[:char_postings].insert(source_id: source_id, char: char,
                                       language: language, docs: docs)
    end
  end

  def teardown = @fulltext.disconnect

  def build!(out_dir)
    Nabu::DataBuild::CharPostingsBuilder
      .new(fulltext: @fulltext, registry: registry_rig)
      .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_the_census_with_codepoint_ids
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "char-postings.csv"), headers: true)
      assert_equal %w[ID Char Language_ID Count Source], table.headers
      assert_equal [%w[kanripo-U5B50 子 lzh 2900 kanripo], %w[kanripo-U984F 顏 lzh 135 kanripo]],
                   table.map(&:fields),
                   "publishable rows only, codepoint-minted IDs, (source, codepoint) order"
      assert_equal 2, result.resources.first.rows
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 3, evaluation["postings_rows"]
      assert_equal 2, evaluation["published_rows"]
      assert_equal({ "nc" => 1 }, evaluation["excluded_rows"])
      assert_equal 2, evaluation["distinct_chars"]
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::CharPostingsBuilder
          .new(fulltext: @fulltext, registry: registry_rig)
          .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
