# frozen_string_literal: true

require "test_helper"

# Zoëga (1910) on the DefinitionsJsonShelf base. Trimmed-real fixture: 3
# records of json/zoega.json (abbadis · the brýnn homograph pair) + the
# rejected no-markup twin's specimen.
class ZoegaTest < Minitest::Test
  include StoreTestDB
  include DefinitionsShelfChecks

  def shelf_adapter_class = Nabu::Adapters::Zoega
  def shelf_slug = "zoega"
  def shelf_url = "https://github.com/stscoundrel/old-icelandic-zoega"
  def shelf_language = "non"
  def shelf_entry_count = 3

  def test_a_known_entry_reads_with_its_english_gloss
    abbess = shelf_entry("abbadis")
    assert_equal "abbess", abbess.gloss
    assert_equal "(pl. -ar), f. abbess.", abbess.body
  end

  # The first brýnn record opens with a bare <strong>I)</strong> sense
  # numeral line; the gloss is still the first italic English.
  def test_the_homograph_pair_is_numbered_and_glossed
    assert_equal "prompt, ready", shelf_entry("brýnn:1").gloss
    assert_equal "I)", shelf_entry("brýnn:1").body.lines(chomp: true).first
    assert_equal "-browed", shelf_entry("brýnn:2").gloss
  end
end
