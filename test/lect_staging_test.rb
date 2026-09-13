# frozen_string_literal: true

require "test_helper"

# Nabu::LectStaging (P99-5 — the P59-4 front-door bullet, finally
# adopted): the post-sync one-liner's data — for one synced source, how
# many live documents of STAGEABLE languages (anchors carrying minted
# stages in the registry) still resolve to bare identity (no lect facet
# row — the LectFacets "no row means identity" invariant). Languages
# with no stages defined never count: 0-unstaged there is the healthy
# steady state, not a gap (the Q71 lesson).
class LectStagingTest < Minitest::Test
  include StoreTestDB

  Ladder = Data.define(:anchor, :name, :stages, :varieties)

  FakeLects = Struct.new(:ladders)

  def setup
    @db = store_test_db
    @src = Nabu::Store::Source.create(slug: "edh", name: "EDH", adapter_class: "X",
                                      license_class: "open")
    @lects = FakeLects.new([
                             Ladder.new(anchor: "la", name: "Latin", stages: %w[old late], varieties: []),
                             Ladder.new(anchor: "zho", name: "Chinese", stages: [], varieties: %w[lit])
                           ])
  end

  def doc(urn, language, withdrawn: false)
    Nabu::Store::Document.create(source_id: @src.id, urn: urn, language: language,
                                 title: "t", canonical_path: urn,
                                 content_sha256: Digest::SHA256.hexdigest(urn),
                                 withdrawn: withdrawn)
  end

  def stage(document, value)
    @db[:document_facets].insert(document_id: document.id, facet: "lect", value: value)
  end

  def census
    Nabu::LectStaging.census(catalog: @db, lects: @lects, slug: "edh")
  end

  def test_counts_identity_docs_of_stageable_languages_only
    stage(doc("urn:e:1", "la"), "la:late")
    doc("urn:e:2", "la")                       # identity — unstaged
    doc("urn:e:3", "xcl")                      # no ladder — never counted
    doc("urn:e:4", "zho")                      # varieties only, no stages — never counted
    doc("urn:e:5", "la", withdrawn: true)      # withdrawn — never counted

    result = census
    assert_equal 2, result.stageable
    assert_equal 1, result.unstaged
    assert_equal ["la"], result.codes
  end

  def test_nil_when_nothing_stageable_is_held
    doc("urn:e:1", "xcl")
    assert_nil census, "no stageable language in the source — honest silence, not a zero line"
  end

  def test_nil_without_a_registry
    assert_nil Nabu::LectStaging.census(catalog: @db, lects: nil, slug: "edh"),
               "no registry = lane off"
  end

  def test_nil_for_an_unknown_source
    assert_nil Nabu::LectStaging.census(catalog: @db, lects: @lects, slug: "ghost")
  end
end
