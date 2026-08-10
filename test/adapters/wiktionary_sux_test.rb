# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Wiktionary-Sumerian (P68-1, the Q8 sign-card sense lane): the kaikki.org
# per-language JSONL as the sixth kaikki dictionary shelf — the
# wiktionary-cu mold verbatim (parser family wiktionary-jsonl, FileFetch,
# deprecation caveat, CC BY-SA dual). The card-side point: 1,314 of the
# 2,499 entries carry PURE-CUNEIFORM headwords (𒊬), so the cuneiform sign
# card can join senses by glyph; descendants carry the sux→akk borrowing
# chains (reflexes: true). Trimmed-real fixture (13 entries: 𒊬/𒀭/𒀊 +
# the "ab" romanization pointer).
class WiktionarySuxTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-sux")

  KAIKKI_URL = "https://kaikki.org/dictionary/Sumerian/kaikki.org-dictionary-Sumerian.jsonl"

  def adapter = Nabu::Adapters::WiktionarySux.new

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  # --- manifest + content kind ---------------------------------------------

  def test_manifest_identifies_the_wiktionary_sux_source
    manifest = adapter.manifest
    assert_equal "wiktionary-sux", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal KAIKKI_URL, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
    assert_equal :dictionary, Nabu::Adapters::WiktionarySux.content_kind
    assert Nabu::Adapters::WiktionarySux.reflex_bearing?, "the sux→akk chains mint reflexes"
  end

  # --- discover → parse ----------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-sux:kaikki.org-dictionary-Sumerian.jsonl"], refs.map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_sux_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wiktionary-sux", document.slug
    assert_equal "sux", document.language
  end

  def test_cuneiform_headwords_carry_their_glosses
    orchard = document.entries.find { |e| e.headword == "𒊬" && e.body.include?("orchard") }
    refute_nil orchard, "the 𒊬 noun entry glosses 'orchard' — the card-join exemplar"
  end

  def test_the_sux_to_akk_descendant_chain_mints_a_reflex
    entry = document.entries.find { |e| e.headword == "𒊬" && e.reflexes.any? }
    refute_nil entry, "𒊬 → Akkadian 𒊬 (kirûm) rides the descendants tree"
    reflex = entry.reflexes.first
    assert_equal "akk", reflex.lang_code
  end

  def test_the_romanization_pointer_entry_rides_too
    assert document.entries.any? { |e| e.headword == "ab" },
           "kaikki's romanization pointer entries are entries — the fold finds them"
  end
end
