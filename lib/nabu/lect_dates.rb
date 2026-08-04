# frozen_string_literal: true

module Nabu
  # Date × band inference (P58-3): the DOCUMENT grain of lect assignment for
  # dated-but-unstaged holdings (Latin epigraphy above all). A document is
  # inferable iff:
  #
  #   1. its code resolves to a BARE anchor at source grain (a source-level
  #      override or codemap stage is already the finer statement);
  #   2. its date interval is CLOSED (both bounds; min not_before /
  #      max not_after over its document_axes rows);
  #   3. the interval is CONTAINED IN EXACTLY ONE of the anchor's attested,
  #      banded stages — containment, never overlap: a date spanning two
  #      bands stays honestly bare.
  #
  # apply! compiles candidates into the lect journal (basis rule:date-band,
  # note = the dating evidence) under the same discipline as LectRules: a
  # re-run supersedes its own basis; an existing (urn, code) row always wins.
  #
  # check() is the reverse audit: journal assignments whose assigned stage
  # carries a band but whose document dates fall entirely OUTSIDE it —
  # the consistency alarm for hand rulings and rule batches alike.
  class LectDates
    BASIS = "rule:date-band"

    Candidate = Data.define(:urn, :source, :code, :lect_id, :not_before, :not_after)
    CensusReport = Data.define(:candidates, :assignable, :skipped)
    ApplyOutcome = Data.define(:assigned, :skipped)
    Finding = Data.define(:urn, :code, :lect_id, :basis, :not_before, :not_after, :band)

    # const: SQLite bound-parameter comfort for the journal bulk insert
    INSERT_BATCH = 1_000

    def initialize(registry:)
      @registry = registry
    end

    # The dry-run view. +assignable+ groups candidate counts by
    # [source, code, lect_id]; +skipped+ tallies every reason a dated
    # document did NOT qualify (open_interval, spans_bands, no_banded_stages,
    # already_refined). Undated documents never enter the census.
    def census(catalog:, source: nil, lang: nil)
      candidates = []
      skipped = Hash.new(0)
      each_dated_document(catalog, source: source, lang: lang) do |row|
        verdict = classify(row)
        if verdict.is_a?(Candidate)
          candidates << verdict
        else
          skipped[verdict] += 1
        end
      end
      assignable = candidates.group_by { |c| [c.source, c.code, c.lect_id] }
                             .transform_values(&:size)
      CensusReport.new(candidates: candidates, assignable: assignable, skipped: skipped)
    end

    # Compile the census into the journal — LectRules discipline: supersede
    # this basis, then insert every candidate whose (urn, code) is not
    # already ruled (hand rulings and facet rules always win).
    def apply!(catalog:, journal:, source: nil, lang: nil, at: Time.now)
      Store::LectJournal.supersede_basis!(journal, basis: BASIS)
      report = census(catalog: catalog, source: source, lang: lang)
      taken = journal[:lect_assignments].select_map(%i[urn code]).to_set
      fresh, held = report.candidates.partition { |c| !taken.include?([c.urn, c.code]) }
      rows = fresh.map do |c|
        { urn: c.urn, code: c.code, lect_id: c.lect_id, basis: BASIS,
          note: "dated #{c.not_before}..#{c.not_after}", created_at: at }
      end
      rows.each_slice(INSERT_BATCH) { |slice| journal[:lect_assignments].multi_insert(slice) }
      ApplyOutcome.new(assigned: fresh.size, skipped: held.size)
    end

    # The reverse audit: every journal assignment whose stage carries a band
    # and whose document interval falls entirely outside it. Bandless lects,
    # undated documents, and half-open intervals that still touch the band
    # are never findings.
    def check(catalog:, journal:)
      findings = []
      journal[:lect_assignments].each do |assignment|
        lect = @registry.lect(assignment[:lect_id])
        band = lect&.band
        next unless band && band[0] && band[1]

        bounds = document_bounds(catalog, assignment[:urn])
        next unless bounds

        not_before, not_after = bounds
        outside = (not_before && not_before > band[1]) || (not_after && not_after < band[0])
        next unless outside

        findings << Finding.new(urn: assignment[:urn], code: assignment[:code],
                                lect_id: assignment[:lect_id], basis: assignment[:basis],
                                not_before: not_before, not_after: not_after, band: band)
      end
      findings
    end

    private

    # Yields one row per dated document: urn, source slug, language, and the
    # closed-hull bounds (MIN not_before, MAX not_after over its axes rows).
    def each_dated_document(catalog, source:, lang:, &)
      scope = catalog[:documents]
              .join(:sources, id: :source_id)
              .join(:document_axes, document_id: Sequel[:documents][:id])
              .where(Sequel[:documents][:withdrawn] => false)
              .exclude(Sequel[:documents][:language] => nil)
      scope = scope.where(Sequel[:sources][:slug] => source) if source
      scope = scope.where(Sequel[:documents][:language] => lang) if lang
      scope.group(Sequel[:documents][:id])
           .select do
             [documents[:urn].as(:urn), sources[:slug].as(:slug), documents[:language].as(:language),
              min(document_axes[:not_before]).as(:not_before), max(document_axes[:not_after]).as(:not_after)]
           end
           .each(&)
    end

    def classify(row)
      resolved = @registry.resolve(row[:language], source: row[:slug])
      match = Nabu::Lects.parse_id(resolved)
      return :unresolvable unless match
      return :already_refined if match[:stage] || match[:variety] || match[:ortho]
      return :open_interval unless row[:not_before] && row[:not_after]
      # A backwards interval (the 2026-08-04 iip find) satisfies containment
      # vacuously — it is a dating defect upstream, never evidence.
      return :reversed_interval if row[:not_before] > row[:not_after]

      bands = banded_stages(match[:anchor])
      return :no_banded_stages if bands.empty?

      containing = bands.select do |stage|
        stage.band[0] <= row[:not_before] && row[:not_after] <= stage.band[1]
      end
      return :spans_bands unless containing.size == 1

      Candidate.new(urn: row[:urn], source: row[:slug], code: row[:language],
                    lect_id: containing.first.id,
                    not_before: row[:not_before], not_after: row[:not_after])
    end

    # The anchor's attested stages with closed bands — reconstructed stages
    # are never date-inference targets (a date puts an attested document in
    # an attested slice, never in a reconstruction).
    def banded_stages(anchor)
      @banded ||= {}
      @banded[anchor] ||= @registry.stages_of(anchor).select do |stage|
        stage.mode == :attested && stage.band && stage.band[0] && stage.band[1]
      end
    end

    def document_bounds(catalog, urn)
      document = catalog[:documents].first(urn: urn)
      return nil unless document

      row = catalog[:document_axes]
            .where(document_id: document[:id])
            .select { [min(:not_before).as(:not_before), max(:not_after).as(:not_after)] }
            .first
      return nil unless row && (row[:not_before] || row[:not_after])

      [row[:not_before], row[:not_after]]
    end
  end
end
