# frozen_string_literal: true

require_relative "../normalize"
require_relative "../slp1"

module Nabu
  module Adapters
    # The entry-to-entry edges of the Monier-Williams parse that need the
    # WHOLE file before they can be minted (a pointer may run forward to a
    # record not yet read): a collector the MwXmlParser feeds one grouped
    # entry at a time (#observe), then asks for each entry's extra
    # crossrefs (#crossrefs) once every record id is known. Two edge
    # families, both on the house crossref seam (Nabu::DictionaryCrossref,
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
    # == Root families ("root")
    #
    # Member → root pointers, never the reverse (a root like √kṛ heads
    # hundreds; the family is the set of pointers AT the root):
    #   * MW prints a root as an H1 record carrying <info verb="root"> or
    #     verb="genuineroot", followed by its primary derivatives as H2
    #     sub-headwords until the next H1 — each such H2 points at the root,
    #     id-keyed. H3/H4 compounds belong to their H2 head, not to the
    #     root's family, and the derivatives of a PREFIXED verb are its own
    #     block, not the bare root's (deliberate coarseness: one hop, MW's
    #     own hierarchy only).
    #   * A prefixed verb (<info verb="pre|gati" parse="ud+lI"/>, printed
    #     ul-√lī — the √ marks the root inside the compound headword) points
    #     at the parse's last member, looked up among ROOT entries only by
    #     key. Homonym roots share a key (√1.as "be", √2.as "throw"); the √
    #     mark then carries the number (<s>aDy-</s>√ <hom>2.</hom> <s>as</s>),
    #     matched against the root entry's own <hom>. Exactly one candidate →
    #     id-keyed; otherwise a display-only pointer, never a fold match
    #     that could land on a noun homograph.
    #
    # Root census (full mw.xml, 2026-10-22): 2,226 root entries (H1,
    # verb root/genuineroot; 187 keys carry homonym roots); 16,429 "root"
    # pointers — 10,083 H2 derivatives (all id-keyed) and 6,346 prefixed
    # verbs, 4,805 of them resolved to one root (542 thanks to the √-mark
    # homonym number) and 1,541 left display-only (a homonym root the mark
    # does not number, or no root entry under the parse's key). 1,240 roots
    # head a family of at least one member (√bhū largest, 283).
    #
    # phw census (full mw.xml, 2026-10-22): 2,375 phwchild and 2,362
    # phwparent attributes upstream mint 2,363 "contains" and 2,313 "partOf"
    # pointers, every one landing on an existing entry. Not minted: 11
    # phwchild ids that name no record (upstream typos such as 91949.2,
    # 95539.11), one phwparent with no comma ("933543.1duHsampAdya"), and
    # the repeats — one duplicated phwchild, 48 phwparent ties a child
    # entry's continuation records (inflected-form H?C blocks) restate.
    class MwEntryLinks
      ROOT_VERBS = %w[root genuineroot].freeze
      PREFIXED_VERBS = %w[pre gati].freeze

      # One observed entry: its id, MW level (1-4), whether it is a root,
      # the root key (and √-mark homonym number) a prefixed verb names, and
      # its raw phw ties.
      Seen = Data.define(:entry_id, :level, :root, :root_key, :root_hom, :children, :parents)
      private_constant :Seen

      def initialize
        @record_entry = {}
        @record_key = {}
        @roots_by_key = Hash.new { |hash, key| hash[key] = [] }
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
        seen = build_seen(group, main, entry_id)
        @roots_by_key[main[:key1]] << [entry_id, main[:hom].to_s] if seen.root
        @seen[entry_id] = seen
        @order << entry_id
      end

      # entry_id => [DictionaryCrossref] for every entry that gains edges.
      # Call once, after the last #observe.
      def crossrefs
        current_root = nil
        @order.each_with_object({}) do |entry_id, out|
          seen = @seen.fetch(entry_id)
          current_root = seen.root ? entry_id : nil if seen.level == 1
          edges = phw_edges(seen) + root_edges(seen, current_root)
          out[entry_id] = edges unless edges.empty?
        end
      end

      private

      def build_seen(group, main, entry_id)
        infos = group.flat_map { |record| record[:body].xpath(".//info") }
        verb_info = main[:body].at_xpath(".//info[@verb]")
        verb = verb_info && verb_info["verb"]
        root_key = (verb_info["parse"].to_s.split("+").last if PREFIXED_VERBS.include?(verb))
        Seen.new(
          entry_id: entry_id, level: main[:tag][1].to_i,
          root: main[:tag] == "H1" && ROOT_VERBS.include?(verb),
          root_key: root_key.to_s.empty? ? nil : root_key,
          root_hom: root_key && root_mark_hom(main[:body]),
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

      def root_edges(seen, current_root)
        if seen.level == 2 && current_root
          [edge("root", iast(@record_key[current_root]), current_root)]
        elsif seen.root_key
          [edge("root", iast(seen.root_key), root_entry(seen.root_key, seen.root_hom))]
        else
          []
        end
      end

      # The one root entry a prefixed verb names, or nil.
      def root_entry(key, hom)
        roots = @roots_by_key.fetch(key, [])
        roots = roots.select { |_id, root_hom| root_hom == hom } if hom && roots.size > 1
        roots.size == 1 ? roots.first.first : nil
      end

      # The homonym number printed right after the √ mark of the headword
      # echo — the mark directly follows the echo's prefix <s> ("<s>aDy-</s>√
      # <hom>2.</hom> <s>as</s>"); a √ later in the body is etymology, never
      # read — as the root entry's <hom> spells it ("2"); nil when the mark
      # carries none.
      def root_mark_hom(body)
        mark = body.at_xpath("s")&.next_sibling
        return nil unless mark&.text? && mark.text.include?("√")

        following = mark.next_sibling
        following = following.next_sibling while following&.text? && following.text.strip.empty?
        return nil unless following&.element? && following.name == "hom"

        following.text.strip.delete_suffix(".")
      end

      # An id-keyed pointer; a nil +target_id+ leaves a display-only one (no
      # resolution key at all — the loader never fold-matches it).
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
