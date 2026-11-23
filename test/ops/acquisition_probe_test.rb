# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/ops/acquisition_probe"

# `rake acquisition:probe` — the acquisition plan's park / re-check
# conditions as one batch of HTTP state checks, read from the instance
# board's probes.yml. WebMock stands in for every upstream (no network).
class AcquisitionProbeTest < Minitest::Test
  AP = Nabu::Ops::AcquisitionProbe

  def setup
    @tmp = Dir.mktmpdir("acquisition-probe-test")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def rows(yaml)
    path = File.join(@tmp, "probes.yml")
    File.write(path, yaml)
    AP.load(path)
  end

  def probe(rows)
    out = StringIO.new
    results = AP.new(rows: rows, out: out).run
    [results, out.string.lines(chomp: true)]
  end

  def test_rows_load_with_status_any_and_substring_expectations
    loaded = rows(<<~YAML)
      - name: host
        url: https://dom.example/data/obj/1
        expect: any
        note: "file host — dead 2026-11-23"
      - name: corpus
        url: https://korpuss.example/
        expect: 200
      - name: page
        url: https://digilab.example/
        expect: "Open corpus"
    YAML
    assert_equal ["any", 200, "Open corpus"], loaded.map(&:expect)
    assert_equal "file host — dead 2026-11-23", loaded.first.note
  end

  def test_a_malformed_row_is_refused
    assert_raises(AP::Invalid) { rows("- name: x\n  url: ftp://nope\n") }
    assert_raises(AP::Invalid) { rows("name: x\n") }
  end

  def test_status_rows_ask_head_and_report_against_the_expectation
    stub_request(:head, "https://korpuss.example/").to_return(status: 200)
    stub_request(:head, "https://gone.example/").to_return(status: 404)
    results, lines = probe(rows(<<~YAML))
      - {name: corpus, url: "https://korpuss.example/", expect: 200, note: the NoSketch surface}
      - {name: gone, url: "https://gone.example/", expect: 200}
    YAML
    assert_equal [true, false], results.map(&:ok?)
    assert_equal "corpus → HTTP 200 (expect 200) — as expected — the NoSketch surface", lines[0]
    assert_equal "gone → HTTP 404 (expect 200) — CHANGED", lines[1]
    assert_equal "acquisition:probe — 2 probe(s): 1 as expected, 1 CHANGED", lines.last
  end

  def test_any_accepts_every_http_answer_and_a_dead_host_is_no_answer
    stub_request(:head, "https://alive.example/").to_return(status: 503)
    stub_request(:head, "https://dead.example/x").to_timeout
    results, lines = probe(rows(<<~YAML))
      - {name: alive, url: "https://alive.example/", expect: any}
      - {name: dead, url: "https://dead.example/x", expect: any, note: dead 2026-11-23}
    YAML
    assert_equal [true, false], results.map(&:ok?)
    assert_match(/\Adead → no answer \(.+\) \(expect any\) — CHANGED — dead 2026-11-23\z/, lines[1])
    assert_requested(:head, "https://dead.example/x", times: 1) # never a retry
  end

  def test_substring_rows_ask_get
    stub_request(:get, "https://digilab.example/").to_return(status: 200, body: "<h1>Open corpus</h1>")
    results, lines = probe(rows(%(- {name: page, url: "https://digilab.example/", expect: "Open corpus"}\n)))
    assert_predicate results.first, :ok?
    assert_equal 'page → HTTP 200 (expect "Open corpus") — as expected', lines.first
  end

  def test_a_head_refused_falls_back_to_one_get
    stub_request(:head, "https://nohead.example/").to_return(status: 405)
    stub_request(:get, "https://nohead.example/").to_return(status: 200)
    results, = probe(rows(%(- {name: nohead, url: "https://nohead.example/", expect: 200}\n)))
    assert_predicate results.first, :ok?
  end

  def test_redirects_are_followed_at_most_three_hops
    4.times do |i|
      stub_request(:head, "https://r.example/#{i}").to_return(status: 302, headers: { "Location" => "/#{i + 1}" })
    end
    stub_request(:head, "https://r.example/4").to_return(status: 200)
    results, lines = probe(rows(%(- {name: hops, url: "https://r.example/0", expect: 200}\n)))
    refute_predicate results.first, :ok?
    assert_match(/hops → HTTP 302 after 3 redirect\(s\)/, lines.first)
    assert_not_requested(:head, "https://r.example/4")

    stub_request(:head, "https://s.example/a").to_return(status: 301, headers: { "Location" => "https://s.example/b" })
    stub_request(:head, "https://s.example/b").to_return(status: 200)
    results, lines = probe(rows(%(- {name: one, url: "https://s.example/a", expect: 200}\n)))
    assert_predicate results.first, :ok?
    assert_match(/one → HTTP 200 after 1 redirect\(s\)/, lines.first)
  end

  def test_the_held_vs_searchable_delta_reads_both_dbs_read_only
    catalog = File.join(@tmp, "catalog.sqlite3")
    fulltext = File.join(@tmp, "fulltext.sqlite3")
    db = Sequel.sqlite(catalog)
    db.create_table(:passages) { primary_key :id }
    5.times { db[:passages].insert({}) }
    db.disconnect
    db = Sequel.sqlite(fulltext)
    db.run("CREATE VIRTUAL TABLE passages_fts USING fts5(text_normalized)")
    3.times { |i| db[:passages_fts].insert(text_normalized: "w#{i}") }
    db.disconnect

    line = AP.searchable_delta(catalog_path: catalog, fulltext_path: fulltext)
    assert_equal "held-vs-searchable: 5 catalog passage(s), 3 in passages_fts — delta 2 " \
                 "(held but not yet searchable)", line
  end

  def test_the_delta_skips_absent_or_unreadable_dbs
    catalog = File.join(@tmp, "catalog.sqlite3")
    assert_match(/\Aheld-vs-searchable: skipped \(no catalog\.sqlite3, fulltext\.sqlite3\)\z/,
                 AP.searchable_delta(catalog_path: catalog, fulltext_path: File.join(@tmp, "fulltext.sqlite3")))
    File.write(catalog, "not a database")
    File.write(File.join(@tmp, "fulltext.sqlite3"), "not a database")
    assert_match(/\Aheld-vs-searchable: skipped \(/,
                 AP.searchable_delta(catalog_path: catalog, fulltext_path: File.join(@tmp, "fulltext.sqlite3")))
  end
end
