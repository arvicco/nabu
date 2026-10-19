# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # The NDL Search bib-record family (the ndl-kotenseki bib join): the SRU
  # searchRetrieve response (recordSchema dcndl) split into per-PID
  # sidecars, and the sidecar read back into the join's fields. Fixture:
  # a real three-PID SRU answer (README) — 玉篇 (NDC 813.2, typed 1605),
  # 古今武者揃 (two authority creators, one with life-years) and
  # 花かつみ考 (the issued year the census lacks).
  class NdlSearchBibTest < Minitest::Test
    Bib = Nabu::Adapters::NdlSearchBib
    FIXTURES = Nabu::TestSupport.fixtures("ndl-kotenseki")
    SRU = File.join(FIXTURES, "sru", "searchRetrieve-3.xml")

    def page = @page ||= Bib.page(File.read(SRU))

    def sidecar(pid) = Bib.sidecar(pid, Bib.records_for(pid, page.records))

    def extract(pid)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "#{pid}.xml")
        File.write(path, sidecar(pid))
        return Bib.read(path)
      end
    end

    def test_query_url_batches_pids_into_one_cql_or
      url = Bib.query_url(%w[2532153 2541107])
      assert url.start_with?("https://ndlsearch.ndl.go.jp/api/sru?operation=searchRetrieve&version=1.2" \
                             "&recordSchema=dcndl&maximumRecords=200&startRecord=1&query=")
      query = URI.decode_www_form_component(url[/query=(.*)\z/, 1])
      assert_equal 'anywhere="info:ndljp/pid/2532153" OR anywhere="info:ndljp/pid/2541107"', query
      refute_includes url, "+", "spaces travel as %20"
      assert_includes Bib.query_url(%w[1], start: 201), "&startRecord=201&"
    end

    def test_page_reads_the_record_count_and_every_record
      assert_equal 3, page.total
      assert_equal 3, page.records.size
      assert_nil page.next_position, "a complete answer names no next record"
      assert(page.records.all? { |rdf| rdf.lstrip.start_with?("<rdf:RDF") })
    end

    def test_a_diagnostic_answer_is_a_fetch_error
      body = File.read(File.join(FIXTURES, "sru", "diagnostic.xml"))
      error = assert_raises(Nabu::FetchError) { Bib.page(body) }
      assert_match(/illegal query syntax/, error.message)
      assert_raises(Nabu::FetchError) { Bib.page("<html>busy</html>") }
    end

    def test_records_match_their_pid_by_the_digital_collection_link_only
      assert_equal 1, Bib.records_for("2532153", page.records).size
      assert_empty Bib.records_for("253215", page.records), "a PID prefix is not a match"
      assert_empty Bib.records_for("9999999", page.records)
    end

    def test_sidecar_wraps_the_records_verbatim
      xml = sidecar("2532153")
      assert xml.start_with?(%(<?xml version="1.0" encoding="UTF-8"?>\n<ndl-bib pid="2532153">))
      assert_includes xml, Bib.records_for("2532153", page.records).first.strip
    end

    def test_ndc_and_typed_issued_year
      bib = extract("2532153")
      assert_equal ["813.2"], bib["ndc"]
      assert_equal [1605], bib["issued"]
      assert_equal "[慶長10(1605)]", bib["date_prose"]
      assert_equal [{ "category" => "R100000002", "bib_id" => "000003284459" }], bib["records"]
      assert_nil bib["creators"], "a record without creators claims none"
    end

    def test_authority_creators_split_life_years_conservatively
      creators = extract("2541107")["creators"]
      assert_equal [
        { "name" => "夷福山人", "reading" => "イフク サンジン",
          "authority" => "http://id.ndl.go.jp/auth/entity/001172893" },
        { "name" => "歌川, 広重 1世", "life" => "1797-1858", "born" => 1797, "died" => 1858,
          "reading" => "ウタガワ, ヒロシゲ 1セイ, 1797-1858",
          "authority" => "http://id.ndl.go.jp/auth/entity/00272450" }
      ], creators
      assert_nil extract("2541107")["issued"], "no issued year, no claim"
    end

    def test_the_issued_year_the_census_lacks
      bib = extract("2537051")
      assert_equal [1795], bib["issued"]
      assert_equal "寛政7 [1795] 序", bib["date_prose"]
      assert_equal [{ "name" => "藤塚, 知明", "reading" => "フジツカ, トモアキ" }], bib["creators"]
    end

    def test_creator_life_forms
      split = Bib.method(:creator_name)
      assert_equal({ "name" => "近藤, 芳樹", "life" => "1801-1880", "born" => 1801, "died" => 1880 },
                   split.call("近藤, 芳樹, 1801-1880"))
      assert_equal({ "name" => "空海", "life" => "774-835", "born" => 774, "died" => 835 },
                   split.call("空海, 774-835"))
      assert_equal({ "name" => "a, b", "life" => "-1700", "died" => 1700 }, split.call("a, b, -1700"))
      assert_equal({ "name" => "a, b 2世", "life" => "1797?-" }, split.call("a, b 2世, 1797?-"),
                   "an uncertain year is kept verbatim in life, never typed")
      assert_equal({ "name" => "八文字, 自笑 2代, 明和頃" }, split.call("八文字, 自笑 2代, 明和頃"),
                   "a floruit era is not a life span — the name stays whole")
      assert_equal({ "name" => "流光斎 1世" }, split.call("流光斎 1世"))
    end

    # A digital-collection record (R100000039, no NDLBibID of its own)
    # carrying both classification schemes and the publisher's location.
    def test_digital_collection_record_with_ndlc_and_publication_place
      bib = Bib.read(File.join(FIXTURES, "bib", "2546138.xml"))
      assert_equal [{ "category" => "R100000039" }], bib["records"]
      assert_equal ["991"], bib["ndc"]
      assert_equal ["KP25"], bib["ndlc"], "the id.ndl.go.jp class URI shape"
      assert_equal ["[製作地不明]"], bib["publication_places"], "verbatim, the unknown marker included"
      assert_equal "[製作年不明]", bib["date_prose"]
      assert_nil bib["issued"], "a prose unknown-date mints no year"
      assert_equal [{ "name" => "和辻, 哲郎", "life" => "1889-1960", "born" => 1889, "died" => 1960 }],
                   bib["creators"]
    end

    def test_a_malformed_sidecar_is_a_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "1.xml")
        File.write(path, "<ndl-bib pid=\"1\"><rdf:RDF")
        assert_raises(Nabu::ParseError) { Bib.read(path) }
        File.write(path, "<ndl-bib pid=\"1\"></ndl-bib>")
        assert_raises(Nabu::ParseError) { Bib.read(path) }
      end
    end

    def test_the_unknown_date_sentinel_mints_no_year
      assert_equal [1700], Bib.issued_years(%w[1000 1700])
    end
  end
end
