# frozen_string_literal: true

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
      private

      # Look the index hits' passage_ids up in the catalog, applying the
      # two-level visibility rule (neither passage nor its document withdrawn)
      # plus the optional language and license filters. No ordering: the
      # caller restores its own index order. +from+/+to+/+place+ (P15-2) add the
      # document-grained timeline filter; +facets+ (P17-2) the
      # document-grained facet filter ({facet name => pattern}); +source+
      # (P22-1) scopes to one source slug.
      def catalog_rows(passage_ids, lang:, license:, from: nil, to: nil, place: nil, facets: nil, source: nil,
                       loans: nil)
        visible_passages(lang: lang, license: license, from: from, to: to, place: place,
                         facets: facets, source: source, loans: loans)
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
      # as a silent empty result.
      def visible_passages(lang:, license:, from: nil, to: nil, place: nil, facets: nil, source: nil,
                           loans: nil)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:sources][:slug] => source) if source
        dataset = dataset.where(Sequel[:passages][:language] => Nabu::Languages.code_variants(lang)) if lang
        dataset = dataset.where(license_expr => license) if license
        dataset = dataset.where(timeline_exists(from: from, to: to, place: place)) if from || to || place
        (facets || {}).each { |facet, pattern| dataset = dataset.where(facet_exists(facet, pattern)) }
        dataset = dataset.where(loans_exists(loans)) if loans
        dataset
      end

      # A correlated EXISTS over document_axes for the current document. The
      # overlap is NULL-aware (fable-reviewed): an open-ended interval (a NULL
      # bound = −∞ / +∞) must NOT silently vanish — `not_after >= from` becomes
      # `(not_after IS NULL OR not_after >= from)`, and likewise the lower bound.
      # A closed-interval overlap `nb <= to AND na >= from` (NOT naive
      # containment, which would drop every precision="low" century-range doc).
      def timeline_exists(from:, to:, place:)
        axes = Sequel[:document_axes]
        sub = @catalog[:document_axes].where(axes[:document_id] => Sequel[:documents][:id])
        sub = sub.where(Sequel.expr(axes[:not_after] => nil) | (axes[:not_after] >= from)) if from
        sub = sub.where(Sequel.expr(axes[:not_before] => nil) | (axes[:not_before] <= to)) if to
        sub = sub.where(Sequel.ilike(axes[:place_name], place)) if place
        sub.exists
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
          license_expr.as(:license_class)
        ]
      end
    end
  end
end
