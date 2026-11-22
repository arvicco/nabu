# frozen_string_literal: true

require "test_helper"

# Nabu::Store::Fts5Tokens — the main lane's token streams asked of SQLite
# itself. Pinned against a REAL passages_fts built by the Indexer: the
# stream this class reads back is what a phrase MATCH sees.
class Fts5TokensTest < Minitest::Test
  def setup
    @tokens = Nabu::Store::Fts5Tokens.new
  end

  def teardown
    @tokens.close
  end

  def test_the_tokenizer_spec_is_passages_fts_verbatim
    assert_includes Nabu::Store::Indexer::CREATE_TABLE,
                    "tokenize = '#{Nabu::Store::Fts5Tokens::MAIN_TOKENIZE}'"
  end

  def test_streams_fold_like_unicode61_not_like_the_ruby_regex
    streams = @tokens.streams(["Abc ÉCOLE", "λόγος ἐπʼ ἐπ’", "áb", "學而時習之 不亦說乎", ""])
    assert_equal %w[abc ecole], streams[0], "case and diacritics fold"
    assert_equal %w[λόγοσ ἐπʼ ἐπ], streams[1], "final sigma maps; U+02BC is a letter, U+2019 a separator"
    assert_equal %w[ab], streams[2], "a combining diacritic stays inside the token and is stripped"
    assert_equal %w[學而時習之 不亦說乎], streams[3], "a Han run is one token"
    assert_empty streams[4]
  end

  def test_streams_survive_batches_in_order
    texts = Array.new(Nabu::Store::Fts5Tokens::BATCH + 3) { |i| "w#{i} x" }
    streams = @tokens.streams(texts)
    assert_equal texts.size, streams.size
    assert_equal %w[w0 x], streams.first
    assert_equal ["w#{texts.size - 1}", "x"], streams.last
  end

  def test_fold_is_per_token_and_nil_when_the_tokenizer_splits
    assert_equal ["λογοσ", "學", nil], @tokens.fold(%w[λογος 學 a-b])
    assert_equal ["λογοσ"], @tokens.fold(["λογος"]), "memoized answers agree"
  end
end
