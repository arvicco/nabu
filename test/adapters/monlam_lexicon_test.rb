# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# MonlamLexicon adapter tests (P88-A3): MonlamIT/Tibetan-Lexicon — the
# licensed slice of the Monlam dictionary world: HEADWORD LISTS ONLY
# (Apache-2.0 in-repo; every definitions-bearing Monlam artifact found is
# unlicensed and stays parked). Two lanes, two physical shapes:
#
#   monlam-lexicon-1.txt  the Monlam Dictionary list — UTF-16LE + BOM,
#                         CRLF, a "word" header line (107,113 entries)
#   monlam-lexicon-2.txt  the Monlam GRAND Dictionary list — UTF-8, LF,
#                         no header (342,716 entries; the upstream file has
#                         a censused 24,295-line BLANK HOLE — the late-འ…ཡ
#                         band — so the README's "367,011" overcounts)
#
# gloss stays nil and the body says what the entry IS (the tibetan-verbs
# glossless-honesty precedent); in-file duplicate headwords take the
# occurrence suffix (":2" — the tibetan-verbs idiom).
class MonlamLexiconTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("monlam-lexicon")

  def adapter
    Nabu::Adapters::MonlamLexicon.new
  end

  # --- manifest / capabilities ----------------------------------------------

  def test_manifest_records_the_apache_grant
    manifest = Nabu::Adapters::MonlamLexicon.manifest
    assert_equal "monlam-lexicon", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/Apache/, manifest.license)
    assert_match(/headword/i, manifest.license,
                 "the license line says plainly this is the headword-list slice")
    assert_equal "monlam-wordlist", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::MonlamLexicon.content_kind
  end

  # --- discover / parse -----------------------------------------------------

  def test_discover_yields_one_ref_per_lane_file_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[monlam-lexicon:monlam-lexicon-1.txt monlam-lexicon:monlam-lexicon-2.txt],
                 refs.map(&:id)
  end

  def documents_by_file
    adapter.discover(FIXTURES).to_h do |ref|
      [File.basename(ref.path), adapter.parse(ref)]
    end
  end

  def test_the_utf16_headered_monlam_lane_parses
    document = documents_by_file.fetch("monlam-lexicon-1.txt")
    assert_equal "monlam-lexicon", document.slug
    assert_equal "bod", document.language
    assert_equal 39, document.count, "40 fixture lines minus the 'word' header"
    first = document.entries.first
    assert_equal "monlam:ཀ", first.entry_id
    assert_equal "ཀ", first.headword
    assert_nil first.gloss, "upstream publishes NO definitions under a license — nil is honest"
    assert_match(/Monlam Dictionary/, first.body)
    assert_match(/headword/, first.body)
  end

  def test_the_utf8_headerless_grand_lane_parses
    document = documents_by_file.fetch("monlam-lexicon-2.txt")
    assert_equal 60, document.count, "no header line; every fixture line is an entry"
    first = document.entries.first
    assert_equal "grand:ཀ", first.entry_id
    assert_match(/Grand Dictionary/, first.body)
    refute_nil first.headword_folded
  end

  def test_censused_dirt_and_duplicates_handle_honestly
    # Real censused shapes: trailing tab dirt, an in-file duplicate (377
    # duplicated headwords in lex-2, max ×2), an empty line (the 24,295-line
    # upstream hole), NFC-unstable composition-excluded vowels (U+0F75
    # decomposes under NFC — the Tibetan exclusion quirk).
    io = StringIO.new("ཀ་ཀ\t\nཀ་ཀ\n\nཀ་ཏྤཱུ་ར\n")
    document = Nabu::Adapters::MonlamWordlistParser.new.parse(
      io, lane: "grand", lane_title: "Monlam Grand Dictionary", header: false,
          slug: "monlam-lexicon", language: "bod", title: "t", canonical_path: "x"
    )
    ids = document.entries.map(&:entry_id)
    assert_equal ["grand:ཀ་ཀ", "grand:ཀ་ཀ:2", "grand:ཀ་ཏྤཱུ་ར"], ids,
                 "trailing dirt strips; empties skip; duplicates take the occurrence suffix"
    assert document.entries.last.headword.unicode_normalized?(:nfc),
           "boundary NFC applies (bod is not exempt) — U+0F75 decomposes"
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["monlam-lexicon"]
    refute_nil entry, "config/sources.yml must register monlam-lexicon"
    assert_equal Nabu::Adapters::MonlamLexicon, entry.adapter_class
    assert entry.wired, "live (first sync verified + owner sign-off 2026-08-30; flipped 2026-08-31)"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
