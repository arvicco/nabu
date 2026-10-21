# frozen_string_literal: true

require "test_helper"

# Nabu::PersonCandidates — the epigraphic person-name CANDIDATE recipe,
# mined from a source's own case-preserving passage text (no external
# list): a word qualifies when it occurs at least 3 times and at least
# 90% of its occurrences are capitalized. Candidates are NAME FORMS, never
# person records: they mint kind=person-name-candidate edges to their own
# urn namespace (urn:nabu:person-candidate:<form>), apart from the person
# index and its authorities, and every exclusion class is censused.
class PersonCandidatesTest < Minitest::Test
  include StoreTestDB

  KIND = "person-name-candidate"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    @source = Nabu::Store::Source.create(slug: "edh", name: "EDH", adapter_class: "X", license_class: "attribution")
  end

  def teardown
    @journal.disconnect
  end

  # Line-grain passages as the edh slice holds them (real EDH lines:
  # HD000001's "Dis Manibus" heading, its "Caius Iulius Cai filius
  # Optatus", HD000002's "Caius Sextius Paris" and "annis LXX").
  def seed(lines)
    doc = Nabu::Store::Document.create(source_id: @source.id, urn: "urn:nabu:edh:HD000001", language: "lat",
                                       title: "t", canonical_path: "x", content_sha256: "1" * 64)
    lines.each_with_index do |text, i|
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:nabu:edh:HD000001:#{i}", language: "lat",
                                  text: text, text_normalized: text.downcase,
                                  content_sha256: Digest::SHA256.hexdigest("#{i}#{text}"), sequence: i, revision: 1)
    end
  end

  def standard_lines
    ["Dis Manibus", "Dis Manibus", "Dis Manibus sacrum",
     "Caius Iulius Cai filius Optatus", "Caius Sextius Paris", "Caius filius", "Filius Optatus",
     "annis LXX", "annis LXX", "annis LXX",
     "שלום", "שלום", "שלום"]
  end

  def miner = Nabu::PersonCandidates.new(catalog: @catalog, journal: @journal)

  def test_the_recipe_qualifies_frequent_capitalized_words_and_censuses_every_exclusion
    seed(standard_lines)
    census = miner.census(source: "edh")
    keys = census.candidates.map(&:key)
    assert_equal 13, census.passages
    assert_equal %w[caius dis manibus], keys.sort, "≥3 occurrences, every one capitalized"
    refute_includes keys, "filius", "1 of 3 capitalized — under the 90% share"
    refute_includes keys, "optatus", "2 occurrences — under the count floor"
    refute_includes keys, "lxx", "a Roman numeral is all capitals, never a name — excluded and censused"
    refute_includes keys, "annis"
    assert_equal 1, census.excluded[:numeral]
    assert_equal 1, census.excluded[:caseless], "a caseless script carries no capitalization signal"
    caius = census.candidates.find { |c| c.key == "caius" }
    assert_equal ["Caius", 3, 1.0], [caius.surface, caius.occurrences, caius.capitalized_share]
    assert_operator census.seconds, :>, 0
  end

  def test_the_numeral_rule_takes_inscriptional_fours_but_not_words_in_numeral_letters
    seed((["IIII"] * 3) + (["DIVI"] * 3) + (["MILL"] * 3))
    census = miner.census(source: "edh")
    assert_equal %w[divi mill], census.candidates.map(&:key).sort
    assert_equal 1, census.excluded[:numeral], "IIII is the additive four the stones write"
  end

  def test_the_share_floor_is_inclusive_at_ninety_percent
    seed((["Felix"] * 9) + ["felix"] + (["Paris"] * 8) + (["paris"] * 2))
    keys = miner.census(source: "edh").candidates.map(&:key)
    assert_includes keys, "felix", "9 of 10 capitalized is exactly 90% — qualifies"
    refute_includes keys, "paris", "8 of 10 is under the share"
  end

  def test_leiden_sigla_inside_a_word_fold_out_before_counting
    seed(["C(aius) Sex[tius]", "Sextius", "Sex(tius) Paris"])
    assert_includes miner.census(source: "edh").candidates.map(&:key), "sextius",
                    "an expansion or restoration reads as the whole word it marks"
  end

  def test_apply_mints_candidate_edges_from_the_capitalized_occurrences_only
    seed((["Felix"] * 9) + ["felix"])
    result = miner.apply!(source: "edh")
    edges = @journal[:links].where(kind: KIND).order(:id).all
    assert_equal (0..8).map { |i| "urn:nabu:edh:HD000001:#{i}" }, edges.map { |e| e[:from_urn] },
                 "the lowercase occurrence (passage 9) mints no edge"
    assert_equal ["urn:nabu:person-candidate:felix"], edges.map { |e| e[:to_urn] }.uniq
    assert_equal 9, result.edges_written
    assert_equal "name candidate «Felix» — 9/10 occurrences capitalized in edh (not a person record)",
                 edges.first[:detail]
    run = @journal[:link_runs].first
    assert_equal %w[person-candidates edh], [run[:producer], run[:scope]]
  end

  def test_candidate_edges_never_enter_the_person_index_or_its_urn_space
    seed(standard_lines)
    miner.apply!(source: "edh")
    refute Nabu::Store::PersonIndex.populated?(@catalog, authority: "edh"), "candidates are not person records"
    @journal[:links].select_map(:to_urn).each do |urn|
      assert urn.start_with?("urn:nabu:person-candidate:"), urn
    end
  end

  def test_a_rerun_supersedes_and_is_idempotent
    seed(standard_lines)
    first = miner.apply!(source: "edh")
    count = @journal[:links].count
    second = miner.apply!(source: "edh")
    assert_equal count, @journal[:links].count
    assert_equal [1, first.edges_written], [second.superseded_runs, second.superseded_edges]
    assert_equal 1, @journal[:link_runs].count
  end

  def test_the_recorded_scope_replays_through_the_links_stage
    seed(standard_lines)
    Nabu::LinkScopeReplay.replay!({ "producer" => "person-candidates", "scope" => "edh", "params" => {} },
                                  db: @catalog, fulltext: nil, journal: @journal, config: nil, places: nil)
    assert_equal 3 + 3 + 3, @journal[:links].where(kind: KIND).count,
                 "Dis ×3, Manibus ×3, Caius ×3 — one edge per (passage, candidate)"
  end
end
