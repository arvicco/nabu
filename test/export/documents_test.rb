# frozen_string_literal: true

require "test_helper"

module Export
  # Nabu::Export::Documents (P121-1): one row per live document — the
  # identity columns always, the library axes (lect, script, date envelope,
  # place, genre, kind) with --with-axes, NULL where an axis is absent.
  class DocumentsTest < Minitest::Test
    include StoreTestDB

    BASE = %w[urn source language title license_class passage_count].freeze
    AXES = %w[lect lect_basis script artifact_script not_before not_after date_precision date_class
              date_basis date_raw place_name place_ref place_lat place_lon genre kind].freeze

    def setup
      @catalog = store_test_db
      @alpha = source("alpha", "open")
      @beta = source("beta", "nc")
    end

    def source(slug, license_class)
      Nabu::Store::Source.create(slug: slug, name: slug.capitalize, adapter_class: "TestAdapter",
                                 license_class: license_class)
    end

    def document(source, urn, language: "lat", title: nil, withdrawn: false, license_override: nil, passages: 1)
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: title || urn, language: language,
                                         content_sha256: "x", revision: 1, withdrawn: withdrawn,
                                         license_override: license_override)
      passages.times do |seq|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:#{seq}", sequence: seq, language: language,
                                    text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
                                    withdrawn: false)
      end
      doc
    end

    def axis(doc, **fields)
      @catalog[:document_axes].insert(document_id: doc.id, axis_source: "test", **fields)
    end

    def facet(doc, facet, value, raw = nil)
      @catalog[:document_facets].insert(document_id: doc.id, facet: facet, value: value, raw: raw)
    end

    def rows(**)
      table = Nabu::Export::Documents.new(catalog: @catalog, **)
      collected = []
      table.each_row { |row| collected << table.columns.map(&:name).zip(row.values).to_h }
      collected
    end

    def test_base_columns_are_the_identity_set_and_axes_extend_them
      assert_equal BASE, Nabu::Export::Documents.new(catalog: @catalog).columns.map(&:name)
      assert_equal BASE + AXES, Nabu::Export::Documents.new(catalog: @catalog, with_axes: true).columns.map(&:name)
      assert(Nabu::Export::Documents.new(catalog: @catalog, with_axes: true).columns.all? do |column|
        !column.description.to_s.strip.empty?
      end, "every column is documented")
    end

    def test_base_row_carries_source_slug_effective_license_and_live_passage_count
      doc = document(@alpha, "urn:a:1", passages: 3)
      @catalog[:passages].where(urn: "urn:a:1:2").update(withdrawn: true)
      document(@alpha, "urn:a:2", license_override: "restricted")
      document(@beta, "urn:b:gone", withdrawn: true)

      got = rows
      assert_equal %w[urn:a:1 urn:a:2], got.map { |row| row["urn"] }, "withdrawn documents never export"
      assert_equal({ "urn" => "urn:a:1", "source" => "alpha", "language" => "lat", "title" => "urn:a:1",
                     "license_class" => "open", "passage_count" => 2 }, got.first)
      assert_equal "restricted", got.last["license_class"], "the document override wins"
      assert doc
    end

    def test_draws_name_the_source_and_effective_class
      document(@alpha, "urn:a:1", license_override: "attribution")
      table = Nabu::Export::Documents.new(catalog: @catalog)
      draws = []
      table.each_row { |row| draws << row.draws }
      assert_equal [[%w[alpha attribution]]], draws
    end

    def test_axes_resolve_lect_script_envelope_place_genre_and_kind
      doc = document(@alpha, "urn:a:1", language: "xcg")
      facet(doc, "lect", "xcg~latn", "override:alpha")
      axis(doc, not_before: -100, not_after: 50, precision: "low", date_raw: "I BCE–I CE",
                date_class: "composition", place_name: "Alesia", place_ref: "pleiades:1", place_lat: 47.5,
                place_lon: 4.5)
      axis(doc, not_before: 200, not_after: 300) # a later lane: the earliest row is primary
      axis(doc, not_before: -500, not_after: -400, passage_seq_from: 1, passage_seq_to: 2) # passage grain: never
      axis(doc, artifact_script: "ital")
      facet(doc, "genre", "epitaph", "titsep")
      facet(doc, "kind", "documentary/legal")
      facet(doc, "kind", "documentary/epistolary")

      row = rows(with_axes: true).first
      assert_equal "xcg~latn", row["lect"]
      assert_equal "override:alpha", row["lect_basis"]
      assert_equal "latn", row["script"], "the held script is the lect id's ~segment"
      assert_equal "ital", row["artifact_script"]
      assert_equal [-100, 50, "low", "composition", "test", "I BCE–I CE"],
                   row.values_at("not_before", "not_after", "date_precision", "date_class", "date_basis", "date_raw")
      assert_equal ["Alesia", "pleiades:1", 47.5, 4.5],
                   row.values_at("place_name", "place_ref", "place_lat", "place_lon")
      assert_equal "epitaph", row["genre"]
      assert_equal "documentary/epistolary|documentary/legal", row["kind"], "multi-valued facets join sorted"
    end

    # P122-1: an estimate is the envelope only where no upstream date
    # exists — and then it ships labeled silver.
    def test_silver_estimates_ship_only_where_no_upstream_date_exists
      silver = { axis_source: Nabu::Store::SilverDates::AXIS_SOURCE, date_class: "silver", precision: "estimate" }
      upstream = document(@alpha, "urn:a:upstream")
      @catalog[:document_axes].insert(document_id: upstream.id, not_before: -900, not_after: -800, **silver)
      axis(upstream, not_before: 100, not_after: 200)
      estimated = document(@alpha, "urn:a:estimated")
      @catalog[:document_axes].insert(document_id: estimated.id, not_before: -300, not_after: -200, **silver)

      by_urn = rows(with_axes: true).to_h { |row| [row["urn"], row] }
      assert_equal [100, "artifact", "test"],
                   by_urn["urn:a:upstream"].values_at("not_before", "date_class", "date_basis")
      assert_equal [-300, "silver", "silver-dates"],
                   by_urn["urn:a:estimated"].values_at("not_before", "date_class", "date_basis")
      assert_empty rows(with_axes: true, from: -1000, to: -200),
                   "the year window reads upstream dates only (search's semantics) — no estimate answers it"
      assert_equal(%w[urn:a:upstream], rows(with_axes: true, from: 100, to: 200).map { |row| row["urn"] })
    end

    def test_absent_axes_are_null_and_a_bare_code_resolves_to_itself
      materialized = document(@alpha, "urn:a:0", language: "grc")
      facet(materialized, "lect", "grc:anc")
      document(@alpha, "urn:a:1", language: "lat")
      artifact = document(@alpha, "urn:a:2", language: "lat")
      axis(artifact, not_before: 100, not_after: 100) # NULL class = the source's own artifact date

      bare, dated = rows(with_axes: true).drop(1)
      assert_equal "lat", bare["lect"], "no facet row = resolves to itself (the materialized invariant)"
      assert_nil bare["lect_basis"]
      (AXES - %w[lect]).each { |name| assert_nil bare[name], "#{name} is NULL when the axis is absent" }
      assert_equal "artifact", dated["date_class"], "a dated row without a class is an artifact date"
    end

    def test_an_unmaterialized_catalog_leaves_lect_null_and_says_so
      document(@alpha, "urn:a:1")
      table = Nabu::Export::Documents.new(catalog: @catalog, with_axes: true)
      lects = []
      table.each_row { |row| lects << row.values[BASE.size] }
      assert_equal [nil], lects, "never a guess: identity holds only once materialization ran"
      assert_equal false, table.notes.fetch("lect_materialized")
    end

    def test_source_language_and_license_filters
      document(@alpha, "urn:a:1", language: "lat")
      document(@alpha, "urn:a:2", language: "grc")
      document(@beta, "urn:b:1", language: "lat")

      assert_equal(%w[urn:b:1], rows(sources: %w[beta]).map { |row| row["urn"] })
      assert_equal(%w[urn:a:1 urn:b:1], rows(langs: %w[lat]).map { |row| row["urn"] })
      assert_equal %w[urn:a:1 urn:b:1], rows(langs: %w[la]).map { |row| row["urn"] }, "ISO 639-1 folds to lat"
      assert_equal(%w[urn:a:1 urn:a:2 urn:b:1], rows(langs: %w[lat grc]).map { |row| row["urn"] })

      table = Nabu::Export::Documents.new(catalog: @catalog)
      urns = []
      table.each_row(license_classes: %w[open]) { |row| urns << row.values.first }
      assert_equal %w[urn:a:1 urn:a:2], urns, "the license filter is pushed into the query"
    end

    def test_year_window_is_a_null_aware_overlap
      document(@alpha, "urn:undated")
      axis(document(@alpha, "urn:early"), not_before: -300, not_after: -200)
      axis(document(@alpha, "urn:open-end"), not_before: -50)
      axis(document(@alpha, "urn:late"), not_before: 400, not_after: 500)

      assert_equal(%w[urn:early urn:open-end], rows(from: -250, to: 1).map { |row| row["urn"] })
      assert_equal(%w[urn:late urn:open-end], rows(from: 450).map { |row| row["urn"] })
    end

    def test_filters_are_validated_and_echoed_for_the_manifest
      error = assert_raises(Nabu::Export::Error) { Nabu::Export::Documents.new(catalog: @catalog, sources: %w[nope]) }
      assert_match(/unknown source "nope"/, error.message)
      assert_match(/alpha, beta/, error.message)
      assert_raises(Nabu::Export::Error) { Nabu::Export::Documents.new(catalog: @catalog, from: 0) }
      error = assert_raises(Nabu::Export::Error) { Nabu::Export::Documents.new(catalog: @catalog, from: 10, to: -10) }
      assert_match(/after/, error.message)

      table = Nabu::Export::Documents.new(catalog: @catalog, sources: %w[alpha], langs: %w[lat], from: -10,
                                          with_axes: true)
      assert_equal({ "source" => %w[alpha], "language" => %w[lat], "from" => -10, "to" => nil,
                     "with_axes" => true, "withdrawn" => "excluded" }, table.filters)
    end

    def test_streams_in_pages_without_loss_or_duplication
      urns = Array.new(300) { |i| format("urn:a:%03d", i) }
      urns.shuffle(random: Random.new(7)).each { |urn| document(@alpha, urn, passages: 0) }
      table = Nabu::Export::Documents.new(catalog: @catalog, with_axes: true, page_size: 7)
      got = []
      table.each_row { |row| got << row.values.first }
      assert_equal urns, got, "every document once, in urn order, across 43 pages"
    end
  end
end
