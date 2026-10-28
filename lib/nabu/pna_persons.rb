# frozen_string_literal: true

require "json"

require_relative "normalize"
require_relative "zip_reader"

module Nabu
  # The PNA person read seam: the network dataset the Pna adapter lands
  # (Zenodo 10.5281/zenodo.6220409 v3 — Networks.zip, SupplementaryData.zip,
  # README.txt, verbatim) projected into the "pna" Store::PersonIndex slice
  # — the DprrPersons mold, driven from the same adapter hook at sync and
  # rebuild. The archives are read in-process (Nabu::ZipReader), never
  # unpacked into canonical/.
  #
  # == Projection onto the Person shape
  #
  # One person per Networks/NodeList.csv row (";"-separated, header Id;
  # Label;NameLanguage;Gender;Time;Profession;Place;Origin;Start date;End
  # date). person_id = the Label VERBATIM — PNA's own disambiguated name,
  # the homonym number after "_" ("Bēl-ibni_18"): the dataset's stable
  # token (the numeric Id is a row number of this release, not an
  # identity). name = the label with that "_N" dropped; name_han stays nil
  # (the transliteration is the native form we hold — no cuneiform rides);
  # female = Gender "fem"; refs nil (the dataset links no other authority).
  # No birth/death years: PNA dates a person by the reign(s) under which
  # they are attested, never by life events.
  #
  # attributes (migration 052) carry the rest of the row, upstream values
  # verbatim under these keys: name_language (NameLanguage), gender,
  # era (Time — the reign-era band, "668–631 Assurbanipal"), era_start /
  # era_end (the band's Start/End date years as signed BCE integers),
  # profession, place, origin. Upstream's placeholders are no value and
  # never ride: "Unknown", "Unknown or not applicable", and Time "N/A" —
  # whose rows carry the dummy date 01/01/2000, which is therefore never
  # read as a year.
  #
  # == Name keys
  #
  # The label sans "_N" keys whole, split into its offered readings: "X or
  # Y" and "X, Y" are two readings ("Šarru-ken, Šarru-ukin"), a trailing
  # parenthesised form is another ("Hundāru (Ahundāra)"), inner optional
  # letters key both ways ("Sili(m)mu" → Silimmu, Silimu), a trailing "?"
  # (an uncertain reading) folds out. A reading with a break ("[...]",
  # "[. . .]") keys nothing — the person stays resolvable by ref (949 of
  # the 17,387 v3 labels carry such a break and key nothing). Every
  # key also has its diacritic-free twin (Normalize.fold_diacritics:
  # "Aššūr-bāni-apli" → "Assur-bani-apli"), so a plain-ASCII query meets
  # the name.
  #
  # == Texts — the crosswalk (Crosswalk below)
  #
  # Networks/biModal.csv (Source;Target) links each person to the texts
  # attesting them, a text named by its PUBLICATION ("SAA 6 10", "StAT 2
  # 53", "ABL 458"). Each link rides in upstream order as
  # Store::PersonIndex::Text: the publication verbatim plus the urn of the
  # HELD document the crosswalk resolves it to (nil = a bare citation).
  module PnaPersons
    AUTHORITY = "pna"

    NETWORKS_ZIP = "Networks.zip"
    SUPPLEMENTARY_ZIP = "SupplementaryData.zip"
    NODES = "Networks/NodeList.csv"
    LINKS = "Networks/biModal.csv"
    # The one-mode co-occurrence network (two weightings of the same
    # edges) — read only to be COUNTED as skipped by rule (class note on
    # Adapters::Pna).
    EDGES = "Networks/EdgeList.csv"
    CONCORDANCE = "SupplementaryData/Lists/oraccConcordances"

    NODE_HEADER = ["Id", "Label", "NameLanguage", "Gender", "Time", "Profession", "Place", "Origin",
                   "Start date", "End date"].freeze
    PLACEHOLDERS = ["Unknown", "Unknown or not applicable", "N/A"].freeze
    NO_PERIOD = "N/A"
    FEMALE = "fem"
    HOMONYM = /_\d+\z/
    DATE = %r{\A\d{2}/\d{2}/(?<year>\d{1,4})\z}
    READINGS = /\s+or\s+|,\s+/
    TRAILING_FORM = /\A(?<head>.+?)\s+\((?<form>[^()]+)\)\z/
    OPTIONAL = /\(([^()]*)\)/
    BREAK = /[\[\]]|\.\s*\./

    Census = Data.define(:persons, :links, :resolved, :seconds)

    module_function

    def present?(workdir)
      File.file?(File.join(workdir, NETWORKS_ZIP))
    end

    # Stream every person as a Store::PersonIndex::Person, NodeList order,
    # each carrying its texts resolved through +crosswalk+.
    def each_person(workdir, crosswalk: Crosswalk.empty, &)
      return enum_for(:each_person, workdir, crosswalk: crosswalk) unless block_given?

      networks = archive(workdir, NETWORKS_ZIP)
      links = links_by_person(member(networks, LINKS))
      node_rows(member(networks, NODES)).each do |row|
        texts = links.fetch(row[1], []).map do |publication|
          Store::PersonIndex::Text.new(publication: publication, urn: crosswalk.resolve(publication))
        end
        yield build_person(row, texts)
      end
    end

    def build_person(row, texts)
      label = row[1]
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: label, name: label.sub(HOMONYM, ""), name_han: nil,
        birth_year: nil, death_year: nil, index_year: nil, dynasty: nil, dynasty_han: nil,
        female: row[3] == FEMALE,
        name_keys: name_keys(label).map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        attributes: attributes(row), texts: texts
      )
    end

    def attributes(row)
      _id, _label, language, gender, era, profession, place, origin, start, finish = row
      attrs = { "name_language" => language, "gender" => gender, "era" => era }
      if value?(era)
        attrs["era_start"] = bce_year(start)
        attrs["era_end"] = bce_year(finish)
      end
      attrs.merge!("profession" => profession, "place" => place, "origin" => origin)
      attrs.select { |_, v| v.is_a?(Integer) || value?(v) }
    end

    def value?(text) = !text.to_s.strip.empty? && !PLACEHOLDERS.include?(text)

    def bce_year(date)
      m = DATE.match(date.to_s)
      m && -Integer(m[:year], 10)
    end

    # The label's readings (module note), each with its diacritic-free twin.
    def name_keys(label)
      readings(label.sub(HOMONYM, "")).flat_map { |r| [r, Normalize.fold_diacritics(r)] }.uniq
    end

    def readings(name)
      parts = name.split(READINGS).flat_map do |part|
        m = TRAILING_FORM.match(part.strip)
        m ? [m[:head], m[:form]] : [part.strip]
      end
      parts.flat_map { |part| optional_forms(part.delete_suffix("?").strip) }
           .reject { |part| part.empty? || part.match?(BREAK) }
    end

    # "Sili(m)mu" → ["Silimmu", "Silimu"]; a name with no inner parentheses
    # passes through.
    def optional_forms(part)
      return [part] unless part.match?(OPTIONAL)

      [part.gsub(OPTIONAL, '\1'), part.gsub(OPTIONAL, "")].map { |f| f.squeeze(" ").strip }.uniq
    end

    # NodeList rows, header checked (a renamed column is a loud failure,
    # never a silent shift of every attribute).
    def node_rows(text)
      header, *rows = csv_rows(text)
      unless header == NODE_HEADER
        raise Nabu::ParseError, "pna: #{NODES} header is #{header.inspect}, expected #{NODE_HEADER.inspect}"
      end

      rows.each do |row|
        raise Nabu::ParseError, "pna: #{NODES} row #{row.first} has #{row.size} fields" unless row.size == 10
      end
    end

    # label → [publication, …] in biModal order.
    def links_by_person(text)
      _header, *rows = csv_rows(text)
      rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(publication, label), acc|
        acc[label] << publication
      end
    end

    def csv_rows(text)
      Normalize.nfc(text).lines.map(&:chomp)
               .reject(&:empty?).map { |line| line.split(";", -1) }
    end

    # The supplementary concordance text (empty when the archive is absent).
    def concordance(workdir)
      return "" unless File.file?(File.join(workdir, SUPPLEMENTARY_ZIP))

      member(archive(workdir, SUPPLEMENTARY_ZIP), CONCORDANCE)
    end

    def archive(workdir, name)
      ZipReader.new(File.binread(File.join(workdir, name)))
    rescue ZipReader::Error => e
      raise Nabu::ParseError, "pna: #{name} is not a readable zip (#{e.message})"
    end

    def member(zip, name)
      entry = zip.entries.find { |e| e.name == name.b }
      raise Nabu::ParseError, "pna: the archive holds no #{name}" if entry.nil?

      Adapters::SourceRead.utf8(zip.extract(entry), label: "pna zip member #{name}")
    end

    # The module census (Adapters::Pna.module_census): +read+ maps a
    # canonical-relative path to its bytes. The co-occurrence edges are
    # counted to show what the skip-by-rule leaves behind.
    def census(read)
      bytes = read.call(NETWORKS_ZIP)
      return nil if bytes.nil?

      networks = ZipReader.new(bytes)
      _header, *links = csv_rows(member(networks, LINKS))
      [ModuleCensus::Count.new(label: "persons", count: csv_rows(member(networks, NODES)).size - 1),
       ModuleCensus::Count.new(label: "person-text links", count: links.size),
       ModuleCensus::Count.new(label: "texts", count: links.map(&:first).uniq.size),
       ModuleCensus::Count.new(label: "co-occurrence edges (skipped by rule)",
                               count: csv_rows(member(networks, EDGES)).size - 1)]
    rescue ZipReader::Error, Nabu::ParseError
      nil
    end

    # The publication → HELD document crosswalk. PNA names a text by its
    # publication; the library holds Neo-Assyrian texts in oracc (SAAo, the
    # ATAE archives, …: urn:nabu:oracc:<project>:<P/Q/X id>, title = the
    # Oracc designation, zero-padded — "SAA 06 010") and cdli
    # (urn:nabu:cdli:p<id>, title = CDLI's designation). Resolution, first
    # hit wins:
    #
    # 1. the dataset's OWN concordance (SupplementaryData/Lists/
    #    oraccConcordances — Oracc catalogue designations → project/id, the
    #    list PNA's text names were standardized against): every row naming
    #    the publication, in file order, offers an Oracc id; a held oracc
    #    document with that id wins — in the row's own project, else the one
    #    whose designation matches, else the first by urn (a text Oracc
    #    serves from two projects, e.g. cams/tlab + saao/saa06);
    # 2. a held oracc document whose designation equals the publication
    #    under the zero-pad fold ("StAT 2 053" = "StAT 2 53"), when unique;
    # 3. a held cdli document carrying a concordance id;
    # 4. a held cdli document whose designation equals it under the same
    #    fold, when unique.
    #
    # Ambiguity never guesses (two held designations alike → no urn).
    # Withdrawn documents and the -en translation siblings never resolve.
    class Crosswalk
      ORACC = "oracc"
      CDLI = "cdli"
      # The held-text id at the end of a tablet urn (siblings carry a suffix).
      TABLET_ID = /:(?<id>[PQXpqx]\d+)\z/

      def self.empty = new(concordance: "", oracc: [], cdli: [])

      # Held documents straight from the catalog (one read per derivation).
      def self.from_catalog(db, concordance:)
        held = db[:documents].join(:sources, id: :source_id)
                             .where(Sequel[:sources][:slug] => [ORACC, CDLI], Sequel[:documents][:withdrawn] => false)
                             .select(Sequel[:sources][:slug], Sequel[:documents][:urn], Sequel[:documents][:title])
                             .map { |row| [row[:slug], row[:urn], row[:title]] }
        by_slug = held.group_by(&:first)
        new(concordance: concordance,
            oracc: by_slug.fetch(ORACC, []).map { |_, urn, title| [urn, title] },
            cdli: by_slug.fetch(CDLI, []).map { |_, urn, title| [urn, title] })
      end

      # +concordance+ the oraccConcordances text; +oracc+/+cdli+ [[urn,
      # title], …] of held documents.
      def initialize(concordance:, oracc:, cdli:)
        @rows = concordance_rows(concordance)
        @oracc = index(oracc)
        @cdli = index(cdli)
      end

      def resolve(publication)
        rows = @rows.fetch(publication, [])
        key = fold(publication)
        by_concordance(rows) || unique(@oracc[:by_title][key]) ||
          rows.lazy.filter_map { |_, id, _| @cdli[:by_id].fetch(id.upcase, []).first }.first ||
          unique(@cdli[:by_title][key])
      end

      # The designation fold: leading zeros off every number, spaces
      # squeezed ("SAA 06 010" → "SAA 6 10").
      def fold(designation)
        designation.to_s.gsub(/\b0+(\d)/, '\1').squeeze(" ").strip
      end

      private

      # Step 1 (class note): a row's own project first, then any held copy
      # of a row's id — the one whose designation matches, else the first.
      def by_concordance(rows)
        own = rows.lazy.filter_map do |project, id, _|
          prefix = "urn:nabu:oracc:#{project.tr('/', '-')}:"
          oracc_ids(id).find { |urn| urn.start_with?(prefix) }
        end.first
        return own if own

        held = rows.flat_map { |_, id, _| oracc_ids(id) }.uniq
        return nil if held.empty?

        designations = rows.map { |_, _, designation| fold(designation) }
        held.find { |urn| designations.include?(fold(@oracc[:titles][urn])) } || held.min
      end

      def oracc_ids(id) = @oracc[:by_id].fetch(id.upcase, [])

      def unique(urns) = urns&.size == 1 ? urns.first : nil

      # designation → [[project, id, designation], …] in file order.
      def concordance_rows(text)
        text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.each_line.with_object({}) do |line, acc|
          oracc_id, designation, = line.chomp.split(";")
          next if oracc_id.nil? || designation.nil? || !oracc_id.include?("/")

          project, _, id = oracc_id.rpartition("/")
          (acc[Normalize.nfc(designation.strip)] ||= []) << [project, id, designation.strip]
        end
      end

      def index(held)
        by_id = {}
        by_title = {}
        titles = {}
        held.each do |urn, title|
          m = TABLET_ID.match(urn)
          next if m.nil?

          (by_id[m[:id].upcase] ||= []) << urn
          (by_title[fold(title)] ||= []) << urn
          titles[urn] = title
        end
        { by_id: by_id, by_title: by_title, titles: titles }
      end
    end

    # The sync/rebuild derivation seam (the DprrPersons Producer mold): the
    # pna person-index slice, wholesale, its links resolved against the
    # catalog's held oracc + cdli documents at derivation time.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      # The sources whose held documents the crosswalk reads — a dirty one
      # re-derives this slice in an incremental rebuild.
      def reads_sources = [Crosswalk::ORACC, Crosswalk::CDLI]

      def run(_slug, workdir:)
        return nil unless PnaPersons.present?(workdir) && Store::PersonIndex.available?(@catalog)

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        crosswalk = Crosswalk.from_catalog(@catalog, concordance: PnaPersons.concordance(workdir))
        links = 0
        resolved = 0
        persons = PnaPersons.each_person(workdir, crosswalk: crosswalk).map do |person|
          links += person.texts.size
          resolved += person.texts.count(&:urn)
          person
        end
        count = Store::PersonIndex.derive!(@catalog, persons: persons, authority: AUTHORITY)
        return nil if count.nil?

        Census.new(persons: count, links: links, resolved: resolved,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
