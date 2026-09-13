# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Wiktionary-Akkadian (P99-7, the Q72-3 deferral): the kaikki.org
# per-language JSONL on the wiktionary-sux mold — parser family
# wiktionary-jsonl, dictionary shelf, FileFetch, deprecation caveat,
# CC BY-SA dual — the first subclass of the shared WiktionaryKaikki
# base. The card-side point: 540 of the 1,348 records carry
# PURE-CUNEIFORM headwords (𒁾 Sumerograms), so the cuneiform sign card
# joins senses by glyph; descendants mint reflexes (ṭuppum → Elamite
# 𒁾, Arabic/Hebrew/Syriac chains). Dictionary-shaped, so it mirrors
# the AdapterConformance checks for the dictionary shape (the
# wiktionary-cu precedent): manifest validity, discover→parse
# round-trip, id uniqueness/stability, NFC, license class. Trimmed-real
# fixture (7 entries: urdu/𒁾 x2/šarrum/ṭuppum/šaṭārum x2).
class WiktionaryAkkTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-akk")

  KAIKKI_URL = "https://kaikki.org/dictionary/Akkadian/kaikki.org-dictionary-Akkadian.jsonl"

  def adapter = Nabu::Adapters::WiktionaryAkk.new

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  # --- manifest + content kind ---------------------------------------------

  def test_manifest_identifies_the_wiktionary_akk_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wiktionary-akk", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license) # the kaikki statement, verbatim
    assert_equal "attribution", manifest.license_class
    assert_equal KAIKKI_URL, manifest.upstream_url
    assert_equal "wiktionary-jsonl", manifest.parser_family
    assert_equal :dictionary, Nabu::Adapters::WiktionaryAkk.content_kind
    assert Nabu::Adapters::WiktionaryAkk.reflex_bearing?, "the descendant chains mint reflexes"
  end

  # --- discover → parse ----------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_fetch
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-akk:kaikki.org-dictionary-Akkadian.jsonl"], refs.map(&:id)
    assert_equal "wiktionary-akk", refs.first.source_id
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_akk_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wiktionary-akk", document.slug
    assert_equal "akk", document.language
    assert_equal 7, document.size
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

  def test_the_sumerogram_headword_carries_its_glosses
    tablet = document.entries.find { |e| e.headword == "𒁾" && e.body.include?("Sumerogram of ṭuppum") }
    refute_nil tablet, "the 𒁾 character entry glosses 'Sumerogram of ṭuppum' — the sign-card join"
  end

  def test_a_known_gloss_rides_a_romanized_headword
    king = document.entries.find { |e| e.headword == "šarrum" }
    refute_nil king
    assert_equal "king", king.gloss
  end

  def test_the_akk_to_elx_descendant_chain_mints_a_reflex
    entry = document.entries.find { |e| e.headword == "ṭuppum" }
    refute_nil entry, "ṭuppum rides the fixture"
    assert entry.reflexes.any? { |r| r.lang_code == "elx" && r.word == "𒁾" },
           "ṭuppum → Elamite 𒁾 rides the descendants tree"
  end

  def test_the_alternative_form_pointer_entry_rides_too
    assert document.entries.any? { |e| e.headword == "urdu" },
           "kaikki's alternative-form pointer entries are entries — the fold finds them"
  end
end
