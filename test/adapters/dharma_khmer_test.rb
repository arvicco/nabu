# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::DharmaKhmer (P92-1): the DHARMA Corpus des inscriptions
# khmères (EFEO/ERC, github.com/erc-dharma/tfc-khmer-epigraphy) — the Cœdès
# K-number corpus, 1,187 live editions of Old Khmer and Sanskrit epigraphy.
# The anchor source of the SEA desk, minting the `dharma-epidoc` parser
# family the four sibling repos compose.
#
# Fixtures: two whole real files (retrieved 2026-09-01, see the fixture
# README): K.1 (okz-Latn prose, lb-grain, add/unclear/break="no") and K.2
# (san-Latn verse, lg/l pada grain, gap-heavy opening).
#
# License: per-file <licence target> CC BY-SA 4.0 (the repo README badge
# says CC BY — the in-file grant governs, recorded verbatim per document);
# both variants are class `attribution`.
class DharmaKhmerTest < Minitest::Test
  include AdapterConformance

  K1 = "urn:nabu:dharma-khmer:INSCIK00001"
  K2 = "urn:nabu:dharma-khmer:INSCIK00002"

  def conformance_adapter = Nabu::Adapters::DharmaKhmer.new

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-khmer")

  def conformance_expected_source_id = "dharma-khmer"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn }
  end

  # -- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_with_the_dharma_credit
    manifest = Nabu::Adapters::DharmaKhmer.manifest
    assert_equal "dharma-khmer", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/DHARMA/, manifest.credit)
    assert_equal "dharma-epidoc", manifest.parser_family
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_edition_file_sorted
    refs = adapter.discover(workdir).to_a
    assert_equal [K1, K2, "urn:nabu:dharma-khmer:INSCIK00046"], refs.map(&:id),
                 "urn:nabu:dharma-khmer:<stem sans DHARMA_>, sorted"
    assert(refs.all? { |ref| ref.source_id == "dharma-khmer" })
  end

  # -- K.1: prose at physical-line grain --------------------------------------

  def test_k1_parses_as_okz_prose_at_line_grain
    document = adapter.parse(ref_for(K1))
    assert_equal "okz-Latn", document.language,
                 "the edition div's own xml:lang, verbatim (the gretil san-Latn precedent)"
    assert_match(/K\. 1\./, document.title)
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/",
                 document.metadata["license"],
                 "the in-file <licence target>, recorded per document"
    assert_equal "83211", document.metadata["maturity"],
                 "the working repo's maturity code rides metadata"
    assert_equal "#{K1}:1", document.passages.first.urn
    assert_equal "vā ta śivadeva saṁ ta kurāk kandāy cap vā kandos I ku tai dau",
                 document.passages.first.text,
                 "<add> reads through; <num>/<g> keep their text; lb-grain"
  end

  def test_k1_break_no_lines_stay_separate_line_grain_passages
    document = adapter.parse(ref_for(K1))
    line4 = document.passages.find { |p| p.urn == "#{K1}:4" }
    line5 = document.passages.find { |p| p.urn == "#{K1}:5" }
    refute_nil line4
    refute_nil line5
    assert line4.text.end_with?("Ī"),
           "lb break=\"no\" still ends the physical line (the titus line-grain precedent)"
    assert line5.text.start_with?("śāna"),
           "the straddling word continues on the next line as upstream prints it"
  end

  # -- K.2: verse at stanza.pada grain ----------------------------------------

  def test_k2_parses_as_san_verse_at_pada_grain
    document = adapter.parse(ref_for(K2))
    assert_equal "san-Latn", document.language
    urns = document.passages.map(&:urn)
    assert_includes urns, "#{K2}:1.d", "lg@n.l@n citation for verse editions"
    refute_includes urns, "#{K2}:1.a",
                    "a pada that is only lost-gap markers minted no passage"
    pada = document.passages.find { |p| p.urn == "#{K2}:1.d" }
    assert_match(/m·/, pada.text)
  end

  # -- K.46: pagelike faces (first-sync regression, 2026-09-01) ---------------

  K46 = "urn:nabu:dharma-khmer:INSCIK00046"

  def test_k46_pagelike_faces_prefix_the_citation
    document = adapter.parse(ref_for(K46))
    keys = document.passages.map { |p| p.urn.split(":").last }
    assert(keys.any? { |k| k.start_with?("A.") }, "face A's units carry the face prefix")
    assert(keys.any? { |k| k.start_with?("B.") },
           "face B restarts its numbering — the pagelike milestone opens the section " \
           "(before this fix the restart collided and quarantined the whole file)")
    assert_equal keys.uniq, keys
  end

  # -- sequences and metadata -------------------------------------------------

  def test_passages_are_ordered_by_document_position
    document = adapter.parse(ref_for(K1))
    assert_equal (0...document.passages.size).to_a,
                 document.passages.map(&:sequence)
  end

  # -- defensive quarantines --------------------------------------------------

  def test_an_unknown_language_label_quarantines_the_record
    with_synthetic_edition(lang: "languageb-Latn") do |dir|
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/languageb-Latn/, error.message,
                   "the upstream template-placeholder bug quarantines loudly, never mints")
    end
  end

  def test_an_edition_with_no_text_quarantines
    with_synthetic_edition(lang: "okz-Latn", body: "<p><lb n=\"1\"/></p>") do |dir|
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # -- discovery skips --------------------------------------------------------

  def test_non_dharma_files_are_censused_not_silently_dropped
    Dir.mktmpdir do |dir|
      xml_dir = File.join(dir, "texts", "xml")
      FileUtils.mkdir_p(xml_dir)
      FileUtils.cp(File.join(workdir, "texts/xml/DHARMA_INSCIK00001.xml"), xml_dir)
      File.write(File.join(xml_dir, "BROUILLON-LISTE.xml"), "<TEI/>")
      assert_equal 1, adapter.discover(dir).to_a.size
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert_match(/BROUILLON/, skips.notes.join(" "))
    end
  end

  private

  def with_synthetic_edition(lang:, body: "<p><lb n=\"1\"/>real text here</p>")
    Dir.mktmpdir do |dir|
      xml_dir = File.join(dir, "texts", "xml")
      FileUtils.mkdir_p(xml_dir)
      File.write(File.join(xml_dir, "DHARMA_INSCIK99999.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TEI xmlns="http://www.tei-c.org/ns/1.0">
          <teiHeader><fileDesc>
            <titleStmt><title>K. 99999. Synthetic quarantine probe</title></titleStmt>
            <publicationStmt><availability>
              <licence target="https://creativecommons.org/licenses/by-sa/4.0/"><p>CC BY-SA 4.0</p></licence>
            </availability></publicationStmt>
          </fileDesc></teiHeader>
          <text><body>
            <div type="edition" xml:lang="#{lang}">#{body}</div>
          </body></text>
        </TEI>
      XML
      yield dir
    end
  end
end
