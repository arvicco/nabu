# frozen_string_literal: true

require "test_helper"

# Wiktionary-Kannada: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Trimmed-real
# fixture: 3 entries (ನುಡಿ · ಒಂದು · ಬಸವ) — two Proto-Dravidian
# inheritance etymons and a name whose descendants tree lends into
# Tamil beside its Sanskrit derivation.
class WiktionaryKnTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryKn
  def kaikki_slug = "wiktionary-kn"
  def kaikki_filename = "kaikki.org-dictionary-Kannada.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Kannada/kaikki.org-dictionary-Kannada.jsonl"
  def kaikki_language = "kan"
  def kaikki_entry_count = 3

  def test_the_numeral_inherits_from_proto_dravidian
    one = kaikki_entry("ಒಂದು")
    assert_equal "one (numeral: ೧ (1))", one.gloss
    reflex = one.reflexes.find { |r| r.lang_code == "dra-pro" }
    assert_equal "*onṯu", reflex&.word
    assert_equal "inherited", reflex&.relation
  end

  def test_the_name_carries_a_derived_etymon_and_a_tamil_descendant
    reflexes = kaikki_entry("ಬಸವ").reflexes
    assert(reflexes.any? { |r| r.lang_code == "sa" && r.relation == "derived" })
    assert(reflexes.any? { |r| r.lang_code == "ta" && r.word == "வசவன்" && r.relation.nil? })
  end
end
