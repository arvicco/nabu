# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

# Nabu::Adapters::Otdo (P48-5): Old Tibetan Documents Online — 414
# critically edited Old Tibetan texts in Wylie transliteration, crawled as
# per-document HTML pages. Fixtures are REAL pages retrieved 2026-07-28
# (Pt_1287 trimmed to its first 12 lines, the rest whole) — see
# test/fixtures/otdo/README.md.
class OtdoTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("otdo")

  def conformance_adapter
    Nabu::Adapters::Otdo.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "otdo"
  end

  def adapter = conformance_adapter

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:otdo:#{slug}" }
    refute_nil ref, "fixture #{slug} must be discovered"
    adapter.parse(ref)
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_ref_per_page_sorted_by_urn
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[
      urn:nabu:otdo:OZ_5
      urn:nabu:otdo:Or_15000_0018
      urn:nabu:otdo:Pt_1287
      urn:nabu:otdo:insc_Zhol
    ], ids
  end

  def test_discovery_skips_counts_nothing_in_the_fixture_dir
    # The fixture dir carries no archives_index.html sidecar; a real
    # canonical dir would, and it is the one skip-by-rule.
    assert_equal 0, adapter.discovery_skips(FIXTURES).skipped_by_rule
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, Nabu::OtdoFetch::ARCHIVES_FILE), "<html/>")
      File.write(File.join(dir, "Pt_0016.html"), "<html/>")
      assert_equal 1, adapter.discovery_skips(dir).skipped_by_rule,
                   "the catalog sidecar is skipped by rule, never silently"
    end
  end

  # --- the flagship scroll (Pt_1287, Old Tibetan Chronicle) ------------------

  def test_pt_1287_lines_carry_wylie_text_verbatim_at_line_urns
    document = parse("Pt_1287")
    assert_equal "urn:nabu:otdo:Pt_1287", document.urn
    assert_equal "otb", document.language
    assert_equal "Old Tibetan Chronicle.", document.title
    assert_equal 12, document.size, "the fixture trim keeps lines (1)..(12)"
    first = document.passages.first
    assert_equal "urn:nabu:otdo:Pt_1287:1", first.urn
    assert_equal "$ /:/ drI gum btsan po sku chung ba 'I tshe mtshan jIr gdags shes / / " \
                 "ma ma gro zha ma skyi brling ma la drIs na / ma ma 'I mchid nas /",
                 first.text,
                 "Wylie verbatim — reversed gi-gu capital I and shad punctuation preserved"
    assert_equal "1", first.annotations["line"]
  end

  def test_pt_1287_tooltip_glosses_ride_annotations_never_the_text
    document = parse("Pt_1287")
    line3 = document.passages.find { |passage| passage.annotations["line"] == "3" }
    assert_includes line3.text, "ces bgyisna / ma ma gro zha",
                    "the SURFACE form stays in the text"
    refute_match(/bgyisnabgyis/, line3.text, "the gloss is never spliced into the text")
    assert_includes line3.annotations["readings"], { "surface" => "bgyisna", "reading" => "bgyis na" },
                    "OTDO's re-segmentation gloss rides the readings annotation"
  end

  def test_pt_1287_metadata_carries_pressmark_category_and_note
    metadata = parse("Pt_1287").metadata
    assert_equal "Pt 1287", metadata["pressmark"]
    assert_equal "manuscript", metadata["category"]
    assert_includes metadata["note"], "Scroll. The end is missing. Recto, 536 lines."
    refute metadata.key?("references"), "bibliographic apparatus is dropped, not stored"
  end

  # --- the inscription (Zhol, south face of the Potala) ----------------------

  def test_insc_zhol_mints_face_scoped_line_urns
    document = parse("insc_Zhol")
    assert_equal "urn:nabu:otdo:insc_Zhol:e1", document.passages.first.urn
    assert_equal "$ / / blon stag sgra klu", document.passages.first.text
    faces = document.map { |passage| passage.annotations["line"][0] }.uniq
    assert_equal %w[e s n], faces, "east, south and north face lines, in the edition's own order"
    assert_equal 158, document.size
  end

  def test_insc_zhol_metadata_captures_the_inscription_fields
    document = parse("insc_Zhol")
    assert_equal "The Zhol inscription", document.title
    metadata = document.metadata
    assert_equal "inscription", metadata["category"]
    assert_equal "post 763", metadata["date_text"], "dating is FREE TEXT, never a structured claim"
    assert_equal "south of the Potala Palace in Lhasa.", metadata["location"]
    assert_equal "extant", metadata["condition"]
    refute metadata.key?("pressmark"), "inscriptions carry no shelfmark"
  end

  # --- the wood-slip letter (Or.15000) ---------------------------------------

  def test_or_15000_letter_keeps_lacuna_brackets_verbatim_on_recto_verso_labels
    document = parse("Or_15000_0018")
    assert_equal "urn:nabu:otdo:Or_15000_0018:r1", document.passages.first.urn
    assert_includes document.passages.first.text, "[---] [jo] bo rgyal bzang gyi zha' snga[r]",
                    "editorial brackets are OTDO's conventions — kept verbatim"
    labels = document.map { |passage| passage.annotations["line"] }
    assert_equal 12, labels.size, "recto 10 + verso 2"
    assert labels.any? { |label| label.start_with?("v") }, "verso lines keep their v labels"
    assert_equal "Or 15000 0018", document.metadata["pressmark"]
  end

  # --- the Old Zhangzhung exception ------------------------------------------

  def test_oz_documents_are_zhangzhung_not_tibetan
    document = parse("OZ_5")
    assert_equal "xzh", document.language,
                 "OTDO's own catalog calls the OZ_* texts Old Zhangzhung — never blanket otb"
    assert_equal 47, document.size, "the edition's own count: 47 lines"
    assert_equal "urn:nabu:otdo:OZ_5:r1", document.passages.first.urn
    assert_includes document.passages.first.text, "$ / di ga rin mu sklungso"
  end

  # --- identity and shape defenses -------------------------------------------

  def test_a_page_served_under_the_wrong_slug_quarantines
    ref = Nabu::DocumentRef.new(source_id: "otdo", id: "urn:nabu:otdo:Pt_9999",
                                path: File.join(FIXTURES, "insc_Zhol.html"))
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/insc_Zhol/, error.message, "the drift names the page's own header")
  end

  def test_a_page_without_a_transliteration_block_quarantines
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Pt_0016.html"), "<html><h2>Pt_0016</h2><p>no text</p></html>")
      ref = Nabu::DocumentRef.new(source_id: "otdo", id: "urn:nabu:otdo:Pt_0016",
                                  path: File.join(dir, "Pt_0016.html"))
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/textBody1/, error.message,
                   "every catalogued document carries text — absence is page-shape drift, loud")
    end
  end

  # --- license ---------------------------------------------------------------

  def test_license_is_cc_by_4_attribution
    manifest = Nabu::Adapters::Otdo.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution 4.0 International",
                    "the /about Site Policy sentence, quoted verbatim"
  end
end
