# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

# Nabu::LectShelfDates — the dictionary SHELF grain of date-band staging.
# A dictionary source whose shelves carry their work's own year (LEME's
# lexicon_year on every entry) stages each covered shelf through the same
# containment law as the document grain (Nabu::LectDates#infer): the
# shelf's closed year hull inside EXACTLY ONE attested banded stage of the
# bare anchor → that stage, basis rule:date-band; anything else stays the
# bare code, the reason declared in the note.
class LectShelfDatesTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
  LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")
  RULES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml")

  def setup
    @catalog = store_test_db
    @leme = @catalog[:sources].insert(slug: "leme", name: "LEME", adapter_class: "X",
                                      license_class: "attribution")
    @other = @catalog[:sources].insert(slug: "other", name: "O", adapter_class: "X", license_class: "open")
  end

  def teardown
    @catalog.disconnect
  end

  def registry
    @registry ||= Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH)
  end

  def shelf_dates(codes: %w[en], sources: %w[leme], parent_anchor_fallback: false)
    Nabu::LectShelfDates.new(rules: [
                               Nabu::LectShelfDates::Rule.new(id: "test-year", sources: sources, codes: codes,
                                                              field: "lexicon_year", note: nil,
                                                              parent_anchor_fallback: parent_anchor_fallback)
                             ])
  end

  def fallback_dates(codes: %w[en fra])
    shelf_dates(codes: codes, parent_anchor_fallback: true)
  end

  # One shelf whose entries carry +years+ (nil = an entry without the field).
  def shelf(slug, years:, language: "en", source_id: @leme, withdrawn: [])
    id = @catalog[:dictionaries].insert(source_id: source_id, slug: slug, title: slug, language: language)
    years.each_with_index do |year, n|
      annotations = year.nil? ? { "page" => "1" } : { "lexicon_year" => year, "page" => "1" }
      @catalog[:dictionary_entries].insert(
        dictionary_id: id, urn: "urn:nabu:dict:#{slug}:e#{n}", entry_id: "e#{n}", key_raw: "k",
        headword: "h", headword_folded: "h", body: "b", content_sha256: "x",
        annotations_json: JSON.generate(annotations), withdrawn: withdrawn.include?(n)
      )
    end
    id
  end

  def stagings(dates = shelf_dates)
    dates.stagings(catalog: @catalog, registry: registry)
  end

  # -- band staging by year ---------------------------------------------------

  def test_a_pre_1700_shelf_stages_early_and_a_post_1700_shelf_stages_late
    cawdrey = shelf("leme-cawdrey", years: %w[1604 1604])
    johnson = shelf("leme-johnson", years: %w[1755])
    result = stagings
    assert_equal "en:early", result.fetch(cawdrey).lect_id
    assert_equal "en:late", result.fetch(johnson).lect_id
  end

  def test_the_boundary_years_follow_the_registry_bands
    floor = shelf("leme-1500", years: %w[1500])
    last_early = shelf("leme-1699", years: %w[1699])
    edge = shelf("leme-1700", years: %w[1700])
    first_late = shelf("leme-1701", years: %w[1701])
    result = stagings
    assert_equal "en:early", result.fetch(floor).lect_id, "en:early's band opens at 1500"
    assert_equal "en:early", result.fetch(last_early).lect_id
    assert_equal "en:late", result.fetch(first_late).lect_id
    refute result.fetch(edge).staged?, "1700 sits inside both [1500,1700] and [1700,1900]"
    assert_equal :spans_bands, result.fetch(edge).reason
  end

  def test_a_year_range_is_a_closed_interval
    nominale = shelf("leme-range", years: ["1550–1600"])
    straddle = shelf("leme-straddle", years: ["1690-1710"])
    result = stagings
    assert_equal "en:early", result.fetch(nominale).lect_id
    assert_equal [1550, 1600], result.fetch(nominale).interval
    assert_equal :spans_bands, result.fetch(straddle).reason
  end

  def test_distinct_years_on_one_shelf_hull_into_one_interval
    mixed = shelf("leme-mixed", years: %w[1604 1623])
    across = shelf("leme-across", years: %w[1650 1720])
    result = stagings
    assert_equal "en:early", result.fetch(mixed).lect_id
    assert_equal [1604, 1623], result.fetch(mixed).interval
    assert_equal :spans_bands, result.fetch(across).reason
  end

  # -- honest-coarseness fallback ---------------------------------------------

  def test_no_year_and_out_of_band_years_stay_bare_with_their_reason
    undated = shelf("leme-undated", years: [nil, nil])
    early = shelf("leme-1477", years: %w[1477])
    garbled = shelf("leme-garbled", years: ["ca. 1600"])
    result = stagings
    assert_equal :undated, result.fetch(undated).reason
    assert_equal :outside_bands, result.fetch(early).reason
    assert_equal :unparsed_year, result.fetch(garbled).reason
    [undated, early, garbled].each do |id|
      refute result.fetch(id).staged?
      assert_nil result.fetch(id).lect_id
      assert_nil result.fetch(id).basis
    end
  end

  def test_entries_without_the_field_do_not_open_the_hull
    partial = shelf("leme-partial", years: ["1604", nil])
    assert_equal "en:early", stagings.fetch(partial).lect_id
  end

  def test_withdrawn_entries_carry_no_year
    revised = shelf("leme-revised", years: %w[1604 1720], withdrawn: [1])
    assert_equal "en:early", stagings.fetch(revised).lect_id
  end

  def test_only_covered_sources_and_codes_are_considered
    latin = shelf("leme-latin", years: %w[1604], language: "lat")
    elsewhere = shelf("other-en", years: %w[1604], source_id: @other)
    result = stagings
    refute result.key?(latin), "lat is not a covered code — its shelf never enters the stager"
    refute result.key?(elsewhere), "a source the rule does not name is untouched"
  end

  def test_an_already_refined_resolution_is_never_restaged
    # fsv-lexica's sv shelves resolve to sv:old at source grain
    # (lect_overrides.yml) — a shelf year must never compete with the
    # finer statement.
    assert_equal "sv:old", registry.resolve("sv", source: "fsv-lexica")
    fsv = @catalog[:sources].insert(slug: "fsv-lexica", name: "F", adapter_class: "X", license_class: "open")
    held = shelf("soederwall", years: %w[1884], language: "sv", source_id: fsv)
    result = stagings(shelf_dates(codes: %w[sv], sources: %w[fsv-lexica]))
    assert_equal :already_refined, result.fetch(held).reason
    assert_nil result.fetch(held).lect_id
  end

  def test_no_registry_means_no_staging
    shelf("leme-cawdrey", years: %w[1604])
    assert_empty shelf_dates.stagings(catalog: @catalog, registry: nil)
  end

  def test_the_dictionaries_scope_narrows_the_pass
    cawdrey = shelf("leme-cawdrey", years: %w[1604])
    johnson = shelf("leme-johnson", years: %w[1755])
    result = shelf_dates.stagings(catalog: @catalog, registry: registry,
                                  dictionaries: @catalog[:dictionaries].where(Sequel[:dictionaries][:id] => johnson))
    assert_equal [johnson], result.keys
    refute result.key?(cawdrey)
  end

  # -- the opt-in parent-anchor fallback (2026-11-09) -------------------------

  # A shelf dated below every stage of its code's own anchor reaches the
  # PARENT anchor's band — LEME's incunable English lexicons (1477–1499)
  # sit under enm [1100, 1500], not under any en stage.
  def test_the_fallback_stages_an_outside_band_shelf_onto_the_parent_anchor
    incunable = shelf("leme-1477", years: %w[1477 1499])
    result = stagings(fallback_dates)
    staging = result.fetch(incunable)
    assert_equal "enm", staging.lect_id
    assert_equal "rule:date-band", staging.basis
    assert_equal "en", staging.fallback_from
    assert_equal "dated 1477..1499 (lexicon_year) — parent-anchor fallback from en", staging.note
  end

  def test_the_fallback_is_off_by_default
    incunable = shelf("leme-1477", years: %w[1477])
    staging = stagings.fetch(incunable)
    assert_equal :outside_bands, staging.reason
    assert_nil staging.lect_id
    assert_nil staging.fallback_from
  end

  def test_a_codemapped_french_shelf_stages_its_own_band_first_and_the_parent_below_it
    cotgrave = shelf("leme-cotgrave", years: %w[1611], language: "fra")
    solleysel = shelf("leme-solleysel", years: %w[1696], language: "fra")
    palsgrave = shelf("leme-palsgrave", years: %w[1530], language: "fra")
    result = stagings(fallback_dates)
    assert_equal "fr:cls", result.fetch(cotgrave).lect_id, "a contemporary headword list stages fr's own band"
    assert_nil result.fetch(cotgrave).fallback_from, "the fallback never fires when the own anchor stages"
    assert_equal "fr:cls", result.fetch(solleysel).lect_id
    assert_equal "frm", result.fetch(palsgrave).lect_id
    assert_equal "fr", result.fetch(palsgrave).fallback_from
  end

  def test_the_fallback_only_rescues_outside_bands_never_a_straddle
    straddle = shelf("leme-straddle", years: ["1490-1510"])
    staging = stagings(fallback_dates).fetch(straddle)
    assert_equal :spans_bands, staging.reason, "a hull touching en:early is a straddle, not a reach below"
    assert_nil staging.lect_id
  end

  # Tie-break: the walk is nearest-first. 1400 sits on the shared edge of
  # frm [1400, 1600] and fro [842, 1400]; the nearer ancestor wins.
  def test_the_nearest_ancestor_whose_band_contains_the_date_wins
    edge = shelf("leme-1400", years: %w[1400], language: "fra")
    assert_equal "frm", stagings(fallback_dates).fetch(edge).lect_id
  end

  def test_the_walk_climbs_past_a_parent_whose_band_misses
    old = shelf("leme-1050", years: %w[1050])
    assert_equal "ang", stagings(fallback_dates).fetch(old).lect_id, "enm [1100, 1500] misses; ang [450, 1100] holds"
  end

  # The fallback reaches BACKWARD only: a hull above the own anchor's
  # floor is no predecessor-stage evidence (fr's chain climbs roa → lat,
  # and lat:new [1550, open] would otherwise swallow a 1950 French shelf).
  def test_a_shelf_above_the_own_anchors_floor_never_falls_back
    modern = shelf("leme-1950", years: %w[1950], language: "fra")
    staging = stagings(fallback_dates).fetch(modern)
    assert_equal :outside_bands, staging.reason
    assert_nil staging.lect_id
  end

  # The walk ends at the first ancestor carrying no attested band — the
  # end of the dated succession (fro → roa, a reconstructed family node);
  # it never crosses into another language's ladder (roa's parent lat).
  def test_the_walk_stops_at_the_first_unbanded_ancestor
    carolingian = shelf("leme-800", years: %w[800], language: "fra")
    staging = stagings(fallback_dates).fetch(carolingian)
    assert_equal :outside_bands, staging.reason, "never lat:med through roa"
    assert_nil staging.lect_id
  end

  def test_a_resolved_script_surface_rides_onto_the_parent_anchor
    raw = YAML.safe_load_file(File.join(FIXTURES, "lects.yml"))
    surfaced = Nabu::Lects.new(anchors: raw.fetch("anchors"), scripts: raw.fetch("scripts"),
                               codemap: YAML.safe_load_file(File.join(FIXTURES, "codemap.yml")).fetch("map"),
                               overrides: { "leme" => { "en" => "en~latn" } })
    incunable = shelf("leme-1477", years: %w[1477])
    staging = fallback_dates.stagings(catalog: @catalog, registry: surfaced).fetch(incunable)
    assert_equal "enm~latn", staging.lect_id
  end

  def test_the_document_grain_is_untouched_by_the_fallback
    dates = Nabu::LectDates.new(registry: registry)
    assert_equal :outside_bands, dates.infer(code: "en", source: "leme", not_before: 1477, not_after: 1477),
                 "document grain never climbs to a parent anchor"
  end

  # -- provenance stamp shape -------------------------------------------------

  def test_the_stamp_mirrors_the_document_grain
    cawdrey = shelf("leme-cawdrey", years: %w[1604])
    edge = shelf("leme-1700", years: %w[1700])
    undated = shelf("leme-undated", years: [nil])
    result = stagings
    assert_equal Nabu::LectDates::BASIS, result.fetch(cawdrey).basis
    assert_equal "rule:date-band", result.fetch(cawdrey).basis
    assert_equal "dated 1604..1604 (lexicon_year)", result.fetch(cawdrey).note
    assert_equal "bare: spans bands — dated 1700..1700 (lexicon_year)", result.fetch(edge).note
    assert_equal "bare: undated", result.fetch(undated).note
    assert_equal "test-year", result.fetch(cawdrey).rule_id
  end

  def test_staging_is_idempotent
    shelf("leme-cawdrey", years: %w[1604])
    shelf("leme-johnson", years: %w[1755])
    assert_equal stagings, stagings
  end

  # -- loading and the shipped rule -------------------------------------------

  def test_load_reads_the_dictionary_date_bands_section_with_overlay_replacement
    Dir.mktmpdir do |dir|
      project = File.join(dir, "project.yml")
      local = File.join(dir, "local.yml")
      File.write(project, <<~YAML)
        rules: []
        dictionary_date_bands:
          - id: a
            sources: [leme]
            codes: [en]
            field: lexicon_year
          - id: b
            sources: [x]
            codes: [fr]
            field: year
      YAML
      File.write(local, <<~YAML)
        dictionary_date_bands:
          - id: b
            sources: [y]
            codes: [fr]
            field: year
      YAML
      loaded = Nabu::LectShelfDates.load([project, local])
      assert_equal %w[a b], loaded.rules.map(&:id)
      assert_equal %w[y], loaded.rules.last.sources
    end
  end

  def test_load_is_nil_without_a_file_and_refuses_a_hostile_field_name
    assert_nil Nabu::LectShelfDates.load("/nonexistent/rules.yml")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "rules.yml")
      File.write(path, "dictionary_date_bands:\n  - {id: x, sources: [s], codes: [en], field: \"a') or 1\"}\n")
      assert_raises(Nabu::Error) { Nabu::LectShelfDates.load(path) }
    end
  end

  def test_the_shipped_leme_rule_stages_english_and_french_shelves_off_lexicon_year
    loaded = Nabu::LectShelfDates.load(RULES_PATH)
    rule = loaded.rules.find { |r| r.sources.include?("leme") }
    refute_nil rule, "config/lect_facet_rules.yml carries the leme shelf-year rule"
    assert_equal %w[en fra], rule.codes,
                 "the living languages' contemporary headwords only — lat stays out (classical headwords)"
    assert_equal "lexicon_year", rule.field
    assert rule.parent_anchor_fallback, "the pre-1500 en / pre-1600 fra shelves reach enm / frm"
    loaded.validate!(registry)
  end

  def test_load_reads_the_parent_anchor_fallback_opt_in_default_off
    Dir.mktmpdir do |dir|
      path = File.join(dir, "rules.yml")
      File.write(path, <<~YAML)
        dictionary_date_bands:
          - {id: on, sources: [s], codes: [en], field: year, parent_anchor_fallback: true}
          - {id: off, sources: [s], codes: [en], field: year}
      YAML
      on, off = Nabu::LectShelfDates.load(path).rules
      assert on.parent_anchor_fallback
      refute off.parent_anchor_fallback
      File.write(path, "dictionary_date_bands:\n  - {id: x, sources: [s], codes: [en], field: year, " \
                       "parent_anchor_fallback: \"yes\"}\n")
      assert_raises(Nabu::Error) { Nabu::LectShelfDates.load(path) }
    end
  end

  def test_validate_refuses_a_code_the_registry_does_not_define
    dates = shelf_dates(codes: %w[zz-not-a-code])
    assert_raises(Nabu::Error) { dates.validate!(registry) }
  end

  def test_validate_accepts_a_shelf_code_the_codemap_maps_onto_a_node
    shelf_dates(codes: %w[fra]).validate!(registry)
  end

  # -- the real upstream field, end to end ------------------------------------

  # The LEME fixture parsed through the real adapter and loader, staged by
  # the SHIPPED rule: the year the stager reads is the lexicon_year the
  # adapter puts on every entry — Aubrey's Surrey word list (1719), an
  # English shelf, stages en:late; Baldwin's Hebrew word list (1549) is an
  # hbo shelf the rule does not cover.
  def test_the_leme_fixture_stages_through_the_shipped_rule
    source = Nabu::Store::Source[@leme]
    Nabu::Store::DictionaryLoader.new(db: @catalog, source: source)
                                 .load_from(Nabu::Adapters::Leme.new, workdir: Nabu::TestSupport.fixtures("leme"))
    result = Nabu::LectShelfDates.load(RULES_PATH).stagings(catalog: @catalog, registry: registry)
    by_slug = result.values.to_h do |staging|
      [@catalog[:dictionaries].where(id: staging.dictionary_id).get(:slug), staging]
    end
    aubrey = by_slug.fetch("leme-124555")
    assert_equal "en:late", aubrey.lect_id
    assert_equal "dated 1719..1719 (lexicon_year)", aubrey.note
    assert_equal "hbo", @catalog[:dictionaries].where(slug: "leme-102611").get(:language)
    refute by_slug.key?("leme-102611")
  end
end
