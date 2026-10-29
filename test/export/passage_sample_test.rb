# frozen_string_literal: true

require "test_helper"
require "json"

module Export
  # Nabu::Export::PassageSample (`nabu export passages --stratum ...`): a
  # stratified, reproducible passage sample — cells keyed by language /
  # century / script / source, equal allocation (--per-cell, the default)
  # or proportional (--proportional TOTAL), a seeded hash order so the same
  # seed draws the same urns, and every row carrying its cell population
  # and inverse-inclusion weight. --exclude-ocr drops documents the catalog
  # flags as OCR text (metadata text_nature).
  class PassageSampleTest < Minitest::Test
    include StoreTestDB

    LATIN = "arma virumque cano"
    GREEK = "μῆνιν ἄειδε θεά"

    def setup
      @catalog = store_test_db
      @alpha = source("alpha", "open")
      @beta = source("beta", "nc")
      @scan = source("scan", "open")
    end

    def source(slug, license_class)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
    end

    def document(source, urn, language:, text:, passages:, metadata: {}, annotations: ->(_seq) { {} })
      doc = Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: language,
                                         content_sha256: "x", revision: 1, withdrawn: false,
                                         metadata_json: JSON.generate(metadata))
      passages.times do |seq|
        Nabu::Store::Passage.create(document_id: doc.id, urn: format("%<urn>s:%<seq>02d", urn: urn, seq: seq),
                                    sequence: seq, language: language, text: text, text_normalized: text,
                                    content_sha256: "x", revision: 1, withdrawn: false,
                                    annotations_json: JSON.generate(annotations.call(seq)))
      end
      doc
    end

    # 6 dated Latin passages (1st c. BCE), 2 undated Greek, 3 OCR Latin.
    def seed
      lat = document(@alpha, "urn:a:lat", language: "lat", text: LATIN, passages: 6)
      @catalog[:document_axes].insert(document_id: lat.id, axis_source: "test", not_before: -100, not_after: -50)
      document(@beta, "urn:b:grc", language: "grc", text: GREEK, passages: 2)
      document(@scan, "urn:s:ocr", language: "lat", text: LATIN, passages: 3,
                                   metadata: { "text_nature" => "uncorrected-ocr" })
    end

    def sample(**)
      table = Nabu::Export::PassageSample.new(catalog: @catalog, **)
      rows = []
      table.each_row { |row| rows << [table.columns.map(&:name).zip(row.values).to_h, row.draws] }
      [table, rows.map(&:first), rows.map(&:last)]
    end

    def test_columns_are_documented
      columns = Nabu::Export::PassageSample.new(catalog: @catalog, strata: %w[language]).columns
      assert_equal %w[urn document_urn source language century script stratum cell_population cell_sampled
                      weight license_class text], columns.map(&:name)
      assert(columns.all? { |column| !column.description.to_s.empty? })
    end

    def test_per_cell_caps_each_cell_and_weights_restore_the_population
      seed
      table, rows, draws = sample(strata: %w[language], per_cell: 2)
      by_language = rows.group_by { |row| row["language"] }
      assert_equal 2, by_language.fetch("grc").size
      assert_equal 2, by_language.fetch("lat").size
      lat = by_language.fetch("lat").first
      assert_equal [9, 2, 4.5, "language=lat"], lat.values_at("cell_population", "cell_sampled", "weight", "stratum")
      grc = by_language.fetch("grc").first
      assert_equal [2, 2, 1.0, "nc", GREEK], grc.values_at("cell_population", "cell_sampled", "weight",
                                                           "license_class", "text")
      assert_includes draws, [%w[beta nc]]
      assert_equal 11, table.notes.fetch("population")
      assert_equal 2, table.notes.fetch("cells")
    end

    def test_default_is_equal_allocation_of_one_hundred_per_cell
      seed
      table, rows, = sample(strata: %w[language])
      assert_equal 11, rows.size, "cells smaller than the default take every passage"
      assert_equal "per_cell", table.filters.fetch("allocation")
      assert_equal 100, table.filters.fetch("per_cell")
    end

    def test_the_seed_decides_the_draw_reproducibly
      seed
      first = sample(strata: %w[language], per_cell: 3, seed: 1)[1].map { |row| row["urn"] }
      again = sample(strata: %w[language], per_cell: 3, seed: 1)[1].map { |row| row["urn"] }
      other = sample(strata: %w[language], per_cell: 3, seed: 7)[1].map { |row| row["urn"] }
      assert_equal first, again
      refute_equal first, other
      assert_equal first.sort_by { |urn| [urn.start_with?("urn:b") ? 0 : 1, urn] }, first,
                   "rows stream cell by cell (grc before lat), urn order within a cell"
    end

    def test_century_and_script_strata
      seed
      _table, rows, = sample(strata: %w[century script], exclude_ocr: true)
      cells = rows.map { |row| row["stratum"] }.uniq
      assert_equal ["century=-1;script=latn", "century=null;script=grek"], cells,
                   "the envelope midpoint's century (−100..−50 → 1st c. BCE); undated is its own cell"
      assert_equal [-1, "latn"], rows.find { |row| row["language"] == "lat" }.values_at("century", "script")
    end

    def test_proportional_allocates_by_largest_remainder
      seed
      table, rows, = sample(strata: %w[language], proportional: 4, exclude_ocr: true)
      counts = rows.group_by { |row| row["language"] }.transform_values(&:size)
      assert_equal({ "grc" => 1, "lat" => 3 }, counts, "6:2 of 4 → 3:1")
      assert_equal "proportional", table.filters.fetch("allocation")
    end

    def test_exclude_ocr_and_exclude_source
      seed
      table, rows, = sample(strata: %w[source], exclude_ocr: true)
      refute(rows.any? { |row| row["source"] == "scan" })
      assert_equal 1, table.notes.fetch("ocr_documents_excluded")
      _table, rows, = sample(strata: %w[source], exclude_sources: %w[beta])
      assert_equal %w[alpha scan], rows.map { |row| row["source"] }.uniq
    end

    def test_exclude_ocr_keeps_corrected_and_ocr_origin_text
      document(@alpha, "urn:a:corr", language: "lat", text: LATIN, passages: 2,
                                     metadata: { "text_nature" => "corrected-ocr" })
      document(@alpha, "urn:a:orig", language: "lat", text: LATIN, passages: 1,
                                     metadata: { "text_nature" => "ocr-origin" })
      document(@scan, "urn:s:raw", language: "lat", text: LATIN, passages: 1,
                                   metadata: { "text_nature" => "machine-ocr" })
      table, rows, = sample(strata: %w[source], exclude_ocr: true)
      assert_equal %w[urn:a:corr urn:a:orig], rows.map { |row| row["document_urn"] }.uniq.sort
      assert_equal 1, table.notes.fetch("ocr_documents_excluded")
    end

    # The ProofreadPage levels the wikisource adapters already record:
    # IndexedWikisource's document-grain proofread.lowest_text_level and
    # ban-wikisource's per-page passage annotation "quality".
    def seed_proofread
      wiki = source("pl-wikisource", "open")
      ban = source("ban-wikisource", "open")
      document(wiki, "urn:w:raw", language: "pol", text: LATIN, passages: 2,
                                  metadata: { "proofread" => { "levels" => { "1" => 3, "3" => 9 },
                                                               "lowest_text_level" => 1 } })
      document(wiki, "urn:w:done", language: "pol", text: LATIN, passages: 2,
                                   metadata: { "proofread" => { "levels" => { "3" => 4 }, "lowest_text_level" => 3 } })
      levels = [{ "quality" => 1 }, { "quality" => 3 }, {}, { "quality" => 4 }]
      document(ban, "urn:n:lontar", language: "ban", text: LATIN, passages: 4, annotations: ->(seq) { levels[seq] })
    end

    def test_exclude_unproofread_drops_level_one_documents_and_pages
      seed
      seed_proofread
      table, rows, = sample(strata: %w[source], exclude_unproofread: true)
      urns = rows.map { |row| row["urn"] }
      refute(urns.any? { |urn| urn.start_with?("urn:w:raw") }, "a document whose lowest text level is 1 drops whole")
      assert_equal %w[urn:w:done:00 urn:w:done:01], urns.grep(/\Aurn:w:/)
      assert_equal %w[urn:n:lontar:01 urn:n:lontar:02 urn:n:lontar:03], urns.grep(/\Aurn:n:/),
                   "the level-1 page drops alone; a page with no recorded level rides"
      assert_equal 11, urns.grep(/\Aurn:[abs]:/).size, "text without ProofreadPage data is untouched"
      assert_equal 1, table.notes.fetch("unproofread_documents_excluded")
      assert_equal 1, table.notes.fetch("unproofread_pages_excluded")
      assert table.filters.fetch("exclude_unproofread")
      _table, rows, = sample(strata: %w[source])
      assert_equal 19, rows.size, "without the flag every passage is in scope"
    end

    def test_refusals_name_the_fix
      error = assert_raises(Nabu::Export::Error) { Nabu::Export::PassageSample.new(catalog: @catalog, strata: %w[era]) }
      assert_match(/unknown stratum "era".*language, century, script, source/, error.message)
      error = assert_raises(Nabu::Export::Error) do
        Nabu::Export::PassageSample.new(catalog: @catalog, strata: %w[language], per_cell: 5, proportional: 9)
      end
      assert_match(/either --per-cell or --proportional/, error.message)
      error = assert_raises(Nabu::Export::Error) do
        Nabu::Export::PassageSample.new(catalog: @catalog, strata: %w[language], per_cell: 0)
      end
      assert_match(/positive/, error.message)
      error = assert_raises(Nabu::Export::Error) { Nabu::Export::PassageSample.new(catalog: @catalog, strata: []) }
      assert_match(/at least one stratum/, error.message)
    end
  end
end
