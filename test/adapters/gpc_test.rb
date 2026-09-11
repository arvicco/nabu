# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Gpc (P97-3): Geiriadur Prifysgol Cymru's CC BY 4.0
# open subset — the Welsh dictionary-shelf occupant, the first
# xlsx-shaped source (parser family gpc-xlsx: in-process ZipReader +
# streaming XML) and a ManualDrop acquisition (the subset arrived by
# email — grant 2026-09-04; the site publication is upstream's future
# channel). Dictionary-shaped, so no passage conformance suite.
class GpcTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("gpc")

  def adapter = Nabu::Adapters::Gpc.new

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  # --- registry / manifest --------------------------------------------------

  def test_manifest_is_attribution_with_the_grant_recorded
    manifest = Nabu::Adapters::Gpc.manifest
    assert_equal "gpc", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY 4.0"
    assert_equal "gpc-xlsx", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Gpc.content_kind
  end

  def test_manual_acquisition_names_the_xlsx
    spec = Nabu::Adapters::Gpc.manual_acquisition
    assert_equal "gpc", spec.slug
    assert(spec.files.any? { |f| f.name.end_with?(".xlsx") && f.required })
  end

  # --- discover / parse -----------------------------------------------------

  def test_discover_yields_one_ref_and_nothing_before_a_drop
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_empty adapter.discover(Dir.mktmpdir).to_a
  end

  def test_parse_yields_the_cy_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "gpc", document.slug
    assert_equal "cy", document.language
    assert_equal 6, document.size, "six real rows, all id-bearing"
  end

  def test_entries_carry_the_stable_gpc_id_and_both_homographs
    ids = document.map(&:entry_id)
    assert_equal ids.uniq, ids
    assert_includes ids, "gpc000002"
    assert_includes ids, "gpc000003"
    a_entries = document.entries.select { |e| e.headword == "a" }
    assert_operator a_entries.size, :>=, 2, "homographs keep distinct entries by gpc id"
  end

  def test_the_body_carries_pos_variants_and_the_gpc_online_link
    entry = document.entries.find { |e| e.entry_id == "gpc000002" }
    assert_includes entry.body, "pos: gn."
    assert_includes entry.body, "variants: ai; y", "underscore-separated variants split honestly"
    assert_includes entry.body, "GPC Online: https://www.geiriadur.ac.uk/gpc/gpc.html?gpc000002",
                    "the grant's link-users condition rides every entry body"
    assert entry.body.unicode_normalized?(:nfc)
  end

  def test_gloss_is_the_first_english_segment_when_present
    entry = document.entries.find { |e| e.entry_id == "gpc000002" }
    assert_equal "in a proper rel. clause with the rel. as subject)", entry.gloss
    no_english = document.entries.find { |e| e.entry_id == "gpc000003" }
    assert_nil no_english.gloss
  end

  def test_entry_ids_are_stable_across_independent_passes
    first = adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id)
    assert_equal first, adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id)
  end
end
