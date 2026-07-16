# frozen_string_literal: true

module Nabu
  module Store
    # One derived owner-note row (P24-1, migration 015) — the index over
    # canonical/local-notes/<topic>.yml, rebuilt wholesale per topic by
    # Store::NoteLoader. Temperature 1: no revisions, no provenance journal
    # (git and the topic files carry history).
    class UrnNote < Sequel::Model(:urn_notes)
    end
  end
end
