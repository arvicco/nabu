# frozen_string_literal: true

module Nabu
  module Query
    # The person desk card (P97-2 — owner ruling 2026-09-11, option b): look a person up in
    # the derived person index by authority ref ("cbdb:1762", "edh:HD000001/3")
    # or by name in either script (the shared fold; exact key equality, never
    # fuzzy — homonyms yield several cards, the place-desk shape). A name
    # searches every derived authority, the default (cbdb) first.
    #
    # == The catalogue-person lane (mentions)
    #
    # A name ALSO answers from the person-shaped document facets: the
    # catalogue names upstream records carry without a person id (oracc/
    # cdli ruler, ancient_author, recipient, eponym, the legal parties; the
    # text sources' author/translator/editor/commentator). They are no
    # authority — a catalogue string is not a stable person — so they never
    # become cards: each matching (facet, value) is listed with the sources
    # cataloguing it and their live document counts. The lookup rides the
    # document_facets (facet, value) index as a prefix range per facet —
    # an indexed probe, never a scan — kept only where the value is the
    # name or continues it past a word boundary ("Sargon" → "Sargon II",
    # never "Sargonid"); values are matched as catalogued (case-sensitive),
    # a lowercase query also tries its title-cased form.
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

      # Census (held catalog, 2026-10-22) of the person-shaped document
      # facets, rows: author 168,926 (35,836 values, ~60 sources) · ruler
      # 135,867 (cdli 118k + oracc 17.5k) · translator 7,770 · recipient
      # 6,100 (oracc) · eponym 2,125 (oracc) · addressee 1,028 (vedaweb) ·
      # editor 594 · commentator 309 · translator_tib 543 · seal_owner 174 ·
      # seller/buyer/debtor/creditor ~360 · author_contested 68. The
      # authority-id facets (author_id, translator_id, work_id) are ids,
      # not names — out.
      PERSON_FACETS = %w[author ruler ancient_author translator recipient eponym addressee editor commentator
                         translator_tib seal_owner seller buyer debtor creditor author_contested].freeze
      # Distinct catalogue values listed per lookup; the overflow is said.
      # const: a render bound, not a corpus claim
      MENTION_VALUES = 12
      # Prefix-range rows probed per facet before the word-boundary filter.
      # const: a probe bound, not a corpus claim
      MENTION_PROBE = 200
      HIGH = "\u{10FFFF}"

      # One catalogue value: its facet, the value verbatim, and
      # [[source slug, live document count]] by count descending.
      Mention = Data.define(:facet, :value, :sources)

      Result = Data.define(:cards, :mentions, :mentions_truncated) do
        def initialize(mentions: [], mentions_truncated: false, **) = super
      end

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
        matches = resolvers.flat_map { |resolver| resolver.named(term) }
        mentions, truncated = catalogue_mentions(term)
        if matches.empty? && mentions.empty?
          if resolvers.empty?
            raise Error, "no person named #{term.inspect}: no catalogue value matches, and the person " \
                         "index is not derived — run `nabu sync cbdb` (or `nabu rebuild`) first"
          end
          raise Error, "no person named #{term.inspect} (exact match under the fold; no catalogue value either)"
        end

        Result.new(cards: matches, mentions: mentions, mentions_truncated: truncated)
      end

      private

      # [mentions, truncated?] — the catalogue-person lane (class note).
      def catalogue_mentions(term)
        return [[], false] unless @catalog.table_exists?(:document_facets)

        probes = [term]
        probes << term.split.map(&:capitalize).join(" ") if term == term.downcase
        values = probes.uniq.flat_map { |probe| facet_values(probe) }.uniq.sort
        listed = values.first(MENTION_VALUES).filter_map do |facet, value|
          sources = value_sources(facet, value)
          Mention.new(facet: facet, value: value, sources: sources) unless sources.empty?
        end
        [listed, values.size > MENTION_VALUES]
      end

      # [facet, value] pairs whose value is +probe+ or continues it past a
      # word boundary — one index range per facet.
      def facet_values(probe)
        PERSON_FACETS.flat_map do |facet|
          @catalog[:document_facets].where(facet: facet)
                                    .where(Sequel[:value] >= probe).where(Sequel[:value] < "#{probe}#{HIGH}")
                                    .distinct.limit(MENTION_PROBE).select_map(:value)
                                    .select { |value| value == probe || value[probe.length].match?(/[^\p{L}\p{N}]/) }
                                    .map { |value| [facet, value] }
        end
      end

      # [[slug, live documents]] cataloguing +value+ under +facet+.
      def value_sources(facet, value)
        @catalog[:document_facets]
          .join(:documents, id: :document_id)
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:document_facets][:facet] => facet, Sequel[:document_facets][:value] => value,
                 Sequel[:documents][:withdrawn] => false)
          .group_and_count(Sequel[:sources][:slug])
          .map { |row| [row[:slug], row[:count]] }
          .sort_by { |slug, count| [-count, slug] }
      end

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
