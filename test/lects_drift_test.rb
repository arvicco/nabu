# frozen_string_literal: true

require "test_helper"

# THE DRIFT GUARD (P57-3): every code a real consumer could pass to
# Nabu::Lects#resolve must land on either (a) an identity bare-anchor lect
# (always valid — codemap.yml's own rule: "Bare-anchor targets need no
# registry entry") or (b) a lect whose non-identity components
# (stage/variety/ortho) are ACTUALLY DEFINED in lects.yml. This guards
# against nabu-lects and config/lect_overrides.yml drifting apart — a
# codemap or override entry pointing at a renamed/removed stage would
# otherwise fail silently (#resolve never raises; it just returns a string,
# by design — see lib/nabu/lects.rb).
#
# The code universe checked here is built from a SMALL SEEDED test store
# (StoreTestDB — NOT the live catalog; CLAUDE.md forbids network/live-db
# reads in tests) plus every codemap.yml key plus every
# config/lect_overrides.yml override target. #assert_codes_resolve_cleanly
# takes a plain Enumerable of codes, so pointing the same guard at a full
# catalog later (e.g. `Nabu::Store::Document.distinct.select_map(:language)`)
# is a one-line swap of the argument, never a rewrite of the validation.
class LectsDriftTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")
  LECT_OVERRIDES_PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml")

  # A small representative seeded set — codes real sources actually carry
  # (config/sources.yml's own language: commentary for perseus-latin/grc,
  # rundata, cantigas), the two ratified-override codes under their owning
  # source, and one code with NO registry entry anywhere (srd — honest
  # coarseness, never a drift).
  SEEDED_DOCUMENTS = [
    { source: "perseus-latin", language: "lat" },
    { source: "perseus-greek", language: "grc" },
    { source: "derom", language: "la-vul" },
    { source: "rundata", language: "gmq-pro" },
    { source: "rundata", language: "non" },
    { source: "cantigas", language: "roa-opt" },
    { source: "some-unmapped-source", language: "srd" }
  ].freeze

  def lects
    @lects ||= Nabu::Lects.load(FIXTURES, overrides_path: LECT_OVERRIDES_PATH)
  end

  # The P61-3 incident, pinned: YAML silently keeps the LAST duplicate
  # mapping key, so a second `papyri-ddbdp:` section appended at the file
  # tail SHADOWED the first — grc:koi vanished for 57,911 docs in one
  # materialize run. Overrides are hand-edited; this guard makes the trap
  # a red test instead of a silent census drop.
  def test_the_overrides_file_has_no_duplicate_source_keys
    keys = File.readlines(LECT_OVERRIDES_PATH)
               .filter_map { |line| line[/\A  ([a-z0-9-]+):\s*\z/, 1] }
    dupes = keys.tally.select { |_, count| count > 1 }.keys
    assert_empty dupes,
                 "duplicate source keys in config/lect_overrides.yml (YAML last-wins would " \
                 "silently shadow the earlier section): #{dupes.join(', ')}"
  end

  def test_seeded_document_codes_resolve_cleanly
    store_test_db
    seed_documents
    codes = document_codes
    assert_equal SEEDED_DOCUMENTS.size, codes.size, "every seeded (language, source) pair must census back"
    codes.each { |language, source| assert_resolves_cleanly(language, source: source) }
  end

  def test_every_codemap_key_resolves_cleanly
    assert_codes_resolve_cleanly(codemap_keys)
  end

  def test_every_lect_override_target_resolves_cleanly_through_its_source
    override_sources.each do |source, codes|
      codes.each_key { |code| assert_resolves_cleanly(code, source: source) }
    end
  end

  private

  def seed_documents
    SEEDED_DOCUMENTS.each do |row|
      source = Nabu::Store::Source.find(slug: row[:source]) ||
               Nabu::Store::Source.create(slug: row[:source], name: row[:source],
                                          adapter_class: "X", license_class: "attribution")
      Nabu::Store::Document.create(
        source_id: source.id,
        urn: "urn:nabu:#{row[:source]}:seed-#{source.id}-#{Nabu::Store::Document.count}",
        title: "seed", language: row[:language], content_sha256: "x", revision: 1, withdrawn: false
      )
    end
  end

  # The DISTINCT (language, source-slug) census read back from the documents
  # table itself — source-scoped so the per-source overrides engage exactly as
  # a live resolution would.
  def document_codes
    Nabu::Store::Document.exclude(language: nil).all.map { |doc| [doc.language, doc.source.slug] }.uniq
  end

  def codemap_keys
    YAML.safe_load_file(File.join(FIXTURES, "codemap.yml")).fetch("map", {}).keys
  end

  def override_sources
    YAML.safe_load_file(LECT_OVERRIDES_PATH).fetch("sources", {})
  end

  # THE reusable guard: any Enumerable of codes, no source binding — the
  # one-line swap point for a future live-catalog run.
  def assert_codes_resolve_cleanly(codes)
    codes.each { |code| assert_resolves_cleanly(code) }
  end

  def assert_resolves_cleanly(code, source: nil)
    resolved = lects.resolve(code, source: source)
    return if bare_identity_anchor?(resolved)

    refute_nil lects.lect(resolved),
               "#{code.inspect} (source=#{source.inspect}) resolves to #{resolved.inspect}, " \
               "which is not a lect defined in the nabu-lects registry"
  end

  # A resolved id with no stage/variety/ortho separator is a bare anchor —
  # the identity default rule (codemap.yml, verbatim: "any code not listed
  # maps to itself as a bare anchor... Bare-anchor targets need no registry
  # entry").
  def bare_identity_anchor?(id)
    !id.match?(%r{[:/@]})
  end
end
