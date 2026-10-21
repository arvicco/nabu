# frozen_string_literal: true

module Nabu
  module Query
    # The entity desk (`nabu entity NAME`): passages by a name marked
    # INSIDE their text — the inline "entities" annotation the EpiDoc,
    # Coptic Scriptorium and DHARMA parsers mine — read from the
    # precompiled index only (Store::EntityIndex). The query is folded the
    # way the index folded every record (case + combining marks), then
    # matched as a substring of the small name dictionary's search key
    # (surface text, identity, authority key, ref); the matched names' pair
    # ranges give the passages. An absent or unbuilt index is an honest
    # error, never a scan of the passages' annotations.
    class Entities
      class Error < StandardError; end

      DEFAULT_LIMIT = 20
      # Matched names listed (by passage count); the total is always told.
      # const: a render cap, not a corpus claim — the desk announces the
      # hidden tail ("… N more names") whatever the census.
      NAME_LIMIT = 15

      Name = Data.define(:id, :source, :type, :text, :identity, :key, :ref, :subtype, :passages) do
        # What a name reads as: its surface, else its identity/key/ref.
        def label = text || identity || key || ref
      end
      Hit = Data.define(:urn, :text, :language, :names)
      Result = Data.define(:query, :names, :name_total, :passage_total, :hits)
      CensusRow = Data.define(:source, :type, :names, :passages)

      MIGRATION_HINT = "this catalog predates the entity index (migration 049) — the next sync or " \
                       "nabu rebuild migrates it, then `bundle exec rake builders:refresh` builds it"
      REFRESH_HINT = "run `bundle exec rake builders:refresh` (or the next nabu rebuild)"

      def initialize(catalog:)
        @catalog = catalog
      end

      def run(query, type: nil, source: nil, limit: DEFAULT_LIMIT)
        term = Store::EntityIndex.fold(query.to_s.strip)
        raise Error, "entity: give a name (or an authority key: tgn,7002681, pers:…)" if term.empty?

        ensure_built!
        matched = matching_names(term, type: type, source: source)
        pairs = @catalog[Store::EntityIndex::TABLE].where(name_id: matched.select(:id))
        Result.new(query: query.to_s.strip, names: top_names(matched, pairs), name_total: matched.count,
                   passage_total: pairs.select(:passage_id).distinct.count,
                   hits: hits(matched, pairs, limit))
      end

      # The index census: names and passages per (source, type).
      def census
        ensure_built!
        names = Sequel[Store::EntityIndex::NAMES_TABLE]
        pairs = Sequel[Store::EntityIndex::TABLE]
        @catalog[Store::EntityIndex::NAMES_TABLE]
          .join(:sources, id: names[:source_id])
          .join(Store::EntityIndex::TABLE, name_id: names[:id])
          .group(Sequel[:sources][:slug], names[:type])
          .select(Sequel[:sources][:slug].as(:source), names[:type],
                  Sequel.function(:count, names[:id]).distinct.as(:names),
                  Sequel.function(:count, pairs[:passage_id]).distinct.as(:passages))
          .order(Sequel[:sources][:slug], Sequel.desc(:passages))
          .map { |row| CensusRow.new(**row.slice(:source, :type, :names, :passages)) }
      end

      private

      def ensure_built!
        raise Error, "entity: #{MIGRATION_HINT}" unless Store::EntityIndex.available?(@catalog)
        raise Error, "entity: the entity index is not built yet — #{REFRESH_HINT}" unless
          Store::EntityIndex.populated?(@catalog)
      end

      def matching_names(term, type:, source:)
        pattern = "%#{term.gsub(/[\\%_]/) { |char| "\\#{char}" }}%"
        dataset = @catalog[Store::EntityIndex::NAMES_TABLE].where(Sequel.like(:search_key, pattern))
        dataset = dataset.where(type: type) if type
        dataset = dataset.where(source_id: source_id!(source)) if source
        dataset
      end

      def source_id!(slug)
        @catalog[:sources].where(slug: slug).get(:id) || raise(Error, "entity: unknown source #{slug.inspect}")
      end

      def top_names(matched, pairs)
        counts = pairs.group_and_count(:name_id).order(Sequel.desc(:count), :name_id).limit(NAME_LIMIT)
                      .to_h { |row| [row[:name_id], row[:count]] }
        rows = matched.where(id: counts.keys).to_h { |row| [row[:id], row] }
        counts.map { |id, count| name_of(rows.fetch(id), passages: count) }
      end

      def hits(matched, pairs, limit)
        ids = pairs.select(:passage_id).distinct.order(:passage_id).limit(limit).select_map(:passage_id)
        return [] if ids.empty?

        on_page = pairs.where(passage_id: ids).order(:name_id).select_map(%i[name_id passage_id])
        names = matched.where(id: on_page.map(&:first).uniq).to_h { |row| [row[:id], row] }
        by_passage = Hash.new { |hash, key| hash[key] = [] }
        on_page.each { |name_id, passage_id| by_passage[passage_id] << name_of(names.fetch(name_id)) }
        @catalog[:passages].where(id: ids, withdrawn: false).order(:id).select_map(%i[id urn text language])
                           .map do |id, urn, text, language|
                             Hit.new(urn: urn, text: text, language: language, names: by_passage[id])
                           end
      end

      def name_of(row, passages: nil)
        Name.new(id: row[:id], source: source_slug(row[:source_id]), type: row[:type], text: row[:text],
                 identity: row[:identity], key: row[:key], ref: row[:ref], subtype: row[:subtype],
                 passages: passages)
      end

      def source_slug(id)
        (@source_slugs ||= {})[id] ||= @catalog[:sources].where(id: id).get(:slug)
      end
    end
  end
end
