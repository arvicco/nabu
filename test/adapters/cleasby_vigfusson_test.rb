# frozen_string_literal: true

require "test_helper"

# Cleasby-Vigfusson (1874) on the DefinitionsJsonShelf base. Trimmed-real
# fixture: 4 records of json/cleasby-vigfusson.json (abbadís · Gýmir ·
# the stefja homograph pair) + the rejected no-markup twin's specimen.
class CleasbyVigfussonTest < Minitest::Test
  include StoreTestDB
  include DefinitionsShelfChecks

  def shelf_adapter_class = Nabu::Adapters::CleasbyVigfusson
  def shelf_slug = "cleasby-vigfusson"
  def shelf_url = "https://github.com/stscoundrel/cleasby-vigfusson-dictionary"
  def shelf_language = "non"
  def shelf_entry_count = 4

  def test_a_known_entry_reads_with_its_english_gloss
    abbess = shelf_entry("abbadís")
    assert_equal "abbess", abbess.gloss
    assert_equal "f. abbess. Hkr. iii. 398, Fms. vii. 239, Gþl. 365.", abbess.body
  end

  def test_the_homograph_pair_is_numbered_in_file_order
    assert_equal "to prevent", shelf_entry("stefja:1").gloss
    assert_match(/a suffix indicating a lay with burdens/, shelf_entry("stefja:2").body)
  end
end
