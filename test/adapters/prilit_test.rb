# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Prilit (P95-1): the PriLit corpus of older Slovenian
# narrative prose (CLARIN.SI hdl 11356/1319, CC BY 4.0) — 43 texts,
# 1643–1866, the slavic desk's Early Modern narrative extension a
# century and a half before goo300k's narrative material. The plain-TEI
# edition is the v1 scope (bodies are pure <ab> text blocks); the
# deposit's .ana silver annotation layer is deliberately not ingested.
# The fixture set carries the deposit's ready collation pair — TWO
# editions of Cigler's Sreča v nesreči with DIFFERENT segmentations.
class PrilitTest < Minitest::Test
  include AdapterConformance

  SVETOKRISKI = "urn:nabu:prilit:Svetokriski_NaNovigaLejtaDan1696"
  CIGLER_1838 = "urn:nabu:prilit:Cigler_SrecaVNesreci1838_1840"
  CIGLER_1984 = "urn:nabu:prilit:Cigler_SrecaVNesreci1984"

  def conformance_adapter
    Nabu::Adapters::Prilit.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("prilit")
  end

  def conformance_expected_source_id
    "prilit"
  end

  def documents
    @documents ||= begin
      adapter = conformance_adapter
      adapter.discover(conformance_workdir).to_h { |ref| [ref.id, adapter.parse(ref)] }
    end
  end

  def test_discovers_works_and_skips_the_corpus_header_and_schema_dir
    assert_equal [CIGLER_1838, CIGLER_1984, SVETOKRISKI], documents.keys.sort,
                 "PriLit.xml (teiCorpus root), 00README.txt and schema/*.xml (TEI-rooted " \
                 "schema DOCUMENTATION — the first live sync quarantined them) never discover"
  end

  def test_header_metadata_rides_the_document
    doc = documents.fetch(SVETOKRISKI)
    assert_equal "Na noviga lejta dan (1696) [PriLit]", doc.title
    assert_equal "Janez Svetokriški (1647-1714)", doc.metadata["author"]
    assert_equal "viaf:61726060", doc.metadata["author_ref"]
    assert_equal "1696", doc.metadata["date"]
    assert_equal "high", doc.metadata["date_cert"]
    assert_equal "sl", doc.language
  end

  def test_blocks_become_passages_with_upstream_ids
    doc = documents.fetch(SVETOKRISKI)
    assert_equal 18, doc.count
    first = doc.first
    assert_equal "#{SVETOKRISKI}:1", first.urn, "citation = the ab xml:id's numeric suffix"
    assert_equal "NA NOVIGA LEJTA DAN.", first.text
  end

  def test_the_collation_pair_keeps_both_editions_distinct
    assert_equal 144, documents.fetch(CIGLER_1838).count
    assert_equal 339, documents.fetch(CIGLER_1984).count,
                 "two editions of the same work, different upstream segmentations — " \
                 "provenance-distinct documents, never merged"
  end

  def test_fetch_is_zip_fetch_of_the_tei_edition
    assert_includes Nabu::Adapters::Prilit::ZIP_URL, "11356/1319/PriLit.TEI.zip"
  end
end
