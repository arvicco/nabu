# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/embed_timings"

module Ops
  # Nabu::Ops::EmbedTimings — the `nabu embed` stage record (kind "embed",
  # the key the reconstruction plan's enrichment line reads). Exercised
  # over a real Embed campaign against the fake worker (no model, no
  # network): the census and encode rows carry the numbers the command
  # already printed.
  class EmbedTimingsTest < Minitest::Test
    include StoreTestDB

    FAKE_WORKER = ["ruby", File.expand_path("../fixtures/embed/fake_worker.rb", __dir__)].freeze
    TIMINGS = Nabu::Store::StageTimings

    def setup
      @catalog = store_test_db
      @vectors = Sequel.sqlite
      @dir = Dir.mktmpdir("nabu-embed-timings")
      @ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
      source = Nabu::Store::Source.create(slug: "lit", name: "Lit", adapter_class: "TestAdapter",
                                          license_class: "open")
      doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:d:1", title: "t", language: "grc",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      %w[μῆνιν ἄειδε θεά].each_with_index do |text, seq|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:d:1:#{seq}", sequence: seq, language: "grc",
                                    text: text, text_normalized: text, content_sha_raw: "x", revision: 1,
                                    withdrawn: false)
      end
    end

    def teardown
      @vectors.disconnect
      @ledger.disconnect
      FileUtils.rm_rf(@dir)
    end

    def embedder = Nabu::Embed.new(catalog: @catalog, vectors: @vectors, slugs: %w[lit], worker_argv: FAKE_WORKER)

    # One CLI-shaped run: census, campaign, then the record.
    def campaign
      embed = embedder
      census = embed.census
      result = embed.run!
      Nabu::Ops::EmbedTimings.record!(@ledger, census: census, census_seconds: 0.25, result: result)
      [census, result]
    end

    def last(stage) = TIMINGS.last(@ledger, kind: "embed", scope: "corpus", stage: stage)

    def test_a_campaign_records_its_census_and_encode_from_the_numbers_in_hand
      census, result = campaign

      assert_equal 3, result.embedded
      assert_equal [0.25, census.total], last("census").values_at(:seconds, :rows)
      assert_equal [result.elapsed_seconds, 3], last("encode").values_at(:seconds, :rows)
      rows = TIMINGS.latest_per_stage(@ledger, kind: "embed")
      assert_equal %w[census encode], rows.map { |row| row[:stage] },
                   "the reconstruction plan's kind-embed read now finds real rows"
    end

    def test_a_fully_fresh_delta_run_records_the_census_but_no_near_zero_encode
      campaign
      first_encode = last("encode")
      campaign

      assert_equal 2, @ledger[TIMINGS::TABLE].where(kind: "embed", stage: "census").count
      assert_equal first_encode, last("encode"), "nothing embedded: the earlier encode still governs"
    end

    # Recording only: the vectors a recorded campaign lands equal an
    # unrecorded one's.
    def test_recording_leaves_the_campaign_unchanged
      embedder.run!
      unrecorded = @vectors[Nabu::Embed::VECTORS_TABLE].select_order_map(%i[urn text_sha vec])
      @vectors[Nabu::Embed::VECTORS_TABLE].delete
      campaign

      assert_equal unrecorded, @vectors[Nabu::Embed::VECTORS_TABLE].select_order_map(%i[urn text_sha vec])
    end
  end
end
