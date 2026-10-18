# frozen_string_literal: true

module Nabu
  module Query
    # The person desk card (P97-2 — owner ruling 2026-09-11, option b): look a person up in
    # the derived person index by authority ref ("cbdb:1762", "edh:HD000001/3")
    # or by name in either script (the shared fold; exact key equality, never
    # fuzzy — homonyms yield several cards, the place-desk shape). A name
    # searches every derived authority, the default (cbdb) first.
    class Person
      class Error < StandardError; end

      # Authority ids are the authority's own: CBDB numeric ("cbdb:1762"),
      # EDH per-attestation ("edh:HD000001/3"), Elephantine p/d-prefixed
      # ("elephantine:p19245", "elephantine:d1"), Aozora's zero-padded
      # 人物ID ("aozora:001257"), kokubunken's name-ids
      # ("kokubunken:藤原定家" — any letter or digit, not only ASCII),
      # NIKH's per source ("sillok:M_0006771", "goryeosa:p094190") or
      # through the markup's shared namespace ("nikh:p094190" — every
      # NIKH slice holding it).
      REF_PATTERN = %r{\A([a-z][a-z0-9-]*):([\p{L}\p{N}][\p{L}\p{N}/._-]*)\z}

      Result = Data.define(:cards)

      def initialize(catalog:)
        @catalog = catalog
      end

      def run(query)
        term = query.to_s.strip
        raise Error, "person: give a name (either script) or an authority ref (cbdb:1762)" if term.empty?

        if (m = term.match(REF_PATTERN))
          cards = ref_authorities(m[1]).filter_map { |authority| resolver_for(authority)&.person(m[2]) }
          raise Error, "no person #{term.inspect} in the derived index" if cards.empty?

          return Result.new(cards: cards)
        end

        resolvers = authorities.filter_map { |authority| resolver_for(authority) }
        if resolvers.empty?
          raise Error, "person: the person index is not derived — run `nabu sync cbdb` " \
                       "(or `nabu rebuild`) first"
        end
        matches = resolvers.flat_map { |resolver| resolver.named(term) }
        raise Error, "no person named #{term.inspect} (exact match under the fold)" if matches.empty?

        Result.new(cards: matches)
      end

      private

      # The authorities a name searches, the default first (the
      # PersonIndex roster — resolver_for answers nil for an underived one,
      # so the check is one indexed lookup per authority, never a scan).
      def authorities = Store::PersonIndex::AUTHORITIES

      # A ref's prefix names its authority — except "nikh:", the NIKH
      # index markup's shared namespace (the passage-annotation refs),
      # which resolves in every NIKH authority holding the id (goryeosa
      # and goryeosa-jeoryo share one person id space).
      def ref_authorities(prefix)
        prefix == "nikh" ? Nabu::NikhPersons::NIKH_AUTHORITIES : [prefix]
      end

      def resolver_for(authority)
        (@resolvers ||= {})[authority] ||=
          Store::PersonIndex.resolver(@catalog, authority: authority)
      end
    end
  end
end
