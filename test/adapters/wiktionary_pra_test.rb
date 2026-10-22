# frozen_string_literal: true

require "test_helper"

# Wiktionary-Prakrit: the kaikki.org per-language JSONL on the shared
# WiktionaryKaikki base (the South Asian dictionary wave). Wiktionary
# heads its Prakrit entries in Brāhmī (𑀫𑀳𑀼 mahu), and the extract is
# the wave's reflex engine: its descendants trees fan out into the New
# Indo-Aryan languages. Trimmed-real fixture: 3 entries (𑀓𑀇 · 𑀫𑀳𑀼 ·
# 𑀚𑀸𑀬) — an inheritance chain back to Proto-Indo-European, and
# descendants into Konkani, Gujarati and Hindi.
class WiktionaryPraTest < Minitest::Test
  include KaikkiShelfChecks

  def kaikki_adapter_class = Nabu::Adapters::WiktionaryPra
  def kaikki_slug = "wiktionary-pra"
  def kaikki_filename = "kaikki.org-dictionary-Prakrit.jsonl"
  def kaikki_url = "https://kaikki.org/dictionary/Prakrit/kaikki.org-dictionary-Prakrit.jsonl"
  def kaikki_language = "pra"
  def kaikki_entry_count = 3

  def test_brahmi_headwords_carry_their_glosses
    assert_equal "honey", kaikki_entry("𑀫𑀳𑀼").gloss
    assert_equal "poet, seer", kaikki_entry("𑀓𑀇").gloss
  end

  def test_the_inheritance_chain_reaches_proto_indo_european
    codes = kaikki_entry("𑀓𑀇").reflexes.select { |r| r.relation == "inherited" }.map(&:lang_code)
    assert_equal %w[sa inc-pro iir-pro ine-pro], codes
  end

  def test_the_descendants_fan_out_into_new_indo_aryan
    reflexes = kaikki_entry("𑀚𑀸𑀬").reflexes.reject(&:relation)
    assert_equal %w[gu gu hi hi], reflexes.map(&:lang_code)
    assert_includes reflexes.map(&:word), "जाया"
  end
end
