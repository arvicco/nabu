# frozen_string_literal: true

require "csv"

module Nabu
  # The EDH person read seam: edh_data_pers.csv — EDH's structured
  # prosopography, one row per person attested on an inscription
  # (93,646 rows / 93,618 named at the frozen 2021 snapshot) — projected
  # into the "edh" person-index slice beside CBDB's. Read-only on
  # canonical; streamed row by row (8.9 MB).
  #
  # == What a person is here
  #
  # An EDH person is an ATTESTATION: upstream's own row id ("HD000001/3",
  # the inscription's HD number + the person's position on it) is the
  # person_id, and nothing is merged across inscriptions — EDH itself
  # never asserts that two rows are one individual (identity work is
  # PIR's and the uri/pir columns', which ride the document metadata).
  #
  # == The Person shape, honestly filled
  #
  # name = the name AS INSCRIBED ("Noniae P.f. Optatae", case and Leiden
  # sigla verbatim); female = geschlecht "W" (the 15 "W?" stay false — an
  # uncertainty is not a claim); EDH records no life years, so the year
  # columns stay nil. Everything else EDH structures about a person —
  # praenomen/nomen/cognomen, filiation, tribus, origo, status, kinship,
  # function, occupation, age at death, the Wikidata/PIR refs — already
  # rides each inscription's document metadata ("persons", the Edh
  # adapter's PERSON_FIELDS), so the index needs no schema widening.
  #
  # == Name keys
  #
  # Texts and readers cite Romans in the nominative, while the inscribed
  # name is often dative or genitive — so each person keys under the
  # inscribed name AND the nominative forms upstream normalized into
  # praenomen/nomen/cognomen: "praenomen nomen cognomen" and "nomen
  # cognomen" (or the lone part a single-name person carries). Leiden
  # sigla ([ ] ( ) < > { } ⟦ ⟧ /), lacunae ("---"), EDH's certainty
  # markers (? ! + *) and its "0" placeholder (an unreadable name part)
  # fold out of the keys — never out of the stored name.
  module EdhPersons
    AUTHORITY = "edh"
    PERS_CSV = File.join("pers", "edh_data_pers.csv")

    Census = Data.define(:persons, :seconds)

    SIGLA = %r{[\[\]()<>{}⟦⟧/?!+*]}
    LACUNA = /-{2,}/
    PLACEHOLDER = /\A0\z/

    module_function

    def csv_path(workdir)
      path = File.join(workdir, PERS_CSV)
      File.file?(path) ? path : nil
    end

    # Stream every named person row as a Store::PersonIndex::Person.
    def each_person(path)
      return enum_for(:each_person, path) unless block_given?

      CSV.foreach(path, headers: true) do |row|
        person = build_person(row)
        yield person if person
      end
    end

    # nil for a row with no usable id or no name at all.
    def build_person(row)
      id = row["id"].to_s.strip
      name = presence(row["name"])
      keys = name_keys(row)
      return nil if id.empty? || (name.nil? && keys.empty?)

      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: id, name: name, name_han: nil,
        birth_year: nil, death_year: nil, index_year: nil,
        dynasty: nil, dynasty_han: nil, female: row["geschlecht"].to_s.strip == "W",
        name_keys: keys
      )
    end

    def name_keys(row)
      praenomen, nomen, cognomen = %w[praenomen nomen cognomen].map { |col| clean(row[col]) }
      forms = [clean(row["name"]), [praenomen, nomen, cognomen].compact.join(" "),
               [nomen, cognomen].compact.join(" ")]
      forms.compact.reject(&:empty?).map { |form| Nabu::Pleiades.name_key(form) }.uniq
    end

    # Sigla, lacunae, markers and placeholders out; whitespace squished;
    # nil when nothing name-like remains.
    def clean(value)
      words = value.to_s.gsub(LACUNA, " ").gsub(SIGLA, "").split.grep_v(PLACEHOLDER)
      words.empty? ? nil : words.join(" ")
    end

    def presence(value)
      s = value.to_s.strip
      s.empty? ? nil : s
    end

    # The sync/rebuild derivation seam (the CbdbPersons::Producer mold):
    # the edh person-index slice, wholesale. No CSV → honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      def run(_slug, workdir:)
        path = EdhPersons.csv_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(@catalog, persons: EdhPersons.each_person(path),
                                                     authority: AUTHORITY)
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
