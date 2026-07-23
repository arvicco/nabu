# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Random (P11-9): the `show --random` sampler. Honest randomness
  # over the two-level-visible passage set (reusing CatalogJoin), optionally
  # scoped to one source, capped at MAX_COUNT. Assertions are on SHAPE (counts,
  # scope, visibility, cap) — never on which passage the RNG picked.
  class RandomTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @open = Nabu::Store::Source.create(
        slug: "alpha", name: "Alpha", adapter_class: "TestAdapter", license_class: "open"
      )
      @nc = Nabu::Store::Source.create(
        slug: "beta", name: "Beta", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def random(source: nil, count: 1)
      Nabu::Query::Random.new(catalog: @catalog).run(source: source, count: count)
    end

    # Seed +n+ passages under one document; returns the document urn.
    def seed_document(source:, urn:, count:, language: "grc", withdrawn: false, doc_withdrawn: false)
      doc_id = @catalog[:documents].insert(
        source_id: source.id, urn: urn, title: urn.split(":").last, language: language,
        content_sha256: "x", revision: 1, withdrawn: doc_withdrawn
      )
      count.times do |i|
        @catalog[:passages].insert(
          document_id: doc_id, urn: "#{urn}:#{i + 1}", sequence: i, language: language,
          text: "text #{i}", text_normalized: "text #{i}", content_sha256: "x",
          revision: 1, withdrawn: withdrawn
        )
      end
      urn
    end

    def test_default_returns_one_visible_passage_in_the_show_layout
      seed_document(source: @open, urn: "urn:nabu:alpha:one", count: 5)
      results = random
      assert_equal 1, results.size
      assert_instance_of Nabu::Query::Show::PassageResult, results.first
      refute results.first.withdrawn
    end

    def test_count_returns_that_many_distinct_passages
      seed_document(source: @open, urn: "urn:nabu:alpha:one", count: 8)
      urns = random(count: 4).map(&:urn)
      assert_equal 4, urns.size
      assert_equal 4, urns.uniq.size, "no passage is drawn twice"
    end

    def test_count_is_capped_at_the_max
      seed_document(source: @open, urn: "urn:nabu:alpha:big", count: 30)
      assert_equal Nabu::Query::Random::MAX_COUNT, random(count: 100).size,
                   "a firehose request is clamped to the sampler ceiling"
    end

    def test_count_below_one_clamps_up_to_one
      seed_document(source: @open, urn: "urn:nabu:alpha:one", count: 3)
      assert_equal 1, random(count: 0).size
      assert_equal 1, random(count: -5).size
    end

    def test_source_scope_restricts_to_that_source
      seed_document(source: @open, urn: "urn:nabu:alpha:one", count: 4)
      seed_document(source: @nc, urn: "urn:nabu:beta:one", count: 4)
      urns = random(source: "alpha", count: 20).map(&:urn)
      assert_equal 4, urns.size
      assert(urns.all? { |urn| urn.start_with?("urn:nabu:alpha:") }, "only the scoped source is drawn")
    end

    def test_withdrawn_passages_are_never_drawn
      seed_document(source: @open, urn: "urn:nabu:alpha:hidden", count: 6, withdrawn: true)
      assert_empty random(count: 20), "a passage-level withdrawal is invisible to the sampler"
    end

    def test_passages_of_a_withdrawn_document_are_never_drawn
      seed_document(source: @open, urn: "urn:nabu:alpha:gone", count: 6, doc_withdrawn: true)
      assert_empty random(count: 20), "a document-level withdrawal hides its passages"
    end

    # P41-r2 (owner report at the 62.8M-passage scale: --random took 2m19s —
    # ORDER BY RANDOM() sorts the whole visible set). The sampler is now an
    # id-probe: O(log n) per draw, near-uniform over bulk-loaded shelves.
    # These pin the probe's correctness properties; uniformity honesty lives
    # in the class comment.
    def test_probe_survives_id_gaps_and_only_lands_on_visible_scope_rows
      # interleaved id space: alpha rows, a beta row between them, a withdrawn
      # alpha row — the probe must land only on visible alpha rows.
      seed_document(source: @open, urn: "urn:a:one", count: 3)
      seed_document(source: @nc, urn: "urn:b:mid", count: 2)
      seed_document(source: @open, urn: "urn:a:two", count: 3)
      seed_document(source: @open, urn: "urn:a:dead", count: 1, withdrawn: true)

      urns = 40.times.flat_map { random(source: "alpha", count: 1).map(&:urn) }.uniq
      refute_empty urns
      assert(urns.all? { |u| u.start_with?("urn:a:") }, "the probe never leaks another source")
      assert(urns.none? { |u| u.start_with?("urn:a:dead") }, "withdrawn rows never drawn")
    end

    def test_a_seeded_rng_makes_the_draw_deterministic
      seed_document(source: @open, urn: "urn:a:seeded", count: 30)
      a = Nabu::Query::Random.new(catalog: @catalog, rng: ::Random.new(7)).run(count: 3).map(&:urn)
      b = Nabu::Query::Random.new(catalog: @catalog, rng: ::Random.new(7)).run(count: 3).map(&:urn)
      assert_equal a, b
    end

    def test_unknown_source_raises_a_clean_error
      seed_document(source: @open, urn: "urn:nabu:alpha:one", count: 2)
      error = assert_raises(Nabu::Query::Random::Error) { random(source: "nope") }
      assert_match(/unknown source "nope"/, error.message)
      assert_match(/nabu status/, error.message)
    end

    def test_a_synced_source_with_nothing_visible_is_an_empty_result_not_an_error
      seed_document(source: @open, urn: "urn:nabu:alpha:hidden", count: 3, withdrawn: true)
      assert_empty random(source: "alpha", count: 5), "a real but empty source is honest emptiness"
    end
  end
end
