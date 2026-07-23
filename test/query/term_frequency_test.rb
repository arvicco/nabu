# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Query
  # Nabu::Query::TermFrequency (P42-2): the fts5vocab df probe behind the
  # ubiquitous-term guard. Same rig as the search tests — fresh in-memory
  # catalog, separate fulltext connection, real Indexer rebuild — so the
  # probe reads the very index shape production reads. The one departure:
  # the readonly test builds a FILE-backed index, because two connections
  # to "sqlite::memory:" are two different databases.
  class TermFrequencyTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    def make_passage(document, urn:, text:, sequence:, language: "lat")
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        content_sha256: "x", revision: 1
      )
    end

    def seed_corpus(catalog: @catalog, fulltext: @fulltext)
      doc = Nabu::Store::Document.create(
        source_id: @source.id, urn: "urn:d:1", title: "Doc", language: "lat",
        content_sha256: "x", revision: 1
      )
      3.times { |i| make_passage(doc, urn: "urn:d:1:a#{i}", text: "aurora nox", sequence: i) }
      make_passage(doc, urn: "urn:d:1:rara", text: "aurora rara", sequence: 3)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
    end

    def probe(fulltext: @fulltext)
      Nabu::Query::TermFrequency.new(fulltext: fulltext)
    end

    # -- the candidate ceiling ---------------------------------------------

    def test_single_term_ceiling_is_its_document_frequency
      seed_corpus
      assert_equal 4, probe.candidate_ceiling(["aurora"]), "aurora appears in 4 passages"
      assert_equal 1, probe.candidate_ceiling(["rara"])
    end

    # The multi-term rule (the packet's design point 4): the candidate set a
    # ranked query must score is the rows matching the WHOLE query (implicit
    # AND), which is bounded by the rarest term's df — a rare term ANDed with
    # a ubiquitous one makes ranking cheap again.
    def test_multi_term_ceiling_is_the_minimum_df
      seed_corpus
      assert_equal 1, probe.candidate_ceiling(["aurora rara"]),
                   "rows matching BOTH terms are at most min(df) = df(rara)"
    end

    # Query-fold variants are ORed in the MATCH, so the union's upper bound
    # is the sum of the per-variant bounds.
    def test_variant_ceilings_sum
      seed_corpus
      assert_equal 5, probe.candidate_ceiling(%w[aurora rara]),
                   "ORed variants bound the union: 4 + 1"
    end

    # -- fail-open bounds ---------------------------------------------------

    def test_unknown_token_bounds_its_variant_at_zero
      seed_corpus
      assert_equal 0, probe.candidate_ceiling(["aurora zzznever"]),
                   "a term absent from the vocabulary caps the AND at zero"
    end

    def test_fts_syntax_tokens_fail_open_to_zero
      seed_corpus
      # A quoted phrase or prefix star never matches a vocabulary term
      # verbatim, so the probe under-counts to 0 and the guard stays off —
      # power queries keep today's ranked behavior exactly.
      assert_equal 0, probe.candidate_ceiling(['"aurora nox"'])
      assert_equal 0, probe.candidate_ceiling(["auror*"])
    end

    def test_empty_variant_contributes_zero
      seed_corpus
      assert_equal 0, probe.candidate_ceiling([""])
    end

    # -- feature detection --------------------------------------------------

    # A fulltext db with no passages_fts at all (nothing was ever indexed):
    # the vocab table cannot be created over a missing base — the probe says
    # "unknown", never raises, and the caller skips the guard.
    def test_probe_is_nil_when_the_fts_table_is_absent
      bare = Nabu::Store.connect_fulltext("sqlite::memory:")
      assert_nil probe(fulltext: bare).candidate_ceiling(["aurora"])
    ensure
      bare&.disconnect
    end

    # -- the MCP posture: a READONLY handle ---------------------------------

    # The MCP server opens the fulltext db with SQLITE_OPEN_READONLY (P8-1).
    # The vocab table lives in the connection's TEMP schema — a pure reader
    # of the existing FTS index, no file-schema write — so the probe must
    # work there too, with no reindex and no writable handle.
    def test_probe_works_on_a_readonly_handle
      Dir.mktmpdir("nabu-vocab") do |dir|
        path = File.join(dir, "fulltext.sqlite3")
        writer = Nabu::Store.connect_fulltext(path)
        seed_corpus(fulltext: writer)
        writer.disconnect

        readonly = Nabu::Store.connect_fulltext(path, readonly: true)
        begin
          assert_equal 4, probe(fulltext: readonly).candidate_ceiling(["aurora"]),
                       "the temp-schema vocab table needs no write access to the file"
        ensure
          readonly.disconnect
        end
      end
    end
  end
end
