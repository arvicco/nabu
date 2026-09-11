# frozen_string_literal: true

module Nabu
  module Query
    # The person desk card (P97-2 — №R-62 option b): look a person up in
    # the derived person index by authority ref ("cbdb:1762") or by name
    # in either script (the shared fold; exact key equality, never
    # fuzzy — homonyms yield several cards, the place-desk shape).
    class Person
      class Error < StandardError; end

      REF_PATTERN = /\A([a-z][a-z0-9-]*):(\d+)\z/

      Result = Data.define(:cards)

      def initialize(catalog:)
        @catalog = catalog
      end

      def run(query)
        term = query.to_s.strip
        raise Error, "person: give a name (either script) or an authority ref (cbdb:1762)" if term.empty?

        if (m = term.match(REF_PATTERN))
          resolver = resolver_for(m[1])
          person = resolver&.person(m[2])
          raise Error, "no person #{term.inspect} in the derived index" if person.nil?

          return Result.new(cards: [person])
        end

        resolver = resolver_for(Store::PersonIndex::DEFAULT_AUTHORITY)
        if resolver.nil?
          raise Error, "person: the person index is not derived — run `nabu sync cbdb` " \
                       "(or `nabu rebuild`) first"
        end
        matches = resolver.named(term)
        raise Error, "no person named #{term.inspect} (exact match under the fold)" if matches.empty?

        Result.new(cards: matches)
      end

      private

      def resolver_for(authority)
        (@resolvers ||= {})[authority] ||=
          Store::PersonIndex.resolver(@catalog, authority: authority)
      end
    end
  end
end
