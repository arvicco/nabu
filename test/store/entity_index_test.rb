# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Store
  # Nabu::Store::EntityIndex: the inline-entity index — the "entities"
  # passage annotation the EpiDoc/Coptic/DHARMA parsers mine (persons,
  # places and upstream's other typed names marked inside the text)
  # projected into a dictionary-encoded, folded name table plus
  # (name, passage) pairs. Records project verbatim (type, surface,
  # identity, key, ref, subtype); the search key folds case and marks so
  # both sides of a lookup meet; wholesale per source, idempotent,
  # withdrawn passages and documents excluded.
  class EntityIndexTest < Minitest::Test
    include StoreTestDB

    INDEX = Nabu::Store::EntityIndex

    def setup
      @db = store_test_db
      @perseus = make_source("perseus-greek")
      @coptic = make_source("coptic-scriptorium")
      @sequence = 0
    end

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T", license_class: "attribution")
    end

    def make_document(source, urn, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: "grc",
        content_sha256: urn, revision: 1, withdrawn: withdrawn
      )
    end

    # Brace-less string-keyed annotations arrive through **fields.
    def make_passage(document, annotations = nil, withdrawn: false, **fields)
      annotations ||= fields
      @sequence += 1
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{document.urn}:#{@sequence}", sequence: @sequence,
        language: "grc", text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
        withdrawn: withdrawn, annotations_json: JSON.generate(annotations)
      )
    end

    SOURCES = %w[perseus-greek coptic-scriptorium].freeze

    # The live stored shapes (catalog read 2026-10-21): Perseus EpiDoc
    # records carry type/text/key; Coptic Scriptorium's carry type/text/
    # head and, when wikified, identity.
    def test_projects_each_record_verbatim_with_a_folded_search_key
      doc = make_document(@perseus, "urn:cts:greekLit:tlg0016.tlg001.perseus-grc2")
      passage = make_passage(doc, "entities" => [
                               { "type" => "place", "text" => "Ἑλλάς", "key" => "tgn,1000074" },
                               { "type" => "person", "text" => "Κροῖσος" }
                             ])
      summary = INDEX.rebuild!(catalog: @db, sources: SOURCES)

      assert_equal 1, summary.passages
      assert_equal 2, summary.rows
      assert_equal 2, summary.names
      place = @db[INDEX::NAMES_TABLE].where(type: "place").first
      assert_equal "Ἑλλάς", place[:text]
      assert_equal "tgn,1000074", place[:key]
      assert_includes place[:search_key], "ελλασ", "case, marks and final sigma fold on the index side"
      assert_includes place[:search_key], "tgn,1000074", "the authority key is searchable too"
      assert_equal [passage.id], @db[INDEX::TABLE].where(name_id: place[:id]).select_map(:passage_id)
    end

    def test_identity_and_subtype_ride_along
      doc = make_document(@coptic, "urn:nabu:coptic-scriptorium:ap.1")
      make_passage(doc, "entities" => [
                     { "head" => "#u3", "identity" => "Macarius of Egypt", "text" => "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ",
                       "type" => "person" },
                     { "identity" => "Poemen", "type" => nil }
                   ])
      INDEX.rebuild!(catalog: @db, sources: SOURCES)

      macarius = @db[INDEX::NAMES_TABLE].where(identity: "Macarius of Egypt").first
      assert_equal "ⲁⲡⲁ ⲙⲁⲕⲁⲣⲓⲟⲥ", macarius[:text]
      assert_includes macarius[:search_key], "macarius of egypt"
      bare = @db[INDEX::NAMES_TABLE].where(identity: "Poemen").first
      assert_nil bare[:text], "an identity-only record keeps its absence honest"
      assert_nil bare[:type]
    end

    def test_names_are_a_per_source_dictionary_deduped_per_passage
      doc = make_document(@perseus, "urn:cts:greekLit:tlg0016.tlg001.perseus-grc2")
      record = { "type" => "place", "text" => "Attica", "key" => "tgn,7002681" }
      make_passage(doc, "entities" => [record, record])
      make_passage(doc, "entities" => [record])
      summary = INDEX.rebuild!(catalog: @db, sources: SOURCES)

      assert_equal 2, summary.passages
      assert_equal 2, summary.rows, "a record repeated inside one passage pairs once"
      assert_equal 1, summary.names
    end

    def test_withdrawn_rows_and_unlisted_sources_contribute_nothing
      live = make_document(@perseus, "urn:cts:a")
      make_passage(live, { "entities" => [{ "type" => "person", "text" => "A" }] }, withdrawn: true)
      gone = make_document(@perseus, "urn:cts:b", withdrawn: true)
      make_passage(gone, "entities" => [{ "type" => "person", "text" => "B" }])
      coptic = make_document(@coptic, "urn:nabu:coptic-scriptorium:x")
      make_passage(coptic, "entities" => [{ "type" => "person", "text" => "C" }])
      summary = INDEX.rebuild!(catalog: @db, sources: %w[perseus-greek])

      assert_equal 0, summary.rows
      assert_equal 0, @db[INDEX::NAMES_TABLE].count
    end

    def test_records_without_any_name_and_other_layers_mint_nothing
      doc = make_document(@perseus, "urn:cts:c")
      make_passage(doc, "entities" => [{ "type" => "person" }, "stray", nil],
                        "notes" => [{ "text" => "Κροῖσος" }])
      assert_equal 0, INDEX.rebuild!(catalog: @db, sources: SOURCES).rows
    end

    def test_rebuild_is_idempotent
      doc = make_document(@perseus, "urn:cts:d")
      make_passage(doc, "entities" => [{ "type" => "person", "text" => "Κροῖσος" }])
      INDEX.rebuild!(catalog: @db, sources: SOURCES)
      before = [@db[INDEX::NAMES_TABLE].count, @db[INDEX::TABLE].count]
      INDEX.rebuild!(catalog: @db, sources: SOURCES)
      assert_equal before, [@db[INDEX::NAMES_TABLE].count, @db[INDEX::TABLE].count]
    end

    def test_refresh_source_replaces_only_that_slice
      perseus_doc = make_document(@perseus, "urn:cts:e")
      make_passage(perseus_doc, "entities" => [{ "type" => "person", "text" => "Κροῖσος" }])
      coptic_doc = make_document(@coptic, "urn:nabu:coptic-scriptorium:y")
      make_passage(coptic_doc, "entities" => [{ "type" => "place", "text" => "ϣⲓⲏⲧ" }])
      INDEX.rebuild!(catalog: @db, sources: SOURCES)

      make_passage(perseus_doc, "entities" => [{ "type" => "place", "text" => "Sardis" }])
      written = INDEX.refresh_source!(catalog: @db, slug: "perseus-greek", sources: SOURCES)
      assert_equal 2, written
      assert_equal 3, @db[INDEX::TABLE].count
      assert_equal 0, INDEX.refresh_source!(catalog: @db, slug: "perseus-greek", sources: %w[coptic-scriptorium])
      assert_equal 1, @db[INDEX::TABLE].count, "a source ruled out of the list loses its slice"
    end

    def test_the_fold_meets_both_sides
      assert_equal INDEX.fold("Κροῖσος"), INDEX.fold("ΚΡΟΙΣΟΣ")
      assert_equal "sataka", INDEX.fold("ŚĀTAKA")
    end

    def test_availability_is_honest
      assert INDEX.available?(@db)
      refute INDEX.populated?(@db)
      doc = make_document(@perseus, "urn:cts:f")
      make_passage(doc, "entities" => [{ "type" => "person", "text" => "Κροῖσος" }])
      INDEX.rebuild!(catalog: @db, sources: SOURCES)
      assert INDEX.populated?(@db)
    end

    # A live catalog migrates only on the write paths, so builders:refresh
    # can meet one predating migration 050: the lane answers nil, never a
    # "no such table" crash.
    def test_a_catalog_predating_the_tables_is_a_quiet_no_op
      bare = Sequel.sqlite
      refute INDEX.available?(bare)
      assert_nil INDEX.rebuild!(catalog: bare, sources: SOURCES)
      assert_equal 0, INDEX.refresh_source!(catalog: bare, slug: "perseus-greek", sources: SOURCES)
    ensure
      bare&.disconnect
    end

    def test_sources_load_from_the_config_list
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "entity_index.yml"), "sources:\n  - perseus-greek\n  - dharma-deccan\n")
        assert_equal %w[perseus-greek dharma-deccan], INDEX.load_sources(config_dir: dir)
        File.write(File.join(dir, "entity_index.yml"), "sources: perseus-greek\n")
        assert_raises(INDEX::ConfigError) { INDEX.load_sources(config_dir: dir) }
      end
      Dir.mktmpdir { |dir| assert_equal [], INDEX.load_sources(config_dir: dir), "no file, lane off" }
    end

    def test_the_shipped_config_lists_the_entity_bearing_sources
      sources = INDEX.load_sources(config_dir: File.expand_path("../../config", __dir__))
      %w[perseus-greek perseus-latin coptic-scriptorium dharma-deccan].each { |slug| assert_includes sources, slug }
    end
  end
end
