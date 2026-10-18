# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::AesAedTitles: the AES shelf mints its documents title-less (the
# corpus JSON carries no title field); the AED stand-off header for the
# same TLA text id does. The pass titles every loaded AES document — the
# original and its -de sibling — by EXACT text-id key. Derived by
# construction: f(canonical/aed + the loaded aes rows), re-filled at
# rebuild, builder refresh, and after aes/aed syncs (the 84000→Derge
# title-crosswalk mold).
class AesAedTitlesTest < Minitest::Test
  FIXTURES_ROOT = Nabu::TestSupport::FIXTURES_ROOT

  ARCH = "urn:nabu:aes:bbawarchive:26BP5JT5RZEDHDDU2R5TMUBD24"
  PLACEHOLDER = "urn:nabu:aes:bbawarchive:IMLY3YQIZFHHNJUGOZXVPOJTGU"
  SAWLIT = "urn:nabu:aes:sawlit:YSJ3UHIOBJEILCD7KFQIGVOCLY"

  def setup
    @catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(@catalog)
    @aes = @catalog[:sources].insert(slug: "aes", name: "AES", adapter_class: "X", license_class: "attribution")
    @other = @catalog[:sources].insert(slug: "other", name: "O", adapter_class: "X", license_class: "open")
    [ARCH, "#{ARCH}-de", PLACEHOLDER, SAWLIT].each { |urn| doc(@aes, urn) }
    @canonical = Dir.mktmpdir
    File.symlink(File.join(FIXTURES_ROOT, "aes", "aed"), File.join(@canonical, "aed"))
  end

  def teardown
    @catalog.disconnect
    FileUtils.remove_entry(@canonical)
  end

  def doc(source_id, urn)
    @catalog[:documents].insert(source_id: source_id, urn: urn, language: "egy", content_sha256: "x")
  end

  def titles
    @catalog[:documents].order(:urn).select_hash(:urn, :title)
  end

  def run_pass(canonical_dir = @canonical)
    Nabu::AesAedTitles.new(catalog: @catalog, canonical_dir: canonical_dir).run
  end

  def test_titles_originals_and_their_german_siblings_by_exact_text_id
    result = run_pass
    assert_equal "pBerlin P 21002 verso (99 E)", titles[ARCH]
    assert_equal "pBerlin P 21002 verso (99 E)", titles["#{ARCH}-de"],
                 "the -de sibling is the same text in translation (the elephantine -en precedent)"
    assert_equal "〈Stele des Nebanch (aus Abydos)〉", titles[SAWLIT]
    assert_equal 3, result.titled
  end

  def test_placeholder_titles_leave_the_row_untitled
    result = run_pass
    assert_nil titles[PLACEHOLDER], "〈TEXT〉 is an editorial placeholder, never a title"
    assert_equal 1, result.untitled
  end

  def test_other_sources_are_never_touched
    doc(@other, "urn:nabu:other:26BP5JT5RZEDHDDU2R5TMUBD24")
    run_pass
    assert_nil titles["urn:nabu:other:26BP5JT5RZEDHDDU2R5TMUBD24"]
  end

  def test_rerun_is_idempotent
    run_pass
    before = titles
    run_pass
    assert_equal before, titles
  end

  def test_absent_aed_tree_is_a_clean_noop
    result = run_pass(Dir.mktmpdir)
    assert_equal 0, result.titled
    assert_nil titles[ARCH]
  end
end
