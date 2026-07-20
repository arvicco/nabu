# frozen_string_literal: true

require_relative "../normalize"
require_relative "../adapters/ids_txt_parser"

module Nabu
  module Query
    # Character-structure search filters (P37-4): the explicit
    # `search --radical N | --strokes A-B | --char-component C` modes, kept
    # deliberately DISTINCT from text FTS (the survey's ruling — structure
    # search is a different question and must look different). Each option
    # resolves to a SET OF HAN CHARACTERS from the held char shelves; the
    # active options AND together (set intersection), and the result composes
    # with the text query and the ordinary passage filters as a
    # CHARACTER-LEVEL containment filter over Han-language passages: a passage
    # matches when it carries at least one character from the resolved set.
    #
    # == The honest composition (the design note)
    #
    # A text query answers "which passages carry this WORD/phrase"; a char
    # filter answers "which passages carry a character with this STRUCTURAL
    # property". They are different questions over the same passages, so they
    # compose by AND — `search 民 --char-component 心` is passages matching the
    # text query 民 that ALSO contain a 心-bearing character — and the char
    # filters never enter the FTS MATCH (folding a radical number into text
    # search would be a category error). The resolution is two-stage and
    # honest about scale: resolve the character set from the char shelves
    # (small, indexed by headword), then test passage membership by
    # containment. At fixture/research scale the membership test scans the
    # candidate passages (an FTS-narrowed page when a text query is present,
    # else the Han-language passages); a character-posting index is the
    # production optimization, named but not built (v1).
    #
    # == --char-component: the containment union (where the two new sources compose)
    #
    # "Contains C anywhere in its structure" = the KRADFILE flat index (kanji
    # whose component list names C — the ~6,355 JIS kanji Jisho searches) ∪
    # the BabelStone IDS TRANSITIVE containment (every character whose IDS
    # decomposition reaches C through component-of-a-component, the full
    # 97,680-entry repertoire KRADFILE cannot span). The IDS half is computed
    # by walking the reverse component graph up from C.
    class CharFilter
      # The resolved filter: the glyph set + human labels for the footer, or
      # nil chars when no structural option was given.
      Resolved = Data.define(:chars, :labels) do
        def active? = !chars.nil?
        def empty? = chars&.empty?
      end

      def initialize(catalog:)
        @catalog = catalog
      end

      def shelf? = @catalog.table_exists?(:dictionary_entries)

      # Resolve the active options to one glyph Set (intersection) + labels.
      # Any option nil = not active; none active = Resolved with chars nil.
      def resolve(radical: nil, strokes: nil, component: nil)
        return Resolved.new(chars: nil, labels: []) unless shelf?

        sets = []
        labels = []
        if radical
          sets << by_radical(radical)
          labels << "radical #{radical}"
        end
        if strokes
          low, high = strokes
          sets << by_strokes(low, high)
          labels << (low == high ? "#{low} strokes" : "#{low}-#{high} strokes")
        end
        if component
          component = Nabu::Normalize.nfc(component)
          sets << containing(component)
          labels << "contains #{component}"
        end
        return Resolved.new(chars: nil, labels: []) if sets.empty?

        Resolved.new(chars: sets.reduce(:&), labels: labels)
      end

      private

      # -- radical / strokes over Unihan -----------------------------------------

      # Characters whose PRIMARY KangXi radical (first kRSUnicode value) is N.
      def by_radical(number)
        number = number.to_i
        unihan_entries("kRSUnicode").each_with_object(Set.new) do |(headword, value), set|
          primary = value.split(/\s+/).first.to_s.split(".").first
          set << headword if primary.to_i == number
        end
      end

      # Characters whose total stroke count (first kTotalStrokes value) is in
      # the inclusive [low, high] range.
      def by_strokes(low, high)
        unihan_entries("kTotalStrokes").each_with_object(Set.new) do |(headword, value), set|
          strokes = value.split(/\s+/).first.to_i
          set << headword if strokes.between?(low, high)
        end
      end

      # [headword, field-value] for every Unihan entry carrying +field+.
      def unihan_entries(field)
        entry_rows("unihan", "%#{field}: %").filter_map do |headword, body|
          value = body.lines.map(&:chomp).find { |l| l.start_with?("#{field}: ") } or next
          [headword, value.delete_prefix("#{field}: ").strip]
        end
      end

      # -- --char-component containment union ------------------------------------

      def containing(component)
        kradfile_containing(component) | ids_transitive_containing(component)
      end

      # KRADFILE flat: kanji whose component list names +component+.
      def kradfile_containing(component)
        entry_rows("kradfile", "%#{component}%").each_with_object(Set.new) do |(headword, body), set|
          line = body.lines.map(&:chomp).find { |l| l.start_with?("components:") } or next
          components = line.delete_prefix("components:").strip.split(/\s+/)
          set << headword if components.include?(component)
        end
      end

      # BabelStone IDS transitive: every character whose IDS reaches
      # +component+ through component-of-a-component. Build the reverse
      # component graph (component => chars directly containing it) over the
      # whole shelf, then BFS up from +component+.
      def ids_transitive_containing(component)
        reverse = Hash.new { |h, k| h[k] = Set.new }
        entry_rows("babelstone-ids", nil).each do |headword, body|
          body.lines.map(&:chomp).reject(&:empty?).each do |field|
            Nabu::Adapters::IdsTxtParser.components(field).each { |c| reverse[c] << headword }
          end
        end
        ancestors(component, reverse)
      end

      # Every character reachable UP the reverse graph from +target+ (all
      # characters that transitively contain it). Cycle-safe.
      def ancestors(target, reverse)
        found = Set.new
        queue = reverse[target].to_a
        until queue.empty?
          char = queue.shift
          next if found.include?(char)

          found << char
          queue.concat(reverse[char].to_a)
        end
        found
      end

      # -- shelf access ----------------------------------------------------------

      # [headword, body] rows for one dictionary slug; +like+ narrows on body
      # (nil = the whole shelf). Withdrawn entries excluded.
      def entry_rows(slug, like)
        dataset = @catalog[:dictionary_entries]
                  .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
                  .where(Sequel[:dictionaries][:slug] => slug,
                         Sequel[:dictionary_entries][:withdrawn] => false)
        dataset = dataset.where(Sequel.like(Sequel[:dictionary_entries][:body], like)) if like
        dataset.select_map([Sequel[:dictionary_entries][:headword], Sequel[:dictionary_entries][:body]])
      end
    end
  end
end
