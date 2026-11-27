# frozen_string_literal: true

require_relative "../arabic_roots"
require_relative "../facet_map"

module Nabu
  module Query
    # The Quranic root → Lane link: a token's consonantal root, written in
    # whatever scheme its source uses, steps to the dictionary entries
    # filed under that root. The house seam is the dictionary-entry facet
    # surface: Lane's `root` heading is an entry facet (facet_map.yml
    # entry_fields), and its keyed rule makes Store::EntryFacetBuilder mint
    # the ArabicRoots comparison keys beside it (root_key strict,
    # root_loose_key fallback). A lookup folds the token's root through the
    # SAME rules and probes those rows by their (facet, value) index, then
    # the pairs by value_id — precompiled rows only, never a scan, nothing
    # stored at read time (the show --senses / Query::Senses read-path
    # precedent, at entry grain).
    #
    # Tiers: the strict key (orthography + gemination) answers first; only
    # a strict miss tries the loose key (weak radicals + reduplication),
    # and the Link says which tier answered — a loose join may over-merge
    # (قول/قيل) and reads as such. An unmapped character (Corpus
    # Coranicum's vowel-bearing non-root analyses) or a root no Lane
    # heading carries is an honest miss (tier nil, no entries).
    #
    # Sources: TOKEN_SCHEMES names, per Quranic source, the scheme its
    # stored tokens' "root" key is written in (the Quranic Arabic Corpus:
    # Buckwalter; Corpus Coranicum: DMG). Any dictionary shelf whose entry
    # rules key a `root` facet answers — Lane's today.
    class RootLink
      FACET = "root"
      TOKEN_KEY = "root"

      # const: a source → transliteration-scheme registry, not a census —
      # each row is the upstream's own documented root notation.
      TOKEN_SCHEMES = { "quranic-corpus" => :buckwalter, "corpus-coranicum" => :dmg }.freeze

      # One dictionary entry the root reaches: its urn, headword, gloss,
      # dictionary slug and the heading it is filed under (verbatim).
      Entry = Data.define(:urn, :headword, :gloss, :dictionary, :heading)

      # A lookup's answer: the root as given, its scheme, its Arabic-script
      # form (nil when unmapped), the tier that answered (:strict, :loose or
      # nil), the distinct headings hit, the entry row ids (dictionary then
      # load order) and the total.
      Link = Data.define(:root, :scheme, :arabic, :tier, :headings, :entry_ids) do
        def total = entry_ids.size
        def hit? = !tier.nil?
      end

      def self.scheme_for(source) = TOKEN_SCHEMES[source.to_s]

      def initialize(catalog:)
        @catalog = catalog
        @memo = {}
      end

      # Whether the key facets are projected in this catalog (the builder
      # has run since the keyed rule shipped).
      def built?
        return false unless @catalog.table_exists?(:entry_facet_values) && @catalog.table_exists?(:entry_facets)

        !@catalog[:entry_facet_values].where(facet: key_facets.first).limit(1).empty?
      end

      # The Link for +root+ in +scheme+ (:buckwalter, :dmg, :arabic; nil =
      # detected from its characters — ArabicRoots.detect_scheme).
      def lookup(root, scheme: nil)
        scheme ||= ArabicRoots.detect_scheme(root)
        @memo.fetch([root, scheme]) { |key| @memo[key] = resolve(root.to_s.strip, scheme) }
      end

      # The [token, Link] pairs of +annotations+' stored tokens carrying a
      # root, for a source TOKEN_SCHEMES names ([] for any other source).
      def token_links(annotations, source:)
        scheme = self.class.scheme_for(source)
        tokens = annotations.is_a?(Hash) ? annotations["tokens"] : nil
        return [] if scheme.nil? || !tokens.is_a?(Array)

        tokens.grep(Hash).filter_map do |token|
          root = token[TOKEN_KEY]
          [token, lookup(root, scheme: scheme)] if root.is_a?(String) && !root.strip.empty?
        end
      end

      # The Entry values of +link+ (first +limit+; nil = all), in the
      # link's entry order.
      def entries(link, limit: nil)
        ids = limit ? link.entry_ids.first(limit) : link.entry_ids
        return [] if ids.empty?

        headings = headings_by_entry(ids)
        rows = @catalog[:dictionary_entries]
               .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
               .where(Sequel[:dictionary_entries][:id] => ids)
               .select_hash(Sequel[:dictionary_entries][:id],
                            [Sequel[:dictionary_entries][:urn], Sequel[:dictionary_entries][:headword],
                             Sequel[:dictionary_entries][:gloss], Sequel[:dictionaries][:slug]])
        ids.filter_map do |id|
          urn, headword, gloss, slug = rows[id]
          urn && Entry.new(urn: urn, headword: headword, gloss: gloss, dictionary: slug, heading: headings[id])
        end
      end

      private

      def key_facets = FacetMap.key_facets(FACET)

      def resolve(root, scheme)
        arabic = ArabicRoots.to_arabic(root, scheme: scheme)
        keys = arabic && ArabicRoots.keys(arabic, scheme: :arabic)
        return miss(root, scheme, arabic) unless keys && built?

        key_facets.zip(keys, %i[strict loose]).each do |facet, key, tier|
          ids = entry_ids(facet, key)
          next if ids.empty?

          headings = headings_by_entry(ids)
          return Link.new(root: root, scheme: scheme, arabic: arabic, tier: tier,
                          headings: ids.filter_map { |id| headings[id] }.uniq, entry_ids: ids)
        end
        miss(root, scheme, arabic)
      end

      def miss(root, scheme, arabic)
        Link.new(root: root, scheme: scheme, arabic: arabic, tier: nil, headings: [], entry_ids: [])
      end

      # Live entry row ids under one key value: the value rows by the
      # (facet, value) index, their pairs by the (value_id, entry_id)
      # primary key — ordered by dictionary, then entry row id (load
      # order: Lane's article order within a root).
      def entry_ids(facet, key)
        value_ids = @catalog[:entry_facet_values].where(facet: facet, value: key).select(:id)
        @catalog[:dictionary_entries]
          .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
          .where(Sequel[:dictionary_entries][:id] => @catalog[:entry_facets].where(value_id: value_ids)
                                                                           .select(:entry_id))
          .where(Sequel[:dictionary_entries][:withdrawn] => false)
          .order(Sequel[:dictionaries][:slug], Sequel[:dictionary_entries][:id])
          .select_map(Sequel[:dictionary_entries][:id])
      end

      # {entry row id => its verbatim root heading}, through the entry_id
      # index of the pair table.
      def headings_by_entry(ids)
        @catalog[:entry_facets]
          .join(:entry_facet_values, id: Sequel[:entry_facets][:value_id])
          .where(Sequel[:entry_facets][:entry_id] => ids, Sequel[:entry_facet_values][:facet] => FACET)
          .select_map([Sequel[:entry_facets][:entry_id], Sequel[:entry_facet_values][:value]])
          .to_h
      end
    end
  end
end
