# frozen_string_literal: true

module Nabu
  # The NIKH person authorities: the person ids NIKH's index markup puts
  # on its tagged mentions (Adapters::NikhXmlParser, entities: true),
  # aggregated per source into that source's Store::PersonIndex slice —
  # the per-source producer mold (ElephantinePersons, EdhPersons), driven
  # from the adapters' person_index_producer hook at sync and rebuild.
  #
  # == The id spaces (censused whole, 2026-10-18)
  #
  # sillok    1,352,152 of 1,572,270 person tags carry ref="M_<7 digits>"
  #           — 68,308 distinct ids, NIKH's Joseon-sillok person keys.
  # goryeosa  66,278 of 66,285 carry ref="p<6 digits>" — 11,505 distinct.
  # goryeosa-jeoryo 23,941 of 31,997 carry the SAME p-id space: 6,924 of
  #           its 6,937 distinct ids recur in goryeosa, every shared id
  #           under the same surfaces — one NIKH Goryeo person authority
  #           tagged across both chronicles. Each source still derives its
  #           own slice from its own passages (one producer per source);
  #           the shared "nikh:" ref namespace is what joins them
  #           (Query::Person fans a nikh: ref out across NIKH_AUTHORITIES).
  # sjw and bibyeonsa mint no authority: their tags carry no person-key
  # ref (only the cross-database person pid @id on a few thousand sjw
  # tags and on bibyeonsa's 923 mentions of 26 persons).
  #
  # == Projection onto the Person shape
  #
  # person_id = the id verbatim (M_0006771, p094190); name and name_han
  # (the native-form lane) = the surface tagged in the most passages
  # (records dedupe per passage) — ties break by document order, so a
  # title alias can win a 1–1 tie; every distinct surface keys under the
  # shared fold. Only a source's own
  # person ids project (ID_PATTERNS): a person tag carrying an office or
  # place id (one each in goryeosa) or the secondary pid (sillok's
  # id-only tags) is no member of the authority. The markup carries no
  # life dates, dynasty or sex — those columns stay nil/false; the
  # sillok pid that co-occurs with an M_ ref on 134 persons is not
  # projected (the passage record keeps only the tag's primary id).
  module NikhPersons
    # Each authority's own id shape, keyed by its source slug.
    ID_PATTERNS = {
      "sillok" => /\AM_\d+\z/,
      "goryeosa" => /\Ap\d+\z/,
      "goryeosa-jeoryo" => /\Ap\d+\z/
    }.freeze

    # The authorities a "nikh:" ref resolves across, in this order.
    NIKH_AUTHORITIES = ID_PATTERNS.keys.freeze

    REF_PREFIX = "nikh:"
    PERSONS_KEY = "persons"

    Census = Data.define(:persons, :seconds)

    module_function

    def adapter_for(slug)
      {
        "sillok" => Adapters::Sillok, "goryeosa" => Adapters::Goryeosa,
        "goryeosa-jeoryo" => Adapters::GoryeosaJeoryo
      }.fetch(slug).new
    end

    # Every person of +authority+ as a Store::PersonIndex::Person, from
    # the passages +adapter+ parses out of +workdir+ — the exact records
    # the catalog carries, so the slice is a pure function of canonical.
    # Memory: one id → surface-count hash (~68k ids for sillok), never a
    # held document.
    def each_person(adapter, workdir, authority:, &)
      return enum_for(:each_person, adapter, workdir, authority: authority) unless block_given?

      surfaces = tally(adapter, workdir, ID_PATTERNS.fetch(authority))
      surfaces.each { |id, counts| yield build_person(authority, id, counts) }
    end

    # id → { surface => count } in first-seen order (Hash order is
    # insertion order, so max_by's first maximum is the first-seen one).
    def tally(adapter, workdir, pattern)
      surfaces = Hash.new { |hash, id| hash[id] = Hash.new(0) }
      adapter.discover(workdir).each do |ref|
        document = parse_or_nil(adapter, ref)
        document&.each do |passage|
          Array(passage.annotations[PERSONS_KEY]).each do |record|
            id = record["ref"]&.delete_prefix(REF_PREFIX)
            surfaces[id][record["value"]] += 1 if id&.match?(pattern)
          end
        end
      end
      surfaces
    end

    def parse_or_nil(adapter, ref)
      adapter.parse(ref)
    rescue Nabu::DocumentSkipped
      nil
    end

    def build_person(authority, id, counts)
      name = counts.max_by { |_, count| count }.first
      Store::PersonIndex::Person.new(
        authority: authority, person_id: id, name: name, name_han: name,
        birth_year: nil, death_year: nil, index_year: nil, dynasty: nil, dynasty_han: nil,
        female: false, name_keys: counts.keys.map { |surface| Nabu::Pleiades.name_key(surface) }.uniq
      )
    end

    # The sync/rebuild derivation seam: +authority+'s slice, wholesale.
    # A workdir holding no members → honest no-op.
    class Producer
      attr_reader :authority

      def initialize(catalog:, authority:)
        @catalog = catalog
        @authority = authority
      end

      def run(_slug, workdir:)
        adapter = NikhPersons.adapter_for(@authority)
        return nil unless Dir.exist?(workdir) && adapter.discover(workdir).any?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(
          @catalog, persons: NikhPersons.each_person(adapter, workdir, authority: @authority),
                    authority: @authority
        )
        return nil if count.nil?

        Census.new(persons: count, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
