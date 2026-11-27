# frozen_string_literal: true

require "digest"
require "json"

require_relative "dbbe_sqlite_reader"

module Nabu
  module Adapters
    # The Database of Byzantine Book Epigrams (DBBE, Ghent University;
    # dbbe.ugent.be, ed. Kristoffel Demoen, Floris Bernard and the DBBE
    # team) — the Greek verse paratexts of medieval manuscripts: colophons,
    # dedications, title and miniature poems, reader admonitions — each
    # recorded as it stands in one manuscript (the OCCURRENCE, orthography
    # and punctuation kept) and as the normalized text the editors propose
    # for every group of similar occurrences (the TYPE), many types with
    # translations. Read from the project's weekly "simplified structure"
    # export, the single SQLite file dbbe_archive.sqlite on Zenodo (concept
    # record 19435533). Language grc (lect by date band, see the posture).
    #
    # == Upstream / grains (whole-file census of the 2026-11-16 file,
    # md5 85b0abf7…, record 23008642, published 2026-09-28)
    #
    # The record serves ONE file. Inside it, upstream's own six concepts:
    #
    #   occurrence  13,050 rows — ACCEPTED as a document (12,928), urn
    #               urn:nabu:dbbe:occurrence-<id>; passages = its verses.
    #               SKIPPED BY RULE: the 122 occurrences with no
    #               transcribed text (text_original blank, no verse rows —
    #               upstream's "text completely unknown" records, 113 of
    #               them so labelled, plus 6 "partially unknown" and 3
    #               "completely known" whose text was never keyed); each is
    #               counted and named in #discovery_skips.
    #   verses      53,898 rows — the occurrence's PASSAGES, never their own
    #               documents: urn <occurrence urn>:<order_in_occurrence+1>
    #               (upstream's 0-based order, contiguous everywhere), the
    #               verse id and verse_group_id (upstream's cross-occurrence
    #               parallel grouping; 42,083 verses carry one) in the
    #               annotations. The 2 blank verse rows are honest gaps: no
    #               passage, numbering keeps upstream's order. The verses
    #               agree line for line with text_original on every
    #               occurrence (censused), so nothing is lost.
    #   type        5,226 rows — ACCEPTED as a document, urn
    #               urn:nabu:dbbe:type-<id>; passages = the lines of its
    #               normalized text_original (2 blank lines are gaps).
    #               Types with no occurrence (89) load too.
    #   type_translation 2,504 rows — ACCEPTED as sibling documents
    #               urn:nabu:dbbe:type-<id>-tr<translation id> (registry
    #               translations: true, the rundata -eng mold; `--parallel`
    #               pairs them through the siblings declaration), one
    #               passage per non-blank line. Languages: English 891,
    #               German 642, French 366, Latin 313, Italian 190, Dutch 80,
    #               Russian 9, Spanish 7, upstream "Greek" 4 + "Modern Greek"
    #               1, Hungarian 1. Upstream's "Greek" (code GR) rows are
    #               Modern Greek renderings (all four read: monotonic
    #               orthography, Modern vocabulary) → ell beside EL.
    #   manuscript  4,560 rows — NOT a document (no text of its own): its
    #               name, repository, place of origin, content, persons and
    #               catalogue ids (Diktyon …) ride every occurrence it holds.
    #   person      3,726 rows — NOT a document: historical persons ride
    #               their occurrence/type/manuscript as role => names
    #               (Poet, Scribe, Patron, Owner, Illuminator, Related,
    #               Subject, Content); the database staff's own editorial
    #               roles are not carried (DbbeSqliteReader::HISTORICAL_ROLES).
    #   bibliography (article, book, book_chapter, blog, blog_post,
    #               bib_varia, online_source, phd) — NOT documents: citation
    #               records, named in the discovery notes, not carried.
    #
    # Reconciliation: 12,928 occurrence + 5,226 type + 2,504 translation
    # documents = 20,658 (translations on), 122 skipped by rule; the
    # first-sync passage total is in docs/02-sources.md row 441.
    #
    # == Metadata (the aggressive-mining rule)
    #
    # Occurrence: date = upstream's completion_date_floor/ceiling (ISO day
    # bounds; the copying date of the epigram in this manuscript, usually
    # the manuscript's date, sometimes finer) banded to years under "date"
    # (Store::TimelineBuilder::MetadataDates :structured; 12,892 of 12,928
    # dated, 501–1800); place = the manuscript's place of origin, leaf to
    # root ("Calabria, Southern Italy, Italy"; 2,357 occurrences), its
    # historical-name chain beside it; the holding library rides as
    # repository (a present location, metadata only — the rundata origin
    # stance). genre (upstream's six classes, scribe- … image-related),
    # metre, keywords, text status, the historical persons, the types it
    # witnesses (urns) and the poets those types name (authors — the
    # attribution of the text the occurrence carries), location in the
    # manuscript, the manuscript's catalogue ids and content, and
    # upstream's comments. Type: genre, metre, keywords, tags (the
    # epigram's function: "Praise of the author", "Prayer" …), text and
    # editorial status, persons (Poet → authors), its occurrences (urns of
    # the held ones), catalogue ids (Vassis incipit numbers, Rhoby …), the
    # critical apparatus and comments. Types carry no date of their own;
    # the poets' life dates are not projected onto them (attribution
    # dating would be inference, not upstream's claim). created/modified
    # timestamps and the occurrence-count columns are volatile bookkeeping
    # and are not carried (a weekly re-export would fake revisions).
    #
    # == License
    #
    # The Zenodo record's license field: "cc-zero" (CC0 1.0 Universal
    # Public Domain Dedication) → open. Credit (courtesy, not a condition):
    # the DBBE team, the record's creator list.
    #
    # == fetch
    #
    # Unattended: GET the concept record's latest-version API endpoint,
    # find dbbe_archive.sqlite with its published md5; if the file on disk
    # already has that md5, nothing is fetched. Otherwise one FileFetch of
    # the version's content URL, md5-verified against the record BEFORE the
    # tree mutates (a mismatch aborts with canonical/dbbe/ untouched), the
    # mass-deletion guard, then the write. Upstream republishes the file
    # (the latest record's file was replaced 2026-11-16), so each sync
    # re-reads the record. Nothing is materialized beside the archive (a
    # plain tree hashes whole; FileFetch's state file is its own); the
    # reader opens the file immutable, so no -wal/-shm ever appears.
    class Dbbe < Nabu::Adapter
      CONCEPT_RECORD = "19435533"
      RECORD_URL = "https://zenodo.org/records/#{CONCEPT_RECORD}".freeze
      LATEST_URL = "https://zenodo.org/api/records/#{CONCEPT_RECORD}/versions/latest".freeze
      FILENAME = "dbbe_archive.sqlite"
      URN_PREFIX = "urn:nabu:dbbe:"
      SITE = "https://www.dbbe.ugent.be"
      LANGUAGE = "grc"

      # upstream language.code => ISO 639-3. GR ("Greek") is Modern Greek
      # in every row that carries it (class note); "?" (Unknown) maps to
      # nothing — such a translation is unrecognized, never guessed.
      TRANSLATION_LANGUAGES = {
        "EN" => "eng", "DE" => "deu", "FR" => "fra", "LA" => "lat", "IT" => "ita", "NL" => "nld",
        "RU" => "rus", "ES" => "spa", "GR" => "ell", "EL" => "ell", "HU" => "hun", "BG" => "bul",
        "DA" => "dan", "PT" => "por", "PL" => "pol", "SV" => "swe"
      }.freeze

      ISO_DAY = /\A(\d{1,4})-\d{2}-\d{2}\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "dbbe",
        name: "Database of Byzantine Book Epigrams (DBBE, Ghent University) — archive",
        license: "CC0 1.0 Universal — the Zenodo record's license field, verbatim: \"cc-zero\" " \
                 "(concept record 19435533, \"Database of Byzantine Book Epigrams - Archive\")",
        license_class: "open",
        upstream_url: RECORD_URL,
        parser_family: "dbbe-sqlite",
        credit: "Database of Byzantine Book Epigrams (dbbe.ugent.be), Ghent University — Kristoffel " \
                "Demoen, Floris Bernard and the DBBE team; Database of Byzantine Book Epigrams - Archive, " \
                "Zenodo, doi:10.5281/zenodo.19435533"
      )

      def self.manifest = MANIFEST

      # A plain (non-git) tree hashes whole; nothing beside the archive.
      def self.materialized_paths = []

      # HEAD the latest-version endpoint: reachability; drift is read
      # against FileFetch's state pin.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: LATEST_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def self.occurrence_urn(id) = "#{URN_PREFIX}occurrence-#{id}"
      def self.type_urn(id) = "#{URN_PREFIX}type-#{id}"
      def self.translation_urn(type_id, id) = "#{type_urn(type_id)}-tr#{id}"

      # +translations+ arrives via SourceRegistry::Entry#build_adapter
      # (registry translations: true).
      def initialize(translations: false)
        super()
        @translations = translations
        @readers = {}
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = archive_path(workdir)
        return if path.nil?

        reader = reader_for(path)
        refs = reader.occurrence_census.select(&:textual).map do |row|
          ref(self.class.occurrence_urn(row.id), path, "record" => "occurrence", "dbbe_id" => row.id)
        end
        refs += reader.type_ids.map { |id| ref(self.class.type_urn(id), path, "record" => "type", "dbbe_id" => id) }
        refs += translation_refs(reader, path) if @translations
        refs.sort_by(&:id).each(&block)
      end

      # The textless occurrences are skipped by rule, one note each; a
      # translation in a language the map cannot code, and any other
      # *.sqlite file, is unrecognized. The record classes that are not
      # documents (manuscripts, persons, bibliography) are named in the
      # notes, uncounted — they ride as metadata or are not carried.
      def discovery_skips(workdir)
        return DiscoverySkips.new unless File.directory?(workdir)

        strays = Dir.glob("*.sqlite", base: workdir).sort - [FILENAME]
        notes = strays.map { |name| "#{name}: not the DBBE archive (#{FILENAME})" }
        path = archive_path(workdir)
        return DiscoverySkips.new(unrecognized: strays.size, notes: notes) if path.nil?

        reader = reader_for(path)
        textless = reader.occurrence_census.reject(&:textual)
        notes += textless.map do |row|
          "occurrence #{row.id}: no transcribed text (no text_original, no verses) — skipped by rule"
        end
        uncoded = @translations ? reader.translation_census.reject { |row| translation_language(row) } : []
        notes += uncoded.map do |row|
          "translation #{row.id} (type #{row.type_id}): language #{row.language_name.inspect} has no code"
        end
        notes << record_note(reader.record_counts)
        DiscoverySkips.new(skipped_by_rule: textless.size, unrecognized: strays.size + uncoded.size, notes: notes)
      end

      def parse(document_ref)
        reader = reader_for(document_ref.path)
        id = document_ref.metadata.fetch("dbbe_id")
        case document_ref.metadata.fetch("record")
        when "occurrence" then occurrence_document(reader, id, document_ref)
        when "type" then type_document(reader, id, document_ref)
        when "translation" then translation_document(reader, id, document_ref)
        else raise ParseError, "#{document_ref.path}: #{document_ref.id}: unknown record kind"
        end
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        release = latest_release
        target = File.join(workdir, FILENAME)
        return unchanged_report(target, release) if held_md5(target) == release[:md5]

        fetch = FileFetch.new(url: release[:url], dir: workdir, filename: FILENAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), http: http, progress: progress)
        fetch.prepare!
        verify_md5!(fetch, release)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        notes = ["#{release_label(release)}; md5 verified against the record", attic_notes(fetch.atticked)]
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: notes.compact.join("; "))
      rescue FileFetch::Error => e
        raise FetchError, "dbbe fetch failed into #{workdir}: #{e.message}"
      end

      private

      # -- discovery --------------------------------------------------------------

      def archive_path(workdir)
        path = File.join(workdir, FILENAME)
        File.file?(path) ? File.expand_path(path) : nil
      end

      def reader_for(path)
        @readers[path] ||= DbbeSqliteReader.new(path)
      end

      def ref(id, path, metadata)
        Nabu::DocumentRef.new(source_id: manifest.id, id: id, path: path, metadata: metadata)
      end

      def translation_refs(reader, path)
        reader.translation_census.filter_map do |row|
          next unless translation_language(row)

          ref(self.class.translation_urn(row.type_id, row.id), path,
              "record" => "translation", "dbbe_id" => row.id, "type_id" => row.type_id)
        end
      end

      def translation_language(row) = TRANSLATION_LANGUAGES[row.language_code.to_s.strip.upcase]

      def record_note(counts)
        "not documents: #{counts.fetch('manuscripts')} manuscripts and #{counts.fetch('persons')} persons " \
          "(their fields ride the occurrences and types as metadata), #{counts.fetch('bibliography')} " \
          "bibliography records (citations, not carried)"
      end

      # -- parse ------------------------------------------------------------------

      def occurrence_document(reader, id, document_ref)
        record = reader.occurrence(id) or raise ParseError, "#{document_ref.path}: no occurrence #{id}"
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: occurrence_title(record), metadata: occurrence_metadata(reader, record))
        record.verses.each do |verse|
          text = verse.text.to_s.strip
          next if text.empty?

          annotations = { "verse_id" => verse.id }
          annotations["verse_group"] = verse.verse_group_id if verse.verse_group_id
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{verse.order + 1}", language: LANGUAGE,
                                        text: Normalize.nfc(text), sequence: verse.order, annotations: annotations)
        end
        document
      end

      def occurrence_title(record)
        incipit = present(record.incipit) || present(record.verses.first&.text)
        where = [record.manuscript&.name, present(record.location_in_ms)].compact.join(", ")
        nfc(where.empty? ? incipit : "#{incipit} (#{where})")
      end

      def occurrence_metadata(reader, record)
        manuscript = record.manuscript
        authors = record.type_ids.flat_map { |tid| reader.type(tid)&.persons&.fetch("Poet", []) || [] }.uniq
        compact(
          "record" => "occurrence", "dbbe_id" => record.id, "url" => "#{SITE}/occurrences/#{record.id}",
          "incipit" => record.incipit, "title" => record.title, "location_in_ms" => record.location_in_ms,
          "date" => date_claim(record.date_floor, record.date_ceiling),
          "place" => manuscript&.origin&.join(", "),
          "place_historical" => manuscript&.origin_historical,
          "manuscript" => manuscript&.name,
          "manuscript_url" => manuscript && "#{SITE}/manuscripts/#{manuscript.id}",
          "manuscript_date" => manuscript && raw_interval(manuscript.date_floor, manuscript.date_ceiling),
          "manuscript_identifiers" => manuscript&.identifiers, "manuscript_content" => manuscript&.content,
          "manuscript_persons" => manuscript&.persons,
          "repository" => manuscript&.repository, "repository_place" => manuscript&.repository_place,
          "genre" => record.genres, "metre" => record.metres, "keywords" => record.keywords,
          "text_status" => record.text_status, "persons" => record.persons, "authors" => authors,
          "types" => record.type_ids.map { |tid| self.class.type_urn(tid) },
          "is_dbbe" => record.is_dbbe.nil? ? nil : record.is_dbbe == 1,
          "palaeographical_info" => record.palaeographical_info, "contextual_info" => record.contextual_info,
          "public_comment" => record.public_comment
        )
      end

      def type_document(reader, id, document_ref)
        record = reader.type(id) or raise ParseError, "#{document_ref.path}: no type #{id}"
        held = (@held ||= {})[reader] ||= reader.occurrence_census.select(&:textual).to_set(&:id)
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: type_title(record), metadata: type_metadata(record, held))
        record.text.to_s.split("\n").each_with_index do |line, index|
          text = line.strip
          next if text.empty?

          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE,
                                        text: Normalize.nfc(text), sequence: index)
        end
        document
      end

      def type_title(record)
        incipit = present(record.incipit) || present(record.text.to_s.lines.first)
        nfc("#{incipit} (type #{record.id})")
      end

      def type_metadata(record, held)
        compact(
          "record" => "type", "dbbe_id" => record.id, "url" => "#{SITE}/types/#{record.id}",
          "incipit" => record.incipit, "title" => record.title,
          "genre" => record.genres, "metre" => record.metres, "keywords" => record.keywords,
          "tags" => record.tags, "text_status" => record.text_status,
          "editorial_status" => record.editorial_status, "persons" => record.persons,
          "authors" => record.persons.fetch("Poet", []), "identifiers" => record.identifiers,
          "critical_apparatus" => record.critical_apparatus, "public_comment" => record.public_comment
        ).merge("occurrences" => record.occurrence_ids.select { |oid| held.include?(oid) }
                                                    .map { |oid| self.class.occurrence_urn(oid) })
      end

      def translation_document(reader, id, document_ref)
        record = reader.translation(id) or raise ParseError, "#{document_ref.path}: no translation #{id}"
        language = TRANSLATION_LANGUAGES.fetch(record.language_code.to_s.strip.upcase)
        type = reader.type(record.type_id) or raise ParseError, "#{document_ref.path}: no type #{record.type_id}"
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: "#{type_title(type)} — #{record.language_name} translation",
          metadata: { "kind" => "translation", "translation_of" => self.class.type_urn(record.type_id),
                      "dbbe_translation_id" => record.id, "translation_language" => record.language_name }
        )
        record.text.to_s.gsub("\r\n", "\n").tr("\r", "\n").split("\n").each_with_index do |line, index|
          text = line.strip
          next if text.empty?

          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{index + 1}", language: language,
                                        text: Normalize.nfc(text), sequence: index)
        end
        document
      end

      # {"not_before", "not_after", "raw"} from upstream's ISO day bounds,
      # or nil when neither parses.
      def date_claim(floor, ceiling)
        not_before = iso_year(floor)
        not_after = iso_year(ceiling)
        return nil if not_before.nil? && not_after.nil?

        { "not_before" => not_before, "not_after" => not_after, "raw" => raw_interval(floor, ceiling) }
      end

      def iso_year(value)
        match = ISO_DAY.match(value.to_s.strip)
        match && Integer(match[1], 10)
      end

      def raw_interval(floor, ceiling)
        raw = [floor, ceiling].map { |bound| bound.to_s.strip }
        raw.all?(&:empty?) ? nil : raw.join("/")
      end

      def present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def nfc(value) = value.is_a?(String) ? Normalize.nfc(value) : value

      # Drop nil / blank / empty values; NFC every string, recursively.
      def compact(hash)
        hash.each_with_object({}) do |(key, value), out|
          value = deep_nfc(value)
          next if value.nil? || (value.respond_to?(:empty?) && value.empty?)
          next if value.is_a?(String) && value.strip.empty?

          out[key] = value.is_a?(String) ? value.strip : value
        end
      end

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Array then value.map { |item| deep_nfc(item) }
        when Hash then value.transform_values { |item| deep_nfc(item) }
        else value
        end
      end

      # -- fetch ------------------------------------------------------------------

      def latest_release
        response, = RedirectFollow.get(LATEST_URL, http: http, error: FetchError)
        record = JSON.parse(response.body.to_s)
        file = Array(record["files"]).find { |entry| entry["key"] == FILENAME }
        if file.nil?
          raise FetchError, "dbbe: the latest version of record #{CONCEPT_RECORD} lists no #{FILENAME} — " \
                            "the deposit changed shape; re-derive the archive by hand"
        end

        { record_id: record["id"], published: record.dig("metadata", "publication_date"),
          md5: file["checksum"].to_s.delete_prefix("md5:"), url: file.dig("links", "self") }
      rescue JSON::ParserError => e
        raise FetchError, "dbbe: #{LATEST_URL} returned no JSON record (#{e.message})"
      end

      def held_md5(target) = File.file?(target) ? Digest::MD5.file(target).hexdigest : nil

      def release_label(release)
        "record #{release[:record_id]} (published #{release[:published]})"
      end

      def unchanged_report(target, release)
        Nabu::FetchReport.new(sha: Digest::SHA256.file(target).hexdigest, fetched_at: Time.now,
                              notes: "#{FILENAME} already current — #{release_label(release)}, md5 matches; " \
                                     "nothing fetched")
      end

      def verify_md5!(fetch, release)
        if fetch.not_modified?
          raise FetchError, "dbbe: #{release[:url]} answered 304 but the held file misses the record's md5 " \
                            "#{release[:md5]} — remove canonical/dbbe/#{FILENAME} and re-sync"
        end
        return if fetch.md5 == release[:md5]

        raise FetchError, "dbbe: the downloaded #{FILENAME} misses the record's md5 (expected " \
                          "#{release[:md5]}, got #{fetch.md5}) — nothing landed"
      end

      def http
        @http ||= FileFetch.default_http
      end
    end
  end
end
