# frozen_string_literal: true

require "test_helper"
require_relative "support/legacy_name_scan"

# Nabu::PlaceMine (P96-3 — Q9 v0, the Han lane): gazetteer name keys
# mined against passage text into place-candidate edges, with every
# precision rule censused: the single-char floor, the ambiguity cap,
# the derived stop rule, the hand stop list, and the non-Han filter.
class PlaceMineTest < Minitest::Test
  include StoreTestDB

  Place = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    derive_gazetteer
    seed_passages
  end

  def teardown
    @journal.disconnect
  end

  # A tiny real-shaped gazetteer slice: 霸州 (the chgis fixture's own
  # first row), an ambiguous name resolving to four places, a
  # single-char name, and a Latin-script name.
  def derive_gazetteer
    Nabu::Store::PlaceIndex.derive!(@catalog, gazetteer: "chgis", places: derive_places,
                                              names_for: :name_keys.to_proc)
  end

  def derive_places
    [
      Place.new(id: "hvd_1", title: "霸州", lat: 39.1, lon: 116.4,
                place_types: ["zhou"], time_periods: ["1820"], name_keys: ["霸州", "ba zhou"]),
      Place.new(id: "hvd_2", title: "順天府", lat: 39.9, lon: 116.4,
                place_types: ["fu"], time_periods: ["1820"], name_keys: ["順天府"]),
      Place.new(id: "amb1", title: "新州一", lat: 1, lon: 1, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb2", title: "新州二", lat: 2, lon: 2, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb3", title: "新州三", lat: 3, lon: 3, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "amb4", title: "新州四", lat: 4, lon: 4, place_types: [], time_periods: [],
                name_keys: ["新州"]),
      Place.new(id: "hvd_9", title: "東", lat: 5, lon: 5, place_types: [], time_periods: [],
                name_keys: ["東"])
    ]
  end

  def seed_passages
    @source = Nabu::Store::Source.create(slug: "kanripo", name: "Kanripo",
                                         adapter_class: "X", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:d1",
                                       language: "lzh", title: "t", canonical_path: "x",
                                       content_sha256: "0" * 64)
    [
      ["urn:nabu:kanripo:d1:1", "臣至霸州見順天府尹"], # both real places
      ["urn:nabu:kanripo:d1:2", "霸州之地新州之民"],         # real + ambiguous
      ["urn:nabu:kanripo:d1:3", "無關之文東行而已"]          # only the single-char name
    ].each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: urn, language: "lzh",
                                  text: text, text_normalized: text,
                                  content_sha256: i.to_s * 64, sequence: i, revision: 1)
    end
  end

  def miner(stop_names: [], allow_names: [])
    Nabu::PlaceMine.new(catalog: @catalog, journal: @journal, gazetteer: "chgis",
                        stop_names: stop_names, allow_names: allow_names)
  end

  def test_census_counts_hits_and_applies_the_precision_rules
    report = miner.census(source: "kanripo")
    assert_equal 3, report.passages
    assert_operator report.seconds, :>, 0, "summary reporting carries elapsed time (owner rule 2026-09-11)"
    hits = report.name_hits.to_h
    assert_equal 2, hits["霸州"], "substring attestation, once per passage"
    assert_equal 1, hits["順天府"]
    refute hits.key?("新州"), "four homonym targets exceed the ambiguity cap"
    assert_equal 1, report.names_ambiguous
    refute hits.key?("東"), "single-character names never match (the floor)"
    assert_operator report.names_non_han, :>=, 1, "the pinyin key is filtered and censused"
  end

  def test_apply_writes_candidate_edges_with_the_mined_name_riding_detail
    result = miner.apply!(source: "kanripo")
    assert_equal 3, result.edges_written, "霸州 ×2 passages + 順天府 ×1"
    assert_operator result.seconds, :>=, result.census.seconds,
                    "apply elapsed covers both passes (owner rule 2026-09-11)"
    edge = @journal[:links].first(to_urn: "urn:nabu:place:chgis:hvd_2")
    assert_equal "place-candidate", edge[:kind]
    assert_equal "urn:nabu:kanripo:d1:1", edge[:from_urn]
    assert_includes edge[:detail], "順天府"
  end

  def test_hand_stop_names_exclude_and_reruns_supersede
    first = miner(stop_names: ["霸州"]).apply!(source: "kanripo")
    assert_equal 1, first.edges_written, "the hand-stopped name mines nothing"

    second = miner.apply!(source: "kanripo")
    assert_equal 1, second.superseded_runs
    assert_equal 3, @journal[:links].count, "reruns supersede, never accrete"
  end

  # Pass 2 must exclude DERIVED stops from the scan itself — the first
  # real kanripo apply crashed here (KeyError on 「君子」, 2026-09-10):
  # apply! narrowed the name hash after the census but kept scanning
  # with buckets built from the full name set.
  def test_apply_survives_derived_stops_excluding_them_from_the_scan
    gate = Place.new(id: "hvd_gate", title: "東門", lat: 6, lon: 6, place_types: [],
                     time_periods: [], name_keys: ["東門"])
    Nabu::Store::PlaceIndex.derive!(@catalog, gazetteer: "chgis",
                                              places: derive_places + [gate],
                                              names_for: :name_keys.to_proc)
    doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:d2",
                                       language: "lzh", title: "t2", canonical_path: "y",
                                       content_sha256: "f" * 64)
    22.times do |i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:kanripo:d2:#{i}",
                                  language: "lzh", text: "出東門而去",
                                  text_normalized: "出東門而去",
                                  content_sha256: format("%064x", 1000 + i),
                                  sequence: i, revision: 1)
    end

    result = miner.apply!(source: "kanripo")

    assert_includes result.census.names_stopped.map(&:first), "東門",
                    "22 hits over 25 passages exceeds the stop ceiling of 20"
    assert_equal 3, result.edges_written, "the derived-stopped name mines nothing"
    refute @journal[:links].where(Sequel.like(:to_urn, "%hvd_gate")).any?
  end

  # The ceiling allow-list (owner-ruled 2026-09-18 — the 吐蕃/Tibet
  # case): a RULED genuinely-geographic name may exceed the derived
  # frequency ceiling and still mine. Allow exempts ONLY the derived
  # stop — the floor, the ambiguity cap and the hand stop list still
  # apply; the census reports the exemption instead of the stop.
  def test_allow_names_exempt_a_ruled_name_from_the_derived_ceiling
    gate = Place.new(id: "hvd_gate", title: "東門", lat: 6, lon: 6, place_types: [],
                     time_periods: [], name_keys: ["東門"])
    Nabu::Store::PlaceIndex.derive!(@catalog, gazetteer: "chgis",
                                              places: derive_places + [gate],
                                              names_for: :name_keys.to_proc)
    doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:d3",
                                       language: "lzh", title: "t3", canonical_path: "z",
                                       content_sha256: "e" * 64)
    22.times do |i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:kanripo:d3:#{i}",
                                  language: "lzh", text: "出東門而去",
                                  text_normalized: "出東門而去",
                                  content_sha256: format("%064x", 2000 + i),
                                  sequence: i, revision: 1)
    end

    result = miner(allow_names: ["東門"]).apply!(source: "kanripo")

    refute_includes result.census.names_stopped.map(&:first), "東門",
                    "an allowed name never enters the derived stop set"
    assert_includes result.census.names_allowed.map(&:first), "東門",
                    "the exemption is censused, never silent"
    assert_equal 22, @journal[:links].where(Sequel.like(:to_urn, "%hvd_gate")).count,
                 "the allowed name mines despite exceeding the ceiling"
  end

  def test_allow_does_not_override_the_hand_stop_list
    result = miner(stop_names: ["霸州"], allow_names: ["霸州"]).apply!(source: "kanripo")
    assert_equal 1, result.edges_written,
                 "allow exempts the ceiling only — a hand stop still wins"
  end

  # THE EQUIVALENCE PIN for the single-pass / automaton / id-window /
  # bulk-write miner: over a corpus built to hit every tricky shape —
  # overlapping and prefix-sharing names, two names of ONE place in one
  # passage (the later name's detail must survive, the pair refreshed not
  # duplicated), a derived stop, a hand stop, another source's passages
  # interleaved in the id range, withdrawn passages and documents, and
  # windows small enough to split the range many times — the journal rows
  # (ids included) and the census equal what the replaced two-pass
  # bucket-scan miner (reimplemented verbatim below) leaves behind.
  def test_apply_is_equivalent_to_the_legacy_two_pass_miner
    seed_equivalence_corpus
    [1, 2, 3, 7, 1_000].each do |window|
      legacy = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      fresh = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
      expected = legacy_apply(legacy, stop_names: ["西州"])
      result = Nabu::PlaceMine.new(catalog: @catalog, journal: fresh, gazetteer: "chgis",
                                   stop_names: ["西州"], allow_names: [], window: window)
                              .apply!(source: "kanripo")

      assert_equal expected[:rows], journal_rows(fresh), "window #{window}: journal rows differ"
      assert_equal expected[:counts], [result.edges_written, result.edges_refreshed], "window #{window}"
      assert_equal expected[:passages], result.census.passages
      assert_equal expected[:tally], result.census.name_hits
      assert_operator expected[:counts][1], :>, 0, "the corpus exercises the same-place refresh"
      assert_includes result.census.names_stopped.map(&:first), "東門", "the corpus exercises a derived stop"
    ensure
      [legacy, fresh].compact.each(&:disconnect)
    end
  end

  def seed_equivalence_corpus
    extra = [
      Place.new(id: "hvd_1", title: "霸州", lat: 39.1, lon: 116.4, place_types: [], time_periods: [],
                name_keys: ["霸州", "霸州城", "ba zhou"]),
      Place.new(id: "hvd_gate", title: "東門", lat: 6, lon: 6, place_types: [], time_periods: [],
                name_keys: ["東門"]),
      Place.new(id: "w1", title: "西州", lat: 7, lon: 7, place_types: [], time_periods: [], name_keys: ["西州"]),
      Place.new(id: "c1", title: "州城", lat: 8, lon: 8, place_types: [], time_periods: [], name_keys: ["州城"]),
      Place.new(id: "c2", title: "城門", lat: 9, lon: 9, place_types: [], time_periods: [], name_keys: ["城門"]),
      Place.new(id: "f1", title: "天府", lat: 9, lon: 9, place_types: [], time_periods: [], name_keys: ["天府"])
    ]
    places = derive_places.reject { |place| place.id == "hvd_1" } + extra
    Nabu::Store::PlaceIndex.derive!(@catalog, gazetteer: "chgis", places: places, names_for: :name_keys.to_proc)
    other = Nabu::Store::Source.create(slug: "other", name: "Other", adapter_class: "X",
                                       license_class: "attribution")
    other_doc = Nabu::Store::Document.create(source_id: other.id, urn: "urn:nabu:other:d", language: "lzh",
                                             title: "o", canonical_path: "o", content_sha256: "a" * 64)
    gone_doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:gone", language: "lzh",
                                            title: "g", canonical_path: "g", content_sha256: "b" * 64,
                                            withdrawn: true)
    live_doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:kanripo:eq", language: "lzh",
                                            title: "e", canonical_path: "e", content_sha256: "c" * 64)
    texts = %w[臣至霸州城門見順天府尹東門 州城西州東門 出東門而去 順天府天府東門
               城門州東門 無關之文 東門東門]
    seq = 0
    90.times do |i|
      text = texts[i % texts.size]
      doc = case i % 6
            when 4 then other_doc
            when 5 then gone_doc
            else live_doc
            end
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:eq:#{i}", language: "lzh", text: text,
                                  text_normalized: text, content_sha256: format("%064x", 5000 + i),
                                  sequence: seq += 1, revision: 1, withdrawn: (i % 9 == 8))
    end
  end

  def journal_rows(journal)
    journal[:links].order(:id).select(:id, :from_urn, :to_urn, :kind, :score, :detail, :chunk).all
  end

  # The replaced miner, verbatim in behaviour: pass 1 bucket-scans every
  # passage (keyset pages ordered by id) and tallies; pass 2 rebuilds the
  # buckets over the surviving names, rescans, and writes edge by edge.
  def legacy_apply(journal, stop_names:)
    probe = Nabu::PlaceMine.new(catalog: @catalog, journal: journal, gazetteer: "chgis",
                                stop_names: stop_names, allow_names: [])
    names = probe.send(:load_names)
    rows = legacy_passages("kanripo")
    buckets = LegacyNameScan.buckets(names.keys)
    tally = Hash.new(0)
    rows.each { |row| LegacyNameScan.scan(row[:text], buckets).each { |name| tally[name] += 1 } }
    ceiling = [(rows.size * Nabu::PlaceMine::STOP_SHARE).ceil, 20].max
    stopped = tally.select { |_name, count| count > ceiling }.keys + stop_names
    survivors = names.except(*stopped)
    buckets = LegacyNameScan.buckets(survivors.keys)
    counts = [0, 0]
    run = Nabu::Store::LinksJournal.record_run!(journal, producer: "place-mine", scope: "kanripo:chgis",
                                                         params: {}, code_version: "legacy")
    rows.each do |row|
      LegacyNameScan.scan(row[:text], buckets).each do |name|
        survivors.fetch(name).each do |place_id|
          outcome = Nabu::Store::LinksJournal.write_edge!(
            journal, from_urn: row[:urn], to_urn: "urn:nabu:place:chgis:#{place_id}", kind: "place-candidate",
                     score: nil, run_id: run, detail: "mined 「#{name}」 (chgis)"
          )
          counts[outcome == :inserted ? 0 : 1] += 1
        end
      end
    end
    { rows: journal_rows(journal), counts: counts, passages: rows.size, tally: tally.sort_by { |_n, c| -c } }
  end

  def legacy_passages(source)
    @catalog[:passages]
      .join(:documents, id: Sequel[:passages][:document_id])
      .join(:sources, id: Sequel[:documents][:source_id])
      .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false,
             Sequel[:sources][:slug] => source)
      .order(Sequel[:passages][:id])
      .select(Sequel[:passages][:id].as(:pid), Sequel[:passages][:urn], Sequel[:passages][:text])
      .all
  end

  def test_candidates_never_touch_place_ref
    miner.apply!(source: "kanripo")
    refute @catalog[:document_axes].where(Sequel.like(:place_ref, "%chgis%")).any?,
           "mining is review fuel for the np: doctrine — place_ref stays untouched"
  end
end
