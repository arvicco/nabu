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

  # -- open-ended bands (P84-3, the Q44 gap) ----------------------------------

  # The №R-42 survey's find: two Menota documents (Þiðriks supplements
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
