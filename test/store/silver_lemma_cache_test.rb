# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Store::SilverLemmaCache (P87-2, Q51 under №R-51-B) — the projection
# cache: the deterministic per-record work (JSON parse, fold, group) runs
# ONCE per shelf state; the cache is derived and disposable, keyed by
# shelf fingerprint + PROJECTION_VERSION. Rebuildable ≠ recomputed.
class SilverLemmaCacheTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("nabu-lemma-cache")
    @shelf_dir = File.join(@dir, "shelf")
    @shelf = Nabu::LemmaShelf.new(dir: @shelf_dir)
    @shelf.append_batch!(language: "lat", records: [
                           record("urn:d:1:1", [%w[Fronte frons NOUN], %w[fronte frons NOUN],
                                                %w[et et CCONJ]]),
                           record("urn:d:1:2", [%w[arma arma NOUN], ["virumque", nil, "NOUN"]])
                         ])
    @cache = Nabu::Store::SilverLemmaCache.new(path: File.join(@dir, "cache.sqlite3"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def record(urn, tokens)
    Nabu::LemmaShelf::Record.new(
      urn: urn, language: "lat", source: "edr", model: "stanza",
      model_version: "1", package: "la:test", tokens: tokens,
      generated_at: "2026-08-29T00:00:00Z"
    )
  end

  def test_shelf_fingerprint_is_content_stable_and_content_sensitive
    first = @shelf.fingerprint
    assert_equal first, Nabu::LemmaShelf.new(dir: @shelf_dir).fingerprint, "stable across loads"
    @shelf.append_batch!(language: "lat", records: [record("urn:d:1:3", [%w[bellum bellum NOUN]])])
    refute_equal first, @shelf.fingerprint, "new shard → new fingerprint"
  end

  def test_build_folds_groups_and_marks_identity_once
    @cache.build!(shelf: @shelf)
    assert @cache.valid_for?(@shelf.fingerprint)

    rows = @cache.rows_dataset.where(urn: "urn:d:1:1").order(:lemma_folded).all
    frons = rows.find { |row| row[:lemma_raw] == "frons" }
    assert_equal "Fronte, fronte", frons[:surface_forms], "distinct forms, first-seen order"
    et = rows.find { |row| row[:lemma_raw] == "et" }
    assert_equal 1, et[:identity], "et folds to its own surface — precomputed at build"
    assert_equal 0, frons[:identity]

    arma = @cache.rows_dataset.where(urn: "urn:d:1:2").all
    assert_equal %w[arma], arma.map { |row| row[:lemma_raw] }, "lemma-less tokens contribute nothing"
  end

  def test_validity_is_fingerprint_and_version_keyed
    @cache.build!(shelf: @shelf)
    refute @cache.valid_for?("somethingelse")
    @cache.stamp_version!("v0-obsolete")
    refute @cache.valid_for?(@shelf.fingerprint), "a fold-rules bump invalidates the cache"
  end

  def test_rebuilding_over_a_stale_cache_replaces_it
    @cache.build!(shelf: @shelf)
    before = @cache.rows_dataset.count
    @shelf.append_batch!(language: "lat", records: [record("urn:d:1:3", [%w[bellum bellum NOUN]])])
    @cache.build!(shelf: @shelf)
    assert_equal before + 1, @cache.rows_dataset.count
    assert @cache.valid_for?(@shelf.fingerprint)
  end
end
