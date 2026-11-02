# frozen_string_literal: true

require "sqlite3"

module Nabu
  module Adapters
    # The ganjoor-sqlite parser family: a READ-ONLY reader over the
    # Ganjoor desktop release database (ganjoor.s3db, the one file inside
    # the github.com/ganjoor/desktop release zip) — the bulk carrier of the
    # Ganjoor Persian poetry library. A standalone, individually tested
    # component the Ganjoor adapter composes.
    #
    # Like RundataSqliteParser, it reads an UPSTREAM canonical artifact
    # that happens to be SQLite (the schema is Ganjoor's; the file lives
    # under canonical/ and is never written), so the sqlite3 gem is used
    # directly, readonly, at the adapter boundary — CLAUDE.md's Sequel
    # rule governs the databases we own.
    #
    # == The schema (release 1405-07-03 = 2026-09-25, census 2026-11-02)
    #
    # - poet (id, name, cat_id, description) — 281 rows; cat_id is the
    #   poet's root category. No dates, no places: those live on the
    #   site's poets endpoint (the adapter's sidecar).
    # - cat (id, poet_id, text, parent_id, url) — 2,511 rows; the work /
    #   section tree under each poet (parent_id 0 = the poet's root).
    # - poem (id, cat_id, title, url) — 140,497 rows; Ganjoor's own ids.
    # - verse (poem_id, vorder, position, text) — 3,223,069 rows, one per
    #   HEMISTICH (or paragraph) in vorder; UNIQUE (poem_id, vorder).
    # - fav, gil, gver, poemsnd, sndsync — the desktop application's
    #   bookmarks / filter / schema-version / recitation-audio tables:
    #   empty in the release (gver holds the schema version, 3). Never read.
    #
    # == The verse positions and the passage unit
    #
    # Ganjoor's VersePosition codes (census of all 3,223,069 rows):
    #   0 right hemistich (1,517,913)   1 left hemistich (1,517,837)
    #   2 centered line 1 (13,561)      3 centered line 2 (7,329)
    #   4 single line — free verse (78,652)
    #  -1 paragraph — prose (86,067)
    #   5 comment — an editorial note, not text (1,710)
    # The passage unit is the COUPLET (bayt — the unit Ganjoor counts and
    # cites): a 0 opens a couplet a following 1 closes; a 2 opens a
    # centered couplet (the band of a tarjiʿ/tarkib or musammat) a
    # following 3 closes; an unpaired hemistich stands as a one-hemistich
    # unit. A 4 is its own line unit, a -1 its own prose unit. Comments
    # are collected apart (the adapter carries them as document metadata);
    # blank rows (empty, or holding only a no-break space, ZWNJ or control byte) are counted and dropped — a
    # missing hemistich is an honest absence. Any other position code is
    # upstream drift: ParseError, never a guess.
    #
    # Values arrive VERBATIM — NFC is the adapter's boundary job.
    class GanjoorSqliteParser
      POSITIONS = {
        0 => :right, 1 => :left, 2 => :center1, 3 => :center2,
        4 => :single, -1 => :paragraph, 5 => :comment
      }.freeze

      # Which opener a closer completes.
      CLOSES = { 1 => 0, 3 => 2 }.freeze

      # A row is text only if it carries a visible character: rows holding
      # nothing but a no-break space, a ZWNJ or a control byte (5 in the
      # whole release — poems 51262, 78294, 88157, 105811, 501256) are
      # blank, exactly like empty ones.
      VISIBLE = /[^\p{Z}\p{C}]/
      EDGE_SPACE = /\A[\s\p{Z}]+|[\s\p{Z}]+\z/

      Poet = Data.define(:id, :name, :cat_id, :description)
      Cat = Data.define(:id, :poet_id, :text, :parent_id, :url)
      Poem = Data.define(:id, :cat_id, :title, :url)

      # One passage unit: +form+ is :couplet (0/1), :band (2/3), :line (4)
      # or :prose (-1); +lines+ the verbatim hemistich texts (one for a
      # line/prose unit or an unpaired hemistich); +vorders+ their rows.
      Unit = Data.define(:form, :lines, :vorders)

      # One poem's content: units in vorder, the comment texts, and the
      # blank-row count.
      Record = Data.define(:units, :comments, :blank_rows)

      def initialize(path)
        @path = path
        @db = SQLite3::Database.new(path, readonly: true)
        @db.results_as_hash = false
      rescue SQLite3::Exception => e
        raise Nabu::ParseError, "#{path}: not a readable Ganjoor database: #{e.message}"
      end

      attr_reader :path

      def close
        @db.close
      end

      # id => Poet.
      def poets
        @poets ||= query("SELECT id, name, cat_id, description FROM poet ORDER BY id")
                   .to_h { |row| [row[0], Poet.new(*row)] }
      end

      # id => Cat (the whole tree — 2,511 rows).
      def cats
        @cats ||= query("SELECT id, poet_id, text, parent_id, url FROM cat ORDER BY id")
                  .to_h { |row| [row[0], Cat.new(*row)] }
      end

      # Every poem in Ganjoor id order.
      def each_poem
        return enum_for(:each_poem) unless block_given?

        query("SELECT id, cat_id, title, url FROM poem ORDER BY id").each { |row| yield Poem.new(*row) }
      end

      def poem(id)
        row = query("SELECT id, cat_id, title, url FROM poem WHERE id = ?", [id]).first
        row && Poem.new(*row)
      end

      # The category chain root → leaf for +cat_id+ (cycle-guarded).
      def cat_path(cat_id)
        chain = []
        seen = {}
        while (cat = cats[cat_id]) && !seen[cat.id]
          seen[cat.id] = true
          chain.unshift(cat)
          cat_id = cat.parent_id
        end
        chain
      end

      # The poet owning +cat_id+ (via the cat row), or nil.
      def poet_for_cat(cat_id)
        cat = cats[cat_id]
        cat && poets[cat.poet_id]
      end

      # Poem ids carrying at least one visible, non-comment row — one
      # streamed pass (~2 s over the whole release), so discovery honors
      # the empty-poem rule with the same VISIBLE test the grouping uses.
      def poem_ids_with_text
        @poem_ids_with_text ||= begin
          ids = Set.new
          @db.execute("SELECT poem_id, text FROM verse WHERE position <> 5") do |poem_id, text|
            ids << poem_id if !ids.include?(poem_id) && text.to_s.match?(VISIBLE)
          end
          ids
        rescue SQLite3::Exception => e
          raise Nabu::ParseError, "#{path}: #{e.message}"
        end
      end

      def record(poem_id)
        rows = query("SELECT vorder, position, text FROM verse WHERE poem_id = ? ORDER BY vorder", [poem_id])
        self.class.group(rows, label: "#{path}: poem #{poem_id}")
      end

      # The pure grouping rule (class note) over [vorder, position, text]
      # rows in vorder. Pairing is POSITIONAL: a blank row still holds its
      # slot (a blank left hemistich closes its couplet, a blank right one
      # opens the next), then blank lines drop and a unit left with no
      # line vanishes.
      def self.group(rows, label: "poem")
        units = []
        comments = []
        blanks = 0
        open = nil # [position, unit] of a couplet awaiting its closer
        rows.each do |vorder, position, text|
          raise Nabu::ParseError, "#{label}: unknown verse position #{position.inspect}" unless
            POSITIONS.key?(position)

          stripped = text.to_s.gsub(EDGE_SPACE, "")
          visible = stripped.match?(VISIBLE)
          if position == 5
            comments << stripped if visible
            next
          end
          blanks += 1 unless visible
          line = visible ? [[stripped, vorder]] : []
          if CLOSES.key?(position) && open && open[0] == CLOSES[position]
            open[1][:lines].concat(line)
            open = nil
            next
          end
          unit = { form: form_for(position), lines: line }
          units << unit
          open = [0, 2].include?(position) ? [position, unit] : nil
        end
        Record.new(units: units.reject { |u| u[:lines].empty? }.map { |u| unit_for(u) },
                   comments: comments, blank_rows: blanks)
      end

      def self.unit_for(fields)
        Unit.new(form: fields[:form], lines: fields[:lines].map(&:first), vorders: fields[:lines].map(&:last))
      end

      def self.form_for(position)
        case position
        when 0, 1 then :couplet
        when 2, 3 then :band
        when 4 then :line
        else :prose
        end
      end

      private

      def query(sql, binds = [])
        @db.execute(sql, binds)
      rescue SQLite3::Exception => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end
    end
  end
end
