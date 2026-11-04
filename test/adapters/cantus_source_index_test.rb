# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::CantusSourceIndex: the Cantus Database's own "Browse
# Sources" listing (segment 4063, "Cantus DB: Sources with Inventories")
# read into per-source metadata — siglum, holding institution, country,
# the curated century labels, the provenance vocabulary, and upstream's
# advertised chant count. The fixture pages are trimmed real pages
# (test/fixtures/cantus/README.md).
class CantusSourceIndexTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/cantus", __dir__)
  Index = Nabu::Adapters::CantusSourceIndex

  def page(number) = File.read(File.join(FIXTURES, "sources-page-#{number}.html"))

  # --- page-level reading ------------------------------------------------------

  def test_a_page_yields_its_rows_with_the_curated_fields
    sources = Index.parse_page(page(1))
    assert_equal [693_666, 123_717], sources.map(&:id)
    hartker = sources.last
    assert_equal "CH-SGs 390", hartker.siglum, "the siglum without the Fragment badge"
    assert_equal "Switzerland", hartker.country
    assert_equal "Sankt-Gallen, Stiftsbibliothek", hartker.institution
    assert_equal ["10th century (975-1000)"], hartker.centuries
    assert_equal ["St. Gall (Sankt-Gallen)"], hartker.provenance
    assert_equal 25, hartker.chants, "the trimmed fixture's advertised count"
    assert_match(/Hartker Antiphoner/, hartker.summary)
  end

  def test_the_fragment_badge_and_melody_count_read_apart
    fragment = Index.parse_page(page(1)).first
    assert_equal "CDN-Mrb MS Medieval 0209", fragment.siglum
    assert_equal 2, fragment.chants
    assert_equal 2, fragment.melodies
    assert_empty fragment.provenance, "no provenance link on the row"
  end

  def test_pagination_and_the_advertised_total
    assert_equal 4, Index.page_total(page(1)), "Displaying 1-2 of 4 sources."
    assert_equal 3, Index.last_page(page(1)), "the last » link"
    assert_equal 3, Index.last_page(page(3)), "the last page names itself"
  end

  def test_a_reshaped_table_raises
    error = assert_raises(Nabu::ParseError) { Index.parse_page("<html><body><table><thead><tr><th>X</th></tr></thead></table></body></html>") }
    assert_match(%r{Chants / Melodies}, error.message)
  end

  # --- the century vocabulary -----------------------------------------------------

  def test_century_labels_band_to_years
    assert_equal [901, 1000], Index.century_years("10th century")
    assert_equal [975, 1000], Index.century_years("10th century (975-1000)"), "the stated span wins"
    assert_equal [1251, 1300], Index.century_years("13th century (2nd half)")
    assert_equal [1401, 1450], Index.century_years("15th century (1st half)")
    assert_equal [801, 900], Index.century_years("09th century"), "upstream's zero-padded label"
    assert_nil Index.century_years("Late 15th century"), "not the curated vocabulary"
  end

  def test_a_source_date_envelopes_every_century_it_names
    date = Index.date_of(["15th century", "16th century"])
    assert_equal 1401, date["not_before"]
    assert_equal 1600, date["not_after"]
    assert_equal "15th century; 16th century", date["raw"]
    assert_nil Index.date_of([]), "no century link = no date claim"
  end

  # --- places ----------------------------------------------------------------------

  def test_religious_orders_name_no_place
    assert_nil Index.place_of(["Dominican"]), "a religious order, not a place"
    assert_equal "St. Gall (Sankt-Gallen)", Index.place_of(["St. Gall (Sankt-Gallen)"])
    assert_equal "Seckau", Index.place_of(%w[Franciscan Seckau]), "the first place-shaped value answers"
  end

  # --- the workdir index ------------------------------------------------------------

  def test_load_reads_every_page_of_a_workdir
    index = Index.load(FIXTURES)
    assert_equal [693_666, 123_717, 123_738, 1_000_458].sort, index.keys.sort
    assert_equal ["13th century (2nd half)"], index.fetch(123_738).centuries
    assert_equal ["Dominican"], index.fetch(123_738).provenance
  end

  def test_load_of_an_attic_reads_the_live_pages_beside_it
    Dir.mktmpdir do |dir|
      FileUtils.cp(Dir.glob(File.join(FIXTURES, "sources-page-*.html")), dir)
      attic = File.join(dir, ".attic")
      FileUtils.mkdir_p(attic)
      assert_equal 4, Index.load(attic).size, "attic CSVs keep their source metadata"
    end
  end
end
