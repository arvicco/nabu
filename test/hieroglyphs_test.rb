# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Hieroglyphs + Adapters::Unikemet (P65-2): the Egyptian sign spine as
# a feature module — Unicode 17's Unikemet.txt (5,067 signs, the normative
# UCD data file, the Egyptian analogue of Unihan) read into a pure seam:
# glyph/codepoint → sign record, Gardiner-style (kEH_JSesh) code → sign.
# Trimmed-real fixture (test/fixtures/unikemet/README.md).
class HieroglyphsTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("unikemet"), "Unikemet.txt")

  def signs
    @signs ||= Nabu::Hieroglyphs.load(FIXTURE)
  end

  # --- registry / module shape ---------------------------------------------

  def test_registry_carries_the_module_row_manual
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    entry = registry["unikemet"]
    refute_nil entry, "unikemet must be registered in config/sources.yml"
    assert entry.feature_module?
    assert_equal "manual", entry.sync_policy
  end

  def test_manifest_records_the_unicode_license_verbatim
    manifest = Nabu::Adapters::Unikemet.manifest
    assert_equal "unikemet", manifest.id
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "UNICODE LICENSE V3"
  end

  def test_discover_yields_no_documents_and_parse_is_unreachable
    adapter = Nabu::Adapters::Unikemet.new
    assert_empty adapter.discover(Nabu::TestSupport.fixtures("unikemet")).to_a
    ref = Nabu::DocumentRef.new(source_id: "unikemet", id: "urn:nabu:unikemet:x",
                                path: Nabu::TestSupport.fixtures("unikemet"), metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  # --- the seam -------------------------------------------------------------

  def test_a_glyph_resolves_to_its_full_record
    falcon = signs.sign_for_glyph("𓅃")
    assert_equal "U+13143", falcon.codepoint
    assert_equal "G-12-002", falcon.cat
    assert_equal "G005", falcon.unik
    assert_equal "C", falcon.core
    assert_equal "A falcon.", falcon.desc
    assert_equal "Logogram (Horus)", falcon.func
    assert_equal "ḥr", falcon.fval
    assert_equal "G5", falcon.jsesh
    assert_equal "G5", falcon.hg
    assert_equal "184,14", falcon.ifao
  end

  def test_a_gardiner_style_code_resolves_via_the_jsesh_field
    assert_equal "U+13171", signs.sign_for_code("G43").codepoint
    assert_equal "U+13216", signs.sign_for_code("N35").codepoint
    assert_nil signs.sign_for_code("Z99")
  end

  def test_absent_fields_are_nil_never_placeholders
    legacy = signs.sign_for_codepoint("U+1305D")
    assert_equal "L", legacy.core
    assert_nil legacy.desc, "U+1305D carries no kEH_Desc upstream"
    assert_nil legacy.jsesh
    assert_equal "1305C 13440", legacy.alt_seq
  end

  def test_extended_a_signs_ride_with_default_core
    ext = signs.sign_for_codepoint("U+13460")
    assert_equal "A001F", ext.unik
    assert_nil ext.core, "kEH_Core absent = the upstream default N — stored as absent"
  end

  def test_sign_count_and_glyph_rendering
    assert_equal 6, signs.sign_count
    assert_equal "𓈖", signs.sign_for_code("N35").glyph
  end

  def test_load_default_is_nil_without_the_held_file
    Dir.mktmpdir do |dir|
      config = Nabu::Config.load(root: dir)
      assert_nil Nabu::Hieroglyphs.load_default(config: config)
    end
  end
end
