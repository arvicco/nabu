# frozen_string_literal: true

require "test_helper"

# Roster parity: a hand-kept roster constant that parallel lanes grow is
# parity-tested against the enumeration of its producers, so producer
# number n+1 cannot be forgotten. A passing suite is NOT evidence a roster
# is complete — fallback paths mask a missing member (the anchor: a new
# person-index producer shipped while PersonIndex::AUTHORITIES still
# listed the old set; name lookups fell back to the default authority, no
# test went red, and the gap was found by a by-hand count at a gate).
#
# Rosters swept for this pattern (lib/, constants enumerating slugs that a
# producer predicate or parser family also defines):
#   * Store::PersonIndex::AUTHORITIES      vs person_index_producer? (here)
#   * NikhPersons::ID_PATTERNS             vs the NikhPersons producers (here)
#   * TimelineBuilder::NikhEntryDates::SLUGS vs the NikhXmlParser family (here)
# Not parity-testable — no producer predicate defines their membership
# (they are curated census choices, e.g. MetadataDates::SHAPES,
# Indexer::SIGN_SOURCES, Query::Char::HDIC_SLUGS); place_index_producer?
# and enrichment_producer? have no roster to drift from (both rebuild
# paths enumerate the predicate directly).
class RosterParityTest < Minitest::Test
  SOURCES = File.expand_path("../config/sources.yml", __dir__)

  # Every adapter the registry wires plus every Adapter subclass loaded —
  # an adapter not yet registered still counts as a producer.
  def adapters
    @adapters ||= begin
      registry = Nabu::SourceRegistry.load(SOURCES)
      registered = registry.each_source.map(&:adapter_class)
      loaded = ObjectSpace.each_object(Class).select { |klass| klass < Nabu::Adapter && klass.name }
      (registered + loaded).uniq
    end
  end

  def person_producers
    adapters.select(&:person_index_producer?).to_h do |klass|
      [klass, klass.person_index_producer(catalog: nil)]
    end
  end

  # { authority => adapter } for every person-index producer.
  def producer_authorities
    person_producers.to_h { |klass, producer| [producer.authority, klass] }
  end

  # What a roster misses / carries beyond its producers.
  def roster_gaps(roster, produced)
    { missing: (produced - roster).sort, stale: (roster - produced).sort }
  end

  def test_person_index_authorities_match_the_registered_producers
    gaps = roster_gaps(Nabu::Store::PersonIndex::AUTHORITIES, producer_authorities.keys)
    assert_equal({ missing: [], stale: [] }, gaps,
                 "Store::PersonIndex::AUTHORITIES must list exactly the authorities the " \
                 "person_index_producer? adapters derive (missing = a producer the lookups never search)")
    assert_equal Nabu::Store::PersonIndex::DEFAULT_AUTHORITY, Nabu::Store::PersonIndex::AUTHORITIES.first,
                 "the default authority leads the lookup order"
  end

  def test_nikh_id_patterns_match_the_nikh_person_producers
    nikh = person_producers.select { |_, producer| producer.is_a?(Nabu::NikhPersons::Producer) }
    authorities = nikh.values.map(&:authority)
    assert_equal({ missing: [], stale: [] }, roster_gaps(Nabu::NikhPersons::ID_PATTERNS.keys, authorities),
                 "NikhPersons::ID_PATTERNS must key exactly the NIKH-markup person authorities")
    nikh.each do |klass, producer|
      assert_instance_of klass, Nabu::NikhPersons.adapter_for(producer.authority),
                         "NikhPersons.adapter_for(#{producer.authority.inspect}) must name its own adapter"
    end
    assert_empty Nabu::NikhPersons::NIKH_AUTHORITIES - Nabu::Store::PersonIndex::AUTHORITIES,
                 "a nikh: ref fans out only across derived authorities"
  end

  def test_nikh_entry_dates_cover_every_nikh_parser_source
    registry = Nabu::SourceRegistry.load(SOURCES)
    family = registry.each_source.select do |entry|
      file = Object.const_source_location(entry.adapter_class.name)&.first
      file && File.read(file).include?("NikhXmlParser")
    end
    gaps = roster_gaps(Nabu::Store::TimelineBuilder::NikhEntryDates::SLUGS, family.map(&:slug))
    assert_equal({ missing: [], stale: [] }, gaps,
                 "NikhEntryDates::SLUGS must cover every source parsed by the NikhXmlParser family " \
                 "(missing = a source whose entry dates never reach the timeline)")
  end

  # The comparison bites: a producer the roster lacks is reported missing.
  def test_a_producer_missing_from_the_roster_is_caught
    assert_equal({ missing: ["new-authority"], stale: [] },
                 roster_gaps(%w[cbdb edh], %w[cbdb edh new-authority]))
    assert_equal({ missing: [], stale: ["gone"] }, roster_gaps(%w[cbdb gone], %w[cbdb]))
  end
end
