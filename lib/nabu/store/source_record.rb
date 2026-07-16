# frozen_string_literal: true

module Nabu
  module Store
    # One derived per-source knowledge row (migration 015, P24-0): the
    # catalog index of a canonical/local-source dossier lane — (slug, kind,
    # body, provenance), one row per (slug, kind) as the dossier currently
    # states it. Replaced wholesale per slug by Store::SourceDossierLoader
    # at every local-source sync/rebuild (and incrementally by the
    # SourceShelf accretion path); read by `nabu list` cards/census and the
    # MCP status payload. No business logic here.
    class SourceRecord < Sequel::Model(:source_records)
    end
  end
end
