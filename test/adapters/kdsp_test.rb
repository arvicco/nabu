# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Kdsp (02-sources row 242): KDSP 1.0, the corpus of
# longer narrative Slovenian prose 1836–1918 (CLARIN.SI hdl 11356/1823,
# CC BY 4.0) — 262 texts aggregated from Wikivir, ELTeC-slv and dLib,
# each classed by type/subtype/theme/canonicity, authors in a corpus
# personography. Fixtures: four real works trimmed (ELTeC 1836 — the
# PriLit overlap witness; Wikivir 1863; ELTeC 1870 with the milestone;
# dLib 1876 with verse) + the corpus file whole.
class KdspTest < Minitest::Test
  include AdapterConformance

  SRECA = "urn:nabu:kdsp:KDSP001"
  DETELJICA = "urn:nabu:kdsp:KDSP003"
  ZALOST = "urn:nabu:kdsp:KDSP010"
  IDEALIST = "urn:nabu:kdsp:KDSP020"

  def conformance_adapter = Nabu::Adapters::Kdsp.new
  def conformance_workdir = Nabu::TestSupport.fixtures("kdsp")
  def conformance_expected_source_id = "kdsp"

  def documents
    @documents ||= begin
      adapter = conformance_adapter
      adapter.discover(conformance_workdir).to_h { |ref| [ref.id, adapter.parse(ref)] }
    end
  end

  def test_discovers_the_works_and_never_the_corpus_file
    assert_equal [SRECA, DETELJICA, ZALOST, IDEALIST], documents.keys,
                 "KDSP.xml (teiCorpus), KDSP-meta.tsv and 00README.txt never discover; urns sort"
  end

  def test_blocks_cite_upstream_ids_in_body_order
    doc = documents.fetch(SRECA)
    assert_equal 8, doc.count
    assert_equal "#{SRECA}:d1.h1", doc.first.urn
    assert_equal "UVOD", doc.first.text
    assert_equal({ "unit" => "head" }, doc.first.annotations)
    second = doc.to_a[1]
    assert_equal "#{SRECA}:d1.p1", second.urn
    assert second.text.start_with?("Blizu mesta L., v vasi"), second.text
    assert_equal "#{SRECA}:d2.d1.h1", doc.to_a.last.urn, "nested divs keep upstream's dotted path"
  end

  def test_verse_groups_are_one_passage_with_line_breaks
    lg = documents.fetch(IDEALIST).find { |p| p.urn.end_with?(":d1.lg2") }
    assert_equal "Srce spet je ozdravelo,\nPolje v prsih zdaj veselo:\nNehal strastij je prepir,\n" \
                 "Sladek v nedrih vlada mir.", lg.text
    assert_equal "lg", lg.annotations["unit"]
  end

  def test_milestone_mints_nothing
    doc = documents.fetch(ZALOST)
    assert_equal(%w[d1.h1 d1.p1 d16.h1 d16.p44 d16.p45 d16.p46 d16.p47],
                 doc.map { |p| p.urn.delete_prefix("#{ZALOST}:") })
  end

  def test_header_mines_title_date_source_and_person
    meta = documents.fetch(SRECA).metadata
    assert_equal "Sreča v nesreči", documents.fetch(SRECA).title, "the bibl's main title, not the [KDSP] label"
    assert_equal({ "not_before" => 1836, "not_after" => 1836, "raw" => "1836" }, meta["date"])
    assert_equal "Cigler, Janez", meta["author"]
    assert_equal "CiglerJanez", meta["author_ref"]
    assert_equal %w[M 1792 1867 duhovnik],
                 meta.values_at("author_sex", "author_birth", "author_death", "author_occupation"),
                 "the corpus personography joins by @corresp"
    assert_equal "ELTeC", meta["digital_source"]
    assert_equal "https://github.com/COST-ELTeC/ELTeC-slv/blob/v0.7.1/level1/SLV10003.xml",
                 meta["digital_source_url"]
    assert_equal "sl", documents.fetch(SRECA).language
  end

  def test_text_class_becomes_facets_and_plain_classes
    meta = documents.fetch(DETELJICA).metadata
    assert_equal "povest", meta.dig("facets", "genre", "value")
    assert_equal "poučno_vzgojna", meta.dig("facets", "subgenre", "value")
    assert_equal "družinska", meta.dig("facets", "subject", "value")
    assert_equal %w[visoka kratka D4], meta.values_at("canonicity", "size", "period_slot")
    assert_equal "Wikivir", meta["digital_source"]
    assert_nil documents.fetch(ZALOST).metadata.dig("facets", "subgenre"), "no subtype catRef, no facet"
  end

  def test_dlib_source_is_recorded
    meta = documents.fetch(IDEALIST).metadata
    assert_equal "dLib", meta["digital_source"]
    assert_equal "https://www.dlib.si/details/URN:NBN:SI:DOC-R7R8ADI9", meta["digital_source_url"]
    assert_equal 1876, meta.dig("date", "not_before")
  end

  def test_fetch_is_zip_fetch_of_the_plain_tei_edition
    assert_equal "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1823/KDSP.TEI.zip",
                 Nabu::Adapters::Kdsp::ZIP_URL
    assert_equal "attribution", Nabu::Adapters::Kdsp.manifest.license_class
  end
end
