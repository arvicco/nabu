# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"

# THE PROPORTIONALITY LAW's suite side (architecture §1; the
# incrementality review, R1): online sync/refresh stages are O(Δ), and
# every timed index stage DECLARES its cost class (Store::IndexCostClasses).
# The declaration is checked two ways: statically (every stage the indexer
# times is declared, and no declaration is orphaned) and empirically —
# every declared-O(Δ) stage is timed through the stage ledger on two
# sources of very different size under the SAME delta, and fails when its
# wall time follows the source. A control proves the instrument can tell
# the difference at these sizes: a genuinely O(source) read measured the
# same way must trip the line.
class IndexProportionalityTest < Minitest::Test
  include StoreTestDB

  Indexer = Nabu::Store::Indexer
  Classes = Nabu::Store::IndexCostClasses
  INDEXER_SOURCE = File.expand_path("../lib/nabu/store/indexer.rb", __dir__)

  SMALL = 100
  LARGE = 6_000
  SIZE_RATIO = LARGE / SMALL
  # A DELTA stage may cost up to this multiple of itself between the two
  # sizes — a quarter of the size ratio: generous against timer noise on
  # a parallel suite, far below what an O(source) stage shows (the
  # control below must exceed it).
  MAX_TIME_RATIO = SIZE_RATIO / 4.0
  # Sub-floor times are noise, never a ratio's denominator.
  FLOOR_SECONDS = 0.001
  # Each size runs this many identical deltas; the MINIMUM per stage
  # governs (one GC pause must not read as a scaling law).
  TRIALS = 3
  DELTA_ADDS = 5
  DELTA_WITHDRAWALS = 5

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @dir = Dir.mktmpdir("nabu-proportionality")
    @ledger = Nabu::Store::Ledger.open!(File.join(@dir, "history.sqlite3"))
    @docs = { "small" => seed_source("small", SMALL), "large" => seed_source("large", LARGE) }
    Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
  end

  def teardown
    @fulltext.disconnect
    @ledger.disconnect
    FileUtils.rm_rf(@dir)
  end

  # -- the declaration ---------------------------------------------------------

  def test_every_timed_index_stage_declares_its_cost_class
    timed = File.read(INDEXER_SOURCE).scan(/timed_sync_stage\(ledger, [^,]+, "([a-z_]+)"/).flatten.uniq

    refute_empty timed
    timed.each { |stage| Classes.for("sync", stage) } # raises UndeclaredStage
    assert_empty Classes::SYNC.keys - timed, "a declared stage no longer timed anywhere is a stale declaration"
  end

  def test_an_undeclared_stage_refuses_to_time
    assert_raises(Classes::UndeclaredStage) do
      Indexer.timed_sync_stage(nil, "small", "mystery_stage", "label", nil) { :ran }
    end
    assert_equal Classes::RAIL, Classes.for(Nabu::Store::IndexMaintenance::KIND, "anything")
  end

  # -- the empirical invariant ---------------------------------------------------

  def test_declared_delta_stages_scale_with_the_delta_not_the_source
    small = measure("small")
    large = measure("large")
    exercised = Classes.delta_stages & small.keys & large.keys

    assert_empty %w[index_slice postings_swaps fts_merge] - exercised,
                 "the fixtures exercise every always-on DELTA stage (got #{exercised.inspect})"
    exercised.each do |stage|
      ratio = large.fetch(stage) / [small.fetch(stage), FLOOR_SECONDS].max
      assert_operator ratio, :<, MAX_TIME_RATIO,
                      "#{stage} is declared O(Δ) but its time followed the source: #{format('%.1f', ratio)}x " \
                      "across a #{SIZE_RATIO}x size step under the same delta " \
                      "(small #{small.fetch(stage).round(4)}s, large #{large.fetch(stage).round(4)}s)"
    end
  end

  # The instrument's control: the whole-source postings read the delta
  # grain retired, timed the same way, DOES follow the source.
  def test_the_instrument_detects_an_o_source_stage
    timings = %w[small large].to_h do |slug|
      source_id = @catalog[:sources].where(slug: slug).get(:id)
      [slug, best_of { Indexer.source_char_postings(@catalog, source_id) }]
    end
    ratio = timings.fetch("large") / [timings.fetch("small"), FLOOR_SECONDS].max

    assert_operator ratio, :>=, MAX_TIME_RATIO,
                    "an O(source) read must trip the line at these sizes (#{format('%.1f', ratio)}x)"
  end

  private

  def seed_source(slug, rows)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: "urn:d:#{slug}", title: "t", language: "grc",
                                       content_sha256: "x", revision: 1, withdrawn: false)
    @catalog[:passages].multi_insert((0...rows).map { |seq| passage_row(doc, seq) })
    doc
  end

  def passage_row(doc, seq)
    urn = "#{doc.urn}:#{seq}"
    text = "λογοσ αρετη #{seq} 天地"
    { document_id: doc.id, urn: urn, sequence: seq, language: "grc", text: text, text_normalized: text,
      content_sha256: Digest::SHA256.hexdigest(urn), revision: 1, withdrawn: false, annotations_json: "{}" }
  end

  # TRIALS identical deltas (DELTA_ADDS new rows + DELTA_WITHDRAWALS
  # withdrawn ones) through the real refresh, the stage ledger recording;
  # { stage => fastest seconds }.
  def measure(slug)
    doc = @docs.fetch(slug)
    best = {}
    TRIALS.times do
      run_delta(slug, doc)
      Classes.delta_stages.each do |stage|
        last = Nabu::Store::StageTimings.last(@ledger, kind: "sync", scope: slug, stage: stage)
        best[stage] = [best[stage], last[:seconds]].compact.min if last
      end
    end
    best
  end

  def run_delta(slug, doc)
    delta = Nabu::Store::IndexDelta.new
    next_seq = @catalog[:passages].where(document_id: doc.id).max(:sequence) + 1
    DELTA_ADDS.times do |offset|
      row = passage_row(doc, next_seq + offset)
      delta.upsert(@catalog[:passages].insert(row), row[:urn])
    end
    @catalog[:passages].where(document_id: doc.id, withdrawn: false).order(:id).limit(DELTA_WITHDRAWALS)
                       .select_map(%i[id urn]).each do |id, urn|
      @catalog[:passages].where(id: id).update(withdrawn: true)
      delta.remove(id, urn)
    end
    Indexer.refresh_source!(catalog: @catalog, fulltext: @fulltext, slug: slug, delta: delta, ledger: @ledger)
  end

  def best_of
    Array.new(TRIALS) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end.min
  end
end
