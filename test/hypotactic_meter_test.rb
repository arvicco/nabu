# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::HypotacticMeter (P44-6): the METER producer for the links journal — the
# Hypotactic scansion instrument over held Perseus lines. Reads the canonical
# tsv/ tree and mints ONE kind="meter" edge per line matched (by folded grc
# text, not citation) against a held passage of the mapped work, from the held
# passage urn to a meter:<name> descriptor node. Exercised against the REAL
# staged TSV (HHAphrodite, retrieved 2026-07-24) laid out as the canonical tree
# stores it, with in-memory grc passages seeded to match.
class HypotacticMeterTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("hypotactic")

  # The Homeric Hymn to Aphrodite's held Perseus grc edition (Hymn 5 =
  # tlg0013.tlg005 — see HypotacticMeter::WORK_MAP evidence).
  WORK_URN = "urn:cts:greekLit:tlg0013.tlg005.perseus-grc2"

  # Three real HHAphrodite lines, VERBATIM from the fixture, with their line
  # numbers as the passage citation. L1/L2 are dactylic hexameter; L9 is the
  # one "lyric" line and carries NO caesura (the empty-4th-column case).
  L1 = "μοῦσά μοι ἔννεπε ἔργα πολυχρύσου Ἀφροδίτης,"
  L2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε"
  L9 = "οὐ γὰρ οἱ εὔαδεν ἔργα πολυχρύσου Ἀφροδίτης,"
  L1_URN = "#{WORK_URN}:1".freeze
  L2_URN = "#{WORK_URN}:2".freeze
  L9_URN = "#{WORK_URN}:9".freeze

  def setup
    @catalog = store_test_db
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
  end

  def teardown
    @journal.disconnect
  end

  def producer
    Nabu::HypotacticMeter.new(catalog: @catalog, journal: @journal)
  end

  # --- TSV parse on the real fixture -----------------------------------------

  def test_parses_every_line_of_the_real_tsv
    parsed = producer.send(:parse_tsv, File.join(FIXTURES, "tsv", "HHAphrodite.tsv"))
    assert_equal 293, parsed.size, "the whole HHAphrodite scansion, one row per line"
    assert_equal L1, parsed.first[:text]
    assert_equal "-u u -uu -u u--- uu--", parsed.first[:scansion]
    assert_equal "dactylic hexameter", parsed.first[:meter]
    assert_equal "feminine penthemimeral", parsed.first[:caesura]
    # line 9 is the lyric line with an empty caesura column
    assert_equal "lyric", parsed[8][:meter]
    assert_equal "", parsed[8][:caesura], "the 4th column can be empty (verified against bytes)"
  end

  def test_a_malformed_row_raises_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tsv"))
      File.write(File.join(dir, "tsv", "HHAphrodite.tsv"), "onecol\tscansion\tmeter\n")
      error = assert_raises(Nabu::ParseError) { producer.run("hypotactic", workdir: dir) }
      assert_match(/4 TAB columns/, error.message)
    end
  end

  # --- fold-based matching: the HIT ------------------------------------------

  def test_matches_lines_by_folded_text_and_mints_meter_edges
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    result = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, result.files
    assert_equal 1, result.mapped_works
    assert_equal 0, result.unmapped_works
    assert_equal 3, result.matched_lines, "the three seeded lines matched by text"
    assert_equal 3, result.edges_written
    assert_equal ["meter"], @journal[:links].select_map(:kind).uniq, "the new enrichment kind"

    edge = edge_from(L1_URN)
    assert_equal "meter:dactylic-hexameter", edge[:to_urn], "the grouping descriptor node"
    assert_equal "scansion -u u -uu -u u--- uu-- · caesura feminine penthemimeral · " \
                 "Hypotactic (D. Chamberlain, hypotactic.com)", edge[:detail],
                 "scansion + caesura + the Chamberlain attribution ride the edge detail"
    assert_nil edge[:score], "an upstream scansion is not a mined similarity score"
  end

  def test_the_lyric_line_gets_its_own_meter_node_and_no_caesura
    seed_hymn!(L9_URN => L9)
    producer.run("hypotactic", workdir: FIXTURES)

    edge = edge_from(L9_URN)
    assert_equal "meter:lyric", edge[:to_urn]
    assert_equal "scansion - u u -uu -u u-uu -u-- · Hypotactic (D. Chamberlain, hypotactic.com)",
                 edge[:detail], "no caesura fragment when the line carries none"
  end

  def test_matches_are_robust_to_elision_and_punctuation_spelling
    # Perseus spells elision with U+2019 and a following space and ends the line
    # with a Greek ano teleia; the fold reduces both editions to bare letters.
    perseus_l2 = "Κύπριδος, ἥτε θεοῖσιν ἐπὶ γλυκὺν ἵμερον ὦρσε·"
    seed_hymn!(L2_URN => perseus_l2)
    result = producer.run("hypotactic", workdir: FIXTURES)
    assert_equal 1, result.matched_lines, "the differently-punctuated held line still matches"
    refute_nil edge_from(L2_URN)
  end

  # --- the MISS + honest census ----------------------------------------------

  def test_unmatched_lines_are_censused_never_forced
    seed_hymn!(L1_URN => L1) # hold only one of the 293 lines
    result = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, result.matched_lines
    assert_equal 292, result.unmatched_lines, "the 292 unheld lines are censused, not guessed"
    assert_equal 292, result.unknown_ids, "unmatched surfaces in the generic sync tail"
    assert_equal 1, @journal[:links].count
  end

  def test_a_mapped_work_with_no_held_passages_censuses_all_lines
    # WORK_MAP knows HHAphrodite → tlg0013.tlg005, but nothing is held.
    result = producer.run("hypotactic", workdir: FIXTURES)
    assert_equal 1, result.mapped_works
    assert_equal 0, result.unmapped_works
    assert_equal 0, result.matched_lines
    assert_equal 293, result.unmatched_lines
    assert_equal 0, @journal[:links].count
  end

  def test_an_unmapped_tsv_is_censused_as_an_unmapped_work
    seed_hymn!(L1_URN => L1)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "tsv"))
      # a file whose stem is NOT in WORK_MAP — two valid 4-column lines
      File.write(File.join(dir, "tsv", "HHDionysus.tsv"),
                 "τάδε\t-u\tdactylic hexameter\t\nκαί\t-u\tlyric\t\n")
      result = producer.run("hypotactic", workdir: dir)
      assert_equal 0, result.mapped_works
      assert_equal 1, result.unmapped_works, "no WORK_MAP entry → an unmapped work, censused"
      assert_equal 2, result.unmatched_lines
      assert_equal 0, @journal[:links].count, "an unmapped work mints nothing — never guessed"
    end
  end

  # --- the consumer: meter surfaces in show's footer + nabu links ------------

  def test_meter_edge_surfaces_in_the_show_linked_footer
    seed_hymn!(L1_URN => L1)
    producer.run("hypotactic", workdir: FIXTURES)

    counts = Nabu::Store::LinksJournal.kind_counts(@journal, L1_URN)
    assert_equal({ "meter" => 1 }, counts, "`show`'s linked footer counts it: 'linked: 1 meter'")
    assert_empty Nabu::Store::LinksJournal.kind_counts(@journal, L2_URN),
                 "a line with no meter edge shows nothing — zero-signal silence"
  end

  def test_meter_lists_cleanly_in_nabu_links
    seed_hymn!(L1_URN => L1)
    producer.run("hypotactic", workdir: FIXTURES)

    result = Nabu::Query::Links.new(catalog: @catalog, journal: @journal).run(L1_URN)
    refute_nil result
    edges = result.groups.fetch("meter")
    assert_equal "meter:dactylic-hexameter", edges.first.urn
    assert_includes edges.first.detail, "-u u -uu -u u--- uu--", "the scansion is on the edge"
    refute edges.first.resolved?, "a meter descriptor node is honestly '(not in catalog)'"
  end

  # --- run mechanics: idempotency, supersede-scoped, rebuild-equivalence -----

  def test_rerun_supersedes_and_is_idempotent
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    first = producer.run("hypotactic", workdir: FIXTURES)
    second = producer.run("hypotactic", workdir: FIXTURES)

    assert_equal first.matched_lines, second.matched_lines
    assert_equal 1, second.superseded_runs
    assert_equal first.edges_written, second.superseded_edges
    assert_equal 3, @journal[:links].count, "the journal holds exactly the current meter graph"
    run = @journal[:link_runs].first(id: second.run_id)
    assert_equal "hypotactic", run[:producer]
    assert_equal "hypotactic", run[:scope]
  end

  def test_supersede_is_scoped_to_this_producer
    seed_hymn!(L1_URN => L1)
    foreign = Nabu::Store::LinksJournal.record_run!(@journal, producer: "parallels", scope: "perseus",
                                                              params: {}, code_version: "test")
    Nabu::Store::LinksJournal.write_edge!(@journal, from_urn: L1_URN, to_urn: L2_URN,
                                                    kind: "parallel", score: 0.9, run_id: foreign)
    producer.run("hypotactic", workdir: FIXTURES)
    producer.run("hypotactic", workdir: FIXTURES)

    assert_equal 1, @journal[:links].where(kind: "parallel").count,
                 "supersede is scoped to (producer=hypotactic, scope=hypotactic) — parallel untouched"
  end

  def test_rebuild_equivalence_after_dropping_the_journal
    seed_hymn!(L1_URN => L1, L2_URN => L2, L9_URN => L9)
    producer.run("hypotactic", workdir: FIXTURES)
    before = meter_edges

    @journal.disconnect
    @journal = Nabu::Store::LinksJournal.migrate!(Nabu::Store::LinksJournal.connect("sqlite::memory:"))
    producer.run("hypotactic", workdir: FIXTURES)

    assert_equal before, meter_edges, "identical edges re-derived from canonical tsv + catalog"
  end

  def test_a_workdir_without_the_tree_is_a_no_op_that_supersedes_nothing
    seed_hymn!(L1_URN => L1)
    producer.run("hypotactic", workdir: FIXTURES)
    count = @journal[:links].count
    Dir.mktmpdir do |empty|
      result = producer.run("hypotactic", workdir: empty)
      assert_equal 0, result.edges_written
      assert_equal 0, result.superseded_runs, "a parse-only sync before the fetch must not wipe edges"
      assert_nil result.run_id
    end
    assert_equal count, @journal[:links].count
  end

  private

  def edge_from(urn)
    @journal[:links].first(from_urn: urn)
  end

  def meter_edges
    @journal[:links].where(kind: "meter").select_map(%i[from_urn to_urn detail]).sort
  end

  # A held Perseus grc document with one passage per { urn => verbatim text }.
  def seed_hymn!(passages)
    source = Nabu::Store::Source.create(slug: "perseus", name: "Perseus",
                                        adapter_class: "Nabu::Adapters::Perseus", license_class: "attribution")
    doc = Nabu::Store::Document.create(source_id: source.id, urn: WORK_URN,
                                       title: "Hymn 5 To Aphrodite", language: "grc",
                                       metadata_json: "{}", content_sha256: "x", revision: 1, withdrawn: false)
    passages.each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: urn, sequence: i, language: "grc",
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end
  end
end
