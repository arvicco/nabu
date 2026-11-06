# frozen_string_literal: true

require "test_helper"

# Nabu::LectDates (P58-3) — date × band inference and the reverse audit.
# A document whose code resolves to a BARE anchor, whose date interval is
# closed, and whose interval is CONTAINED IN EXACTLY ONE attested stage
# band, is inferable into that stage (journal basis rule:date-band).
# Anything else — open interval, band-spanning, already-refined, no banded
# stages — is honestly skipped and tallied. check() is the reverse: journal
# assignments whose document dates fall outside the assigned stage's band.
class LectDatesTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
  LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")

  def registry
    @registry ||= Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH)
  end

  def dates
    @dates ||= Nabu::LectDates.new(registry: registry)
  end

  # -- census -----------------------------------------------------------------

  def test_a_closed_interval_inside_exactly_one_band_is_inferable
    with_seeded_catalog do |catalog|
      report = dates.census(catalog: catalog)
      assert_equal 1, report.assignable.fetch(["edh", "lat", "lat:late"]),
                   "urn:t:edh:late is dated 250..450 — inside lat:late [200,600] alone"
    end
  end

  def test_band_spanning_open_and_refined_documents_are_tallied_not_assigned
    with_seeded_catalog do |catalog|
      report = dates.census(catalog: catalog)
      assignable_urns = report.candidates.map(&:urn)
      refute_includes assignable_urns, "urn:t:edh:spans", "100..300 spans cla|late"
      refute_includes assignable_urns, "urn:t:edh:open", "an open interval can never be contained"
      refute_includes assignable_urns, "urn:t:papyri:koi", "papyri grc already resolves to grc:koi at source grain"
      refute_includes assignable_urns, "urn:t:edh:undated"
      assert_equal 1, report.skipped.fetch(:spans_bands)
      assert_equal 1, report.skipped.fetch(:open_interval)
      assert_equal 1, report.skipped.fetch(:already_refined)
    end
  end

  # The 2026-08-04 live-audit find (iip idum0080): a REVERSED interval
  # (not_before -36, not_after -335) satisfies the containment arithmetic
  # vacuously and slipped into arc:imp — check-dates caught it. A backwards
  # interval is a dating defect, never an inference candidate.
  def test_a_reversed_interval_is_skipped_not_inferred
    with_seeded_catalog do |catalog|
      doc = catalog[:documents].insert(
        source_id: catalog[:sources].first(slug: "edh")[:id],
        urn: "urn:t:edh:reversed", language: "lat", content_sha256: "x"
      )
      catalog[:document_axes].insert(document_id: doc, not_before: 450, not_after: 250,
                                     axis_source: "test")
      report = dates.census(catalog: catalog)
      refute_includes report.candidates.map(&:urn), "urn:t:edh:reversed"
      assert_equal 1, report.skipped.fetch(:reversed_interval)
    end
  end

  def test_source_filter_scopes_the_census
    with_seeded_catalog do |catalog|
      report = dates.census(catalog: catalog, source: "nope")
      assert_empty report.candidates
    end
  end

  # -- the interval-grain seam (shared with the dictionary shelf grain) --------

  # #infer is the classification core every grain shares: one closed
  # interval for one (code, source) answers a stage id or the skip reason.
  # The document census and the dictionary shelf stager both run through
  # it, so the containment law cannot drift between grains.
  def test_infer_answers_the_single_containing_stage
    assert_equal "lat:late", dates.infer(code: "lat", source: "edh", not_before: 250, not_after: 450)
    assert_equal "en:early", dates.infer(code: "en", source: "leme", not_before: 1604, not_after: 1604)
    assert_equal "en:late", dates.infer(code: "en", source: "leme", not_before: 1755, not_after: 1755)
  end

  def test_infer_answers_skip_reasons_for_everything_else
    assert_equal :spans_bands, dates.infer(code: "lat", source: "edh", not_before: 100, not_after: 300)
    assert_equal :spans_bands, dates.infer(code: "en", source: "leme", not_before: 1700, not_after: 1700),
                 "the shared 1700 edge lies inside BOTH closed bands — honestly bare"
    assert_equal :outside_bands, dates.infer(code: "en", source: "leme", not_before: 1477, not_after: 1477),
                 "before en:early's 1500 floor no stage contains the year"
    assert_equal :open_interval, dates.infer(code: "lat", source: "edh", not_before: 250, not_after: nil)
    assert_equal :reversed_interval, dates.infer(code: "lat", source: "edh", not_before: 450, not_after: 250)
    assert_equal :already_refined, dates.infer(code: "grc", source: "papyri-ddbdp", not_before: -100,
                                               not_after: 100)
  end

  # The document census keeps its historical tally: a date no band contains
  # still counts under spans_bands there (the CLI report and the suite's
  # census tallies predate the finer reason).
  def test_the_document_census_tallies_outside_bands_as_spans_bands
    with_seeded_catalog do |catalog|
      seed_document(catalog, slug: "edh", urn: "urn:t:edh:none", language: "en",
                             not_before: 1400, not_after: 1450)
      report = dates.census(catalog: catalog, lang: "en")
      assert_equal({ spans_bands: 1 }, report.skipped)
    end
  end

  # -- open-ended bands (P84-3) -----------------------------------------------

  # The 2026-08-24 survey's find: two Menota documents (Þiðriks supplements
  # 1600–1700, Heimskringla 2 1695–1705) sit wholly inside isl:mod's
  # [1550, null] band yet were never offered — banded_stages demanded BOTH
  # bounds, so an open-ended band was no band at all. The law:
  # [a, null] contains [x, y] iff a <= x.
  def test_an_interval_inside_an_open_ended_band_is_inferable
    with_seeded_catalog do |catalog|
      seed_document(catalog, slug: "edh", urn: "urn:t:edh:new", language: "lat",
                             not_before: 1600, not_after: 1700)
      report = dates.census(catalog: catalog)
      assert_equal 1, report.assignable.fetch(["edh", "lat", "lat:new"]),
                   "1600..1700 sits wholly inside lat:new [1550, null]"
    end
  end

  def test_an_interval_straddling_an_open_bands_start_stays_bare
    with_seeded_catalog do |catalog|
      seed_document(catalog, slug: "edh", urn: "urn:t:edh:straddle", language: "lat",
                             not_before: 1500, not_after: 1700)
      report = dates.census(catalog: catalog)
      refute_includes report.candidates.map(&:urn), "urn:t:edh:straddle",
                      "1500..1700 crosses ren|new — contained in neither"
    end
  end

  # No live registry row carries a null START today (the 2026-08-27 census:
  # lat:new and isl:mod, both [1550, null]) — but the containment law is
  # symmetric: [null, b] contains [x, y] iff y <= b.
  def test_a_null_start_band_contains_intervals_up_to_its_end
    stub_registry = Object.new.tap do |registry|
      def registry.resolve(code, source:) = code # rubocop:disable Lint/UnusedMethodArgument

      def registry.stages_of(_anchor)
        [Nabu::Lects::Record.new(id: "xx:old", anchor: "xx", stage: "old", variety: nil,
                                 script: nil, ortho: nil, name: "Old Xx", mode: :attested,
                                 ord: 10, band: [nil, 1500])]
      end
    end
    dates = Nabu::LectDates.new(registry: stub_registry)
    with_seeded_catalog do |catalog|
      seed_document(catalog, slug: "edh", urn: "urn:t:edh:xx-old", language: "xx",
                             not_before: 1200, not_after: 1400)
      seed_document(catalog, slug: "edh", urn: "urn:t:edh:xx-late", language: "xx",
                             not_before: 1400, not_after: 1600)
      report = dates.census(catalog: catalog, lang: "xx")
      assert_equal 1, report.assignable.fetch(["edh", "xx", "xx:old"]),
                   "1200..1400 sits inside [null, 1500]"
      refute_includes report.candidates.map(&:urn), "urn:t:edh:xx-late",
                      "1400..1600 overruns the closed end"
    end
  end

  # -- the script surface rides through -----------------------------------------

  # A source-grain override that claims only a SURFACE (yi~latn: PPCHY holds
  # its Yiddish romanized) leaves the stage open, so date-band inference
  # stages the text — but the row it mints must keep the surface, exactly
  # as the per-source override states it: yi:mid~latn, never a bare yi:mid
  # that silently drops the romanization claim for every dated text while
  # the undated ones keep yi~latn.
  def test_a_surface_only_override_keeps_its_script_on_the_inferred_stage
    with_seeded_catalog do |catalog|
      seed_source(catalog, "ppchy")
      seed_document(catalog, slug: "ppchy", urn: "urn:t:ppchy:mid", language: "yi",
                             not_before: 1550, not_after: 1600)
      seed_document(catalog, slug: "ppchy", urn: "urn:t:ppchy:undated", language: "yi",
                             not_before: nil, not_after: nil)
      report = dates.census(catalog: catalog, source: "ppchy")
      assert_equal([%w[urn:t:ppchy:mid yi:mid~latn]], report.candidates.map { |c| [c.urn, c.lect_id] })
      assert registry.lect("yi:mid~latn"), "the surfaced stage is a registry-valid id"
    end
  end

  # The papyri egy~latn shape: Demotic held as Latin transliteration, dated
  # inside egy:dem's band — the stage gains the surface the override states.
  def test_the_papyri_demotic_surface_survives_date_banding
    with_seeded_catalog do |catalog|
      seed_document(catalog, slug: "papyri-ddbdp", urn: "urn:t:papyri:dem", language: "egy-Egyd",
                             not_before: -200, not_after: -100)
      report = dates.census(catalog: catalog, source: "papyri-ddbdp")
      assert_equal 1, report.assignable.fetch(["papyri-ddbdp", "egy-Egyd", "egy:dem~latn"])
    end
  end

  def test_apply_writes_the_surfaced_row
    with_seeded_catalog do |catalog|
      seed_source(catalog, "ppchy")
      seed_document(catalog, slug: "ppchy", urn: "urn:t:ppchy:old", language: "yi",
                             not_before: 1300, not_after: 1400)
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      dates.apply!(catalog: catalog, journal: journal, source: "ppchy")
      assert_equal "yi:old~latn", journal[:lect_assignments].first(urn: "urn:t:ppchy:old")[:lect_id]
      journal.disconnect
    end
  end

  # -- apply! -----------------------------------------------------------------

  def test_apply_writes_date_band_rows_and_respects_existing_rulings
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      outcome = dates.apply!(catalog: catalog, journal: journal)
      assert_equal 1, outcome.assigned
      row = journal[:lect_assignments].first(urn: "urn:t:edh:late")
      assert_equal %w[lat lat:late rule:date-band], row.values_at(:code, :lect_id, :basis)
      assert_match(/250\D+450/, row[:note], "the note carries the dating evidence")

      rerun = dates.apply!(catalog: catalog, journal: journal)
      assert_equal 1, rerun.assigned, "re-run supersedes its own basis — idempotent"
      assert_equal 1, journal[:lect_assignments].count
      journal.disconnect
    end
  end

  # The wipe class, caught live 2026-10-19: a per-source apply used to
  # supersede the WHOLE inference basis, so the second source's run
  # deleted the first source's 45,869 freshly-journaled rows.
  def test_a_scoped_apply_supersedes_only_its_own_scope
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      # A prior per-source run's row for ANOTHER source, same basis:
      journal[:lect_assignments].insert(
        urn: "urn:t:other:doc", code: "lat", lect_id: "lat:late",
        basis: "rule:date-band", note: "dated 300..400", created_at: Time.now
      )
      outcome = dates.apply!(catalog: catalog, journal: journal, source: "edh")
      assert_equal 1, outcome.assigned
      assert_equal 1, journal[:lect_assignments].where(urn: "urn:t:other:doc").count,
                   "a per-source apply must never supersede another source's rows"
      assert_equal 2, journal[:lect_assignments].count
      journal.disconnect
    end
  end

  def test_apply_never_overwrites_a_hand_ruling
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:late", code: "lat",
                                                lect_id: "lat:med", basis: "owner")
      outcome = dates.apply!(catalog: catalog, journal: journal)
      assert_equal 0, outcome.assigned
      assert_equal 1, outcome.skipped
      assert_equal "lat:med", journal[:lect_assignments].first(urn: "urn:t:edh:late")[:lect_id]
      journal.disconnect
    end
  end

  # -- check: the reverse audit -----------------------------------------------

  def test_check_flags_assignments_whose_dates_fall_outside_the_band
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      # A koi claim on a document dated 500..600 — koi's band is [-300, 330].
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:spans", code: "grc",
                                                lect_id: "grc:koi", basis: "owner")
      catalog[:documents].where(urn: "urn:t:edh:spans").update(language: "grc")
      catalog[:document_axes].where(
        document_id: catalog[:documents].first(urn: "urn:t:edh:spans")[:id]
      ).update(not_before: 500, not_after: 600)
      # A consistent claim for contrast.
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:late", code: "lat",
                                                lect_id: "lat:late", basis: "owner")

      findings = dates.check(catalog: catalog, journal: journal)
      assert_equal 1, findings.size
      finding = findings.first
      assert_equal "urn:t:edh:spans", finding.urn
      assert_equal "grc:koi", finding.lect_id
      assert_equal [500, 600], [finding.not_before, finding.not_after]
      assert_equal [-300, 330], finding.band
      journal.disconnect
    end
  end

  # P84-3: the reverse audit covers open-ended bands too — a document dated
  # wholly BEFORE an open band's start is outside it, null end or not.
  def test_check_flags_dates_before_an_open_ended_bands_start
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      # lat:new is [1550, null]; urn:t:edh:late is dated 250..450 — outside.
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:late", code: "lat",
                                                lect_id: "lat:new", basis: "owner")
      findings = dates.check(catalog: catalog, journal: journal)
      assert_equal 1, findings.size
      assert_equal "lat:new", findings.first.lect_id
      assert_equal [1550, nil], findings.first.band
      journal.disconnect
    end
  end

  def test_check_ignores_bandless_and_undated_assignments
    with_seeded_catalog do |catalog|
      journal = Nabu::Store::LectJournal.connect("sqlite::memory:")
      Nabu::Store::LectJournal.migrate!(journal)
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:undated", code: "lat",
                                                lect_id: "lat:late", basis: "owner")
      Nabu::Store::LectJournal.assign!(journal, urn: "urn:t:edh:late", code: "lat",
                                                lect_id: "lat", basis: "owner") # bare anchor, no band
      assert_empty dates.check(catalog: catalog, journal: journal)
      journal.disconnect
    end
  end

  private

  def seed_source(catalog, slug)
    catalog[:sources].insert(slug: slug, name: slug, adapter_class: "X", license_class: "open")
  end

  def seed_document(catalog, slug:, urn:, language:, not_before:, not_after:)
    doc = catalog[:documents].insert(
      source_id: catalog[:sources].first(slug: slug)[:id],
      urn: urn, language: language, content_sha256: "x"
    )
    return if not_before.nil? && not_after.nil?

    catalog[:document_axes].insert(document_id: doc, not_before: not_before,
                                   not_after: not_after, axis_source: "test")
  end

  # edh (no source-grain override): one doc inside lat:late alone, one
  # spanning cla|late, one open-ended, one undated. papyri-ddbdp: a dated
  # grc doc that already resolves to grc:koi at source grain (the ratified
  # override) — never date-inferred.
  def with_seeded_catalog
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    edh = catalog[:sources].insert(slug: "edh", name: "EDH", adapter_class: "X", license_class: "attribution")
    papyri = catalog[:sources].insert(slug: "papyri-ddbdp", name: "DDbDP", adapter_class: "X",
                                      license_class: "open")
    seed = lambda do |source_id, urn, language, not_before, not_after|
      doc = catalog[:documents].insert(source_id: source_id, urn: urn, language: language,
                                       content_sha256: "x")
      unless not_before.nil? && not_after.nil?
        catalog[:document_axes].insert(document_id: doc, not_before: not_before, not_after: not_after,
                                       axis_source: "test")
      end
      doc
    end
    seed.call(edh, "urn:t:edh:late", "lat", 250, 450)
    seed.call(edh, "urn:t:edh:spans", "lat", 100, 300)
    seed.call(edh, "urn:t:edh:open", "lat", 250, nil)
    seed.call(edh, "urn:t:edh:undated", "lat", nil, nil)
    seed.call(papyri, "urn:t:papyri:koi", "grc", -100, 100)
    yield catalog
  ensure
    catalog&.disconnect
  end
end
