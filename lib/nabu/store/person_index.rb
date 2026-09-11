# frozen_string_literal: true

module Nabu
  module Store
    # The derived person index (P97-2, migration 031 — №R-62 option b):
    # a prosopography authority's persons projected into catalog tables
    # at sync time, the PlaceIndex mold exactly — keyed (authority,
    # person_id) so CBDB is one authority among future several, derived
    # wholesale per authority (delete + insert in one transaction, a
    # pure function of the canonical artifact, replayed by rebuild),
    # name keys folded in Ruby via the shared Pleiades.name_key rule
    # (Unicode case fold; Han text passes untouched, so 王安石 and
    # "wang anshi" both key).
    module PersonIndex
      TABLE = :person_index
      NAMES_TABLE = :person_index_names

      INSERT_SLICE = 2_000

      DEFAULT_AUTHORITY = "cbdb"

      Person = Data.define(:authority, :person_id, :name, :name_han,
                           :birth_year, :death_year, :index_year,
                           :dynasty, :dynasty_han, :female, :name_keys)

      module_function

      def available?(db)
        !db.nil? && db.table_exists?(TABLE)
      end

      # Populated per authority — the PlaceIndex contract: empty means
      # "not yet derived", never "the authority holds no persons".
      def populated?(db, authority: DEFAULT_AUTHORITY)
        available?(db) && !db[TABLE].where(authority: authority).empty?
      end

      def resolver(db, authority: DEFAULT_AUTHORITY)
        populated?(db, authority: authority) ? Resolver.new(db, authority: authority) : nil
      end

      # Re-derive ONE authority's slice from +persons+ (an enumerable of
      # Person). Wholesale per-authority delete + insert in one
      # transaction; returns the person count, or nil on a catalog
      # predating the tables.
      def derive!(db, persons:, authority: DEFAULT_AUTHORITY)
        return nil unless available?(db)

        count = 0
        db.transaction do
          db[NAMES_TABLE].where(authority: authority).delete
          db[TABLE].where(authority: authority).delete
          rows = []
          name_rows = []
          persons.each do |person|
            rows << { authority: authority, person_id: person.person_id,
                      name: person.name, name_han: person.name_han,
                      birth_year: person.birth_year, death_year: person.death_year,
                      index_year: person.index_year, dynasty: person.dynasty,
                      dynasty_han: person.dynasty_han, female: person.female }
            person.name_keys.uniq.each do |key|
              name_rows << { authority: authority, person_id: person.person_id, name_key: key }
            end
            count += 1
            next unless rows.size >= INSERT_SLICE

            db[TABLE].multi_insert(rows)
            db[NAMES_TABLE].multi_insert(name_rows)
            rows.clear
            name_rows.clear
          end
          db[TABLE].multi_insert(rows) unless rows.empty?
          db[NAMES_TABLE].multi_insert(name_rows) unless name_rows.empty?
        end
        count
      end

      # Reads over one authority's derived slice.
      class Resolver
        def initialize(db, authority: DEFAULT_AUTHORITY)
          @db = db
          @authority = authority
        end

        def person(id)
          row = @db[TABLE].first(authority: @authority, person_id: id.to_s)
          row && build_person(row)
        end

        # Every person matching +name+ exactly under the shared fold
        # (whole-name key equality — never fuzzy), person_id order.
        def named(name)
          @db[TABLE]
            .join(NAMES_TABLE, authority: :authority, person_id: :person_id)
            .where(Sequel[TABLE][:authority] => @authority,
                   Sequel[NAMES_TABLE][:name_key] => Nabu::Pleiades.name_key(name))
            .distinct
            .order(Sequel[TABLE][:person_id])
            .select_all(TABLE)
            .map { |row| build_person(row) }
        end

        def size
          @db[TABLE].where(authority: @authority).count
        end

        private

        def build_person(row)
          Person.new(
            authority: row[:authority], person_id: row[:person_id],
            name: row[:name], name_han: row[:name_han],
            birth_year: row[:birth_year], death_year: row[:death_year],
            index_year: row[:index_year], dynasty: row[:dynasty],
            dynasty_han: row[:dynasty_han], female: row[:female],
            name_keys: []
          )
        end
      end
    end
  end
end
