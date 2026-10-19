# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Store
  # Store::LemmaRollup (P121-2): the lemma attestation instrument's three
  # precompiled catalog rollups — lemma_rollup (attestations per lemma ×
  # language × century × basis × grade × source), language_curve
  # (documents + passages per language × century) and language_mix (one
  # row per document: passage-language inventory + adjacent switches).
  # The rig is the vocab/lemma-search one: real catalog rows, the real
  # Indexer building passage_lemmas into an on-disk fulltext file (the
  # builder ATTACHes it), a gold source and a lemma_tier: silver source.
  class LemmaRollupTest < Minitest::Test
    include StoreTestDB

    TABLES = %i[lemma_rollup language_curve language_mix].freeze

    def setup
      @dir = Dir.mktmpdir("nabu-rollup")
      @fulltext_path = File.join(@dir, "fulltext.sqlite3")
      @catalog = store_test_db
      @gold = source("proiel")
      @silver = source("silvery")
    end

    def teardown
      @catalog.disconnect
      FileUtils.rm_rf(@dir)
    end

    # -- rig -----------------------------------------------------------------

    def source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
    end

    def document(source, urn, language: "lat", withdrawn: false)
      Nabu::Store::Document.create(source_id: source.id, urn: urn, title: urn, language: language,
                                   content_sha256: "x", revision: 1, withdrawn: withdrawn)
    end

    def passage(doc, sequence, lemmas: [], language: "lat", withdrawn: false)
      tokens = lemmas.map { |lemma| { "lemma" => lemma, "form" => lemma } }
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:#{sequence}", sequence: sequence, language: language,
        text: lemmas.join(" "), text_normalized: lemmas.join(" "),
        annotations_json: JSON.generate({ "tokens" => tokens }),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def date(doc, not_before, not_after, date_class: nil)
      @catalog[:document_axes].insert(document_id: doc.id, not_before: not_before, not_after: not_after,
                                      date_class: date_class, axis_source: "test")
    end

    def index!
      fulltext = Nabu::Store.connect_fulltext(@fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext,
                                    lemma_tiers: { "silvery" => "silver" })
    ensure
      fulltext&.disconnect
    end

    def build!(path = @fulltext_path)
      Nabu::Store::LemmaRollup.rebuild!(catalog: @catalog, fulltext_path: path)
    end

    # A small dated corpus: a gold Latin text of 300–30 BCE (midpoint 165
    # BCE → 2nd c. BCE), a gold composition-dated text of 101–200 CE, an
    # undated gold text, a silver inscription of 1 BCE–1 CE straddling the
    # era boundary, and a bilingual document interleaving lat and grc.
    def seed
      @bce = document(@gold, "urn:t:bce")
      date(@bce, -300, -30)
      passage(@bce, 1, lemmas: %w[hostis et])
      passage(@bce, 2, lemmas: %w[hostis])
      @ce = document(@gold, "urn:t:ce")
      date(@ce, 101, 200, date_class: "composition")
      passage(@ce, 1, lemmas: %w[hostis])
      @undated = document(@gold, "urn:t:undated")
      passage(@undated, 1, lemmas: %w[hostis])
      @stone = document(@silver, "urn:s:stone")
      date(@stone, -1, 1)
      passage(@stone, 1, lemmas: %w[hostis])
      @mixed = document(@gold, "urn:t:mixed")
      passage(@mixed, 1, lemmas: %w[et], language: "lat")
      passage(@mixed, 2, lemmas: %w[καί], language: "grc")
      passage(@mixed, 3, lemmas: %w[et], language: "lat")
      passage(@mixed, 4, lemmas: %w[καί], language: "grc")
      passage(@mixed, 5, language: "grc", withdrawn: true) # invisible: never counted
      index!
    end

    def rollup_rows(lemma)
      @catalog[:lemma_rollup].where(lemma: lemma).order(:grade, :century, :source_id).all
    end

    # -- migration shape -------------------------------------------------------

    def test_migration_mints_the_three_rollup_tables_with_their_natural_keys
      assert_equal %i[lemma language century basis grade source_id occurrences documents],
                   @catalog.schema(:lemma_rollup).map(&:first)
      assert_equal %i[language century basis source_id documents passages],
                   @catalog.schema(:language_curve).map(&:first)
      assert_equal %i[document_id source_id urn languages language_count switches],
                   @catalog.schema(:language_mix).map(&:first)
      key = @catalog.indexes(:lemma_rollup).fetch(:lemma_rollup_key)
      assert key[:unique]
      assert_equal %i[lemma language century basis grade source_id], key[:columns]
      assert(@catalog.indexes(:language_mix).values.any? do |index|
        index[:columns] == [:document_id] && index[:unique]
      end)
    end

    # -- century midpoint math --------------------------------------------------

    def test_document_dates_bucket_the_envelope_midpoint_in_signed_centuries
      cases = {
        [-300, -30] => -2,   # midpoint 165 BCE
        [-101, -101] => -2,  # a point year: 101 BCE
        [-100, -1] => -1,    # midpoint 50/51 BCE
        [-1, 1] => -1,       # straddles the missing year 0 → 1 BCE
        [-100, 100] => -1,   # astronomical midpoint 0 = 1 BCE
        [1, 100] => 1,
        [101, 200] => 2,
        [100, 101] => 1,     # floor of 100.5 → 100 CE
        [nil, -450] => -5,   # open lower end: the other bound
        [1201, nil] => 13    # open upper end
      }
      docs = cases.keys.each_with_index.to_h do |(low, high), index|
        doc = document(@gold, "urn:m:#{index}")
        date(doc, low, high)
        [doc.id, [low, high]]
      end
      dated = Nabu::Store::LemmaRollup.document_dates(@catalog).as_hash(:document_id, :century)
      docs.each do |id, bounds|
        assert_equal cases.fetch(bounds), dated.fetch(id), "envelope #{bounds.inspect}"
      end
    end

    def test_midpoint_centuries_agree_with_the_timeline_model
      # The SQL arithmetic against Nabu::Timeline's own century index of the
      # historical midpoint, over a sweep across the era boundary.
      bounds = [-801, -650, -201, -200, -199, -101, -100, -99, -2, -1, 1, 2, 99, 100, 101, 199, 1999]
      pairs = bounds.product(bounds).select { |low, high| low <= high }
      ids = pairs.each_with_index.to_h do |(low, high), index|
        doc = document(@gold, "urn:sweep:#{index}")
        date(doc, low, high)
        [doc.id, [low, high]]
      end
      dated = Nabu::Store::LemmaRollup.document_dates(@catalog).as_hash(:document_id, :century)
      ids.each do |id, (low, high)|
        astro = ->(year) { year.negative? ? year + 1 : year }
        mid = (astro.call(low) + astro.call(high)).div(2) # Ruby floors
        historical = mid <= 0 ? mid - 1 : mid
        assert_equal Nabu::Timeline.century_index(historical), dated.fetch(id), "#{low}..#{high}"
      end
    end

    def test_basis_is_the_date_class_and_place_only_rows_stay_undated
      composed = document(@gold, "urn:b:composed")
      date(composed, 101, 200, date_class: "composition")
      artifact = document(@gold, "urn:b:artifact")
      date(artifact, 101, 200)
      placed = document(@gold, "urn:b:placed")
      date(placed, nil, nil) # a place-only axis row carries no date
      dated = Nabu::Store::LemmaRollup.document_dates(@catalog).as_hash(:document_id, :basis)
      assert_equal "composition", dated.fetch(composed.id)
      assert_equal "artifact", dated.fetch(artifact.id)
      refute dated.key?(placed.id), "a place-only document is undated, never bucketed"
    end

    # P122-1: a silver estimate dates only what no upstream row dates, under
    # its own basis — it never widens or relabels an upstream envelope.
    def test_silver_estimates_fill_only_the_upstream_gap_under_their_own_basis
      estimate = lambda do |doc, low, high|
        @catalog[:document_axes].insert(document_id: doc.id, not_before: low, not_after: high,
                                        date_class: Nabu::Store::SilverDates::DATE_CLASS,
                                        axis_source: Nabu::Store::SilverDates::AXIS_SOURCE)
      end
      upstream = document(@gold, "urn:s:upstream")
      date(upstream, 101, 200)
      estimate.call(upstream, -900, -800)
      gap = document(@gold, "urn:s:gap")
      estimate.call(gap, -300, -201)
      placed = document(@gold, "urn:s:placed")
      date(placed, nil, nil)
      estimate.call(placed, 501, 600)

      rows = Nabu::Store::LemmaRollup.document_dates(@catalog).as_hash(:document_id, %i[century basis])
      assert_equal [2, "artifact"], rows.fetch(upstream.id), "the upstream envelope stands untouched"
      assert_equal [-3, "silver"], rows.fetch(gap.id)
      assert_equal [6, "silver"], rows.fetch(placed.id), "a place-only upstream row dates nothing"
    end

    # -- lemma_rollup ------------------------------------------------------------

    def test_lemma_rollup_separates_gold_and_silver_with_centuries_and_the_undated_row
      seed
      summary = build!
      assert_operator summary.lemma_rows, :>, 0
      rows = rollup_rows("hostis")
      gold = rows.select { |row| row[:grade] == "gold" }
      silver = rows.select { |row| row[:grade] == "silver" }

      assert_equal(Set[nil, -2, 2], gold.to_set { |row| row[:century] })
      bce = gold.find { |row| row[:century] == -2 }
      assert_equal 2, bce[:occurrences], "two passages of the BCE text attest hostis"
      assert_equal 1, bce[:documents]
      assert_equal "artifact", bce[:basis]
      assert_equal "composition", gold.find { |row| row[:century] == 2 }[:basis]
      undated = gold.find { |row| row[:century].nil? }
      assert_nil undated[:basis], "the undated row carries no basis"
      assert_equal 1, undated[:documents]

      assert_equal 1, silver.size, "the lemma_tier: silver source rides as its own grade"
      assert_equal [-1, @silver.id, "lat"], silver.first.values_at(:century, :source_id, :language)
    end

    def test_lemma_rollup_keys_by_passage_language_in_a_mixed_document
      seed
      build!
      kai = Nabu::Normalize.search_form("καί", language: "grc")
      assert_equal ["grc"], rollup_rows(kai).map { |row| row[:language] }.uniq
      assert_equal(2, rollup_rows(kai).sum { |row| row[:occurrences] })
    end

    def test_rebuild_is_idempotent
      seed
      build!
      first = TABLES.to_h { |table| [table, @catalog[table].order(*@catalog[table].columns).all] }
      build!
      TABLES.each do |table|
        assert_equal first.fetch(table), @catalog[table].order(*@catalog[table].columns).all, table.to_s
      end
    end

    def test_refresh_source_matches_the_wholesale_build
      seed
      build!
      wholesale = TABLES.to_h { |table| [table, @catalog[table].order(*@catalog[table].columns).all] }
      @catalog[:lemma_rollup].where(source_id: @gold.id).delete
      @catalog[:language_mix].where(source_id: @gold.id).delete
      Nabu::Store::LemmaRollup.refresh_source!(catalog: @catalog, fulltext_path: @fulltext_path, slug: "proiel")
      TABLES.each do |table|
        assert_equal wholesale.fetch(table), @catalog[table].order(*@catalog[table].columns).all, table.to_s
      end
    end

    # The per-source slice joins passages to the lemma table by passage id;
    # a v1 lemma table (urn stored + indexed — the live file until the next
    # full rebuild) joins by its urn instead, to the identical rollup.
    def test_refresh_source_over_a_v1_lemma_table_matches_the_wholesale_build
      seed
      build!
      wholesale = @catalog[:lemma_rollup].order(*@catalog[:lemma_rollup].columns).all
      fulltext = Nabu::Store.connect_fulltext(@fulltext_path)
      LegacyLemmaTable.widen!(fulltext, @catalog)
      fulltext.disconnect
      @catalog[:lemma_rollup].where(source_id: @gold.id).delete
      Nabu::Store::LemmaRollup.refresh_source!(catalog: @catalog, fulltext_path: @fulltext_path, slug: "proiel")
      assert_equal wholesale, @catalog[:lemma_rollup].order(*@catalog[:lemma_rollup].columns).all
    end

    def test_no_fulltext_file_leaves_the_lemma_rollup_empty_and_builds_the_rest
      seed
      summary = build!(File.join(@dir, "absent.sqlite3"))
      assert_equal 0, summary.lemma_rows
      assert @catalog[:lemma_rollup].empty?
      assert_operator summary.mix_rows, :>, 0
      assert_operator summary.curve_rows, :>, 0
    end

    # -- language_mix + language_curve --------------------------------------------

    def test_language_mix_counts_the_inventory_and_adjacent_switches
      seed
      build!
      mixed = @catalog[:language_mix].where(document_id: @mixed.id).first
      assert_equal "grc,lat", mixed[:languages], "sorted, comma-joined"
      assert_equal 2, mixed[:language_count]
      assert_equal 3, mixed[:switches], "lat→grc→lat→grc; the withdrawn passage never counts"
      mono = @catalog[:language_mix].where(document_id: @bce.id).first
      assert_equal ["lat", 1, 0], mono.values_at(:languages, :language_count, :switches)
      assert_equal 5, @catalog[:language_mix].count, "one row per live document"
    end

    def test_language_curve_counts_documents_and_passages_per_century
      seed
      build!
      lat = @catalog[:language_curve].where(language: "lat", source_id: @gold.id)
      assert_equal({ documents: 1, passages: 2 }, lat.where(century: -2).select(:documents, :passages).first)
      undated = lat.where(century: nil).select(:documents, :passages).first
      assert_equal({ documents: 2, passages: 3 }, undated, "the undated text + the mixed doc's lat passages")
      grc = @catalog[:language_curve].where(language: "grc").all
      assert_equal([[nil, 1, 2]], grc.map { |row| row.values_at(:century, :documents, :passages) })
    end
  end
end
