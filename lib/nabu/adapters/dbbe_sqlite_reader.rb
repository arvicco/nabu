# frozen_string_literal: true

require "sqlite3"

module Nabu
  module Adapters
    # The dbbe-sqlite parser family: a READ-ONLY reader over
    # dbbe_archive.sqlite, the Database of Byzantine Book Epigrams'
    # "simplified structure" export (Ghent University, Zenodo concept record
    # 19435533). A standalone, individually tested component the Dbbe
    # adapter composes.
    #
    # == Convention scoping: the sqlite3 gem, not Sequel
    #
    # CLAUDE.md's "SQL only through Sequel datasets/models in
    # lib/nabu/store/" governs OUR databases (the catalog and its derived
    # siblings, whose schema we migrate). This file reads an UPSTREAM
    # canonical artifact that happens to be SQLite — the rundata-sqlite /
    # ganjoor precedent: the sqlite3 gem directly, read-only, at the adapter
    # boundary only.
    #
    # == Opened immutable
    #
    # Upstream ships the file with the WAL header bytes set (offsets 18/19 =
    # 2). A plain read-only open of a WAL database creates -wal/-shm files
    # BESIDE it — litter inside canonical/dbbe/ that would make the tree
    # drift on every parse. The archive never changes in place (fetch
    # replaces the whole file), so it opens with the SQLite URI flag
    # `immutable=1`: no locks, no side files, nothing written.
    #
    # == What it reads (the schema censused 2026-11-27)
    #
    # occurrence (+ verses, the per-verse rows in order_in_occurrence order
    # with their verse_group_id), type (+ type_translation + language),
    # type_occurrence (many-to-many), the genre / metre / keyword / tag /
    # text_status / editorial_status link tables, the *_person_role tables
    # joined to person and roles, manuscript (+ library, the hierarchical
    # location table via manuscript_location, manuscript_content over the
    # hierarchical content table) and identification (external catalogue
    # ids per entity). The *_management tables are internal workflow and
    # private_comment columns are internal notes (blank across the archive
    # as published, censused) — neither is ever selected.
    #
    # Values arrive VERBATIM — NFC is the adapter's boundary job. Damage
    # (not a database, a missing table) raises Nabu::ParseError naming the
    # file.
    class DbbeSqliteReader
      # The roles that name a HISTORICAL person's part in the epigram or
      # book. The rest of upstream's roles vocabulary (Creator, Contributor,
      # Transcriber, Editor, Supervisor, Translator, Author) credits the
      # database's own modern staff for a record — editorial provenance, not
      # a claim about the object — and is not carried.
      HISTORICAL_ROLES = %w[Poet Scribe Patron Owner Illuminator Related Subject Content].freeze

      # One census row: the occurrence id and whether it carries text.
      OccurrenceCensus = Data.define(:id, :textual)
      # One translation census row (the language row's own code and name).
      TranslationCensus = Data.define(:id, :type_id, :language_code, :language_name)

      Verse = Data.define(:id, :order, :text, :verse_group_id)
      Manuscript = Data.define(:id, :name, :date_floor, :date_ceiling, :repository, :repository_place,
                               :origin, :origin_historical, :content, :persons, :identifiers)
      Occurrence = Data.define(:id, :incipit, :title, :verses, :location_in_ms, :date_floor, :date_ceiling,
                               :palaeographical_info, :contextual_info, :public_comment, :is_dbbe,
                               :manuscript, :genres, :metres, :keywords, :text_status, :persons, :type_ids)
      Type = Data.define(:id, :incipit, :title, :text, :critical_apparatus, :public_comment, :genres,
                         :metres, :keywords, :tags, :text_status, :editorial_status, :persons,
                         :occurrence_ids, :identifiers)
      Translation = Data.define(:id, :type_id, :text, :language_code, :language_name)

      # file: URI with immutable=1 (class note); the path's URI-reserved
      # characters percent-encoded.
      def self.immutable_uri(path)
        escaped = File.expand_path(path).gsub(/[%?#]/) { |char| format("%%%02X", char.ord) }
        "file:#{escaped}?immutable=1"
      end

      def initialize(path)
        @path = path
        @db = nil
        @memo = {}
      end

      # Every occurrence, by id, with its text-bearing flag.
      def occurrence_census
        memo(:occurrence_census) do
          query("SELECT id, text_original FROM occurrence ORDER BY id").map do |row|
            OccurrenceCensus.new(id: row["id"], textual: !blank?(row["text_original"]))
          end
        end
      end

      def type_ids
        memo(:type_ids) { query("SELECT id FROM type ORDER BY id").map { |row| row["id"] } }
      end

      def translation_census
        memo(:translation_census) do
          query(<<~SQL).map { |row| translation_census_row(row) }
            SELECT t.id, t.type_id, l.code, l.name
            FROM type_translation t LEFT JOIN language l ON l.id = t.language_id
            ORDER BY t.id
          SQL
        end
      end

      # Row counts of the non-document record classes (the discovery census
      # notes): manuscripts, persons, and every bibliography table.
      def record_counts
        memo(:record_counts) do
          bibliography = %w[article book book_chapter blog blog_post bib_varia online_source phd]
          { "manuscripts" => count("manuscript"), "persons" => count("person"),
            "bibliography" => bibliography.sum { |table| count(table) } }
        end
      end

      def occurrence(id)
        row = occurrence_rows[id]
        return nil if row.nil?

        Occurrence.new(
          id: id, incipit: row["incipit"], title: row["title"], verses: verses.fetch(id, []),
          location_in_ms: row["location_in_ms"], date_floor: row["completion_date_floor"],
          date_ceiling: row["completion_date_ceiling"], palaeographical_info: row["palaeographical_info"],
          contextual_info: row["contextual_info"], public_comment: row["public_comment"],
          is_dbbe: row["is_dbbe"], manuscript: manuscript(row["manuscript_id"]),
          genres: labels("occurrence_genre", "occurrence_id", "genre", "genre_id")[id] || [],
          metres: labels("occurrence_metre", "occurrence_id", "metre", "metre_id")[id] || [],
          keywords: labels("occurrence_keyword", "occurrence_id", "keyword", "keyword_id")[id] || [],
          text_status: labels("occurrence_text_status", "occurrence_id", "text_status", "text_status_id")[id]&.first,
          persons: persons("occurrence_person_role", "occurrence_id")[id] || {},
          type_ids: types_by_occurrence[id] || []
        )
      end

      def type(id)
        row = type_rows[id]
        return nil if row.nil?

        Type.new(
          id: id, incipit: row["incipit"], title: row["title"], text: row["text_original"],
          critical_apparatus: row["critical_apparatus"], public_comment: row["public_comment"],
          genres: labels("type_genre", "type_id", "genre", "genre_id")[id] || [],
          metres: labels("type_metre", "type_id", "metre", "metre_id")[id] || [],
          keywords: labels("type_keyword", "type_id", "keyword", "keyword_id")[id] || [],
          tags: labels("type_tag", "type_id", "tag", "tag_id")[id] || [],
          text_status: labels("type_text_status", "type_id", "text_status", "text_status_id")[id]&.first,
          editorial_status: labels("type_editorial_status", "type_id", "editorial_status",
                                   "editorial_status_id")[id]&.first,
          persons: persons("type_person_role", "type_id")[id] || {},
          occurrence_ids: occurrences_by_type[id] || [], identifiers: identifiers("type")[id] || {}
        )
      end

      def translation(id)
        census = memo(:translation_index) { translation_census.to_h { |row| [row.id, row] } }[id]
        return nil if census.nil?

        text = query("SELECT translation FROM type_translation WHERE id = ?", [id]).first&.fetch("translation")
        Translation.new(id: id, type_id: census.type_id, text: text, language_code: census.language_code,
                        language_name: census.language_name)
      end

      private

      def translation_census_row(row)
        TranslationCensus.new(id: row["id"], type_id: row["type_id"], language_code: row["code"],
                              language_name: row["name"])
      end

      def occurrence_rows
        memo(:occurrence_rows) do
          query(<<~SQL).to_h { |row| [row["id"], row] }
            SELECT id, incipit, title, location_in_ms, completion_date_floor, completion_date_ceiling,
                   palaeographical_info, contextual_info, public_comment, is_dbbe, manuscript_id
            FROM occurrence
          SQL
        end
      end

      def type_rows
        memo(:type_rows) do
          query(<<~SQL).to_h { |row| [row["id"], row] }
            SELECT id, incipit, title, text_original, critical_apparatus, public_comment FROM type
          SQL
        end
      end

      # occurrence_id => [Verse] in upstream order (whole table, ~54k rows).
      def verses
        memo(:verses) do
          rows = query("SELECT id, occurrence_id, order_in_occurrence, text, verse_group_id FROM verses " \
                       "ORDER BY occurrence_id, order_in_occurrence, id")
          rows.group_by { |row| row["occurrence_id"] }.transform_values do |group|
            group.map do |row|
              Verse.new(id: row["id"], order: row["order_in_occurrence"], text: row["text"],
                        verse_group_id: row["verse_group_id"])
            end
          end
        end
      end

      def types_by_occurrence
        memo(:types_by_occurrence) { type_links.group_by(&:last).transform_values { |pairs| pairs.map(&:first) } }
      end

      def occurrences_by_type
        memo(:occurrences_by_type) { type_links.group_by(&:first).transform_values { |pairs| pairs.map(&:last) } }
      end

      def type_links
        memo(:type_links) do
          query("SELECT type_id, occurrence_id FROM type_occurrence ORDER BY type_id, occurrence_id")
            .map { |row| [row["type_id"], row["occurrence_id"]] }
        end
      end

      # owner id => [label names] for one link table, in label-id order.
      def labels(link_table, owner_key, label_table, label_key)
        memo([:labels, link_table]) do
          query(<<~SQL).group_by { |row| row["owner"] }.transform_values { |rows| rows.map { |row| row["name"] } }
            SELECT x.#{owner_key} AS owner, l.name AS name
            FROM #{link_table} x JOIN #{label_table} l ON l.id = x.#{label_key}
            ORDER BY x.#{owner_key}, l.id
          SQL
        end
      end

      # owner id => { role => [person names] } — historical roles only, in
      # role-name then person-id order.
      def persons(link_table, owner_key)
        memo([:persons, link_table]) do
          rows = query(<<~SQL)
            SELECT x.#{owner_key} AS owner, r.name AS role, p.first_name, p.last_name
            FROM #{link_table} x JOIN roles r ON r.id = x.role_id JOIN person p ON p.id = x.person_id
            ORDER BY x.#{owner_key}, r.name, p.id
          SQL
          rows.select { |row| HISTORICAL_ROLES.include?(row["role"]) }
              .group_by { |row| row["owner"] }
              .transform_values { |owned| role_map(owned) }
        end
      end

      def role_map(rows)
        rows.each_with_object({}) do |row, roles|
          name = [row["first_name"], row["last_name"]].map { |part| part.to_s.strip }.reject(&:empty?).join(" ")
          next if name.empty?

          (roles[row["role"]] ||= []) << name unless roles[row["role"]]&.include?(name)
        end
      end

      # entity id => { catalogue => [catalogue ids] } for one entity type.
      def identifiers(entity_type)
        memo([:identifiers, entity_type]) do
          query("SELECT entity_id, catalogue, catalogue_id FROM identification WHERE entity_type = ? " \
                "ORDER BY entity_id, catalogue, id", [entity_type])
            .group_by { |row| row["entity_id"] }
            .transform_values do |rows|
              rows.each_with_object({}) { |row, ids| (ids[row["catalogue"]] ||= []) << row["catalogue_id"].to_s }
            end
        end
      end

      def manuscript(id)
        return nil if id.nil?

        key = id.is_a?(Integer) ? id : Integer(id.to_s, 10) # occurrence.manuscript_id is TEXT upstream
        memo([:manuscript, key]) do
          row = manuscript_rows[key]
          row && build_manuscript(key, row)
        end
      rescue ArgumentError
        nil
      end

      def build_manuscript(id, row)
        library = library_rows[row["library_id"]]
        origin_id = manuscript_origins[id]
        Manuscript.new(
          id: id, name: row["name"], date_floor: row["completion_date_floor"],
          date_ceiling: row["completion_date_ceiling"], repository: library&.fetch("name"),
          repository_place: library && location_rows[library["location_id"]]&.fetch("name"),
          origin: location_chain(origin_id, "name"), origin_historical: location_chain(origin_id, "historical_name"),
          content: content_paths[id] || [], persons: persons("manuscript_person_role", "manuscript_id")[id] || {},
          identifiers: identifiers("manuscript")[id] || {}
        )
      end

      def manuscript_rows
        memo(:manuscript_rows) do
          query("SELECT id, name, completion_date_floor, completion_date_ceiling, library_id FROM manuscript")
            .to_h { |row| [row["id"], row] }
        end
      end

      def library_rows
        memo(:library_rows) { query("SELECT id, name, location_id FROM library").to_h { |row| [row["id"], row] } }
      end

      def location_rows
        memo(:location_rows) do
          query("SELECT id, name, historical_name, parent_id FROM location").to_h { |row| [row["id"], row] }
        end
      end

      def manuscript_origins
        memo(:manuscript_origins) do
          query("SELECT manuscript_id, origin_id FROM manuscript_location ORDER BY manuscript_id, origin_id")
            .each_with_object({}) { |row, origins| origins[row["manuscript_id"]] ||= row["origin_id"] }
        end
      end

      # Leaf → root names of one location (the hierarchical location
      # table), cycle-guarded; blank names drop out.
      def location_chain(id, column)
        chain = []
        seen = {}
        while id && (row = location_rows[id]) && !seen[id]
          seen[id] = true
          name = row[column].to_s.strip
          chain << name unless name.empty?
          id = row["parent_id"]
        end
        chain
      end

      # manuscript id => ["Biblica > Novum Testamentum", …] — the stored
      # leaf with its ancestors (the hierarchical content table).
      def content_paths
        memo(:content_paths) do
          names = query("SELECT id, parent_id, name FROM content").to_h { |row| [row["id"], row] }
          query("SELECT manuscript_id, content_id FROM manuscript_content ORDER BY manuscript_id, content_id")
            .group_by { |row| row["manuscript_id"] }
            .transform_values { |rows| rows.map { |row| content_path(names, row["content_id"]) }.reject(&:empty?) }
        end
      end

      def content_path(names, id)
        chain = []
        seen = {}
        while id && (row = names[id]) && !seen[id]
          seen[id] = true
          chain.unshift(row["name"].to_s.strip)
          id = row["parent_id"]
        end
        chain.reject(&:empty?).join(" > ")
      end

      def count(table)
        query("SELECT COUNT(*) AS n FROM #{table}").first.fetch("n")
      end

      def blank?(value) = value.to_s.strip.empty?

      def memo(key)
        return @memo[key] if @memo.key?(key)

        @memo[key] = yield
      end

      def query(sql, params = [])
        db.execute(sql, params)
      rescue SQLite3::Exception => e
        raise ParseError, "#{@path}: #{e.message}"
      end

      def db
        @db ||= begin
          raise ParseError, "#{@path}: no such file" unless File.file?(@path)

          flags = SQLite3::Constants::Open::READONLY | SQLite3::Constants::Open::URI
          SQLite3::Database.new(self.class.immutable_uri(@path), flags: flags, results_as_hash: true)
        rescue SQLite3::Exception => e
          raise ParseError, "#{@path}: #{e.message}"
        end
      end
    end
  end
end
