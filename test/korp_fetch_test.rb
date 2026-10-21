# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

# Nabu::KorpFetch against recorded real Korp API responses (Kielipankki
# api8, 2026-10-21 — test/fixtures/vks/korp/): corpus_info for VKS_FROSTERUS
# + VKS_LPETRI and three two-sentence query pages. The pages are served
# verbatim; the corpus totals (corpus_info Sentences, the pages' hits) are
# RESTATED at stub time to the four / two sentences the test serves — the
# recorded totals (967 / 778) would demand the whole corpus. No network.
class KorpFetchTest < Minitest::Test
  BASE = "https://www.kielipankki.fi/korp/api8"
  KORP = File.join(Nabu::TestSupport.fixtures("vks"), "korp")
  ATTRS = %w[word word_completed word_tilde].freeze
  STRUCTS = %w[text_filename text_title text_datefrom text_dateto sentence_id sentence_code span_page].freeze

  def recorded(name) = JSON.parse(File.read(File.join(KORP, name)))

  def stub_corpus_info(totals)
    body = recorded("corpus_info.json")
    totals.each { |corpus, n| body["corpora"][corpus]["info"]["Sentences"] = n.to_s }
    stub_request(:get, "#{BASE}/corpus_info").with(query: hash_including({}))
                                             .to_return(status: 200, body: JSON.generate(body))
  end

  def stub_page(corpus, start, file, total)
    body = recorded(file).merge("hits" => total)
    stub_request(:get, "#{BASE}/query")
      .with(query: hash_including("corpus" => corpus, "start" => start.to_s))
      .to_return(status: 200, body: JSON.generate(body))
  end

  def stub_harvest
    stub_corpus_info("VKS_FROSTERUS" => 4, "VKS_LPETRI" => 2)
    stub_page("VKS_FROSTERUS", 0, "query_frosterus_0-1.json", 4)
    stub_page("VKS_FROSTERUS", 2, "query_frosterus_2-3.json", 4)
    stub_page("VKS_LPETRI", 0, "query_lpetri_0-1.json", 2)
  end

  def sync(dir, **)
    Nabu::KorpFetch.sync!(base_url: BASE, dir: dir, attic_dir: File.join(dir, ".attic"),
                          corpora: %w[VKS_LPETRI VKS_FROSTERUS], attrs: ATTRS, structs: STRUCTS,
                          text_key: "text_filename", page_size: 2, pause: 0, **)
  end

  def test_harvest_lands_one_jsonl_per_text_in_corpus_order
    stub_harvest
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal 6, result.sentences
      assert_equal 2, result.texts
      assert_match(/\A\h{64}\z/, result.sha)
      lines = File.readlines(File.join(dir, "texts", "VKS_FROSTERUS", "jafro1791.jsonl"))
      assert_equal 4, lines.size
      first = JSON.parse(lines.first)
      assert_equal "JAFro1791-1", first.dig("structs", "sentence_code")
      assert_equal ["Hyödyllinen", nil, nil], first["tokens"].first,
                   "word kept, completed/tilde nulled where they equal it"
      assert_path_exists File.join(dir, "texts", "VKS_LPETRI", "lpet1644a.jsonl")
    end
  end

  def test_the_ledger_records_the_census_and_every_file
    stub_harvest
    Dir.mktmpdir do |dir|
      result = sync(dir)
      ledger = JSON.parse(File.read(File.join(dir, Nabu::KorpFetch::LEDGER_FILE)))
      assert_equal result.sha, ledger.dig("harvest", "pin")
      assert_equal %w[VKS_FROSTERUS VKS_LPETRI], ledger["corpora"].keys
      assert_equal %w[texts/VKS_FROSTERUS/jafro1791.jsonl texts/VKS_LPETRI/lpet1644a.jsonl], ledger["files"].keys
    end
  end

  def test_a_resync_of_the_same_answers_is_byte_identical
    stub_harvest
    Dir.mktmpdir do |dir|
      first = sync(dir).sha
      assert_equal first, sync(dir).sha
    end
  end

  def test_progress_narrates_every_page
    stub_harvest
    lines = []
    Dir.mktmpdir { |dir| sync(dir, progress: ->(line) { lines << line }) }
    assert_equal(["VKS_FROSTERUS 2/4", "VKS_FROSTERUS 4/4", "VKS_LPETRI 2/2"],
                 lines.map { |line| line[%r{\A\S+ \d+/\d+}] })
  end

  def test_a_short_page_is_a_loud_error_never_a_short_corpus
    stub_corpus_info("VKS_FROSTERUS" => 4, "VKS_LPETRI" => 2)
    stub_page("VKS_FROSTERUS", 0, "query_frosterus_0-1.json", 4)
    stub_page("VKS_LPETRI", 0, "query_lpetri_0-1.json", 2)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::KorpFetch::Error) do
        Nabu::KorpFetch.sync!(base_url: BASE, dir: dir, attic_dir: File.join(dir, ".attic"),
                              corpora: %w[VKS_FROSTERUS], attrs: ATTRS, structs: STRUCTS,
                              text_key: "text_filename", page_size: 4, pause: 0)
      end
      assert_match(/returned 2 rows/, error.message)
      refute_path_exists File.join(dir, "texts"), "the live tree stays untouched"
    end
  end

  def test_a_hit_total_disagreeing_with_corpus_info_is_an_error
    stub_corpus_info("VKS_FROSTERUS" => 4, "VKS_LPETRI" => 2)
    stub_page("VKS_FROSTERUS", 0, "query_frosterus_0-1.json", 967)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::KorpFetch::Error) { sync(dir) }
      assert_match(/reports 967 sentence hits, corpus_info says 4/, error.message)
    end
  end

  def test_a_corpus_upstream_no_longer_serves_is_an_error
    stub_corpus_info("VKS_FROSTERUS" => 4, "VKS_LPETRI" => 2)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::KorpFetch::Error) do
        Nabu::KorpFetch.sync!(base_url: BASE, dir: dir, attic_dir: File.join(dir, ".attic"),
                              corpora: %w[VKS_NOPE], attrs: ATTRS, structs: STRUCTS,
                              text_key: "text_filename", pause: 0)
      end
      assert_match(/VKS_NOPE is not served/, error.message)
    end
  end

  def test_a_text_upstream_dropped_goes_to_the_attic_after_the_guard
    stub_harvest
    Dir.mktmpdir do |dir|
      sync(dir)
      gone = File.join(dir, "texts", "VKS_LPETRI", "old_text.jsonl")
      File.write(gone, "{}\n")
      seen = nil
      sync(dir, guard: ->(doomed) { seen = doomed })
      assert_equal [gone], seen
      refute_path_exists gone
      assert_path_exists File.join(dir, ".attic", "texts", "VKS_LPETRI", "old_text.jsonl")
    end
  end
end
