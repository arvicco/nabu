# frozen_string_literal: true

module Nabu
  module Store
    # A registered corpus source (architecture §5). No business logic here;
    # the loader (P1-4) and registry (P1-6) own behavior. Its run history and
    # repo pins live in the history ledger, keyed by slug (P7-1) — no
    # associations to them: catalog ids are re-minted on every rebuild.
    class Source < Sequel::Model(:sources)
      one_to_many :documents, class: "Nabu::Store::Document", key: :source_id
    end
  end
end
