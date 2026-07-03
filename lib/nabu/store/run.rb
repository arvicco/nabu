# frozen_string_literal: true

module Nabu
  module Store
    # One sync run with its Fetch/Load counts (architecture §8). Read by
    # `nabu status`.
    class Run < Sequel::Model(:runs)
      many_to_one :source, class: "Nabu::Store::Source", key: :source_id
    end
  end
end
