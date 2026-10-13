# frozen_string_literal: true

require "test_helper"

module Adapters
  # The bu-ajami-html family: one NEH Ajami item page (sites.bu.edu/nehajami)
  # read into its metadata table and its PDF links. Fixtures are the real
  # pages as served (test/fixtures/bu-ajami/items/<language>/<slug>.html).
  class BuAjamiItemParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("bu-ajami")

    def page(lang, slug)
      Nabu::Adapters::BuAjamiItemParser.parse_file(File.join(FIXTURES, "items", lang, "#{slug}.html"))
    end

    def test_reads_the_metadata_table_verbatim_by_its_own_labels
      item = page("hausa", "falke-2729-wakar-sarkin-kano")
      assert_equal "A Poem in Honor of the Emir of Kano (Waƙar Sarkin Kano)", item.fields.fetch("Title")
      assert_equal "Abd al-Wahhab Adam al-Falaki (author), Umar Falke (owner)", item.fields.fetch("Author or Owner")
      assert_equal "Kano, Nigeria", item.fields.fetch("Provenance")
      assert_equal "Hausa", item.fields.fetch("Language")
      assert_equal "Hausa Ajami", item.fields.fetch("Script")
      assert_equal "Poetry", item.fields.fetch("Genre")
      assert_match(/\AThis is a short poem praising Abdullahi Bayero \(1881-1953\)/, item.fields.fetch("Content"))
      assert_match(/Creative Commons Attribution-Non-Commercial 4\.0 License/,
                   item.fields.fetch("Access condition and copyright"))
    end

    def test_finds_the_one_transcription_pdf_and_the_other_resources
      item = page("hausa", "falke-2729-wakar-sarkin-kano")
      assert_equal "/nehajami/files/2022/02/Falke-2729_Transcription.pdf", item.transcription_href
      assert_equal "/nehajami/files/2022/02/Falke-2729_English-translation.pdf", item.translation_hrefs["en"]
      assert_equal "/nehajami/files/2022/02/Falke-2729_French-translation.pdf", item.translation_hrefs["fr"]
      refute_empty item.manuscript_hrefs
      assert(item.manuscript_hrefs.all? { |href| href.end_with?(".pdf") && !href.include?("ranscription") })
    end

    def test_an_nfd_href_is_kept_byte_verbatim_for_the_request
      item = page("wolof", "bakk-wi")
      href = item.transcription_href
      assert_equal "/nehajami/files/2021/07/Bàkk-wi_Transcription.pdf", href,
                   "upstream serves the file under its NFD name — the request must use those bytes"
      refute href.unicode_normalized?(:nfc)
    end

    def test_source_links_ride_beside_the_reference_text
      item = page("hausa", "falke-2729-wakar-sarkin-kano")
      assert_includes item.fields.fetch("Source Reference"), "Courtesy of Northwestern University Libraries"
      assert(item.source_links.any? { |url| url.include?("northwestern.edu") })
    end

    def test_values_are_whitespace_collapsed_and_nfc
      item = page("mandinka", "mandinkakan-leetaroolu-3")
      item.fields.each_value do |value|
        assert value.unicode_normalized?(:nfc), value
        refute_match(/\s{2,}/, value)
      end
    end

    def test_a_page_without_the_metadata_table_is_a_parse_error
      assert_raises(Nabu::ParseError) do
        Nabu::Adapters::BuAjamiItemParser.parse("<html><body><article><p>x</p></article></body></html>",
                                                source: "inline")
      end
    end

    def test_two_distinct_transcription_links_are_a_parse_error
      html = File.read(File.join(FIXTURES, "items", "hausa", "falke-2729-wakar-sarkin-kano.html"))
      doubled = html.sub("</article>", '<a href="/nehajami/files/x/Other_Transcription.pdf">t</a></article>')
      assert_raises(Nabu::ParseError) { Nabu::Adapters::BuAjamiItemParser.parse(doubled, source: "inline") }
    end
  end
end
