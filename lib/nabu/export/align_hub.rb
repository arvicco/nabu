# frozen_string_literal: true

require_relative "types"
require_relative "../alignment_registry"
require_relative "../query/align"
require_relative "../store/alignment_indexer"

module Nabu
  module Export
    # The alignment-hub walk the align and collation tables share: one
    # citation query (a ref, a range, a chapter, or a passage urn — the
    # `nabu align` grammar) or, with no query, the WHOLE work, walked chapter
    # by chapter through Query::Align with the render cap lifted (--long:
    # an export is the deliberate whole-range consumer). Yields one Group per
    # attested ref, its witnesses in registry order exactly as Align answers
    # them — the exporter adds no second lookup model.
    #
    # == The work-wide walk
    #
    # The chapters are read off the derived ref index (fulltext
    # alignment_refs), never guessed: books in index-insertion order (the
    # indexer walks witnesses in registry order and passages in sequence
    # order, so the first witness's book order is the walk's), chapters
    # numerically within a book. A numeric chapter is one chapter query; a
    # ref whose leading segment is not a number (Gothic "MARK Incipit.0")
    # cannot be spelled as a chapter and is aligned singly.
    class AlignHub
      Group = Data.define(:ref, :witnesses)

      attr_reader :work

      def initialize(catalog:, fulltext:, registry:, ref: nil, work: nil)
        raise Error, "no alignment works registered — add one to config/alignments.yml" if registry.empty?
        unless fulltext.table_exists?(Store::AlignmentIndexer::TABLE)
          raise Error, "alignment index not built — run nabu sync or nabu rebuild"
        end

        @fulltext = fulltext
        @registry = registry
        @ref = ref.to_s.strip.empty? ? nil : ref.to_s.strip
        @work = work && (registry.work(work) || raise(Error, unknown_work(work)))
        @work ||= registry.sole_work
        if @ref.nil? && @work.nil?
          raise Error, "give a REF, or name the work to export whole with --work " \
                       "(registered: #{registry.works.map(&:id).join(', ')})"
        end
        @align = Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
      end

      # The registry witness matching +wanted+ by label or document urn
      # (case-insensitive), or nil.
      def self.witness_match?(witness, wanted)
        key = wanted.to_s.strip.downcase
        witness.label.to_s.downcase == key || witness.document_urns.any? { |urn| urn.downcase == key }
      end

      # The query echo for the manifest.
      def scope = @ref || "#{@work.id} (whole work)"

      # Yields Group per attested ref. +on_work+ receives the resolved
      # registry work before the first group (a bare REF resolves its work
      # through the index, so callers validate witness labels there).
      def each_group(on_work: nil, &block)
        announced = false
        queries.each do |query|
          result = run(query)
          @work ||= @registry.work(result.work)
          on_work&.call(@work) unless announced
          announced = true
          groups(result).each(&block)
        end
      end

      private

      def unknown_work(id)
        "unknown alignment work #{id.inspect} — registered: #{@registry.works.map(&:id).join(', ')}"
      end

      def run(query)
        @align.run(query, work: @work&.id, long: true)
      rescue Query::Align::Error => e
        raise Error, e.message
      end

      def groups(result)
        if result.is_a?(Query::Align::RangeResult)
          result.groups.map { |group| Group.new(ref: group.ref, witnesses: group.witnesses) }
        else
          [Group.new(ref: result.ref, witnesses: result.witnesses)]
        end
      end

      def queries
        return [@ref] if @ref

        chapters.flat_map do |(book, chapter), refs|
          chapter.match?(/\A\d+\z/) ? ["#{book} #{chapter}"] : refs
        end
      end

      # [[book, chapter], [refs in index order]] in walk order (class note).
      def chapters
        first_seen = @fulltext[Store::AlignmentIndexer::TABLE].where(work: @work.id).group(:ref)
                                                              .select(:ref, Sequel.function(:min, :rowid).as(:at))
                                                              .as_hash(:ref, :at)
        by_chapter = first_seen.sort_by { |_ref, at| at }.group_by do |ref, _at|
          book, cite = ref.split(" ", 2)
          [book, cite.to_s.split(".", 2).first.to_s]
        end
        book_rank = {}
        by_chapter.each_key { |(book, _)| book_rank[book] ||= book_rank.size }
        by_chapter.sort_by { |(book, chapter), _| [book_rank[book], chapter_key(chapter)] }
                  .map { |key, pairs| [key, pairs.map(&:first)] }
      end

      def chapter_key(chapter)
        chapter.match?(/\A\d+\z/) ? [0, chapter.to_i, ""] : [1, 0, chapter]
      end
    end
  end
end
