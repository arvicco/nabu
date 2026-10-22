# frozen_string_literal: true

require_relative "../normalize"
require_relative "../slp1"

module Nabu
  module Adapters
    # The entry-to-entry edges of the Monier-Williams parse that need the
    # WHOLE file before they can be minted (a pointer may run forward to a
    # record not yet read): a collector the MwXmlParser feeds one grouped
    # entry at a time (#observe), then asks for each entry's extra
    # crossrefs (#crossrefs) once every record id is known. One edge family,
    # on the house crossref seam (Nabu::DictionaryCrossref,
    # the AED vocabulary), id-keyed so the loader resolves them on entry_id
    # exactly:
    #
    # == phw parent/child ties ("contains" / "partOf")
    #
    # Cologne manufactures an entry for every headword MW prints
    # PARENTHETICALLY inside another (mw-meta2.txt): <info phwchild="LC"/>
    # sits in the parent record, <info phwparent="LP,HWP"/> in the child.
    # Both name RECORD ids; a record may be a lettered continuation of its
    # entry (an H2B gender block), so ids are mapped onto the grouped
    # entry's id. The parent's pointer displays the child's own headword;
    # the child's displays the HWP upstream names (the record's key — the
    # parenthetical's real context). A tie naming a record id that does
    # not exist upstream mints nothing — never a guess at the intended one.
    #
    # Census over the full mw.xml (2026-10-22): 2,375 phwchild and 2,362
    # phwparent attributes upstream mint 2,363 "contains" and 2,313 "partOf"
    # pointers, every one landing on an existing entry. Not minted: 11
    # phwchild ids that name no record (upstream typos such as 91949.2,
    # 95539.11), one phwparent with no comma ("933543.1duHsampAdya"), and
    # the repeats — one duplicated phwchild, 48 phwparent ties a child
    # entry's continuation records (inflected-form H?C blocks) restate.
    class MwEntryLinks
      # One observed entry: its id and its raw phw ties.
      Seen = Data.define(:entry_id, :children, :parents)
      private_constant :Seen

      def initialize
        @record_entry = {}
        @record_key = {}
        @seen = {}
        @order = []
      end

      # Record one grouped entry (the parser's record hashes: tag, key1, l,
      # body).
      def observe(group)
        main = group.first
        entry_id = main[:l]
        group.each do |record|
          @record_entry[record[:l]] = entry_id
          @record_key[record[:l]] = record[:key1]
        end
        @seen[entry_id] = build_seen(group, entry_id)
        @order << entry_id
      end

      # entry_id => [DictionaryCrossref] for every entry that gains edges.
      # Call once, after the last #observe.
      def crossrefs
        @order.each_with_object({}) do |entry_id, out|
          edges = phw_edges(@seen.fetch(entry_id))
          out[entry_id] = edges unless edges.empty?
        end
      end

      private

      def build_seen(group, entry_id)
        infos = group.flat_map { |record| record[:body].xpath(".//info") }
        Seen.new(
          entry_id: entry_id,
          children: infos.filter_map { |info| info["phwchild"] }.uniq,
          parents: infos.filter_map { |info| info["phwparent"]&.split(",", 2) }.uniq
        )
      end

      # Ties whose record id does not exist upstream are skipped.
      def phw_edges(seen)
        contains = seen.children.filter_map do |child|
          edge("contains", iast(@record_key[child]), @record_entry[child]) if @record_entry.key?(child)
        end
        part_of = seen.parents.filter_map do |parent, key|
          edge("partOf", iast(key) || iast(@record_key[parent]), @record_entry[parent]) if @record_entry.key?(parent)
        end
        contains + part_of
      end

      def edge(kind, target, target_id)
        Nabu::DictionaryCrossref.new(kind: kind, label: "#{kind} #{target}", target: target,
                                     target_id: target_id)
      end

      def iast(slp1)
        return nil if slp1.nil? || slp1.empty?

        Nabu::Normalize.nfc(Nabu::Slp1.to_iast(slp1))
      end
    end
  end
end
