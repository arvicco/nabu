# frozen_string_literal: true

require "sqlite3"

module Nabu
  module Adapters
    # The rundata-sqlite parser family (P40-6): a READ-ONLY reader over the
    # SQLite artifact Rundata-net ships to the browser
    # (runes.<hash>.sqlite3) — the bulk carrier of the Scandinavian
    # Runic-text Database (SRDB / Samnordisk runtextdatabas). A standalone,
    # individually tested component the Rundata adapter composes.
    #
    # == Convention scoping: why sqlite3 here and not Sequel in store/
    #
    # CLAUDE.md's "SQL only through Sequel datasets/models in
    # lib/nabu/store/" governs OUR databases — the catalog and its derived
    # siblings, whose schema we own and migrate. This file reads an
    # UPSTREAM canonical artifact that happens to be SQLite: the schema is
    # Rundata-net's (rundatanet/runes/models.py is authoritative), the file
    # lives under canonical/ and is never written. That is adapter-boundary
    # parsing — the same posture as Nokogiri over upstream TEI — so the
    # sqlite3 gem is used directly, `readonly: true`, at the adapter
    # boundary only. First precedent of an adapter reading a canonical
    # SQLite file (censused 2026-07-22: none prior; CorPH walks a MySQL
    # dump as TEXT).
    #
    # == What it reads
    #
    # - `signatures` (id, signature_text, parent_id): roots are
    #   inscriptions, children are alias signa (Bautil/Liljegren/KJ
    #   numbers — the JSON API's `aliases` list).
    # - `meta_information` (one row per inscription, signature_id UNIQUE):
    #   geography, BOTH WGS84 pairs, dating + year_from/year_to, style/
    #   carver/material/rune_type, the lost/new_reading/ornamental/recent
    #   booleans.
    # - The FIVE text lanes, one one-to-one table each:
    #   `transliterated_text` (run), `normalisation_norse` (fvn),
    #   `normalisation_scandinavian` (rsv), `translation_english` (eng),
    #   `translation_swedish` (swe). A missing or blank row is an honest
    #   absence. The `all_data` view is deliberately NOT used: its INNER
    #   JOINs drop inscriptions lacking a normalisation lane.
    # - `material_types` (materialType_id -> name), `meta_with_crosses_textual`
    #   (the Lager cross-form classification, rendered by upstream's own
    #   view), `meta_information_references` + `references` (bibliography
    #   text entries and stable links).
    #
    # Values arrive VERBATIM — NFC normalization is the adapter's boundary
    # job, not the reader's. Damage (not a database, missing tables) raises
    # Nabu::ParseError naming the file.
    class RundataSqliteParser
      # The lane tables, keyed by the JSON API's language_code vocabulary,
      # in the canonical lane order (transliteration first — it IS the
      # inscription's text).
      LANE_TABLES = {
        "run" => "transliterated_text",
        "fvn" => "normalisation_norse",
        "rsv" => "normalisation_scandinavian",
        "eng" => "translation_english",
        "swe" => "translation_swedish"
      }.freeze

      # The meta_information columns carried through (upstream's own names,
      # objectInfo included — verbatim vocabulary, translated nowhere).
      META_COLUMNS = %w[
        found_location parish district municipality current_location
        original_site parish_code rune_type dating style carver material
        objectInfo additional reference lost new_reading ornamental recent
        materialType_id year_from year_to latitude longitude
        present_latitude present_longitude
      ].freeze

      # One census entry: the inscription's signature row id, its signum
      # (signature_text, the natural id), and which lanes are present
      # (non-blank), in LANE_TABLES order.
      Inscription = Data.define(:signature_id, :signum, :lanes)

      # One full record: lanes maps lane code => verbatim text; meta is the
      # column => value hash (META_COLUMNS); aliases are the child signa in
      # id order; references are { "text", "kind", "label" } hashes;
      # crosses is upstream's textual cross-form rendering or nil.
      Record = Data.define(:signature_id, :signum, :lanes, :meta, :material_type,
                           :aliases, :references, :crosses)

      def initialize(path)
        @path = path
        @db = nil
      end

      # Every inscription (signature with a meta_information row), ordered
      # by signum. Without a block, returns an Enumerator.
      def each_inscription(&block)
        return enum_for(:each_inscription) unless block

        rows = query(<<~SQL)
          SELECT s.id AS signature_id, s.signature_text AS signum
          FROM meta_information m
          JOIN signatures s ON s.id = m.signature_id
        SQL
        rows.map { |row| census_entry(row) }
            .sort_by(&:signum)
            .each(&block)
      end

      # The full record for one signature id, or nil when the artifact
      # holds no such inscription.
      def record(signature_id)
        row = query("SELECT id, signature_text FROM signatures WHERE id = ?", [signature_id]).first
        return nil if row.nil? || meta_row(signature_id).nil?

        Record.new(
          signature_id: signature_id, signum: row["signature_text"],
          lanes: lane_values(signature_id), meta: meta_row(signature_id),
          material_type: material_type(signature_id), aliases: aliases(signature_id),
          references: references(signature_id), crosses: crosses(signature_id)
        )
      end

      private

      def census_entry(row)
        id = row["signature_id"]
        lanes = LANE_TABLES.keys.select { |lane| lane_index(lane).key?(id) }
        Inscription.new(signature_id: id, signum: row["signum"], lanes: lanes)
      end

      # signature_id => verbatim value for one lane table, whole-table and
      # memoized (the artifact holds ~6,800 rows per lane — small). Blank
      # values are dropped here, once: a lane row with only whitespace is
      # an honest absence everywhere downstream.
      def lane_index(lane)
        (@lane_index ||= {})[lane] ||= query(
          "SELECT signature_id, value FROM #{LANE_TABLES.fetch(lane)}"
        ).each_with_object({}) do |row, index|
          value = row["value"].to_s
          index[row["signature_id"]] = value unless value.strip.empty?
        end
      end

      def lane_values(signature_id)
        LANE_TABLES.keys.each_with_object({}) do |lane, lanes|
          value = lane_index(lane)[signature_id]
          lanes[lane] = value if value
        end
      end

      def meta_row(signature_id)
        (@meta ||= {})[signature_id] ||= query(
          "SELECT #{META_COLUMNS.join(', ')} FROM meta_information WHERE signature_id = ?",
          [signature_id]
        ).first&.slice(*META_COLUMNS)
      end

      def material_type(signature_id)
        type_id = meta_row(signature_id)["materialType_id"]
        return nil if type_id.nil?

        query("SELECT name FROM material_types WHERE id = ?", [type_id]).first&.fetch("name", nil)
      end

      def aliases(signature_id)
        query(
          "SELECT signature_text FROM signatures WHERE parent_id = ? ORDER BY id",
          [signature_id]
        ).map { |row| row["signature_text"] }
      end

      def references(signature_id)
        rows = query(<<~SQL, [signature_id])
          SELECT r.text AS text, r.kind AS kind, r.label AS label
          FROM meta_information_references mr
          JOIN "references" r ON r.id = mr.reference_id
          JOIN meta_information m ON m.id = mr.metainformation_id
          WHERE m.signature_id = ?
          ORDER BY mr.id
        SQL
        rows.map { |row| row.slice("text", "kind", "label") }
      end

      # Upstream's own textual rendering of the Lager cross-form
      # classification (the meta_with_crosses_textual view), or nil.
      def crosses(signature_id)
        rows = query(<<~SQL, [signature_id])
          SELECT c.crosses_textual AS crosses_textual
          FROM meta_with_crosses_textual c
          JOIN meta_information m ON m.id = c.meta_id
          WHERE m.signature_id = ?
        SQL
        value = rows.first&.fetch("crosses_textual", nil).to_s
        value.strip.empty? ? nil : value
      end

      def query(sql, params = [])
        db.execute(sql, params)
      rescue SQLite3::Exception => e
        raise ParseError, "#{@path}: #{e.message}"
      end

      def db
        @db ||= begin
          raise ParseError, "#{@path}: no such file" unless File.file?(@path)

          SQLite3::Database.new(@path, readonly: true, results_as_hash: true)
        end
      end
    end
  end
end
