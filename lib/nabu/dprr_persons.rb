# frozen_string_literal: true

require "json"

require_relative "normalize"

module Nabu
  # The DPRR person read seam: the two SPARQL answers the Dprr adapter
  # lands (persons.json, dates.json — sparql-results+json verbatim)
  # projected into the "dprr" Store::PersonIndex slice — the CbdbPersons
  # mold, driven from the same adapter hook at sync and rebuild.
  #
  # == Projection onto the Person shape
  #
  # person_id = DPRR's numeric :hasID (the /person/<id> page and the
  # entity URI share it, so the desk ref is dprr:1); name = DPRR's own
  # styled name with its leading DPRR-id token dropped ("L. Iunius (46a,
  # Supb. 5.356ff.) M. f. Brutus" — the RE number disambiguates homonyms
  # on the card); name_han stays nil (the Latin is already the native
  # form); female = :isSex Sex/Female; refs = the entity URI verbatim,
  # the person's Linked Open Data identity.
  #
  # Years: birth_year from a DateType/1 (birth) assertion, death_year from
  # DateType/2 (death) or DateType/4 (death - violent), ONLY when the
  # interval is "S" (in that year) — "B"efore/"A"fter bounds are not
  # years. DPRR's own uncertain flag does not suppress an S year: the
  # year is DPRR's dated claim, its doubt rides the canonical answer.
  # Several qualifying assertions → the lowest DateInformation id. The
  # :hasEraFrom/:hasEraTo activity window is NOT projected (index_year
  # is CBDB's single floruit anchor, not a window) — it stays in the
  # canonical answer; deliberate coarseness, declared.
  #
  # == Name keys
  #
  # Texts cite Romans in the nominative by praenomen + nomen + cognomen
  # (+ agnomen) or nomen + cognomen, so each person keys under: "nomen
  # cognomen otherNames" and "nomen cognomen", each also prefixed with
  # the praenomen abbreviation (L.) and the full praenomen (Lucius). A
  # nomen-only name (most women, some men) keys whole; a lone cognomen
  # never keys (the homonym swamp — "Brutus" is a dozen persons). DPRR's
  # editorial marks fold out of the KEYS, never out of the stored name:
  # ( ) ? ' are stripped ("(Furius?)" → Furius, "Carve(tus)" → Carvetus),
  # a trailing alternative reading is dropped ("Philo (or Chilo)" →
  # Philo), and a part that still is not plain words — the "-" unknown,
  # "-onius" fragments, "(Veturius) or (Publilius)" — keys nothing; the
  # "-." praenomen placeholder never keys. A person whose nomen does not
  # key gets no name keys at all (still resolvable by ref).
  module DprrPersons
    AUTHORITY = "dprr"
    PERSONS_FILE = "persons.json"
    DATES_FILE = "dates.json"

    ENTITY = "http://romanrepublic.ac.uk/rdf/entity/"
    FEMALE = "#{ENTITY}Sex/Female".freeze
    BIRTH_TYPES = ["#{ENTITY}DateType/1"].freeze
    DEATH_TYPES = ["#{ENTITY}DateType/2", "#{ENTITY}DateType/4"].freeze
    EXACT_INTERVAL = "S"

    PRAENOMEN_PLACEHOLDER = "-."
    ALTERNATIVE = /\s+\((?:or\s+)?[^()]*\)\z/
    MARKS = /[()?']/
    WORDS = /\A\p{L}+(?: \p{L}+)*\z/
    # "(Cornelius or Mucius)", "(Veturius) or (Publilius)": two readings
    # offered as one part — neither is DPRR's claim, so nothing keys.
    DISJUNCTION = /\bor\b/

    Census = Data.define(:persons, :seconds)

    module_function

    def present?(workdir)
      File.file?(File.join(workdir, PERSONS_FILE))
    end

    # Stream every person as a Store::PersonIndex::Person, persons.json
    # order (DPRR id order). dates.json is optional — a missing file
    # projects no years.
    def each_person(workdir, &)
      return enum_for(:each_person, workdir) unless block_given?

      years = life_years(File.join(workdir, DATES_FILE))
      bindings(File.join(workdir, PERSONS_FILE)).each do |row|
        yield build_person(row, years.fetch(value(row, "person"), {}))
      end
    end

    def build_person(row, years)
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: value(row, "id"),
        name: styled_name(row), name_han: nil,
        birth_year: years[:birth], death_year: years[:death], index_year: nil,
        dynasty: nil, dynasty_han: nil,
        female: value(row, "sex") == FEMALE,
        name_keys: name_keys(row).map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        refs: value(row, "person")
      )
    end

    # "IUNI0001 L. Iunius … Brutus" → "L. Iunius … Brutus" (squeezed).
    def styled_name(row)
      name = Normalize.nfc(value(row, "name").to_s).squeeze(" ").strip
      dprr_id = value(row, "dprrId").to_s
      name = name.delete_prefix(dprr_id).strip unless dprr_id.empty?
      name.empty? ? nil : name
    end

    def name_keys(row)
      nomen = part_key(value(row, "nomen"))
      return [] if nomen.nil?

      cognomen = part_key(value(row, "cognomen"))
      other = part_key(value(row, "otherNames"))
      tails = [[nomen, cognomen, other], [nomen, cognomen]].map { |parts| parts.compact.join(" ") }.uniq
      prefixes = praenomina(row)
      tails.flat_map { |tail| [tail] + prefixes.map { |pre| "#{pre} #{tail}" } }
    end

    def praenomina(row)
      abbr = value(row, "praenomenAbbr").to_s.strip
      return [] if abbr.empty? || abbr == PRAENOMEN_PLACEHOLDER

      [abbr, part_key(value(row, "praenomen"))].compact.uniq
    end

    # One name part's key form, or nil when it is not plain words after
    # the marks fold (module note).
    def part_key(raw)
      text = Normalize.nfc(raw.to_s).strip.sub(ALTERNATIVE, "").gsub(MARKS, "").squeeze(" ").strip
      text.match?(WORDS) && !text.match?(DISJUNCTION) ? text : nil
    end

    # person URI → { birth:, death: } from the exact-year assertions.
    def life_years(path)
      return {} unless File.file?(path)

      exact = bindings(path).select { |row| value(row, "interval") == EXACT_INTERVAL }
      exact.sort_by { |row| value(row, "date").to_s.split("/").last.to_i }
           .each_with_object(Hash.new { |h, k| h[k] = {} }) do |row, years|
        slot = year_slot(value(row, "type"))
        next if slot.nil?

        years[value(row, "person")][slot] ||= Integer(value(row, "value"), exception: false)
      end
    end

    def year_slot(type)
      if BIRTH_TYPES.include?(type) then :birth
      elsif DEATH_TYPES.include?(type) then :death
      end
    end

    def bindings(path)
      JSON.parse(File.read(path, encoding: "UTF-8")).dig("results", "bindings") || []
    end

    def value(row, var)
      row.dig(var, "value")
    end

    # The sync/rebuild derivation seam (the CbdbPersons Producer mold):
    # the dprr person-index slice, wholesale. No answers → honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      def run(_slug, workdir:)
        return nil unless DprrPersons.present?(workdir)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(
          @catalog, persons: DprrPersons.each_person(workdir), authority: AUTHORITY
        )
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
