# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Person — the catalogue-person lane: a name lookup widens
  # beyond the derived authorities to the person-shaped DOCUMENT FACETS
  # (oracc/cdli ruler, ancient_author, recipient, eponym …; the author
  # facets of the text sources), each value with the sources that catalogue
  # it. Values below are real catalogue values from the held catalog
  # (census 2026-10-22).
  class PersonTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @cdli = Nabu::Store::Source.create(slug: "cdli", name: "CDLI", adapter_class: "T", license_class: "open")
      @oracc = Nabu::Store::Source.create(slug: "oracc", name: "ORACC", adapter_class: "T",
                                          license_class: "attribution")
      @n = 0
    end

    def doc_with(source, facets, withdrawn: false)
      @n += 1
      doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:t:#{@n}", title: "t#{@n}", language: "akk",
                                         content_sha256: "x", revision: 1, withdrawn: withdrawn)
      facets.each { |facet, value| @catalog[:document_facets].insert(document_id: doc.id, facet: facet, value: value) }
    end

    def person(term) = Nabu::Query::Person.new(catalog: @catalog).run(term)

    def test_a_name_finds_its_catalogue_values_with_their_sources
      2.times { doc_with(@cdli, { "ruler" => "Esarhaddon" }) }
      doc_with(@oracc, { "ruler" => "Esarhaddon" })
      doc_with(@oracc, { "ancient_author" => "Esarhaddon" })
      doc_with(@oracc, { "ruler" => "Esarhaddon or Ashurbanipal" })
      doc_with(@cdli, { "ruler" => "Esarhaddon" }, withdrawn: true)
      doc_with(@cdli, { "period" => "Esarhaddon" })

      result = person("Esarhaddon")
      assert_empty result.cards, "no derived authority holds the king"
      rows = result.mentions.map { |m| [m.facet, m.value, m.sources] }
      assert_equal [["ancient_author", "Esarhaddon", [["oracc", 1]]],
                    ["ruler", "Esarhaddon", [["cdli", 2], ["oracc", 1]]],
                    ["ruler", "Esarhaddon or Ashurbanipal", [["oracc", 1]]]], rows,
                   "whole-word prefix over person facets only; withdrawn documents never count"
      refute result.mentions_truncated
    end

    def test_the_prefix_stops_at_a_word_boundary_and_case_is_tried_as_catalogued
      doc_with(@oracc, { "ruler" => "Sargon II" })
      doc_with(@oracc, { "ruler" => "Sargonid" })
      assert_equal ["Sargon II"], person("Sargon").mentions.map(&:value)
      assert_equal ["Sargon II"], person("sargon").mentions.map(&:value), "a lowercase query tries title case"
    end

    def test_no_card_and_no_mention_is_the_honest_error
      doc_with(@oracc, { "ruler" => "Sargon II" })
      error = assert_raises(Nabu::Query::Person::Error) { person("Nabonidus") }
      assert_match(/no person named "Nabonidus"/, error.message)
    end

    def test_an_authority_ref_never_reaches_the_catalogue_lane
      doc_with(@oracc, { "ruler" => "cbdb:1762" })
      assert_raises(Nabu::Query::Person::Error) { person("cbdb:1762") }
    end

    def test_the_value_list_is_capped_and_says_so
      (Nabu::Query::Person::MENTION_VALUES + 2).times { |i| doc_with(@oracc, { "author" => "Anonymous #{i}" }) }
      result = person("Anonymous")
      assert_equal Nabu::Query::Person::MENTION_VALUES, result.mentions.size
      assert result.mentions_truncated
    end
  end
end
