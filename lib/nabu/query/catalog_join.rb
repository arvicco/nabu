# frozen_string_literal: true

require_relative "place_filter"

module Nabu
  module Query
    # The catalog half every index-backed query shares (P4-2's Search, P7-5's
    # LemmaSearch): index hits carry passage_ids; the display text, language,
    # title, and effective license live in the catalog, in a SEPARATE SQLite
    # file. One module so the two-level visibility rule and the license
    # semantics can never drift apart between query classes.
    #
    # == Two-step id join, not ATTACH
    #
    # A cross-database JOIN would need ATTACH. Instead the caller takes its
    # index hits' passage_ids and looks them up here with an ordinary Sequel
    # dataset — no raw SQL, no ATTACH, and the catalog join is needed anyway
    # for language/license/withdrawn filtering and the pristine text.
    #
    # == License filter semantics (v1)
    #
    # `license: "open"` means EXACTLY the open class — not "at least as open
    # as". A permissiveness ordering ("open ⊇ attribution ⊇ …") is
    # deliberately out of scope for v1; exact-match is predictable and easy to
    # reason about. The effective class is the document's license_override
    # when present, else the source's license_class (the P1-3 override column).
    #
    # Expects the including class to hold the catalog handle in @catalog.
    module CatalogJoin
      # The exhausted-inner-window honesty hint (P35-6, dev-loop §6b — this
      # lie bit twice at the P34 gate): every index-backed page is filled
      # from a bounded inner window (limit × INNER_LIMIT_FACTOR index hits)
      # that the catalog join then thins. When the window came back FULL and
      # a catalog-side filter was active and the page still came back short,
      # matches may exist beyond the window — the surface must say so
      # instead of serving a clean-looking short (or empty) page. One house
      # line, shared verbatim by every surface, CLI and MCP alike.
      INCOMPLETE_PAGE_HINT = "page may be incomplete under these filters — raise --limit to search deeper"

      # nil, or INCOMPLETE_PAGE_HINT after a #run whose page may be missing
      # matches beyond the inner window. Reset on every run.
      attr_reader :incomplete_hint

      private

      # Record the completeness verdict for the page a run just filled (the
      # class-note condition: full inner window AND active catalog filters
      # AND a short page).
      def note_page_completeness(window_exhausted:, filters_active:, page_size:, limit:)
        @incomplete_hint = window_exhausted && filters_active && page_size < limit ? INCOMPLETE_PAGE_HINT : nil
      end

      # Look the index hits' passage_ids up in the catalog, applying the
      # two-level visibility rule (neither passage nor its document withdrawn)
      # plus the optional language and license filters. No ordering: the
      # caller restores its own index order. +from+/+to+/+place+ (P15-2) add the
      # document-grained timeline filter; +facets+ (P17-2) the
      # document-grained facet filter ({facet name => pattern}); +source+
      # (P22-1) scopes to one source slug.
      def catalog_rows(passage_ids, lang:, license:, from: nil, to: nil, place: nil, facets: nil, source: nil,
                       sources: nil, loans: nil, meter: nil, meter_pattern: nil, lect_pairs: nil,
                       lect_target: nil, script: nil)
        visible_passages(lang: lang, license: license, from: from, to: to, place: place,
                         facets: facets, source: source, sources: sources, loans: loans,
                         meter: meter, meter_pattern: meter_pattern, lect_pairs: lect_pairs,
                         lect_target: lect_target, script: script)
          .where(Sequel[:passages][:id] => passage_ids)
          .select(*catalog_columns).all
      end

      # The passages/documents/sources join with the two-level visibility rule
      # (neither passage nor its document withdrawn) and the optional
      # language/license filters — unordered, unselected, so callers add their
      # own scoping (Random's source filter + ORDER BY RANDOM(), a caller's
      # id join). One place for the visibility rule so it can never drift.
      #
      # +from+/+to+/+place+ (P15-2, the timeline) filter on the
      # document's document_axes rows — a single correlated EXISTS, so a
      # document with several timeline rows (a chronicle's annals, Part 2) never
      # multiplies passage rows. A document with NO timeline row is undated and
      # falls out under any active date/place filter (an absence, never an
      # error). +source+ (P22-1, `--source SLUG`) filters on the already-joined
      # sources row — validated CLI-side, so an unknown slug never reaches here
      # as a silent empty result. +sources+ (P37-8, `--axis`) is the multi-source
      # generalization of +source+: a research axis expands to its member slugs
      # and filters on `slug IN (...)` — an ordinary catalog-side conjunct, so it
      # composes with every search path exactly as the single-slug filter does
      # (and, being catalog-side, arms the inner-window honesty hint). An empty
      # list is treated as no filter (never a silent `IN ()`); it AND-composes
      # with +source+ when both are given. +lect_pairs+ (P57-4, Query::Search's
      # `--lect` filter) is a precomputed array of [language, source slug]
      # pairs ALREADY resolved through Nabu::Lects — this module stays
      # DB-only and never touches the resolver itself; an empty array is a
      # legal "matches nothing" (never a silent no-op — unlike +sources+,
      # which treats [] as "no filter").
      # +lect_target+ (P58-4) is the materialized-facet successor to
      # +lect_pairs+: the raw --lect id, filtered as (a lect facet row under
      # the target) OR (the bare stored code matches AND no facet row) — the
      # LectFacets invariant "no row means identity" makes the two branches
      # exhaustive, and per-DOCUMENT journal rulings ride branch one, which
      # (language, source) pairs cannot express. Search picks the path:
      # facet rows present -> lect_target, none -> the legacy pairs.
      def visible_passages(lang:, license:, from: nil, to: nil, place: nil, facets: nil, source: nil,
                           sources: nil, loans: nil, meter: nil, meter_pattern: nil, lect_pairs: nil,
                           lect_target: nil, script: nil)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:sources][:slug] => source) if source
        dataset = dataset.where(Sequel[:sources][:slug] => sources) if sources && !sources.empty?
        dataset = dataset.where(Sequel[:passages][:language] => Nabu::Languages.code_variants(lang)) if lang
        dataset = dataset.where(license_expr => license) if license
        dataset = dataset.where(timeline_exists(from: from, to: to, place: place)) if from || to || place
        dataset = dataset.where(script_exists(script)) if script
        (facets || {}).each { |facet, pattern| dataset = dataset.where(facet_exists(facet, pattern)) }
        dataset = dataset.where(loans_exists(loans)) if loans
        dataset = dataset.where(lect_pairs_expr(lect_pairs)) if lect_pairs
        dataset = dataset.where(lect_target_expr(lect_target)) if lect_target
        if meter || meter_pattern
          dataset = dataset.where(Sequel[:passages][:id] => meter_enrichments(meter, meter_pattern)
                                                            .select(:passage_id))
        end
        dataset
      end

      # The meter facet (P45-5, `search --meter`): passages carrying a P44-6/7
      # meter enrichment (kind="meter" — pedecerto's Latin scansions,
      # hypotactic's Greek ones) whose payload meter code / foot pattern
      # matches case-insensitively (pedecerto codes are "H"/"P", hypotactic
      # names are lowercase — one filter must reach both).
      #
      # COST, measured on the live catalog 2026-07-25 (P42 rule — justify
      # read-time work from reality): the meter layer is 65,185 rows, and a
      # full kind-scan with json_extract costs ~40ms; as an IN-subquery it is
      # computed once per page and semi-joined, so both the windowed search
      # path (≤ limit×10 candidate ids) and a term-less browse stay well
      # under the probe budget. That is why there is NO derived column and NO
      # new index: the layer is bounded by scanned verse (10⁵ rows), not by
      # the corpus (10⁷ passages) — a write-time projection would buy nothing
      # measurable and cost a migration + rebuild bookkeeping. Revisit only
      # if the meter layer ever grows corpus-shaped.
      def meter_enrichments(meter, pattern)
        dataset = @catalog[:enrichments].where(kind: "meter")
        dataset = dataset.where(payload_field("meter") => meter.to_s.downcase) if meter
        dataset = dataset.where(payload_field("pattern") => pattern.to_s.downcase) if pattern
        dataset
      end

      # lower(json_extract(payload_json, '$.<key>')) — the case-insensitive
      # probe into the enrichment payload.
      def payload_field(key)
        Sequel.function(:lower, Sequel.function(:json_extract, :payload_json, "$.#{key}"))
      end

      # A correlated EXISTS over document_axes for the current document. The
      # overlap is NULL-aware (fable-reviewed): an open-ended interval (a NULL
      # bound = −∞ / +∞) must NOT silently vanish — `not_after >= from` becomes
      # `(not_after IS NULL OR not_after >= from)`, and likewise the lower bound.
      # A closed-interval overlap `nb <= to AND na >= from` (NOT naive
      # containment, which would drop every precision="low" century-range doc).
      # +place+ is a PlaceFilter::Resolution (a raw string coerces to the
      # name-LIKE lane, byte-identical pre-P75 behavior): the conjunct is
      # name-ILIKE OR identity-claims — a resolved name keeps its name
      # recall, a mint is identity-only (PlaceFilter class note).
      def timeline_exists(from:, to:, place:)
        axes = Sequel[:document_axes]
        sub = @catalog[:document_axes].where(axes[:document_id] => Sequel[:documents][:id])
        sub = sub.where(Sequel.expr(axes[:not_after] => nil) | (axes[:not_after] >= from)) if from
        sub = sub.where(Sequel.expr(axes[:not_before] => nil) | (axes[:not_before] <= to)) if to
        if (resolution = PlaceFilter.coerce(place))
          clauses = []
          clauses << Sequel.ilike(axes[:place_name], resolution.pattern) if resolution.pattern
          clauses << place_ref_claims(axes, resolution.identities) if resolution.identity?
          sub = sub.where(Sequel.|(*clauses))
        end
        sub.exists
      end

      # TRUE when the row's place_ref claims ANY of +identities+ in any
      # spelling — Nabu::PlaceRefs.ref_globs owns the spellings; the field
      # is space-padded per that contract. Same correlated, per-candidate
      # cost class as the name-ILIKE lane (no place_ref index by design —
      # the axes row fetch rides the document_id index either way).
      def place_ref_claims(axes, identities)
        padded = Sequel.join([" ", axes[:place_ref], " "])
        Sequel.|(*identities.flat_map do |namespace, id|
          Nabu::PlaceRefs.ref_globs(namespace, id).map do |glob|
            Sequel.expr(Sequel.function(:glob, glob, padded) => 1)
          end
        end)
      end

      # The script filter (P75 C-2): a document matches +code+ when its
      # resolved lect id claims the held surface's script — a ~code segment,
      # last-but-@ in the canonical order, so it ends the value or an @ortho
      # follows — OR its artifact-script axis row claims the artifact's
      # original system (the D60-b differs-only lane). Either lane answers
      # "Latin-script Gaulish"; absence from both is honest absence. +code+
      # is validated upstream (Search#script_code): bare [a-z]{4}, so the
      # LIKE interpolation carries no metacharacters.
      def script_exists(code)
        facets = Sequel[:document_facets]
        held = @catalog[:document_facets]
               .where(facets[:document_id] => Sequel[:documents][:id],
                      facets[:facet] => Store::LectFacets::FACET)
               .where(Sequel.like(facets[:value], "%~#{code}") |
                      Sequel.like(facets[:value], "%~#{code}@%"))
               .exists
        axes = Sequel[:document_axes]
        artifact = @catalog[:document_axes]
                   .where(axes[:document_id] => Sequel[:documents][:id],
                          axes[:artifact_script] => code)
                   .exists
        Sequel.|(held, artifact)
      end

      # A correlated EXISTS over document_facets for the current document
      # (P17-2, the genre facet — one EXISTS per active facet, so a document
      # carrying several facet rows never multiplies passage rows). The
      # pattern matches the normalized value OR the upstream raw code
      # case-insensitively (`--type epitaph` and `--type titsep?` both work;
      # LIKE patterns pass through, the --place semantics). A document with
      # no facet row falls out under an active filter — honest absence.
      def facet_exists(facet, pattern)
        facets = Sequel[:document_facets]
        @catalog[:document_facets]
          .where(facets[:document_id] => Sequel[:documents][:id], facets[:facet] => facet.to_s)
          .where(Sequel.ilike(facets[:value], pattern) | Sequel.ilike(facets[:raw], pattern))
          .exists
      end

      # The loans facet (P34-2, honoring P17-1's "a future --loans facet reads
      # them without reparse"): a correlated EXISTS over the passage's OWN
      # stored annotations — json_each unpacks the "loans" object ({code =>
      # token count}, the language-contact layer the Coptic Scriptorium
      # parser tallies per passage) and the code matches case-insensitively
      # (the facet house rule; verbatim upstream names like "Akkadian" stay
      # queryable as typed or folded). PASSAGE-grain, unlike the document
      # facets above, and pure query-time: no projection table, so `nabu
      # rebuild` has nothing extra to maintain — the loader's annotations_json
      # IS the facet store. The code rides as a bound value (never a JSON
      # path), so any string is safe and an unattested one is an honest empty.
      # The LIKE probe cheaply skips the JSON walk for the loan-free majority;
      # json_each on a missing/NULL path yields zero rows, never an error.
      def loans_exists(code)
        loan = Sequel[:loan]
        exists = @catalog
                 .from(Sequel.function(:json_each, Sequel[:passages][:annotations_json], "$.loans").as(:loan))
                 .where(Sequel.function(:lower, loan[:key]) => code.to_s.downcase)
                 .exists
        Sequel.like(Sequel[:passages][:annotations_json], '%"loans"%') & exists
      end

      # The OR-of-(language AND source slug) filter over +pairs+ (P57-4). An
      # empty +pairs+ is a legal, honest "matches nothing" — `id IS NULL`
      # against the passages primary key (NOT NULL), never a raised error or
      # a silently-dropped filter.
      def lect_pairs_expr(pairs)
        return { Sequel[:passages][:id] => nil } if pairs.empty?

        Sequel.|(*pairs.map do |language, slug|
          Sequel.&({ Sequel[:passages][:language] => language }, { Sequel[:sources][:slug] => slug })
        end)
      end

      # The two-branch facet filter (P58-4, class note at visible_passages).
      # Prefix semantics ride SQL: value = target, or value beginning
      # target + one axis separator (":"/"/"/"@"). Branch two applies the
      # same rule to the bare stored code — but codes never contain
      # separators, so it reduces to equality; a staged/varietied target can
      # only ever match branch one.
      def lect_target_expr(target)
        facet_rows = @catalog[:document_facets]
                     .where(document_id: Sequel[:documents][:id], facet: Store::LectFacets::FACET)
        under = Sequel.|({ value: target },
                         *%w[: / @].map { |sep| Sequel.like(:value, "#{target}#{sep}%") })
        identity = { Sequel[:documents][:language] => target }
        facet_rows.where(under).exists |
          Sequel.&(identity, ~facet_rows.exists)
      end

      # Effective license class: document override wins over source class (P1-3).
      def license_expr
        Sequel.function(:coalesce,
                        Sequel[:documents][:license_override],
                        Sequel[:sources][:license_class])
      end

      def catalog_columns
        [
          Sequel[:passages][:id].as(:passage_id),
          Sequel[:passages][:urn],
          Sequel[:passages][:language],
          Sequel[:passages][:text],
          Sequel[:documents][:title].as(:document_title),
          license_expr.as(:license_class),
          # P43-2: the source's optional credit line rides beside license_class
          # (sources is already joined) so every index-backed hit can render it.
          Sequel[:sources][:credit].as(:credit)
        ]
      end
    end
  end
end
