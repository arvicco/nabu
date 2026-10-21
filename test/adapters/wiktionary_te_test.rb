# frozen_string_literal: true

require "test_helper"

# Wiktionary-Telugu: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Trimmed-real
# fixture: 3 entries (తెలుగు · నాలుగు · బలపము) — two Proto-Dravidian
# inheritance etymons (the starling-dravet reconstruction space) and a
# descendants tree lending into Tamil.
class WiktionaryTeTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryTe
  def kaikki_slug = "wiktionary-te"
  def kaikki_filename = "kaikki.org-dictionary-Telugu.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Telugu/kaikki.org-dictionary-Telugu.jsonl"
  def kaikki_language = "tel"
  def kaikki_entry_count = 3

  def test_the_numeral_inherits_from_proto_dravidian
    four = kaikki_entry("నాలుగు")
    assert_equal "four", four.gloss
    reflex = four.reflexes.find { |r| r.lang_code == "dra-pro" }
    refute_nil reflex, "Inherited from Proto-Dravidian — the inh template mints the ancestor edge"
    assert_equal "inherited", reflex.relation
  end

  def test_the_descendants_tree_lends_into_tamil
    words = kaikki_entry("బలపము").reflexes.select { |r| r.lang_code == "ta" }.map(&:word)
    assert_equal %w[பலப்பம் பல்பம்], words
  end
end
