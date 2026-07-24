# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # Derived per-passage payloads: lemmas, glosses, meter, etc.
    # (architecture §5/§6; CLAUDE.md "bulky derived payloads in enrichments").
    # Embeddings live in vectors.sqlite3, not here.
    #
    # == The producer write path (P44-7, the first enricher to land)
    #
    # An enrichment PRODUCER (Nabu::PedecertoScansions is the first) re-derives
    # rows from canonical + the catalog and writes them here through the two
    # dataset helpers below, exactly as the links producers write through
    # Store::LinksJournal. The rows are keyed by (kind, model): +kind+ names the
    # enrichment layer ("meter") and +model+ names the PRODUCER that minted it
    # ("pedecerto"), so a rerun/rebuild supersedes only its own rows, and a
    # future second meter producer (hypotactic) coexists under the same kind
    # with a different model. The helpers take the db explicitly (the Show
    # doctrine — never depend on whichever db the global model is bound to),
    # so the same code serves the SyncRunner catalog and a rebuild's fresh one.
    class Enrichment < Sequel::Model(:enrichments)
      many_to_one :passage, class: "Nabu::Store::Passage", key: :passage_id

      # Delete every row a (kind, model) producer previously wrote — the
      # supersede step of an idempotent rerun. Returns the count removed.
      def self.supersede!(db, kind:, model:)
        db[:enrichments].where(kind: kind, model: model).delete
      end

      # Write one enrichment row for +passage_id+. +payload+ is JSON-encoded.
      # +model_version+ carries the producer's code-version stamp (the links
      # journal's code_version analogue) for provenance.
      def self.write!(db, passage_id:, kind:, model:, model_version:, payload:, at: Time.now)
        db[:enrichments].insert(
          passage_id: passage_id, kind: kind, model: model,
          model_version: model_version, payload_json: JSON.generate(payload), at: at
        )
      end
    end
  end
end
