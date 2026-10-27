# frozen_string_literal: true

require "test_helper"
require "json"

# Nabu::Adapters::MvpCrosswalk: the Mahāvyutpatti crosswalk — each Mvy.
# entry's Sanskrit headword and Tibetan equivalent joined, exact forms
# only, onto the DCS lexicon (san) and the 84000 glossaries (bod) as
# kind=equivalent edges. The mvp side is the REAL fixture through the real
# adapter + DictionaryLoader; the target rows are real catalog entries of
# the two shelves (copied verbatim from the live dcs-lexicon and
# e84000-glossary shelves, 2026-10-22: entry ids, IAST/script headwords and
# their stored folds) — their fixture trims carry none of the Buddhist
# vocabulary the Mvy. trim holds, so the rows are planted directly, the
# ccl_etymologies "other source" pattern.
class MvpCrosswalkTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("mvp")

  # [entry_id, IAST headword] — real dcs-lexicon rows. ananda (joyless) and
  # tāthāgata (Buddhist) share a search fold with ānanda / tathāgata but
  # are different lemmas: the precision pins.
  DCS_ROWS = [
    %w[148995 buddha], %w[148996 buddha], %w[149046 bodhisattva],
    %w[95992 tathāgata], %w[169357 tathāgata], %w[170960 tāthāgata],
    %w[58281 ānanda], %w[9905 ananda], %w[106817 sukha], %w[205178 sukham]
  ].freeze

  # [entry_id, Tibetan-script headword] — real e84000-glossary rows.
  GLOSSARY_ROWS = [
    %w[UT22084-029-001-13199 བྱང་ཆུབ་སེམས་དཔའ], %w[UT22084-040-007-2324 བྱང་ཆུབ་སེམས་དཔའ],
    %w[UT22084-062-017-246 ཀུན་དགའ་བོ]
  ].freeze

  MVP_625 = "urn:nabu:dict:mvp:625"

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    source = Nabu::Store::Source.create(slug: "mvp", name: "MVP", adapter_class: "Nabu::Adapters::Mvp",
                                        license_class: "open")
    Nabu::Store::DictionaryLoader.new(db: @catalog, source: source)
                                 .load_from(Nabu::Adapters::Mvp.new, workdir: FIXTURES)
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::Adapters::MvpCrosswalk.new(catalog: @catalog, journal: @journal)
  end

  def plant_targets!
    plant!("dcs", "dcs-lexicon", "san", DCS_ROWS)
    plant!("e84000", "e84000-glossary", "xct", GLOSSARY_ROWS)
  end

  def plant!(slug, dictionary, language, rows)
    source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "X", license_class: "open")
    shelf = Nabu::Store::Dictionary.create(source_id: source.id, slug: dictionary, title: dictionary,
                                           language: language)
    rows.each do |(id, headword)|
      Nabu::Store::DictionaryEntry.create(
        dictionary_id: shelf.id, urn: "urn:nabu:dict:#{dictionary}:#{id}", entry_id: id, key_raw: headword,
        headword: headword, headword_folded: Nabu::Normalize.search_form(headword, language: language),
        body: headword, content_sha256: id
      )
    end
  end

  def edges_from(urn) = @journal[:links].where(from_urn: urn).order(:to_urn).all

  # --- the legs --------------------------------------------------------------

  # The golden walk: Mvy. 625 bodhisattvaḥ reaches the DCS stem lemma and
  # both 84000 glossary entries rendering byang chub sems dpa', visible
  # (and resolved) through the links reader.
  def test_bodhisattva_reaches_the_dcs_lemma_and_the_84000_glossaries
    plant_targets!
    producer.run("mvp")

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(MVP_625)
    edges = result.groups.fetch("equivalent")
    assert_equal %w[urn:nabu:dict:dcs-lexicon:149046 urn:nabu:dict:e84000-glossary:UT22084-029-001-13199
                    urn:nabu:dict:e84000-glossary:UT22084-040-007-2324], edges.map(&:urn).sort
    edges.each do |edge|
      assert_equal :out, edge.direction, "the glossary entry asserts the equation"
      assert_nil edge.score, "a curated glossary equation is not a mined similarity"
      assert edge.resolved?, "both target shelves are on the catalog"
      assert_includes edge.detail, "Mvy. 625", "the provenance rides every edge"
    end
    dcs = edges_from(MVP_625).find { |row| row[:to_urn].include?("dcs-lexicon") }
    assert_equal "Mvy. 625 · san bodhisattvaḥ → bodhisattva (stem)", dcs[:detail]
    glossary = edges_from(MVP_625).find { |row| row[:to_urn].include?("e84000") }
    assert_equal "Mvy. 625 · bod byang chub sems dpa'", glossary[:detail]
  end

  def test_mints_exactly_the_exact_and_stem_matches_of_the_fixture
    plant_targets!
    result = producer.run("mvp")

    # san: buddhaḥ→buddha ×2, tathāgataḥ→tathāgata ×2, bodhisattvaḥ,
    # ānandaḥ→ānanda (stem), sukham (exact); bod: byang chub sems dpa' ×2,
    # kun dga' bo.
    assert_equal 10, result.edges_written
    assert_equal 15, result.entries
    assert_equal({ san: 5, bod: 2 }, result.matched)
    assert_equal ["equivalent"], @journal[:links].select_map(:kind).uniq
    assert_equal(["Mvy. 2347:2 · san sukham → sukham (exact)"],
                 edges_from("urn:nabu:dict:mvp:2347:2").map { |row| row[:detail] })

    run = @journal[:link_runs].first(id: result.run_id)
    assert_equal %w[mvp mvp], [run[:producer], run[:scope]]
    assert_equal({ "kind" => "equivalent" }, JSON.parse(run[:params_json]))
  end

  # The search fold strips diacritics; the lemma join must not: ānanda
  # (the disciple) never lands on ananda (joyless), tathāgata never on
  # tāthāgata.
  def test_the_sanskrit_join_is_exact_iast_not_the_search_fold
    plant_targets!
    producer.run("mvp")

    assert_equal(%w[urn:nabu:dict:dcs-lexicon:58281 urn:nabu:dict:e84000-glossary:UT22084-062-017-246],
                 edges_from("urn:nabu:dict:mvp:1040").map { |row| row[:to_urn] })
    assert_equal(%w[urn:nabu:dict:dcs-lexicon:169357 urn:nabu:dict:dcs-lexicon:95992],
                 edges_from("urn:nabu:dict:mvp:3").map { |row| row[:to_urn] })
  end

  # --- refresh mechanics -----------------------------------------------------

  def test_rerun_is_idempotent_and_supersedes_the_prior_run
    plant_targets!
    first = producer.run("mvp")
    before = @journal[:links].order(:from_urn, :to_urn).select_map(%i[from_urn to_urn kind detail])
    second = producer.run("mvp")

    assert_equal first.edges_written, second.edges_written
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal before, @journal[:links].order(:from_urn, :to_urn).select_map(%i[from_urn to_urn kind detail]),
                 "the journal holds exactly the current derivation, unchanged"
  end

  def test_absent_target_shelves_mint_nothing_and_still_record_the_run
    result = producer.run("mvp")

    assert_equal 0, result.edges_written
    assert_equal({ san: 0, bod: 0 }, result.matched)
    refute_nil result.run_id
  end

  def test_withdrawn_entries_on_either_side_contribute_nothing
    plant_targets!
    @catalog[:dictionary_entries].where(urn: MVP_625).update(withdrawn: true)
    @catalog[:dictionary_entries].where(urn: "urn:nabu:dict:dcs-lexicon:58281").update(withdrawn: true)
    producer.run("mvp")

    assert_empty edges_from(MVP_625)
    assert_equal(["urn:nabu:dict:e84000-glossary:UT22084-062-017-246"],
                 edges_from("urn:nabu:dict:mvp:1040").map { |row| row[:to_urn] })
  end

  # --- the join keys ----------------------------------------------------------

  def test_tibetan_keys_read_the_wylie_half_of_the_lane
    body = "Sanskrit: kārṣikaḥ — कार्षिकः\nTibetan: zhing pa — ཞིང་རྨོད་པ་ · ཞིང་རྨོད་པ་\nChinese: 農夫"
    assert_equal ["zhing pa"], Nabu::Adapters::MvpCrosswalk.tibetan_keys(body),
                 "upstream's Wylie and script disagree on Mvy. 3824 — the Wylie half is the key"
  end

  def test_a_script_only_lane_folds_through_the_bod_transcoder
    keys = Nabu::Adapters::MvpCrosswalk.tibetan_keys("Tibetan: བྱང་ཆུབ་སེམས་དཔའ")
    assert_equal ["byang chub sems dpa'"], keys
  end

  def test_sic_and_corr_both_contribute
    assert_equal %w[菩薩 菩提薩埵 開士], Nabu::Adapters::MvpCrosswalk.quotes("菩薩 (corr. 菩提薩埵) · 開士")
  end

  def test_sanskrit_keys_carry_their_basis
    assert_equal({ "bodhisattvaḥ" => "exact", "bodhisattva" => "stem", "bodhisattvas" => "stem" },
                 Nabu::Adapters::MvpCrosswalk.sanskrit_keys("bodhisattvaḥ"))
  end

  def test_the_adapter_declares_the_producer_on_the_shared_seam
    assert Nabu::Adapters::Mvp.reference_edges?
    built = Nabu::Adapters::Mvp.reference_producer(catalog: @catalog, journal: @journal)
    assert_instance_of Nabu::Adapters::MvpCrosswalk, built
  end
end
