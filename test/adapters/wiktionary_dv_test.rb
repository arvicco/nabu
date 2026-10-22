# frozen_string_literal: true

require "test_helper"

# Wiktionary-Dhivehi: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Thaana
# headwords; the Insular Indo-Aryan line reads back through Prakrit.
# Trimmed-real fixture: 3 entries (ދިވެހި · ފޮތް · މާލެ) — a
# compound with no typed etymon, a Prakrit inheritance into the
# wiktionary-pra headword space, and a place name lent onward. The
# stored code is div (no Dhivehi node in the lect registry yet; the
# dictionary shelf carries the code verbatim).
class WiktionaryDvTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryDv
  def kaikki_slug = "wiktionary-dv"
  def kaikki_filename = "kaikki.org-dictionary-Dhivehi.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Dhivehi/kaikki.org-dictionary-Dhivehi.jsonl"
  def kaikki_language = "div"
  def kaikki_entry_count = 3

  def test_the_prakrit_ancestor_is_an_inherited_etymon
    book = kaikki_entry("ފޮތް")
    assert_equal "book", book.gloss
    reflex = book.reflexes.find { |r| r.lang_code == "pra" }
    assert_equal "𑀧𑀼𑀢𑁆𑀣", reflex&.word, "Inherited from Prakrit puttha — Brāhmī, the pra shelf's own script"
    assert_equal "inherited", reflex&.relation
  end

  def test_the_place_name_lends_onward
    assert(kaikki_entry("މާލެ").reflexes.any? { |r| r.lang_code == "hi" && r.word == "माले" })
  end
end
