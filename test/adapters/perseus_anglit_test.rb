# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::PerseusAnglit (P95-4): the angLit namespace-shift
# subclass — one upstream work, Beowulf (Klaeber 1922) with its aligned
# English translation. The namespace delta: manifest perseus-anglit,
# language "ang", edition slugs perseus-ang<n>; and the repo's one
# structural quirk, NO __cts__.xml — titles fall back to the urn tail.
# Everything else is the inherited Perseus machinery PerseusTest covers.
class PerseusAnglitTest < Minitest::Test
  include AdapterConformance

  WORKDIR = Nabu::TestSupport.fixtures("perseus-anglit")
  BEOWULF = "urn:cts:angLit:anon.beowulf.perseus-ang1"
  BEOWULF_ENG = "urn:cts:angLit:anon.beowulf.perseus-eng1"

  def conformance_adapter
    Nabu::Adapters::PerseusAnglit.new
  end

  def conformance_workdir
    WORKDIR
  end

  def conformance_expected_source_id
    "perseus-anglit"
  end

  def test_manifest_is_the_anglit_manifest
    manifest = Nabu::Adapters::PerseusAnglit.manifest
    assert_equal "perseus-anglit", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Attribution-ShareAlike 3.0 United States"
    assert_equal "https://github.com/PerseusDL/canonical-angLit", manifest.upstream_url
  end

  def test_default_discover_yields_the_original_only
    ids = Nabu::Adapters::PerseusAnglit.new.discover(WORKDIR).map(&:id)
    assert_equal [BEOWULF], ids, "translations stay out until the registry flag opts in"
  end

  def test_translations_flag_adds_the_aligned_english
    ids = Nabu::Adapters::PerseusAnglit.new(translations: true).discover(WORKDIR).map(&:id)
    assert_equal [BEOWULF, BEOWULF_ENG], ids.sort
  end

  def test_the_english_translation_parses_despite_reversed_refsdecl_order
    # The eng twin declares its legacy refsDecls line-FIRST, card-second —
    # the ang file's order reversed. The first live sync quarantined it
    # under the first-refsDecl-wins rung; the rung now treats each legacy
    # refsDecl as an alternative scheme.
    adapter = Nabu::Adapters::PerseusAnglit.new(translations: true)
    ref = adapter.discover(WORKDIR).find { |r| r.id == BEOWULF_ENG }
    document = adapter.parse(ref)
    assert_equal "eng", document.language
    assert_operator document.count, :>=, 40, "the translation cards parse like the original's"
    assert_includes document.first.text, "Scyld",
                    "Child's 1904 prose rendering of the Prologue"
  end

  def test_beowulf_parses_at_card_grain_with_old_english_text
    adapter = Nabu::Adapters::PerseusAnglit.new
    ref = adapter.discover(WORKDIR).find { |r| r.id == BEOWULF }
    document = adapter.parse(ref)
    assert_equal "ang", document.language
    assert_operator document.count, :>=, 40, "Klaeber's cards chunk the poem"
    opening = document.first.text
    assert_includes opening, "Hwæt", "the most famous opening word in Old English, as edited"
  end
end
