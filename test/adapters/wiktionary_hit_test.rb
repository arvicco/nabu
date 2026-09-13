# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Wiktionary-Hittite (P99-7, the Q72-3 deferral): the kaikki.org
# per-language JSONL on the wiktionary-sux mold — parser family
# wiktionary-jsonl, dictionary shelf, FileFetch, deprecation caveat,
# CC BY-SA dual — the second subclass of the shared WiktionaryKaikki
# base. The card-side point: 414 of the 481 records carry
# PURE-CUNEIFORM headwords (𒉿𒀀𒋻 wātar), so the cuneiform sign card
# joins senses by glyph on the hittite desk too; descendants mint
# reflexes (𒋻𒌑𒍣 → Akkadian 𒅴𒁄 — the hit→akk chain).
# Dictionary-shaped, so it mirrors the AdapterConformance checks for
# the dictionary shape (the wiktionary-cu precedent). Trimmed-real
# fixture (4 entries: ekan/𒉿𒀀𒋻/𒋻𒌑𒍣/𒁍𒊒𒌓).
class WiktionaryHitTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-hit")

  KAIKKI_URL = "https://kaikki.org/dictionary/Hittite/kaikki.org-dictionary-Hittite.jsonl"

  def adapter = Nabu::Adapters::WiktionaryHit.new

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  # --- manifest + content kind ---------------------------------------------

  def test_manifest_identifies_the_wiktionary_hit_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wiktionary-hit", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license) # the kaikki statement, verbatim
    assert_equal "attribution", manifest.license_class
    assert_equal KAIKKI_URL, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
    assert_equal :dictionary, Nabu::Adapters::WiktionaryHit.content_kind
    assert Nabu::Adapters::WiktionaryHit.reflex_bearing?, "the descendant chains mint reflexes"
  end

  # --- discover → parse ----------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-hit:kaikki.org-dictionary-Hittite.jsonl"], refs.map(&:id)
    assert_equal "wiktionary-hit", refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_hit_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wiktionary-hit", document.slug
    assert_equal "hit", document.language
    assert_equal 4, document.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  def test_entry_output_is_nfc
    document.entries.each do |entry|
      assert entry.headword.unicode_normalized?(:nfc)
      assert entry.body.unicode_normalized?(:nfc)
    end
  end

  # --- the source-specific claims ------------------------------------------

  def test_the_cuneiform_headword_carries_its_gloss
    water = document.entries.find { |e| e.headword == "𒉿𒀀𒋻" }
    refute_nil water, "𒉿𒀀𒋻 (wātar) rides the fixture — the decipherment exemplar"
    assert_equal "water", water.gloss
  end

  def test_the_hit_to_akk_descendant_chain_mints_a_reflex
    entry = document.entries.find { |e| e.headword == "𒋻𒌑𒍣" && e.reflexes.any? }
    refute_nil entry, "𒋻𒌑𒍣 → Akkadian 𒅴𒁄 rides the descendants tree"
    assert_equal "akk", entry.reflexes.first.lang_code
  end

  def test_the_romanization_pointer_entry_rides_too
    assert document.entries.any? { |e| e.headword == "ekan" },
           "kaikki's romanization pointer entries are entries — the fold finds them"
  end
end
