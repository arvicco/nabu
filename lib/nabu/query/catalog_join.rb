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
      # caller restores its own index order.
      def catalog_rows(passage_ids, lang:, license:)
        visible_passages(lang: lang, license: license)
          .where(Sequel[:passages][:id] => passage_ids)
          .select(*catalog_columns).all
      end

      # The passages/documents/sources join with the two-level visibility rule
      # (neither passage nor its document withdrawn) and the optional
      # language/license filters — unordered, unselected, so callers add their
      # own scoping (Random's source filter + ORDER BY RANDOM(), a caller's
      # id join). One place for the visibility rule so it can never drift.
      def visible_passages(lang:, license:)
        dataset = @catalog[:passages]
                  .join(:documents, id: Sequel[:passages][:document_id])
                  .join(:sources, id: Sequel[:documents][:source_id])
                  .where(Sequel[:passages][:withdrawn] => false,
                         Sequel[:documents][:withdrawn] => false)
        dataset = dataset.where(Sequel[:passages][:language] => lang) if lang
        dataset = dataset.where(license_expr => license) if license
        dataset
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
