# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # ndl-kotenseki (P109-2, Q108 phase-1): the NDL 次世代デジタルライブ
  # ラリー classical-materials OCR mass, crawled over the granted bulk
  # route. Fixture: a real fulltext-json capture for PID 2532153
  # (玉篇 巻中 — a 1605 Yupian print's classical OCR), trimmed to its
  # first 6 koma (2 empty cover koma + the title koma + text koma),
  # and the census.tsv row the fetch derives from the NDL open
  # bibliographic dataset.
  class NdlKotensekiTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ndl-kotenseki")

    def conformance_adapter = Nabu::Adapters::NdlKotenseki.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ndl-kotenseki"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pid) = documents.find { |d| d.urn.end_with?(":#{pid}") } || flunk("#{pid} missing")

    def test_discovers_one_document_per_crawled_book
      assert_equal %w[urn:nabu:ndl-kotenseki:2532153],
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_koma_contents_become_passages_empty_koma_skipped
      d = doc(2_532_153)
      assert_equal "jpn", d.language
      assert_equal %w[3 4 5 6], d.passages.map { |p| p.annotations["koma"] },
                   "cover koma with empty OCR contents mint nothing"
      assert_equal "#{d.urn}:3", d.passages.first.urn
      assert_equal "玉篇巻中本", d.passages.first.text
    end

    def test_census_bibliography_joins_the_document
      d = doc(2_532_153)
      assert_equal "玉篇 巻中", d.title
      meta = d.metadata
      assert_equal "machine-ocr", meta["text_nature"], "the OCR-nature label rides every document"
      assert_equal "https://dl.ndl.go.jp/pid/2532153", meta["permalink"],
                   "per-item NDL provenance, as promised in the grant thread"
      assert_equal "[慶長10(1605)]", meta["pub_date"], "the prose date rides verbatim"
      assert_equal({ "value" => "古典籍資料（貴重書等）-その他" }, meta.dig("facets", "collection"))
      assert_equal({ "values" => %w[倭玉篇 辞書] }, meta.dig("facets", "subject"),
                   "the ||-separated 件名 values each facet")
    end

    def test_w3cdtf_year_mints_the_date_envelope
      date = doc(2_532_153).metadata["date"]
      assert_equal [1605, 1605, "[慶長10(1605)]"],
                   date.values_at("not_before", "not_after", "raw")
    end
  end
end
