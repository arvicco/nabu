# frozen_string_literal: true

require "test_helper"

module Export
  # Nabu::Export::Links (P121-1): the edge dump — every journal edge with
  # its run provenance, each endpoint resolved through the catalog to its
  # source and license (passage, document, then dictionary-entry grain),
  # and with --dated the endpoints' primary date envelopes.
  class LinksTest < Minitest::Test
    include StoreTestDB

    COLUMNS = %w[kind from_urn to_urn score detail run_id producer scope code_version
                 from_source from_license_class to_source to_license_class mined_at].freeze
    DATED = %w[from_not_before from_not_after from_date_class to_not_before to_not_after to_date_class].freeze

    def setup
      @catalog = store_test_db
      @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      @alpha = source("alpha", "open")
      @beta = source("beta", "nc")
      @run = Nabu::Store::LinksJournal.record_run!(@journal, producer: "parallels", scope: "alpha",
                                                             params: { min_score: 0.1 }, code_version: "test/1")
    end

    def teardown
      @journal.disconnect
    end

    def source(slug, license_class)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
    end

    def document(source, urn, dated: nil)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: "lat",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1", sequence: 1, language: "lat", text: "t",
                                  text_normalized: "t", content_sha256: "x", revision: 1, withdrawn: false)
      @catalog[:document_axes].insert(document_id: doc.id, axis_source: "test", **dated) if dated
      doc
    end

    def edge(from, to, kind: "parallel", score: 0.5, detail: nil)
      Nabu::Store::LinksJournal.write_edge!(@journal, from_urn: from, to_urn: to, kind: kind, score: score,
                                                      detail: detail, run_id: @run)
    end

    def rows(**)
      table = Nabu::Export::Links.new(catalog: @catalog, journal: @journal, **)
      collected = []
      table.each_row { |row| collected << [table.columns.map(&:name).zip(row.values).to_h, row.draws] }
      collected
    end

    def test_columns_and_dated_extension
      assert_equal COLUMNS, Nabu::Export::Links.new(catalog: @catalog, journal: @journal).columns.map(&:name)
      assert_equal COLUMNS + DATED,
                   Nabu::Export::Links.new(catalog: @catalog, journal: @journal, dated: true).columns.map(&:name)
    end

    def test_an_edge_carries_run_provenance_and_both_endpoints_licenses
      document(@alpha, "urn:a:1")
      document(@beta, "urn:b:1")
      edge("urn:a:1:1", "urn:b:1:1", detail: "gram")

      row, draws = rows.first
      assert_equal({ "kind" => "parallel", "from_urn" => "urn:a:1:1", "to_urn" => "urn:b:1:1", "score" => 0.5,
                     "detail" => "gram", "run_id" => @run, "producer" => "parallels", "scope" => "alpha",
                     "code_version" => "test/1", "from_source" => "alpha", "from_license_class" => "open",
                     "to_source" => "beta", "to_license_class" => "nc", "mined_at" => nil }, row)
      assert_equal [%w[alpha open], %w[beta nc]], draws
    end

    def test_document_grain_dictionary_grain_and_unresolved_endpoints
      document(@alpha, "urn:a:1")
      dict = Nabu::Store::Dictionary.create(source_id: @beta.id, slug: "d", title: "D", language: "lat")
      Nabu::Store::DictionaryEntry.create(dictionary_id: dict.id, urn: "urn:nabu:dict:d:amo", entry_id: "amo",
                                          key_raw: "amo", headword: "amo", headword_folded: "amo",
                                          body: "to love", content_sha256: "x")
      edge("urn:a:1", "urn:nabu:dict:d:amo", kind: "reference")
      edge("urn:a:1:1", "urn:gone:9", kind: "reference")

      table = Nabu::Export::Links.new(catalog: @catalog, journal: @journal)
      got = []
      table.each_row { |row| got << row }
      first, second = got
      assert_equal %w[alpha open beta nc], first.values.values_at(9, 10, 11, 12), "document + dictionary grain"
      assert_equal ["alpha", "open", nil, nil], second.values.values_at(9, 10, 11, 12)
      assert_equal [%w[alpha open], [nil, nil]], second.draws, "an unresolved endpoint is drawn as unknown"
      assert_equal({ "unresolved_endpoints" => 1, "journal_runs" => 1 }, table.notes)
    end

    def test_kind_filter_and_filters_echo
      document(@alpha, "urn:a:1")
      edge("urn:a:1:1", "urn:a:1:x", kind: "parallel")
      edge("urn:a:1:1", "urn:a:1:y", kind: "formula")

      assert_equal(%w[formula], rows(kinds: %w[formula]).map { |row, _| row["kind"] })
      table = Nabu::Export::Links.new(catalog: @catalog, journal: @journal, kinds: %w[formula], dated: true)
      assert_equal({ "kind" => %w[formula], "dated" => true }, table.filters)
    end

    def test_dated_adds_each_endpoints_primary_envelope
      document(@alpha, "urn:a:1", dated: { not_before: -100, not_after: -50, date_class: "composition" })
      document(@beta, "urn:b:1")
      edge("urn:a:1:1", "urn:b:1:1")

      row, = rows(dated: true).first
      assert_equal [-100, -50, "composition", nil, nil, nil], row.values_at(*DATED)
    end

    def test_streams_in_pages_without_loss_or_duplication
      document(@alpha, "urn:a:1")
      targets = Array.new(25) { |i| "urn:t:#{i}" }
      targets.each { |urn| edge("urn:a:1:1", urn) }
      got = []
      Nabu::Export::Links.new(catalog: @catalog, journal: @journal, page_size: 4).each_row do |row|
        got << row.values[2]
      end
      assert_equal targets, got, "journal order, every edge once"
    end

    # The links union (Store::LinkLayers): mined-layer edges carry negative
    # ids, so the keyset must start below them — every edge of both stores
    # exported once, the mined ones dated by their layer.
    def test_the_union_exports_both_stores_with_the_mined_layer_date
      Dir.mktmpdir("nabu-export-union") do |dir|
        links_path = File.join(dir, "links.sqlite3")
        journal = Nabu::Store::LinksJournal.open!(links_path)
        run = Nabu::Store::LinksJournal.record_run!(journal, producer: "formulas", scope: "alpha", params: {},
                                                             code_version: "f/1")
        3.times { |i| Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:c:#{i}", to_urn: "urn:c:x", kind: "formula", score: 1.0, run_id: run) }
        journal.disconnect
        mined_path = File.join(dir, "mined-links.sqlite3")
        Nabu::Store::MinedLinks.mine!(mined_path, producer: "parallels", scope: "alpha", stamp: nil, inputs: nil,
                                                  catalog: nil) do |store|
          mined_run = Nabu::Store::LinksJournal.record_run!(store, producer: "parallels", scope: "alpha", params: {},
                                                                   code_version: "p/1")
          3.times { |i| Nabu::Store::LinksJournal.write_edge!(store, from_urn: "urn:m:#{i}", to_urn: "urn:m:x", kind: "parallel", score: 0.5, run_id: mined_run) }
          Nabu::Store::LinksJournal.finish_run!(store, mined_run)
        end
        union = Nabu::Store::LinkLayers.open_paths(links_path: links_path, mined_path: mined_path)
        table = Nabu::Export::Links.new(catalog: @catalog, journal: union, page_size: 2)
        got = []
        table.each_row { |row| got << table.columns.map(&:name).zip(row.values).to_h }
        assert_equal 6, got.size, "both stores, every edge once, across page boundaries"
        mined, cheap = got.partition { |row| row["kind"] == "parallel" }
        assert(mined.all? { |row| row["mined_at"].is_a?(String) && row["run_id"].negative? })
        assert(cheap.all? { |row| row["mined_at"].nil? && row["run_id"].positive? })
        assert_equal(%w[parallels], mined.map { |row| row["producer"] }.uniq, "the run join holds across the union")
        union.disconnect
      end
    end
  end
end
