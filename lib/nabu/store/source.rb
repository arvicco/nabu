# frozen_string_literal: true

module Nabu
  module Store
    # A registered corpus source (architecture §5). No business logic here;
    # the loader (P1-4) and registry (P1-6) own behavior.
    class Source < Sequel::Model(:sources)
      one_to_many :documents, class: "Nabu::Store::Document", key: :source_id
      one_to_many :runs, class: "Nabu::Store::Run", key: :source_id
      one_to_many :source_repos, class: "Nabu::Store::SourceRepo", key: :source_id
    end
  end
end
