# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LectRules (P58-2) — the facet→lect rules compiler: declarative
# owner-ratified rules (config/lect_facet_rules.yml) mapping a source's
# facet values onto lects, COMPILED into per-document journal assignments
# (basis rule:<id>) rather than resolved live. Census (dry-run) and apply
# are exercised against an in-memory catalog; the shipped rules file is
# drift-pinned against the fixture registry.
class LectRulesTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
  RULES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml")

  def registry
    @registry ||= Nabu::Lects.load(FIXTURES)
  end

  # -- value normalization ----------------------------------------------------

  def test_normalization_strips_parentheticals_and_uncertainty_markers
    assert_equal "Old Babylonian", Nabu::LectRules.normalize_value("Old Babylonian (ca. 1900-1600 BC)")
    assert_equal "Neo-Babylonian", Nabu::LectRules.normalize_value("Neo-Babylonian (ca. 626-539 BC) ?")
    assert_equal "Neo-Assyrian", Nabu::LectRules.normalize_value("Neo-Assyrian")
    assert_equal "Egyptian 0", Nabu::LectRules.normalize_value("Egyptian 0 (ca. 3300-3000 BC)")
  end

  def test_normalization_leaves_compound_values_unmatchable
    compound = Nabu::LectRules.normalize_value("ED I-II (ca. 2900-2700 BC), Old Babylonian (ca. 1900-1600 BC)")
    refute_equal "ED I-II", compound
    refute_equal "Old Babylonian", compound
  end

  # -- loading ----------------------------------------------------------------

  def test_load_is_nil_for_an_absent_file
    assert_nil Nabu::LectRules.load("/nonexistent/lect_facet_rules.yml")
  end

  def test_the_shipped_rules_file_loads_and_every_target_is_defined
    rules = Nabu::LectRules.load(RULES_PATH)
    refute_nil rules
    refute_empty rules.rules
    rules.validate!(registry) # raises on an undefined target — the drift guard
    rules.rules.each do |rule|
      assert_match(/\A[a-z0-9][a-z0-9-]*\z/, rule.id, "rule ids are journal basis slugs")
      assert_includes %w[certain approximation], rule.tier
      refute_empty rule.sources
      case rule.kind
      when "compose"
        refute_empty rule.match_prefix
        refute_empty rule.variety
        refute_empty rule.onto
      else
        refute_empty rule.map
      end
    end
  end

  def test_validate_names_the_rule_and_the_undefined_target
    rules = Nabu::LectRules.new(rules: [bad_rule])
    error = assert_raises(Nabu::Error) { rules.validate!(registry) }
    assert_match(/bad-rule/, error.message)
    assert_match(/akk:zzz/, error.message)
  end

  # -- census and apply against a seeded catalog -------------------------------

  def test_census_counts_matched_and_unmatched_values
    with_seeded_catalog do |catalog|
      report = akk_rules.census(akk_rules.find("akk-period"), catalog: catalog)
      assert_equal 2, report.matched.fetch(["Old Babylonian", "akk:ob"])
      assert_equal 1, report.matched.fetch(["Neo-Assyrian", "akk:na"])
      assert_equal({ "Middle Elamite" => 1 }, report.unmatched)
      assert_equal 3, report.assignable
    end
  end

  def test_census_ignores_other_sources_languages_and_facets
    with_seeded_catalog do |catalog|
      report = akk_rules.census(akk_rules.find("akk-period"), catalog: catalog)
      total = report.matched.values.sum + report.unmatched.values.sum
      assert_equal 4, total, "the sux row, the off-source row and the genre facet never census"
    end
  end

  def test_apply_writes_journal_rows_with_the_rule_basis_and_verbatim_note
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      outcome = akk_rules.apply!(akk_rules.find("akk-period"), catalog: catalog, journal: journal)
      assert_equal 3, outcome.assigned
      assert_equal 0, outcome.skipped
      row = journal[:lect_assignments].first(urn: "urn:t:cdli:na1")
      assert_equal %w[akk akk:na rule:akk-period], row.values_at(:code, :lect_id, :basis)
      assert_equal "Neo-Assyrian", row[:note], "the note is the verbatim facet value — the evidence"
      journal.disconnect
    end
  end

  def test_apply_never_overwrites_an_existing_assignment_and_reruns_supersede
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:cdli:ob1", code: "akk",
                                                lect_id: "akk:mb", basis: "owner", note: "hand ruling")
      rule = akk_rules.find("akk-period")

      outcome = akk_rules.apply!(rule, catalog: catalog, journal: journal)
      assert_equal 2, outcome.assigned
      assert_equal 1, outcome.skipped
      assert_equal "akk:mb", journal[:lect_assignments].first(urn: "urn:t:cdli:ob1")[:lect_id],
                   "an owner row is never overwritten by a rule"

      rerun = akk_rules.apply!(rule, catalog: catalog, journal: journal)
      assert_equal 2, rerun.assigned, "a re-run supersedes its own basis and re-mints — idempotent"
      assert_equal 3, journal[:lect_assignments].count
      journal.disconnect
    end
  end

  # -- the compose kind (P59-2: eBL akk/lit — a register onto a stage) --------

  def test_a_compose_rule_refines_onto_stage_rows_in_place
    with_compose_setup do |catalog, journal|
      outcome = compose_rules.apply!(compose_rule, catalog: catalog, journal: journal)
      assert_equal 2, outcome.assigned, "the na and nb rows compose"
      na = journal[:lect_assignments].first(urn: "urn:t:ebl:na1")
      assert_equal "akk:na/lit", na[:lect_id]
      assert_equal "rule:akk-period", na[:basis],
                   "composition refines the base rule's own row IN PLACE — its basis (and thus " \
                   "its supersede lifecycle) stays the base rule's; re-running the base rule " \
                   "un-composes, re-running compose re-refines"
      assert_match(/\+lit .rule:ebl-akk-lit./, na[:note], "the note carries the composition evidence")
      assert_equal "akk:nb/lit", journal[:lect_assignments].first(urn: "urn:t:ebl:nb1")[:lect_id]
    end
  end

  def test_a_compose_rule_never_touches_owner_rows_off_stage_rows_or_rowless_docs
    with_compose_setup do |catalog, journal|
      outcome = compose_rules.apply!(compose_rule, catalog: catalog, journal: journal)
      assert_equal "akk:nb", journal[:lect_assignments].first(urn: "urn:t:ebl:own1")[:lect_id],
                   "an owner row is a hand ruling — composition never rewrites it"
      assert_equal "akk:ob", journal[:lect_assignments].first(urn: "urn:t:ebl:ob1")[:lect_id],
                   "OB is not in the rule's onto list — the OB literary tail stays uncomposed"
      assert_nil journal[:lect_assignments].first(urn: "urn:t:ebl:bare1"),
                 "a stage-less CANONICAL doc gains nothing — there is no stage to refine"
      assert_equal 3, outcome.skipped, "owner + off-stage + rowless, all reported"
    end
  end

  def test_a_compose_rerun_is_idempotent
    with_compose_setup do |catalog, journal|
      compose_rules.apply!(compose_rule, catalog: catalog, journal: journal)
      rerun = compose_rules.apply!(compose_rule, catalog: catalog, journal: journal)
      assert_equal 0, rerun.assigned, "already-composed rows never re-compose"
      na = journal[:lect_assignments].first(urn: "urn:t:ebl:na1")
      assert_equal "akk:na/lit", na[:lect_id]
      assert_equal 1, na[:note].scan("+lit").size, "the note never accretes duplicates"
    end
  end

  def test_compose_census_buckets_by_current_journal_state
    with_compose_setup do |catalog, journal|
      report = compose_rules.census(compose_rule, catalog: catalog, journal: journal)
      assert_equal 2, report.assignable
      assert_equal 1, report.matched.fetch(["CANONICAL/Divination", "akk:na/lit"])
      assert_equal 1, report.matched.fetch(["CANONICAL", "akk:nb/lit"])
      assert_equal 3, report.unmatched.values.sum, "owner/off-stage/rowless report as unmatched"
    end
  end

  def test_compose_rule_targets_validate_against_the_registry
    bad = Nabu::LectRules.new(rules: [Nabu::LectRules::Rule.new(
      id: "bad-compose", sources: ["ebl"], code: "akk", facet: "genre",
      kind: "compose", match_prefix: "CANONICAL", variety: "zzz", onto: ["akk:na"], tier: "certain"
    )])
    error = assert_raises(Nabu::Error) { bad.validate!(registry) }
    assert_match(/bad-compose/, error.message)
    assert_match(%r{akk/zzz|akk:na/zzz}, error.message)
  end

  private

  def akk_rules
    @akk_rules ||= Nabu::LectRules.load(RULES_PATH)
  end

  def compose_rule
    compose_rules.find("ebl-akk-lit") || flunk("the shipped rules file must carry ebl-akk-lit")
  end

  def compose_rules
    @compose_rules ||= Nabu::LectRules.load(RULES_PATH)
  end

  # ebl docs: one NA-staged CANONICAL (composes), one NB-staged CANONICAL
  # (composes), one OB-staged (onto excludes it), one owner-ruled NB (hand
  # rulings untouchable), one stage-less CANONICAL, one ARCHIVAL red
  # herring (prefix never matches).
  def with_compose_setup
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    ebl = catalog[:sources].insert(slug: "ebl", name: "eBL", adapter_class: "X", license_class: "open")
    seed = lambda do |urn, value|
      doc = catalog[:documents].insert(source_id: ebl, urn: urn, language: "akk", content_sha256: "x")
      catalog[:document_facets].insert(document_id: doc, facet: "genre", value: value)
    end
    seed.call("urn:t:ebl:na1", "CANONICAL/Divination")
    seed.call("urn:t:ebl:nb1", "CANONICAL")
    seed.call("urn:t:ebl:ob1", "CANONICAL/Literature")
    seed.call("urn:t:ebl:own1", "CANONICAL/Magic")
    seed.call("urn:t:ebl:bare1", "CANONICAL")
    seed.call("urn:t:ebl:arch1", "ARCHIVAL/Letter")

    journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
    Nabu::Store::LectJournal.migrate!(journal)
    assign = lambda do |urn, lect_id, basis|
      Nabu::Store::LectJournal.assign!(journal, urn: urn, code: "akk", lect_id: lect_id,
                                                basis: basis, note: "seed")
    end
    assign.call("urn:t:ebl:na1", "akk:na", "rule:akk-period")
    assign.call("urn:t:ebl:nb1", "akk:nb", "rule:date-band")
    assign.call("urn:t:ebl:ob1", "akk:ob", "rule:akk-period")
    assign.call("urn:t:ebl:own1", "akk:nb", "owner")
    yield catalog, journal
  ensure
    journal&.disconnect
    catalog&.disconnect
  end

  def bad_rule
    Nabu::LectRules::Rule.new(id: "bad-rule", sources: ["x"], code: "akk", facet: "period",
                              map: { "Old Babylonian" => "akk:zzz" }, tier: "certain", note: nil)
  end

  # An in-memory catalog: cdli with three matching akk docs (two OB — one
  # with the parenthetical+? decoration — and one NA), one unmatchable
  # (Middle Elamite), one sux row, one genre-facet red herring, and an
  # off-source akk row that must never census.
  def with_seeded_catalog
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    cdli = catalog[:sources].insert(slug: "cdli", name: "CDLI", adapter_class: "X", license_class: "attribution")
    other = catalog[:sources].insert(slug: "other", name: "Other", adapter_class: "X", license_class: "open")
    seed = lambda do |source_id, urn, language, facet, value|
      doc = catalog[:documents].insert(source_id: source_id, urn: urn, language: language, content_sha256: "x")
      catalog[:document_facets].insert(document_id: doc, facet: facet, value: value)
    end
    seed.call(cdli, "urn:t:cdli:ob1", "akk", "period", "Old Babylonian (ca. 1900-1600 BC)")
    seed.call(cdli, "urn:t:cdli:ob2", "akk", "period", "Old Babylonian (ca. 1900-1600 BC) ?")
    seed.call(cdli, "urn:t:cdli:na1", "akk", "period", "Neo-Assyrian")
    seed.call(cdli, "urn:t:cdli:me1", "akk", "period", "Middle Elamite (ca. 1300-1000 BC)")
    seed.call(cdli, "urn:t:cdli:sux1", "sux", "period", "Ur III (ca. 2100-2000 BC)")
    seed.call(cdli, "urn:t:cdli:gen1", "akk", "genre", "Old Babylonian")
    seed.call(other, "urn:t:other:ob9", "akk", "period", "Old Babylonian")
    yield catalog
  ensure
    catalog&.disconnect
  end
end
