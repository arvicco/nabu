# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # The derived person index (P97-2, migration 031 — owner-ruled 2026-09-11, option b):
    # a prosopography authority's persons projected into catalog tables
    # at sync time, the PlaceIndex mold exactly — keyed (authority,
    # person_id) so CBDB is one authority among several (EDH's attested
    # persons the second — Nabu::EdhPersons), derived
    # wholesale per authority (delete + insert in one transaction, a
    # pure function of the canonical artifact, replayed by rebuild),
    # name keys folded in Ruby via the shared Pleiades.name_key rule
    # (Unicode case fold; Han text passes untouched, so 王安石 and
    # "wang anshi" both key).
    #
    # Authorities (one slice each): "cbdb" (Nabu::CbdbPersons), "edh"
    # (Nabu::EdhPersons), "elephantine" (Nabu::ElephantinePersons),
    # "aozora" (Nabu::AozoraPersons), "kokubunken"
    # (Nabu::KokubunkenPersons), and the NIKH index-markup authorities
    # "sillok", "goryeosa", "goryeosa-jeoryo" (Nabu::NikhPersons), and
    # "dprr" (Nabu::DprrPersons — the Roman Republic's elite, refs = the
    # DPRR entity URI).
    # The column names are
    # CBDB-born; name_han is the NATIVE-form lane every authority fills
    # with its original-script/original-language name (CBDB: the Han name;
    # Elephantine: the Egyptian/Greek/Aramaic/Coptic form beside the
    # English; Aozora: the index's kanji/katakana form beside the romaji;
    # kokubunken: the record's own form, which is already native), and
    # refs (migration 044) carries links into other prosopographies as
    # verbatim URLs (Elephantine: Trismegistos; kokubunken: VIAF).
    # Migration 052 adds two lanes, both optional per authority: texts
    # (person_index_texts — the person's attestations, the publication as
    # the authority cites it plus the HELD document's urn when the
    # derivation resolved one) and attributes (attributes_json — the
    # authority's own fields the CBDB-born columns have no lane for).
    # "pna" (Nabu::PnaPersons) fills both.
    module PersonIndex
      TABLE = :person_index
      NAMES_TABLE = :person_index_names
      TEXTS_TABLE = :person_index_texts

      INSERT_SLICE = 2_000

      DEFAULT_AUTHORITY = "cbdb"

      # Every authority a producer derives (each keyed by its source slug),
      # the default first — the order name lookups search in.
      AUTHORITIES = [DEFAULT_AUTHORITY, "edh", "elephantine", "aozora", "kokubunken", "dprr", "pna",
                     "sillok", "goryeosa", "goryeosa-jeoryo"].freeze

      # One attestation: the publication as the authority cites it, and the
      # held document's urn (nil = a bare citation).
      Text = Data.define(:publication, :urn)

      Person = Data.define(:authority, :person_id, :name, :name_han,
                           :birth_year, :death_year, :index_year,
                           :dynasty, :dynasty_han, :female, :name_keys, :refs,
                           :attributes, :texts) do
        # refs, attributes and texts are optional: an authority without
        # external links, extra fields or attestations omits them.
        def initialize(refs: nil, attributes: nil, texts: nil, **fields)
          super
        end
      end

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
        # Migration 052's lanes (texts + attributes) ride when the catalog has them.
        lanes = db.table_exists?(TEXTS_TABLE)
        db.transaction do
          db[NAMES_TABLE].where(authority: authority).delete
          db[TEXTS_TABLE].where(authority: authority).delete if lanes
          db[TABLE].where(authority: authority).delete
          batch = { TABLE => [], NAMES_TABLE => [], TEXTS_TABLE => [] }
          persons.each do |person|
            batch[TABLE] << person_row(authority, person, lanes: lanes)
            person.name_keys.uniq.each do |key|
              batch[NAMES_TABLE] << { authority: authority, person_id: person.person_id, name_key: key }
            end
            batch[TEXTS_TABLE].concat(text_rows(authority, person)) if lanes
            count += 1
            flush!(db, batch) if batch[TABLE].size >= INSERT_SLICE
          end
          flush!(db, batch)
        end
        count
      end

      def person_row(authority, person, lanes:)
        row = { authority: authority, person_id: person.person_id,
                name: person.name, name_han: person.name_han,
                birth_year: person.birth_year, death_year: person.death_year,
                index_year: person.index_year, dynasty: person.dynasty,
                dynasty_han: person.dynasty_han, female: person.female,
                refs: person.refs }
        row[:attributes_json] = person.attributes && JSON.generate(person.attributes) if lanes
        row
      end

      def text_rows(authority, person)
        Array(person.texts).each_with_index.map do |text, position|
          { authority: authority, person_id: person.person_id, position: position,
            publication: text.publication, urn: text.urn }
        end
      end

      def flush!(db, batch)
        batch.each do |table, rows|
          next if rows.empty?

          db[table].multi_insert(rows)
          rows.clear
        end
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
            name_keys: [], refs: row[:refs],
            attributes: row[:attributes_json] && JSON.parse(row[:attributes_json]),
            texts: texts_of(row[:person_id])
          )
        end

        # The person's attestations in the authority's order; nil when the
        # authority derives none (the lane is optional per authority).
        def texts_of(person_id)
          return nil unless @db.table_exists?(TEXTS_TABLE)

          texts = @db[TEXTS_TABLE].where(authority: @authority, person_id: person_id).order(:position)
                                  .map { |row| Text.new(publication: row[:publication], urn: row[:urn]) }
          texts.empty? ? nil : texts
        end
      end
    end
  end
end
