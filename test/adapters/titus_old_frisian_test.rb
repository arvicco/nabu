# frozen_string_literal: true

require "test_helper"

# TITUS Old Frisian adapter tests: the titus_levels family over Shannon's
# Corpus of Old East and West Frisian Texts (one text per page, sentence
# units) and the Brokmer Recht (one paragraph per page). Fixtures are FULL
# real pages (the Ten Commandments, the Seventeen Statutes, two Brokmer
# paragraphs) plus both framesets + index frames (the page census).
#
# The bytes are gated (no redistribution): gitignored
# local/fixtures/titus-old-frisian/ (README: re-cut recipe + sha256); every
# data-bearing case SKIPs when absent — StrictSkips fails it on this box.
class TitusOldFrisianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-old-frisian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  URN = "urn:nabu:titus-old-frisian"
  ADAPTER = Nabu::Adapters::TitusOldFrisian

  def conformance_adapter = ADAPTER.new

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id = SLUG

  def setup
    @adapter = ADAPTER.new
  end

  def documents
    require_fixtures!
    @documents ||= @adapter.discover(FIXTURES).to_h { |ref| [ref.id.split(":").last, @adapter.parse(ref)] }
  end

  def passage(urn)
    documents.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  def test_manifest_carries_the_credit_duty
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes manifest.credit, "Shannon"
    assert_includes manifest.credit, "Deutschen Rechtswörterbuchs"
  end

  def test_the_index_frames_census_248_pages
    require_fixtures!
    census = ADAPTER::EDITIONS.to_h do |id, edition|
      [id, Nabu::TestSupport::TitusIndexCensus.pages(File.join(FIXTURES, id), edition.prefix)]
    end
    assert_equal({ "afrcorp" => 6, "brokmrx" => 242 }, census)
  end

  def test_discover_yields_one_document_per_page
    require_fixtures!
    assert_equal %w[afrcorp.afrco001 afrcorp.afrco002 brokmrx.brokm001 brokmrx.brokm010],
                 @adapter.discover(FIXTURES).map { |ref| ref.id.split(":").last }.sort
    assert_equal 0, @adapter.discovery_skips(FIXTURES).skipped_by_rule
  end

  def test_the_ten_commandments_sentences_with_their_latin_incipit
    document = documents.fetch("afrcorp.afrco001")
    assert_equal "ofs", document.language
    assert_equal 11, document.passages.size
    first = passage("#{URN}:afrcorp.afrco001:OFr.Corp._10_Gebote___1")
    assert_equal "thet erste bod: minna thinne god fore feder ende moder mith inlekere herta.", first.text
    assert_equal({ "unit" => "Sentence", "latin" => "Primun mandatum," }, first.annotations)
    assert_match(/\AHir is scriuen alsa dene bode/, passage("#{URN}:afrcorp.afrco001:OFr.Corp._10_Gebote___0").text)
  end

  def test_each_corpus_page_keys_its_kind_by_its_text_header
    assert_equal "10_Gebote", documents.fetch("afrcorp.afrco001").metadata["work"]
    assert_equal "17_Küren", documents.fetch("afrcorp.afrco002").metadata["work"]
    assert_equal "brokmrx", documents.fetch("brokmrx.brokm010").metadata["work"]
    assert_equal 45, documents.fetch("afrcorp.afrco002").passages.size
  end

  def test_the_brokmer_sentence_carries_its_print_page
    document = documents.fetch("brokmrx.brokm001")
    assert_equal 1, document.passages.size
    sentence = document.passages.first
    assert_equal "#{URN}:brokmrx.brokm001:Brokm._1_1", sentence.urn
    assert_match(/\AThit ist thiu forme kere, ther Brocmon ekeren hebbath/, sentence.text)
    assert_equal({ "unit" => "Sentence", "page" => "020" }, sentence.annotations)
    refute document.metadata.key?("date"), "the header names only the 1965 edition — no claim"
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (no redistribution — bytes live in local/fixtures/, never in git)"
  end
end
