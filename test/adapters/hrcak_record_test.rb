# frozen_string_literal: true

require "test_helper"
require "nokogiri"

module Adapters
  # Nabu::Adapters::HrcakRecord — one Hrčak OAI article record (oai_openaire
  # + its oai_dc twin), read from the real hrcak-marulana fixtures.
  class HrcakRecordTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("hrcak-marulana")
    KLASS = Nabu::Adapters::HrcakRecord

    def record(id, twin: true)
      base = File.join(FIXTURES, "records", id)
      KLASS.from_files("#{base}.oai_openaire.xml", twin ? "#{base}.oai_dc.xml" : nil)
    end

    # Record 641 from the trimmed first ListRecords page: two languages,
    # one PDF — the summary language printed inside it.
    def two_language_one_pdf_record
      page = Nokogiri::XML(File.read(File.join(FIXTURES, "oai", "oai_openaire-1.xml")))
      node = page.xpath("//oai:record", KLASS::NS).find { |r| r.text.include?("oai:hrcak.srce.hr:641") }
      doc = Nokogiri::XML::Document.new
      doc.root = node.dup
      KLASS.new(openaire: doc.to_xml)
    end

    def test_files_pair_with_languages_and_page_ranges_in_parallel
      versions = record("8030").file_versions
      assert_equal([%w[12183 hrv 5 12], %w[12184 eng 13 13]],
                   versions.map { |v| [v.file_id, v.language, v.first_page, v.last_page] })
      assert_empty record("8030").inner_languages
    end

    def test_languages_beyond_the_pdfs_are_inner_languages_of_the_last_pdf
      rec = two_language_one_pdf_record
      assert_equal %w[fre hrv], rec.languages
      assert_equal([%w[1309 fre]], rec.file_versions.map { |v| [v.file_id, v.language] })
      assert_equal %w[hrv], rec.inner_languages
      assert_equal "12", rec.volume
      assert_includes rec.abstracts.fetch("hrv"), "Evanđelistar"
      refute_includes rec.abstracts.fetch("hrv"), "\r"
    end

    def test_bibliographic_fields
      rec = record("23933")
      assert_equal "23933", rec.id
      assert_equal "2008-04-22", rec.issued
      assert_equal %w[17 17], [rec.volume, rec.issue]
      assert_equal "book review", rec.resource_type
      assert_equal "Colloquia Maruliana", rec.journal
      assert_equal "https://hrcak.srce.hr/23933", rec.landing_url
      assert_equal ["Tomasović, Mirko"], rec.creators.map(&:name)
      assert_equal "2008-06-03", rec.datestamp
      assert_equal [{ "lang" => "hrv", "text" => rec.titles.first["text"] }], rec.titles
      assert_equal ["Filozofski fakultet Sveučilišta u Zagrebu, Zagreb, Hrvatska"], rec.creators.first.affiliations
    end

    def test_licence_conditions_govern_their_record_and_the_journal_grant_the_rest
      assert_equal "attribution", record("8030").license_class
      assert_nil record("8030").license_condition
      assert_includes record("8030").journal_rights_statement, "(CC BY 4.0)"
      assert_equal "nc", record("277980").license_class
      assert_nil record("277999").license_class, "rightsstatements.org InC grants nothing"
      assert record("277999").known_license?
      assert_empty record("8030", twin: false).dc_rights
    end

    def test_an_unknown_licence_uri_is_not_known
      xml = File.read(File.join(FIXTURES, "records", "277980.oai_openaire.xml"))
                .sub("http://creativecommons.org/licenses/by-nc/4.0/", "http://example.org/some-licence/")
      rec = KLASS.new(openaire: xml)
      refute rec.known_license?
      assert_nil rec.license_class
    end

    def test_a_record_without_a_resource_is_a_parse_error
      assert_raises(Nabu::ParseError) do
        KLASS.new(openaire: '<record xmlns="http://www.openarchives.org/OAI/2.0/"><header>' \
                            "<identifier>oai:hrcak.srce.hr:1</identifier></header></record>")
      end
    end
  end
end
