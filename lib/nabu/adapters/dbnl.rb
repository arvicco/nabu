# frozen_string_literal: true

require "csv"

require_relative "dbnl_tei_parser"
require_relative "source_read"
require_relative "../zip_fetch"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # dbnl — the DBNL public-domain collection (Digitale Bibliotheek voor de
    # Nederlandse Letteren, owned by the KB, the national library of the
    # Netherlands): edited, hand-corrected transcriptions of Dutch and Flemish
    # literature and language, Middle Ages to 1899 — Middle Dutch drama and
    # mysticism, incunabula, the Golden Age poets and songbooks, 18th-century
    # prose and periodicals, 19th-century novels, children's books and
    # scholarship. DBNL offers the public-domain part as ONE zip of TEI files
    # plus a metadata CSV on dbnl.org/letterkunde/pd/.
    #
    # == The route law (absolute)
    #
    # The OFFERED zip and the offered CSV only — one GET each per sync. The
    # site's robots.txt is "User-Agent: * / Disallow: /" and the terms page
    # forbids downloading large numbers of works ("Het downloaden van grote
    # aantallen werken is niet toegestaan"): those clauses govern the
    # per-title pages, which this adapter NEVER fetches. The zip is the KB's
    # own offered download. ZIP_URL and METADATA_URL are the only two URLs.
    #
    # == Delivery grains (enumerated 2026-11-08)
    #
    # - xml_pd.zip (692,154,667 B, Last-Modified 2026-11-04) — TAKEN: 3,654
    #   flat members <ti_id>_01.xml, one per title, every one TEI.2 (no
    #   non-title member: no DTD, no images, no index file). Document = the
    #   member file (urn:nabu:dbnl:<ti_id>_01).
    # - titels_pd.csv (dbnl.org/extern/titels_pd.php, pipe-separated, a
    #   "sep=|" Excel line first) — TAKEN as the register (dating, edition,
    #   genre, persons), landed in metadata/; never text.
    # - txt_pd.zip (631 MB, the same titles as plain text) — REJECTED, never
    #   fetched: the TEI carries the same text with its page structure.
    # - the per-title pages (/tekst/<id>/, /nieuws/xml.php?id=…,
    #   /nieuws/text.php?id=… — the CSV's url/text_url columns) — REJECTED,
    #   never fetched (robots + terms; the route law above).
    #
    # == Reconciliation (through the adapter over the whole zip, 2026-11-08)
    #
    # The CSV — upstream's own advertised catalogue — lists 7,440 titles
    # (9,105 rows: one per title × person × genre). The zip serves 3,654 of
    # them; every member has a register row, none is unregistered. Of the
    # 3,786 register-only titles, 115 carry a text_url but post-date the zip
    # (added 2025-01 … 2026-11, the CSV's maand column; the zip is
    # 2026-11-04); the rest are catalogue entries whose text DBNL does not
    # ship in the dump (most of the Middle Dutch canon among them: the zip
    # holds 16 titles dated before 1500, the register 136; before 1800 the
    # zip holds 1,584, the register 2,658). Discovery yields one ref per
    # member, 3,654, skipped-by-rule 0 (the register and the two fetch pins
    # are furniture notes); the register-only titles are reported in the
    # register's discovery note, never as skips (nothing to skip: no file).
    # Parsed through the adapter: 3,653 documents / 950,870 page passages
    # (482,182 notes aside), 1 honest quarantine — vry_001anat01_01.xml is
    # malformed upstream (a stray "in" before its DOCTYPE).
    #
    # == License
    #
    # The PD page, verbatim: "De titels op deze pagina behoren tot het publieke
    # domein. Dat betekent dat ze auteursrechtvrij zijn. Iedereen mag ze dus
    # voor elk doel gebruiken." The KB dataset page: "Work belonging to a
    # maker who has been dead for over 70 years is part of the public domain
    # … may be used without restrictions." The KB holds the database right on
    # the collection as a whole → attribution class, crediting DBNL/KB.
    #
    # == Axes (aggressive-mining law)
    #
    # - date (MetadataDates :structured) from the register's jaar — DBNL's
    #   date of the TRANSCRIBED witness — classed by its druk column:
    #   "handschrift" (the manuscript's date) and "1ste druk…" (the first
    #   print — the work's first publication) are the artifact's own date
    #   (no class); any later or unknown printing ("4de druk", "herdruk",
    #   "?", blank) is class "edition" — never the text's date. For such an
    #   edition, a header statement of the first print's year ("De eerste
    #   druk dateert uit 1838") becomes the date instead, class
    #   "composition", the edition year riding raw. jaar shapes: "1834",
    #   "ca. 1880", "1832-1853", "ca. 1880-1890", "[1487-1488]", "1882?",
    #   "13de eeuw" (the century), "voor 1343" / "na 1415" (one-sided),
    #   "1837-" (open); "?" mints nothing.
    # - kind: the register's genre values (poëzie, proza, drama, non-fictie,
    #   jeugdliteratuur, sec - letterkunde, sec - taalkunde; up to four per
    #   title) → metadata "genres", projected as the genre facet
    #   (config/facet_map.yml) and folded in config/kind_map.yml.
    # - lect: the header's langUsage ids (nl · fr · la/lat · de · fy · en ·
    #   af · nds; "nl-fr"/"nl-rus" take their first part) → the ISO 639-3
    #   code; a title without langUsage (1,055 members, the older files) is
    #   Dutch. Census: nld 3,599 · fra 23 · dum 15 · lat 11 · deu, eng, fry,
    #   afr, nds 1 each (nds = the ca. 1478 Seven Sages incunable, upstream's
    #   own claim). A Dutch title whose date ends
    #   by 1500 is Middle Dutch (dum) — the conventional close of the
    #   Middle Dutch period (the INL's Middelnederlandsch Woordenboek); the
    #   basis rides metadata "language_basis". One language per document:
    #   the polyglot titles (Vaenius' Latin/Dutch/French emblems, Willems'
    #   French letter quoting Middle Dutch) keep the header's first.
    # - places: none as an axis — the imprint lives only in the sourceDesc
    #   prose ("A. Tjaden, Deventer 1875"), carried verbatim as
    #   "source_edition"; the persons' birth/death places ride "authors".
    #   DBNL's place/person/date link codes ride the passages ("dbnl_interp")
    #   unresolved (no code table ships with the dump).
    #
    # == Fetch and storage
    #
    # ZipFetch (stream mode — the 692 MB body goes to a staging file, never
    # memory) unpacks the zip's flat members into the workdir root, keeping
    # metadata/ out of its deletion sweep; FileFetch lands the CSV in
    # metadata/. Both prepared before either tree mutates (the socinian-
    # letters shape). Extracted: 2,096,835,993 B (2.0 GB) in 3,654 files +
    # the 2.7 MB CSV. The workdir is a plain (non-git) tree, hashed whole by
    # the identity walker; the declared materializations below are recorded
    # for the contract's sake (they act only inside git trees).
    class Dbnl < Nabu::Adapter
      SLUG = "dbnl"
      URN_PREFIX = "urn:nabu:dbnl:"
      ZIP_URL = "https://www.dbnl.org/letterkunde/pd/xml_pd.zip"
      METADATA_URL = "https://www.dbnl.org/extern/titels_pd.php"
      METADATA_DIR = "metadata"
      METADATA_FILE = "titels_pd.csv"
      TITLE_FILE = /\A(?<ti_id>[a-z0-9_]+)_(?<part>\d\d)\.xml\z/

      # langUsage id → house code (the 2026-11-08 census, every id covered).
      LANGUAGES = { "nl" => "nld", "la" => "lat", "lat" => "lat", "fr" => "fra", "de" => "deu",
                    "en" => "eng", "fy" => "fry", "af" => "afr", "nds" => "nds" }.freeze
      DEFAULT_LANGUAGE = "nld"
      MIDDLE_DUTCH = "dum"
      MIDDLE_DUTCH_END = 1500

      FIRST_PRINT = /\A1ste druk/
      MANUSCRIPT = "handschrift"
      ANONYMOUS = "Anoniem"
      # The header's own statement of the first print's year in a later
      # edition ("De eerste druk dateert uit 1838." / "… verscheen in …").
      FIRST_EDITION_STATEMENT = /eerste druk (?:dateert (?:uit|van)|verscheen in|is uit) (?:ca\. )?(\d{4})\b/i

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "DBNL — Digitale Bibliotheek voor de Nederlandse Letteren, public-domain collection (KB)",
        license: "Public domain, the DBNL PD page verbatim: \"De titels op deze pagina behoren tot het " \
                 "publieke domein. Dat betekent dat ze auteursrechtvrij zijn. Iedereen mag ze dus voor elk " \
                 "doel gebruiken.\" The KB (owner of DBNL) holds the database right on the collection as a " \
                 "whole; credit DBNL / KB (read 2026-11-08).",
        license_class: "attribution",
        upstream_url: "https://www.dbnl.org/letterkunde/pd/index.php",
        parser_family: "dbnl-tei",
        credit: "DBNL — Digitale Bibliotheek voor de Nederlandse Letteren (dbnl.org), KB, nationale " \
                "bibliotheek van Nederland: collectie publiek domein."
      )

      def self.manifest = MANIFEST

      # Parallel replay (audited): #parse reads one member plus the memoized
      # register — a pure function of the two files' bytes.
      def self.parallel_parse? = true

      def self.materialized_paths = [METADATA_DIR, Nabu::ZipFetch::STATE_FILE]

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(label: "xml_pd.zip", zip_url: ZIP_URL, metadata_url: nil,
                                            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE),
         Nabu::Adapter::HttpProbeTarget.new(label: METADATA_FILE, zip_url: METADATA_URL, metadata_url: nil,
                                            state_subdir: METADATA_DIR, state_file: Nabu::FileFetch::STATE_FILE)]
      end

      def initialize
        super
        @registers = {}
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        title_files(workdir).each do |name|
          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{name.delete_suffix('.xml')}",
                                      path: File.expand_path(File.join(workdir, name)))
        end
      end

      def discovery_skips(workdir)
        return Nabu::Adapter::DiscoverySkips.new unless Dir.exist?(workdir)

        notes = []
        unrecognized = []
        stray_files(workdir).each do |rel|
          if (note = rule_note(rel, workdir))
            notes << note
          else
            unrecognized << "#{rel}: unrecognized member of the dbnl tree"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: unrecognized.size,
                                          notes: notes + unrecognized)
      end

      def parse(document_ref)
        path = document_ref.path
        stem = File.basename(path, ".xml")
        ti_id = File.basename(path)[TITLE_FILE, :ti_id] || stem
        parser = DbnlTeiParser.new
        result = parser.read(path)
        record = register_for(path).fetch(ti_id, nil)
        metadata = TitleMetadata.new(stem: stem, ti_id: ti_id, result: result, record: record).call
        parser.document(result, urn: "#{URN_PREFIX}#{stem}", language: metadata.delete("language"),
                                path: path, title: result.header["title"] || record&.title, metadata: metadata)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        @registers.clear
        attic = File.join(workdir, ATTIC_DIRNAME)
        zip = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, attic_dir: attic, progress: progress,
                                 stream: true, keep: [METADATA_DIR])
        csv = Nabu::FileFetch.new(url: METADATA_URL, dir: File.join(workdir, METADATA_DIR), filename: METADATA_FILE,
                                  attic_dir: File.join(attic, METADATA_DIR), progress: progress)
        begin
          zip.prepare!
          csv.prepare!
          guard_mass_deletion!(workdir, zip.doomed_paths + csv.doomed_paths, force: force)
          zip.complete!
          csv.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, csv))
      rescue Nabu::ZipFetch::Error, Nabu::FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # The register beside a member (the attic's copy for an attic ref; an
      # absent register means header-only metadata, never a guess).
      def register_for(path)
        csv = File.expand_path(File.join(File.dirname(path), METADATA_DIR, METADATA_FILE))
        @registers[csv] ||= Register.load(csv)
      end

      private

      def title_files(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.children(workdir).grep(TITLE_FILE).select { |name| File.file?(File.join(workdir, name)) }.sort
      end

      def fetch_notes(zip, csv)
        [zip.not_modified? ? "xml_pd.zip not modified (304)" : "xml_pd.zip unpacked (sha256 #{zip.sha})",
         csv.not_modified? ? "titels_pd.csv not modified (304)" : "titels_pd.csv landed (sha256 #{csv.sha})",
         attic_notes(zip.atticked + csv.atticked)].compact.join("; ")
      end

      def stray_files(workdir)
        root = File.expand_path(workdir)
        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).filter_map do |path|
          next unless File.file?(path)

          rel = path.delete_prefix("#{root}/")
          next if rel.start_with?("#{ATTIC_DIRNAME}/")
          next if !rel.include?("/") && rel.match?(TITLE_FILE)

          rel
        end.sort
      end

      def rule_note(rel, workdir)
        case rel
        when Nabu::ZipFetch::STATE_FILE then "#{rel}: the zip fetcher's own state pin — not upstream content"
        when File.join(METADATA_DIR, Nabu::FileFetch::STATE_FILE)
          "#{rel}: the register fetcher's own state pin — not upstream content"
        when File.join(METADATA_DIR, METADATA_FILE) then register_note(rel, workdir)
        end
      end

      def register_note(rel, workdir)
        register = register_for(File.join(workdir, "x.xml"))
        held = title_files(workdir).map { |name| name[TITLE_FILE, :ti_id] }.uniq
        "#{rel}: the title register (dating, edition, genre, persons — read as lookups, not text); " \
          "#{register.size} titles listed, #{(register.ids - held).size} with no file in xml_pd.zip " \
          "(DBNL's PD catalogue beyond the dump — not served, nothing to skip)"
      end

      # titels_pd.csv: one row per title × person × genre; folded per ti_id.
      class Register
        Person = Data.define(:id, :name, :born, :died, :birth_place, :death_place, :woman)
        Record = Data.define(:ti_id, :title, :volumes, :year_raw, :printing, :ppn, :library, :url,
                             :persons, :genres)

        def self.load(path)
          return new({}) unless File.file?(path)

          text = SourceRead.utf8_file(path, label: "dbnl register").delete_prefix("﻿").sub(/\Asep=\|\r?\n/, "")
          new(index(CSV.parse(text, col_sep: "|", headers: true)))
        rescue CSV::MalformedCSVError => e
          raise Nabu::ParseError, "#{path}: malformed register CSV: #{e.message}"
        end

        def self.index(table)
          table.group_by { |row| clean(row["ti_id"]) }.except(nil).to_h do |ti_id, rows|
            first = rows.first
            [ti_id, Record.new(ti_id: ti_id, title: clean(first["titel"]), volumes: clean(first["vols"]),
                               year_raw: clean(first["jaar"]), printing: clean(first["druk"]),
                               ppn: clean(first["ppn_o"]), library: clean(first["bibliotheek"]),
                               url: clean(first["url"]), persons: persons(rows),
                               genres: rows.filter_map { |row| clean(row["genre"]) }.uniq)]
          end
        end

        def self.persons(rows)
          rows.uniq { |row| row["pers_id"] }.filter_map do |row|
            id = clean(row["pers_id"])
            next unless id

            name = [row["voornaam"], row["voorvoegsel"], row["achternaam"]].filter_map { |part| clean(part) }.join(" ")
            Person.new(id: id, name: name, born: clean(row["jaar_geboren"]), died: clean(row["jaar_overlijden"]),
                       birth_place: clean(row["geb_plaats"]), death_place: clean(row["overl_plaats"]),
                       woman: row["vrouw"].to_s.strip == "1")
          end
        end

        def self.clean(value)
          value = value.to_s.gsub(/[[:space:]]+/, " ").strip
          value.empty? ? nil : Normalize.nfc(value)
        end

        def initialize(records)
          @records = records
        end

        def fetch(ti_id, default) = @records.fetch(ti_id, default)
        def size = @records.size
        def ids = @records.keys
      end

      # One title's metadata from its header and register record (the axes
      # class note), plus the "language" the caller pops for the Document.
      class TitleMetadata
        def initialize(stem:, ti_id:, result:, record:)
          @stem = stem
          @ti_id = ti_id
          @header = result.header
          @result = result
          @record = record
        end

        def call
          date = date_hash
          code, basis = language(date)
          {
            "language" => code, "language_basis" => basis, "dbnl_id" => @header["dbnl_id"] || @stem,
            "ti_id" => @ti_id, "grain" => @result.grain.to_s, "date" => date,
            **header_fields, **record_fields,
            "dbnl_interp" => (@result.interps unless @result.interps.empty?),
            "register" => (@record ? nil : "absent")
          }.reject { |_, value| value.nil? || value == [] }
        end

        private

        def header_fields
          @header.slice("authors", "editors", "edition_statement", "editorial_interventions",
                        "source_edition", "used_copy", "lang_usage")
                 .transform_keys { |key| key == "authors" ? "header_authors" : key }
        end

        def record_fields
          return {} unless @record

          named = @record.persons.reject { |person| person.name.start_with?(ANONYMOUS) }
          {
            "printing" => @record.printing, "volumes" => @record.volumes, "ppn" => @record.ppn,
            "holding_library" => @record.library, "dbnl_url" => @record.url, "genres" => @record.genres,
            "author" => named.map(&:name), "anonymous" => (true if named.empty? && @record.persons.any?),
            "authors" => named.map { |person| person_hash(person) }
          }
        end

        def person_hash(person)
          { "id" => person.id, "name" => person.name, "born" => person.born, "died" => person.died,
            "birth_place" => person.birth_place, "death_place" => person.death_place,
            "woman" => (true if person.woman) }.compact
        end

        # -- date --------------------------------------------------------------

        def date_hash
          raw = @record&.year_raw
          bounds = raw && DbnlDate.bounds(raw)
          return nil unless bounds

          not_before, not_after = bounds
          printing = @record.printing.to_s
          return envelope(not_before, not_after, raw, nil, "witness (#{printing})") if artifact?(printing)

          printing = "printing unknown" if printing.empty?
          first = @header["edition_statement"].to_s[FIRST_EDITION_STATEMENT, 1]
          if first
            year = Integer(first, 10)
            return envelope(year, year, "eerste druk #{first} (header); this witness #{raw}, #{printing}",
                            "composition", "first edition (header statement)")
          end
          envelope(not_before, not_after, raw, "edition", "edition (#{printing})")
        end

        def artifact?(printing) = printing == MANUSCRIPT || printing.match?(FIRST_PRINT)

        def envelope(not_before, not_after, raw, klass, basis)
          { "not_before" => not_before, "not_after" => not_after, "raw" => raw, "class" => klass,
            "basis" => basis }.compact
        end

        # -- language ----------------------------------------------------------

        def language(date)
          ident = @header.fetch("lang_usage", []).first
          code = if ident
                   LANGUAGES.fetch(ident.split("-").first) do
                     raise Nabu::ParseError, "#{@stem}: langUsage id #{ident.inspect} has no house code"
                   end
                 else
                   DEFAULT_LANGUAGE
                 end
          basis = ident ? "langUsage #{ident}" : "no langUsage (Dutch)"
          latest = date && (date["not_after"] || date["not_before"])
          if code == DEFAULT_LANGUAGE && latest && latest <= MIDDLE_DUTCH_END
            return [MIDDLE_DUTCH, "#{basis}; dated by #{MIDDLE_DUTCH_END} → Middle Dutch"]
          end

          [code, basis]
        end
      end

      # The register's jaar shapes → [not_before, not_after] (either may be
      # nil for a one-sided bound), or nil when nothing parses.
      module DbnlDate
        CENTURY = /(\d{1,2})(?:de|ste)\s+eeuw/i
        YEAR = /\d{3,4}/

        module_function

        def bounds(raw)
          text = raw.delete("[]").strip
          return nil if text.empty? || text == "?"

          century(text) || one_sided(text) || span(text)
        end

        def century(text)
          hits = text.scan(CENTURY).flatten.map { |c| Integer(c, 10) }
          return nil if hits.empty? || text.match?(/\d{3,4}/)

          [((hits.min - 1) * 100) + 1, hits.max * 100]
        end

        def one_sided(text)
          year = text[YEAR]
          return nil unless year

          case text
          when /\Avoor\s/i then [nil, Integer(year, 10)]
          when /\Ana\s/i, /\A(?:ca\.\s*)?\d{3,4}\s*-\s*\z/ then [Integer(year, 10), nil] # "na 1415", "1837-"
          end
        end

        def span(text)
          years = text.scan(YEAR).map { |y| Integer(y, 10) }
          return nil if years.empty? || years.size > 2

          years.minmax
        end
      end
    end
  end
end
