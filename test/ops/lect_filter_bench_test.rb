# frozen_string_literal: true

require "test_helper"

module Ops
  # Nabu::Ops::LectFilterBench: the reproducible timing harness for the
  # lect: filter's catalog-join path. Per (term, lect) case it times the
  # same Query::Search run with and without the lect filter, so the
  # difference isolates the filter's cost; read-only on the catalog.
  class LectFilterBenchTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                                overlay: { "urn:d:plautus" => { "lat" => "lat:arch" } })
      src = Nabu::Store::Source.create(slug: "perseus-latin", name: "Perseus Latin",
                                       adapter_class: "TestAdapter", license_class: "open")
      { "urn:d:plautus" => "lat", "urn:d:cicero" => "lat", "urn:d:lamed" => "la-med" }.each do |urn, lang|
        doc = Nabu::Store::Document.create(source_id: src.id, urn: urn, title: "t", language: lang,
                                           content_sha256: "x", revision: 1)
        Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1", sequence: 0, language: lang,
                                    text: "libertas",
                                    text_normalized: Nabu::Normalize.search_form("libertas", language: lang),
                                    content_sha256: "x", revision: 1)
      end
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def teardown
      @fulltext.disconnect
    end

    # A fake monotonic clock: every reading advances 0.5 s, so one timed
    # call measures exactly 500 ms — deterministic arithmetic, no sleep.
    def ticking_clock
      tick = 0.0
      -> { tick += 0.5 }
    end

    def bench(**)
      Nabu::Ops::LectFilterBench.new(catalog: @catalog, fulltext: @fulltext, lects: @lects,
                                     clock: ticking_clock, **)
    end

    def test_parses_term_at_lect_cases
      cases = Nabu::Ops::LectFilterBench.parse_cases("libertas@lat:arch, λόγος@grc:koi")
      assert_equal([%w[libertas lat:arch], %w[λόγος grc:koi]], cases.map { |c| [c.query, c.lect] })
      assert_raises(Nabu::Error) { Nabu::Ops::LectFilterBench.parse_cases("no-lect-here") }
      refute_empty Nabu::Ops::LectFilterBench.parse_cases(Nabu::Ops::LectFilterBench::DEFAULT_CASES)
    end

    def test_times_each_case_with_and_without_the_filter
      rows = bench(repeats: 3).run(Nabu::Ops::LectFilterBench.parse_cases("libertas@lat,libertas@lat:med"))
      lat, med = rows
      assert_equal 3, lat.baseline_hits, "the unfiltered run sees every libertas passage"
      assert_equal 3, lat.hits, "pairs path: la-med resolves to lat:med, under the lat anchor"
      assert_equal 1, med.hits, "only the la-med document is lat:med"
      rows.each do |row|
        assert_in_delta 500.0, row.baseline_ms, 0.001
        assert_in_delta 500.0, row.filtered_ms, 0.001
        assert_in_delta 0.0, row.overhead_ms, 0.001
      end
    end

    def test_reports_the_dispatch_path
      b = bench(repeats: 1)
      assert_equal :pairs, b.path, "no lect facet rows yet: the legacy (language, source) pairs path"
      Nabu::Store::LectFacets.rebuild!(catalog: @catalog, registry: @lects)
      assert_equal :target, b.path, "materialized: the lect_target catalog-join path"
      rows = b.run(Nabu::Ops::LectFilterBench.parse_cases("libertas@lat:arch"))
      assert_equal 1, rows.first.hits, "the per-document ruling rides the facet path"
    end

    def test_read_only_on_the_catalog
      counts = -> { %i[documents passages document_facets].to_h { |t| [t, @catalog[t].count] } }
      before = counts.call
      bench(repeats: 2).run(Nabu::Ops::LectFilterBench.parse_cases("libertas@lat"))
      assert_equal before, counts.call
    end

    def test_report_lines_carry_per_query_wall_times
      b = bench(repeats: 1)
      lines = b.report(b.run(Nabu::Ops::LectFilterBench.parse_cases("libertas@lat")))
      assert_match(/path: pairs/, lines.first)
      assert(lines.any? { |l| l.match?(%r{libertas\s+lat\s+.*hits 3/3.*500\.0 ms.*500\.0 ms.*\+0\.0 ms}) },
             lines.join("\n"))
    end
  end
end
