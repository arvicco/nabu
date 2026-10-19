# frozen_string_literal: true

require_relative "../model/dictionary_entry"

module Nabu
  module Store
    # The direction rule of the reflex table (migration 046). A row with an
    # ETYMON relation (Nabu::DictionaryReflex::ETYMON_RELATIONS — the kaikki
    # etymology templates inh/der/bor/lbor) names the OWNING entry's own
    # ancestor or donor: an UP edge, the reverse of a descendants-tree row.
    # Every descent walk — etym's reflex match and ascent, the reflex-roots
    # closure, an entry's cognate list, the reflex-chains export — scopes
    # its rows through .scope, so an UP edge never reads as a descendant
    # (an OCS entry inheriting from *bogъ must never surface as *bogъ's
    # ancestor). Rows with no relation (every descendants-tree, MW, DÉRom
    # and WOLD row) and "cognate" rows walk exactly as before.
    module ReflexDescent
      module_function

      # +dataset+ narrowed to descent rows: relation NULL or non-etymon.
      # +table+ qualifies the column for joined datasets. A catalog
      # predating migration 046 has no relation column and every row is a
      # descent row (the dataset passes through untouched — a READ surface
      # never migrates, the pre-006 precedent).
      def scope(dataset, catalog:, table: :dictionary_reflexes)
        return dataset unless relation_column?(catalog)

        column = Sequel[table][:relation]
        dataset.where(Sequel.|({ column => nil }, Sequel.~(column => Nabu::DictionaryReflex::ETYMON_RELATIONS)))
      end

      # Database#schema is cached per connection — cheap on repeated calls.
      def relation_column?(catalog)
        catalog.table_exists?(:dictionary_reflexes) &&
          catalog.schema(:dictionary_reflexes).any? { |name, _| name == :relation }
      end
    end
  end
end
