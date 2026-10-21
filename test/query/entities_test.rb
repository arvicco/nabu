# frozen_string_literal: true

require "test_helper"
require "json"

module Query
  # Nabu::Query::Entities — the `nabu entity` desk: passages by a name
  # marked inside their text, read from the precompiled entity index only
  # (folded substring over the name dictionary → the pair ranges), with
  # honest errors for an absent or unbuilt index.
  class EntitiesTest < Minitest::Test
    include StoreTestDB

    INDEX = Nabu::Store::EntityIndex

    def setup
      @db = store_test_db
      @perseus = source("perseus-greek")
      @coptic = source("coptic-scriptorium")
      @sequence = 0
      herodotus = document(@perseus, "urn:cts:greekLit:tlg0016.tlg001.perseus-grc2")
      @p1 = passage(herodotus, "Κροῖσος ἦν Λυδὸς μὲν γένος",
                    [{ "type" => "person", "text" => "Κροῖσος" }, { "type" => "ethnic", "text" => "Λυδὸς" }])
      @p2 = passage(herodotus, "ἐς Σάρδις ἀπικνέεται",
                    [{ "type" => "place", "text" => "Σάρδις", "key" => "tgn,7002011" }])
      @p3 = passage(herodotus, "Κροίσου δὲ ἐπαίνεε",
                    [{ "type" => "person", "text" => "Κροίσου" }])
      apophthegmata = document(@coptic, "urn:nabu:coptic-scriptorium:ap.1")
      @p4 = passage(apophthegmata, "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ ⲡⲉϫⲁϥ",
                    [{ "type" => "person", "text" => "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ", "identity" => "Macarius of Egypt" }])
      INDEX.rebuild!(catalog: @db, sources: %w[perseus-greek coptic-scriptorium])
      @query = Nabu::Query::Entities.new(catalog: @db)
    end

    def source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T", license_class: "attribution")
    end

    def document(source, urn)
      Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: "grc",
                                   content_sha256: urn, revision: 1)
    end

    def passage(document, text, entities)
      @sequence += 1
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{document.urn}:#{@sequence}", sequence: @sequence,
        language: "grc", text: text, text_normalized: text, content_sha256: "x", revision: 1,
        annotations_json: JSON.generate("entities" => entities)
      )
    end

    def test_a_name_finds_its_passages_through_the_fold
      result = @query.run("κροισ")
      assert_equal 2, result.name_total, "both inflected surfaces match the unaccented stem"
      assert_equal 2, result.passage_total
      assert_equal [@p1.urn, @p3.urn], result.hits.map(&:urn)
      assert_equal ["Κροῖσος"], result.hits.first.names.map(&:text), "the hit names what matched"
      assert_equal "perseus-greek", result.names.first.source
    end

    def test_both_sides_fold_case_and_marks
      assert_equal @query.run("ΚΡΟΙΣΟΣ").hits.map(&:urn), @query.run("Κροῖσος").hits.map(&:urn)
    end

    def test_identity_and_key_are_searchable
      assert_equal [@p4.urn], @query.run("macarius").hits.map(&:urn)
      assert_equal [@p2.urn], @query.run("tgn,7002011").hits.map(&:urn)
    end

    def test_type_and_source_narrow
      assert_empty @query.run("κροισ", type: "place").hits
      assert_equal 2, @query.run("κροισ", type: "person").hits.size
      assert_empty @query.run("κροισ", source: "coptic-scriptorium").hits
      error = assert_raises(Nabu::Query::Entities::Error) { @query.run("κροισ", source: "nope") }
      assert_match(/unknown source "nope"/, error.message)
    end

    def test_limit_caps_the_page_not_the_totals
      result = @query.run("κροισ", limit: 1)
      assert_equal 1, result.hits.size
      assert_equal 2, result.passage_total
    end

    def test_like_wildcards_in_the_query_are_literal
      assert_empty @query.run("%").hits
      assert_empty @query.run("_").hits
    end

    def test_no_match_is_an_empty_result
      result = @query.run("Ξέρξης")
      assert_equal 0, result.passage_total
      assert_empty result.hits
    end

    def test_census_counts_names_and_pairs_per_source_and_type
      rows = @query.census
      person = rows.find { |row| row.source == "perseus-greek" && row.type == "person" }
      assert_equal 2, person.names
      assert_equal 2, person.passages
      assert_equal 4, rows.size
    end

    def test_an_empty_name_is_refused
      assert_raises(Nabu::Query::Entities::Error) { @query.run("  ") }
    end

    def test_an_unbuilt_index_says_so_without_scanning
      @db[INDEX::TABLE].delete
      @db[INDEX::NAMES_TABLE].delete
      error = assert_raises(Nabu::Query::Entities::Error) { @query.run("κροισ") }
      assert_match(/entity index is not built yet — run `bundle exec rake builders:refresh`/, error.message)
    end

    def test_a_catalog_predating_the_index_says_so
      bare = Sequel.sqlite
      error = assert_raises(Nabu::Query::Entities::Error) { Nabu::Query::Entities.new(catalog: bare).run("x") }
      assert_match(/predates the entity index \(migration 049\)/, error.message)
    ensure
      bare&.disconnect
    end
  end
end
