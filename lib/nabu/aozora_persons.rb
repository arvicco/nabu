# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # The Aozora Bunko persons read seam: the person columns of the
  # person×work index (index_pages/list_person_all_extended_utf8 — the
  # same CSV discovery reads) projected into the "aozora"
  # Store::PersonIndex slice — the ElephantinePersons mold, driven from
  # the adapter hook at sync and rebuild.
  #
  # == The authority (censused whole, 2026-10-18)
  #
  # 19,493 person×work rows name 1,335 distinct persons by 人物ID — a
  # stable zero-padded id upstream also uses for its person pages; every
  # row of one id carries identical name/date columns (0 conflicts). The
  # rows of in-copyright works count too: a person record is a fact about
  # the person, not the work's text. Per person:
  #   姓/名            the index's own form (kanji for Japanese persons,
  #                    katakana for foreign ones; 名 empty on 71)
  #   姓読み/名読み    the kana reading
  #   姓ローマ字/名ローマ字  the romaji, surname first ("Irving Washington")
  #   生年月日/没年月日  "1783-04-03" on 18,310 rows; bare years, "前427"
  #                    (BCE), century prose ("紀元前7世紀末"), "192X",
  #                    "不詳" and blanks also occur
  #
  # == Projection onto the Person shape
  #
  # name = the romaji (surname first, as upstream orders it); name_han =
  # the index's own 姓 名 form (the native-form lane); birth/death years
  # from the leading year of the date columns (前 = BCE; anything else —
  # century prose, an X digit, 不詳 — stays nil, never guessed); female
  # = nil (the index has no sex column: unknown, never false); every
  # spelling — spaced and unspaced native form, kana reading, romaji —
  # keys under the shared fold. No refs (the index names no external
  # authority), no dynasty, no index year.
  module AozoraPersons
    AUTHORITY = "aozora"

    COL_ID = "人物ID"
    COL_SURNAME = "姓"
    COL_GIVEN = "名"
    COL_SURNAME_READING = "姓読み"
    COL_GIVEN_READING = "名読み"
    COL_SURNAME_ROMAJI = "姓ローマ字"
    COL_GIVEN_ROMAJI = "名ローマ字"
    COL_BIRTH = "生年月日"
    COL_DEATH = "没年月日"

    LIFE_YEAR = /\A(前)?(\d{3,4})(?![\dX])/

    Census = Data.define(:persons, :seconds)

    module_function

    # Every distinct person in the index under +workdir+, first row per
    # 人物ID, as Store::PersonIndex::Person (id order).
    def each_person(workdir, &)
      return enum_for(:each_person, workdir) unless block_given?

      rows = Adapters::Aozora.new.index_rows(workdir)
      rows.reject { |row| row[COL_ID].to_s.strip.empty? }
          .uniq { |row| row[COL_ID] }
          .sort_by { |row| row[COL_ID] }
          .each { |row| yield build_person(row) }
    end

    def build_person(row)
      native = joined(row[COL_SURNAME], row[COL_GIVEN])
      romaji = joined(row[COL_SURNAME_ROMAJI], row[COL_GIVEN_ROMAJI])
      reading = joined(row[COL_SURNAME_READING], row[COL_GIVEN_READING])
      spellings = [native, native&.delete(" "), reading, romaji].compact
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: row[COL_ID].strip,
        name: romaji || native, name_han: native,
        birth_year: life_year(row[COL_BIRTH]), death_year: life_year(row[COL_DEATH]),
        index_year: nil, dynasty: nil, dynasty_han: nil, female: nil,
        name_keys: spellings.map { |form| Nabu::Pleiades.name_key(form) }.uniq
      )
    end

    # "1783-04-03" → 1783, "前427" → -427, "800" → 800; nil for century
    # prose, an X digit, 不詳 or blank.
    def life_year(value)
      match = LIFE_YEAR.match(value.to_s.strip) or return nil

      year = Integer(match[2], 10)
      return nil if year.zero?

      match[1] ? -year : year
    end

    def joined(*parts)
      text = parts.map { |part| part.to_s.strip }.reject(&:empty?).join(" ")
      text.empty? ? nil : Normalize.nfc(text)
    end

    # The sync/rebuild derivation seam (the ElephantinePersons::Producer
    # mold): the aozora person-index slice, wholesale. No index → honest
    # no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      def run(_slug, workdir:)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        persons = AozoraPersons.each_person(workdir).to_a
        return nil if persons.empty?

        count = Store::PersonIndex.derive!(@catalog, persons: persons, authority: AUTHORITY)
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
