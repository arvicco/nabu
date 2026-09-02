# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Ojw adapter tests (P92-5): the Old Javanese Wordnet — the SEA desk's
# glossary, the open stand-in for the license-blocked Zoetmulder OJED.
# One OMW-format tab file; entries are lemmas grouped over their sense
# rows, PWN 3.0 synset ids riding citations (no glosses ship upstream —
# gloss nil is honest, the monlam precedent). Fixture: a real 23-row
# slice of wn-kaw.tab (header line included) covering multi-synset
# lemmas and the 4-column derived-form rows.
class OjwTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ojw")

  def adapter
    Nabu::Adapters::Ojw.new
  end

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  def entry(id)
    document.entries.find { |e| e.entry_id == id }
  end

  def test_manifest_and_content_kind
    manifest = Nabu::Adapters::Ojw.manifest
    assert_equal "ojw", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Moeljadi/, manifest.credit)
    assert_equal :dictionary, Nabu::Adapters::Ojw.content_kind
  end

  def test_discover_yields_the_one_tab_file
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["ojw:wn-kaw.tab"], refs.map(&:id)
    assert_equal "ojw", refs.first.source_id
  end

  def test_lemmas_group_their_senses_into_one_entry
    e = entry("abrĕsih")
    refute_nil e
    assert_equal "kaw", e.language
    assert_nil e.gloss, "no glosses ship upstream — nil is honest"
    assert_match(/00417413-a, 01904845-a, 01905653-a/, e.body,
                 "the PWN 3.0 synset ids ride the body — the cross-lexicon join key")
    assert_match(/mabrĕsih/, e.body, "the derived form rides the body")
  end

  def test_a_multi_synset_lemma_keeps_one_entry
    e = entry("pracima")
    refute_nil e
    assert_match(/08561835-n.*13834399-n/, e.body)
  end

  def test_headwords_are_nfc_with_the_search_fold
    e = entry("abrĕsih")
    assert_equal e.headword, e.headword.unicode_normalize(:nfc)
    refute_empty e.headword_folded
  end

  def test_a_malformed_row_quarantines_the_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "wn-kaw.tab"), "not a wordnet row\n")
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_idempotent_parse
    ids1 = adapter.parse(adapter.discover(FIXTURES).first).entries.map(&:entry_id)
    ids2 = adapter.parse(adapter.discover(FIXTURES).first).entries.map(&:entry_id)
    assert_equal ids1, ids2
    assert_equal ids1.uniq, ids1, "grouping leaves no duplicate entry ids"
  end
end
