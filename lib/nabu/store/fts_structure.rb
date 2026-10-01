# frozen_string_literal: true

module Nabu
  module Store
    # The fts5 structure-record reader (P112-3, Q114) — the gauge behind
    # the index health probes and `nabu index doctor`.
    #
    # Why it exists (the 2026-10-01 wedge, P111-1c): fts5 hard-caps TOTAL
    # segments at 2000 (fts5AllocateSegid returns SQLITE_FULL — which
    # renders as "database or disk is full"), crisismerge silently clamps
    # to 1999 PER LEVEL, and nothing in SQLite's public surface reports
    # the live count — the live index was measured at exactly 2000/2000
    # and write-wedged (even merge commands need a segment allocation).
    # These gauges make segment pressure visible long before the cap.
    #
    # Format (fts5_index.c, fts5StructureDecode; verified against 3.53.2
    # during the incident and pinned by behavioral tests): the record is
    # row id=10 of the shadow table <name>_data —
    #   4-byte big-endian cookie
    #   optional V2 marker "\xFF\x00\x00\x01" (FTS5_STRUCTURE_V2 —
    #     present on contentless_delete tables)
    #   varint nLevel · varint nSegment (total) · varint nWriteCounter
    #   per level: varint nMerge · varint nSeg
    #     per segment: varint iSegid · varint pgnoFirst · varint pgnoLast
    #       (+V2: varint iOrigin1 · varint iOrigin2 · varint nPgTombstone ·
    #        varint nEntryTombstone · varint nEntry — the 3.44 contentless-
    #        delete bookkeeping, fitted against live records at 0/1/2/3
    #        segments and across a delete)
    # Raw-bytes parsing of a shadow table is the standing raw-read
    # exception (the CREATE_TABLE DDL precedent): fts5 exposes no SQL
    # surface for this record.
    module FtsStructure
      STRUCTURE_ROWID = 10
      V2_MARKER = "\xFF\x00\x00\x01".b

      # The health thresholds against the hard cap of 2000 (P111-1c):
      # warn with ample runway, call anomaly while a plain sync can still
      # consolidate.
      SEGMENT_WARN = 1200
      SEGMENT_ANOMALY = 1600

      Structure = Data.define(:cookie, :v2, :write_counter, :levels, :total_segments) do
        def v2? = v2

        def tombstone_pages
          levels.sum { |level| level[:segments].sum { |seg| seg[:tombstone_pages] } }
        end

        def pages
          levels.sum do |level|
            level[:segments].sum { |seg| seg[:pgno_last] - seg[:pgno_first] + 1 }
          end
        end
      end

      module_function

      # Parse +table+'s structure record from +fulltext+, or nil when the
      # table (or its record) is absent.
      def read(fulltext, table)
        shadow = :"#{table}_data"
        return nil unless fulltext.table_exists?(shadow)

        blob = fulltext[shadow].where(id: STRUCTURE_ROWID).get(:block)
        return nil if blob.nil?

        decode(blob.to_s.b)
      end

      # The health summary: segment/page/tombstone counts plus the share
      # of pages that are tombstones (the deletemerge pressure gauge).
      def gauges(fulltext, table)
        structure = read(fulltext, table)
        return nil if structure.nil?

        pages = structure.pages
        tombstones = structure.tombstone_pages
        {
          segments: structure.total_segments,
          levels: structure.levels.size,
          pages: pages,
          tombstone_pages: tombstones,
          tombstone_share: pages.zero? ? 0.0 : tombstones.fdiv(pages)
        }
      end

      def decode(bytes)
        pos = 4 # cookie
        cookie = bytes[0, 4].unpack1("N")
        v2 = bytes[4, 4] == V2_MARKER
        pos += 4 if v2
        n_level, pos = varint(bytes, pos)
        n_segment, pos = varint(bytes, pos)
        write_counter, pos = varint(bytes, pos)
        levels = Array.new(n_level) do
          n_merge, pos = varint(bytes, pos)
          n_seg, pos = varint(bytes, pos)
          segments = Array.new(n_seg) do
            segid, pos = varint(bytes, pos)
            first, pos = varint(bytes, pos)
            last, pos = varint(bytes, pos)
            tombstones = entry_tombstones = entries = 0
            if v2
              _origin1, pos = varint(bytes, pos)
              _origin2, pos = varint(bytes, pos)
              tombstones, pos = varint(bytes, pos)
              entry_tombstones, pos = varint(bytes, pos)
              entries, pos = varint(bytes, pos)
            end
            { segid: segid, pgno_first: first, pgno_last: last, tombstone_pages: tombstones,
              entry_tombstones: entry_tombstones, entries: entries }
          end
          { merge: n_merge, segments: segments }
        end
        Structure.new(cookie: cookie, v2: v2, write_counter: write_counter,
                      levels: levels, total_segments: n_segment)
      end

      # SQLite varint: up to eight 7-bit high-bit-continued bytes, a ninth
      # byte carrying a full 8 bits. Returns [value, new_position].
      def varint(bytes, pos)
        value = 0
        8.times do |i|
          byte = bytes.getbyte(pos + i)
          return [(value << 7) | byte, pos + i + 1] if byte < 0x80

          value = (value << 7) | (byte & 0x7F)
        end
        [(value << 8) | bytes.getbyte(pos + 8), pos + 9]
      end
    end
  end
end
