# frozen_string_literal: true

require "test_helper"
require "json"

module Query
  # Nabu::Query::Export (P4-3). Catalog is a fresh in-memory SQLite. Rows are
  # created directly (the search-test pattern) so filters and visibility are
  # exercised without a full sync.
  class ExportTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @open = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
      @nc = Nabu::Store::Source.create(
        slug: "nc", name: "NC", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    # -- helpers -------------------------------------------------------------

    def make_document(source:, urn:, language: "grc", license_override: nil, withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: "Iliad", language: language,
        license_override: license_override, content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "grc",
                     text_normalized: nil, annotations_json: "{}", withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: text_normalized || text, annotations_json: annotations_json,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def export(**)
      Nabu::Query::Export.new(catalog: @catalog).run(**)
    end

    # -- plain ---------------------------------------------------------------

    def test_plain_emits_one_line_per_passage_newlines_stripped
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν\nἄειδε", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text: "θεά", sequence: 1)

      lines = export(format: "plain").to_a
      assert_equal ["μῆνιν ἄειδε", "θεά"], lines
    end

    # -- jsonl ---------------------------------------------------------------

    def test_jsonl_round_trips_keys_and_parsed_annotations
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(
        doc, urn: "urn:d:1:1", text: "μῆνιν", text_normalized: "μηνιν",
             annotations_json: '{"speaker":"Homer"}', sequence: 0
      )

      record = JSON.parse(export(format: "jsonl").first)
      assert_equal %w[annotations language text text_normalized urn].sort, record.keys.sort
      assert_equal "urn:d:1:1", record.fetch("urn")
      assert_equal "μῆνιν", record.fetch("text")
      assert_equal "μηνιν", record.fetch("text_normalized")
      # annotations is a real nested object, not a double-encoded string.
      assert_kind_of Hash, record.fetch("annotations")
      assert_equal "Homer", record.fetch("annotations").fetch("speaker")
    end

    def test_jsonl_empty_annotations_is_an_object
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν", sequence: 0)

      record = JSON.parse(export(format: "jsonl").first)
      assert_equal({}, record.fetch("annotations"))
    end

    # -- filters -------------------------------------------------------------

    def test_lang_filter
      grc = make_document(source: @open, urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "alpha", sequence: 0, language: "grc")
      lat = make_document(source: @open, urn: "urn:d:lat", language: "lat")
      make_passage(lat, urn: "urn:d:lat:1", text: "beta", sequence: 0, language: "lat")

      lines = export(format: "plain", lang: "lat").to_a
      assert_equal ["beta"], lines
    end

    def test_license_filter_is_exact_and_override_wins
      open_doc = make_document(source: @open, urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "libertas", sequence: 0)
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "vinculum", sequence: 0)
      demoted = make_document(source: @open, urn: "urn:d:demoted", license_override: "nc")
      make_passage(demoted, urn: "urn:d:demoted:1", text: "servitus", sequence: 0)

      assert_equal ["libertas"], export(format: "plain", license: "open").to_a
      assert_equal %w[vinculum servitus].sort, export(format: "plain", license: "nc").to_a.sort
    end

    # --source SLUG (P22-1): scope the stream to one source.
    def test_source_filter_scopes_the_stream
      open_doc = make_document(source: @open, urn: "urn:d:open")
      make_passage(open_doc, urn: "urn:d:open:1", text: "libertas", sequence: 0)
      nc_doc = make_document(source: @nc, urn: "urn:d:nc")
      make_passage(nc_doc, urn: "urn:d:nc:1", text: "vinculum", sequence: 0)

      assert_equal ["vinculum"], export(format: "plain", source: "nc").to_a
      assert_equal ["vinculum"], export(format: "plain", source: "nc", lang: "grc").to_a
      assert_empty export(format: "plain", source: "nc", lang: "lat").to_a, "filters compose"
    end

    def test_withdrawn_passage_and_document_are_excluded
      doc = make_document(source: @open, urn: "urn:d:1")
      make_passage(doc, urn: "urn:d:1:1", text: "kept", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text: "gone", sequence: 1, withdrawn: true)
      wdoc = make_document(source: @open, urn: "urn:d:2", withdrawn: true)
      make_passage(wdoc, urn: "urn:d:2:1", text: "hidden", sequence: 0)

      assert_equal ["kept"], export(format: "plain").to_a
    end

    # -- streaming -----------------------------------------------------------

    # #run returns a lazy Enumerator that pulls only what is taken: first(2)
    # over a large seeded set yields the first two correctly without demanding
    # full materialization.
    def test_returns_streaming_enumerator
      doc = make_document(source: @open, urn: "urn:d:1")
      50.times { |i| make_passage(doc, urn: "urn:d:1:#{i}", text: "line#{i}", sequence: i) }

      enum = export(format: "plain")
      assert_kind_of Enumerator, enum
      assert_equal %w[line0 line1], enum.first(2)
    end
  end
end
