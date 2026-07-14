# frozen_string_literal: true

module Nabu
  module Store
    # One derived per-language knowledge row (migration 014, P19-1): the
    # catalog index of a canonical/local-language dossier lane — (lang_code,
    # kind, body, source), one row per (code, kind) as the dossier currently
    # states it. Replaced wholesale per code by Store::LanguageDossierLoader
    # at every local-language sync/rebuild (and incrementally by the
    # LanguageShelf accretion path); read by Nabu::Languages ahead of the
    # transitional ledger language_notes. No business logic here.
    class LanguageRecord < Sequel::Model(:language_records)
    end
  end
end
