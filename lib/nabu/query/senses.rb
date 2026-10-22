# frozen_string_literal: true

module Nabu
  module Query
    # The sense desk (`nabu sense TERM`): passages — and the tokens in them
    # — by the word sense their gold tokens cite. The DCS chapters' tokens
    # carry WordSem sense ids in their CoNLL-U MISC column; facet_map.yml's
    # token_fields rule projects them into the passage facet tables under
    # the facet name "sense", each value an id, its ref the dcs-senses
    # shelf entry's urn (Store::PassageFacetBuilder's token lane).
    #
    # TERM is a sense id (or a comma-joined list), else a sense NAME matched
    # case-insensitively against the shelf headwords (LIKE wildcards
    # honoured: circum%); --gloss widens a name to a substring of the gloss.
    # Names resolve to entry urns in the small shelf, the urns to facet
    # values, the values' pair ranges to passages — never a scan of the
    # passages. The pairs are PASSAGE grain; the tokens a hit lists are read
    # back from the listed passages' own stored tokens (at most +limit+
    # passages parsed), every id of each citing token kept.
    #
    # An absent or unbuilt facet surface is an honest error, never a scan.
    class Senses
      class Error < StandardError; end

      FACET = "sense"
      DEFAULT_LIMIT = 20
      # Matched senses listed (by passage count); the total is always told.
      # const: a render cap, not a corpus claim — the desk announces the
      # hidden tail whatever the census.
      SENSE_LIMIT = 15
      ID_LIST = /\A\d+(?:\s*,\s*\d+)*\z/

      Sense = Data.define(:id, :shelf, :urn, :headword, :gloss, :passages)
      Token = Data.define(:form, :lemma, :ids)
      Hit = Data.define(:urn, :text, :language, :source, :tokens)
      Result = Data.define(:query, :senses, :sense_total, :passage_total, :hits)
      CensusRow = Data.define(:source, :senses, :passages, :pairs)
      Entry = Data.define(:id, :urn, :headword, :gloss)

      MIGRATION_HINT = "this catalog predates the passage facet surface (migration 045) — the next sync " \
                       "or nabu rebuild migrates it, then `bundle exec rake builders:refresh` builds it"
      REFRESH_HINT = "run `bundle exec rake builders:refresh` (or the next nabu rebuild) — it needs a " \
                     "synced source whose tokens carry senses (dcs)"

      def initialize(catalog:, facet_map:)
        @catalog = catalog
        @facet_map = facet_map
      end

      # The dictionary shelves the sense ids belong to (facet_map's
      # token_fields rules under FACET).
      def shelves = @facet_map ? @facet_map.token_shelves(FACET) : []

      def run(query, gloss: false, source: nil, limit: DEFAULT_LIMIT)
        term = query.to_s.strip
        raise Error, "sense: give a sense id (59344) or a sense name (finger)" if term.empty?

        ensure_built!
        values = matching_values(term, gloss: gloss)
        values = values.where(source_id: source_id!(source)) if source
        pairs = @catalog[:passage_facets].where(value_id: values.select(:id))
        listed = top_senses(values, pairs)
        Result.new(query: term, senses: listed, sense_total: values.select(:value, :ref).distinct.count,
                   passage_total: pairs.select(:passage_id).distinct.count,
                   hits: hits(values, pairs, limit))
      end

      # The index census: distinct senses, passages and (passage, sense)
      # pairs per source.
      def census
        ensure_built!
        values = Sequel[:passage_facet_values]
        pairs = Sequel[:passage_facets]
        @catalog[:passage_facet_values]
          .join(:sources, id: values[:source_id])
          .join(:passage_facets, value_id: values[:id])
          .where(values[:facet] => FACET)
          .group(Sequel[:sources][:slug])
          .select(Sequel[:sources][:slug].as(:source),
                  Sequel.function(:count, values[:id]).distinct.as(:senses),
                  Sequel.function(:count, pairs[:passage_id]).distinct.as(:passages),
                  Sequel.function(:count).*.as(:pairs))
          .order(Sequel[:sources][:slug])
          .map { |row| CensusRow.new(**row.slice(:source, :senses, :passages, :pairs)) }
      end

      # {id => Entry} for the +ids+ the sense shelves hold (absent ids are
      # simply missing — the caller labels them unresolved).
      def entries_for(ids)
        ids = Array(ids).map(&:to_s).uniq
        return {} if ids.empty? || shelf_ids.empty?

        @catalog[:dictionary_entries].where(dictionary_id: shelf_ids, entry_id: ids, withdrawn: false)
                                     .select_map(%i[entry_id urn headword gloss])
                                     .to_h { |id, urn, headword, gloss| [id, Entry.new(id, urn, headword, gloss)] }
      end

      # The [token, ids] pairs of +annotations+' stored tokens carrying a
      # sense under +source+'s token rules (every id of a citing token).
      def token_senses(annotations, source:)
        keys = misc_keys(source)
        tokens = annotations.is_a?(Hash) ? annotations["tokens"] : nil
        return [] if keys.empty? || !tokens.is_a?(Array)

        tokens.grep(Hash).filter_map do |token|
          ids = keys.flat_map { |key| Store::PassageFacetBuilder.misc_values(token["misc"], key) }.uniq
          [token, ids] unless ids.empty?
        end
      end

      # The MISC keys +source+'s token rules project under FACET.
      def misc_keys(source)
        rules = @facet_map&.token_fields_for(source.to_s) || {}
        rules.select { |_key, rule| rule.facet == FACET }.keys
      end

      private

      def ensure_built!
        unless @catalog.table_exists?(:passage_facet_values) && @catalog.table_exists?(:passage_facets)
          raise Error, "sense: #{MIGRATION_HINT}"
        end
        return unless @catalog[:passage_facet_values].where(facet: FACET).empty?

        raise Error, "sense: the sense index is not built yet — #{REFRESH_HINT}"
      end

      # The facet value rows TERM selects: ids verbatim, else the shelf
      # entries' urns a name (or gloss) pattern matches.
      def matching_values(term, gloss:)
        values = @catalog[:passage_facet_values].where(facet: FACET)
        return values.where(value: term.split(",").map(&:strip)) if term.match?(ID_LIST)

        if shelf_ids.empty?
          raise Error, "sense: no sense shelf is loaded (#{shelves.join(', ')}) — a name lookup resolves " \
                       "against it; a numeric sense id still answers from the index"
        end
        values.where(ref: matching_entries(term, gloss: gloss).select(:urn))
      end

      def matching_entries(term, gloss:)
        match = Sequel.ilike(:headword, term)
        match |= Sequel.ilike(:gloss, "%#{term}%") if gloss
        @catalog[:dictionary_entries].where(dictionary_id: shelf_ids, withdrawn: false).where(match)
      end

      def shelf_ids
        @shelf_ids ||= shelves.empty? ? [] : @catalog[:dictionaries].where(slug: shelves).select_map(:id)
      end

      def source_id!(slug)
        @catalog[:sources].where(slug: slug).get(:id) || raise(Error, "sense: unknown source #{slug.inspect}")
      end

      # The most-attested senses (one per id + ref, counts summed over the
      # sources carrying it), resolved against the shelf.
      def top_senses(values, pairs)
        rows = values.select_map(%i[id value ref])
        counts = pairs.group_and_count(:value_id).to_h { |row| [row[:value_id], row[:count]] }
        grouped = rows.group_by { |_id, value, ref| [value, ref] }
                      .map { |(value, ref), members| [value, ref, members.sum { |id, *| counts.fetch(id, 0) }] }
        top = grouped.sort_by { |value, _ref, count| [-count, value.to_i, value] }.first(SENSE_LIMIT)
        entries = entries_for(top.map(&:first))
        top.map do |value, ref, count|
          entry = entries[value] if ref.nil? || entries[value]&.urn == ref
          Sense.new(id: value, shelf: shelf_of(ref), urn: ref, headword: entry&.headword, gloss: entry&.gloss,
                    passages: count)
        end
      end

      # "urn:nabu:dict:<shelf>:<id>" → shelf.
      def shelf_of(ref)
        ref.to_s[/\Aurn:nabu:dict:([^:]+):/, 1]
      end

      def hits(values, pairs, limit)
        ids = pairs.select(:passage_id).distinct.order(:passage_id).limit(limit).select_map(:passage_id)
        return [] if ids.empty?

        wanted = values.select_map(:value).to_set
        @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                           .join(:sources, id: Sequel[:documents][:source_id])
                           .where(Sequel[:passages][:id] => ids, Sequel[:passages][:withdrawn] => false)
                           .order(Sequel[:passages][:id])
                           .select_map([Sequel[:passages][:urn], Sequel[:passages][:text],
                                        Sequel[:passages][:language], Sequel[:sources][:slug],
                                        Sequel[:passages][:annotations_json]])
                           .map do |urn, text, language, slug, json|
                             Hit.new(urn: urn, text: text, language: language, source: slug,
                                     tokens: citing_tokens(json, slug, wanted))
                           end
      end

      def citing_tokens(json, slug, wanted)
        annotations = JSON.parse(json.to_s)
        token_senses(annotations, source: slug).filter_map do |token, ids|
          Token.new(form: token["form"], lemma: token["lemma"], ids: ids) if ids.any? { |id| wanted.include?(id) }
        end
      rescue JSON::ParserError
        []
      end
    end
  end
end
