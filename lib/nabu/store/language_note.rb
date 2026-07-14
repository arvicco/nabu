# frozen_string_literal: true

module Nabu
  module Store
    # One accumulated per-language note in the history LEDGER (P18-4, ledger
    # migration 004): curated context, family lines, name overrides, future
    # accretions. Append-only — supersession is a newer row for the same
    # (lang_code, kind); the read side (Nabu::Languages) takes the latest.
    # No business logic here.
    class LanguageNote < Sequel::Model(:language_notes)
    end
  end
end
