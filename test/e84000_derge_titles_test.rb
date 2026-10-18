# frozen_string_literal: true

require "test_helper"

# Nabu::E84000DergeTitles (P106-5 — the e84000 sidecar lode 2): every 84000
# header — the 3,926 placeholder stubs AND the published translations —
# carries the Tibetan (Wylie) and English titles of its Toh text, and the
# derge shelves mint those texts title-less. The pass reads the headers
# off canonical/e84000 and titles the matching derge documents by EXACT
# Toh key ("toh846a" titles derge toh846a; a part key titles the part
# document; no base-container inference). Derived by construction:
# f(canonical/e84000 + the loaded derge rows) — idempotent re-fill at
# rebuild, builder refresh, and after e84000/derge syncs.
class E84000DergeTitlesTest < Minitest::Test
  FIXTURES_ROOT = File.expand_path("fixtures", __dir__)

  def setup
    @catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(@catalog)
    @kangyur = @catalog[:sources].insert(slug: "derge-kangyur", name: "K", adapter_class: "X",
                                         license_class: "open")
    @tengyur = @catalog[:sources].insert(slug: "derge-tengyur", name: "T", adapter_class: "X",
                                         license_class: "open")
    %w[toh767 toh846a toh539e toh774 toh1].each { |slug| derge_doc(@kangyur, "derge-kangyur", slug) }
    derge_doc(@tengyur, "derge-tengyur", "toh3156")
  end

  def teardown
    @catalog.disconnect
  end

  def derge_doc(source_id, shelf, slug, metadata: nil)
    row = { source_id: source_id, urn: "urn:nabu:#{shelf}:#{slug}", language: "xct", content_sha256: "x" }
    row[:metadata_json] = JSON.generate(metadata) if metadata
    @catalog[:documents].insert(row)
  end

  def titles
    @catalog[:documents].order(:urn).select_hash(:urn, :title)
  end

  def run_pass
    Nabu::E84000DergeTitles.new(catalog: @catalog, canonical_dir: FIXTURES_ROOT).run
  end

  def test_titles_derge_documents_from_placeholder_and_published_headers
    result = run_pass
    assert_equal "Tantra of the Supreme Dancer of the Yakṣas (gnod sbyin gar mkhan mchog gyi rgyud)",
                 titles["urn:nabu:derge-kangyur:toh767"], "placeholder stub titles its text, shad stripped"
    assert_equal "The Threefold Ritual (rgyud gsum pa)", titles["urn:nabu:derge-kangyur:toh846a"]
    assert_equal "The Dhāraṇī of Siṃhanāda (seng ge sgra’i gzungs)",
                 titles["urn:nabu:derge-tengyur:toh3156"], "tengyur routes to its own shelf"
    assert_operator result.titled, :>=, 4
  end

  def test_a_multi_toh_publication_titles_every_key_it_carries
    run_pass
    expected = "The Dhāraṇī of the Polished Gem (rin po che brdar ba’i gzungs)"
    assert_equal expected, titles["urn:nabu:derge-kangyur:toh539e"]
    assert_equal expected, titles["urn:nabu:derge-kangyur:toh774"]
  end

  def test_documents_without_crosswalk_data_stay_untouched
    run_pass
    assert_nil titles["urn:nabu:derge-kangyur:toh1"], "no fixture header names toh1"
  end

  def test_keys_without_a_derge_document_are_censused_not_invented
    result = run_pass
    assert_operator result.missing_docs, :>=, 1, "toh1074 and toh761 have no derge doc seeded here"
    refute titles.key?("urn:nabu:derge-kangyur:toh1074")
  end

  def test_idempotent_re_run
    run_pass
    first = titles
    result = run_pass
    assert_equal first, titles
    assert_operator result.titled, :>=, 4, "re-fill is the contract — the pass converges"
  end

  # -- the persons half of the same seam ---------------------------------------
  # Each header's sourceDesc bibl names its text's persons — role-less
  # original authors, contested attributions, Tibetan translators. The pass
  # merges them into the matching derge document's metadata (exact key,
  # published over placeholder, like titles) and writes that document's
  # author / author_contested / translator facet rows itself: the facet
  # builders run before this pass, and config/facet_map.yml re-projects the
  # same rows from the merged metadata on any later facet refresh.

  def metadata_of(urn)
    JSON.parse(@catalog[:documents].where(urn: urn).get(:metadata_json) || "{}")
  end

  def facets_of(urn)
    id = @catalog[:documents].where(urn: urn).get(:id)
    @catalog[:document_facets].where(document_id: id).order(:facet, :value).select_map(%i[facet value])
  end

  def test_placeholder_persons_merge_into_derge_metadata_with_facets
    derge_doc(@tengyur, "derge-tengyur", "toh1127", metadata: { "volume" => "ka" })
    result = run_pass
    meta = metadata_of("urn:nabu:derge-tengyur:toh1127")
    assert_equal "ka", meta["volume"], "the loader's own metadata survives the merge"
    assert_equal [{ "name" => "Rāhulabhadra", "role" => "authorContested", "lang" => "Sa-Ltn" },
                  { "name" => "Nāgārjuna", "role" => "authorContested", "lang" => "Sa-Ltn" },
                  { "name" => "Tilakakalaśa (Kaśmīr)", "role" => "translatorTib", "lang" => "Sa-Ltn" },
                  { "name" => "lo tsA ba blo ldan shes rab", "role" => "translatorTib", "lang" => "Bo-Ltn" }],
                 meta["persons"]
    assert_equal %w[Rāhulabhadra Nāgārjuna], meta["authors_contested"]
    assert_equal ["Tilakakalaśa (Kaśmīr)", "lo tsA ba blo ldan shes rab"], meta["translators_tib"]
    assert_nil meta["authors"]
    assert_equal [%w[author_contested Nāgārjuna], %w[author_contested Rāhulabhadra],
                  ["translator", "Tilakakalaśa (Kaśmīr)"], ["translator", "lo tsA ba blo ldan shes rab"]],
                 facets_of("urn:nabu:derge-tengyur:toh1127")
    assert_operator result.persons, :>=, 2
  end

  def test_published_original_author_reaches_its_own_bibl_key
    derge_doc(@tengyur, "derge-tengyur", "toh2006")
    run_pass
    meta = metadata_of("urn:nabu:derge-tengyur:toh2006")
    assert_equal ["Tathāgata­rakṣita"], meta["authors"], "the toh2006 bibl's role-less author, verbatim"
    assert_equal [{ "name" => "Tathāgata­rakṣita", "role" => "author", "lang" => "Sa-Ltn" }], meta["persons"]
    assert_equal [%w[author Tathāgata­rakṣita]], facets_of("urn:nabu:derge-tengyur:toh2006")
    assert_equal "The Myth Chapter (gtam rgyud kyi rtog pa)", titles["urn:nabu:derge-tengyur:toh2006"],
                 "a Kangyur file's Tengyur bibl routes by its own location/@work, titles included"
    assert_equal ["Tsultrim Gyaltsen"], metadata_of("urn:nabu:derge-tengyur:toh3156")["translators_tib"]
  end

  def test_persons_pass_is_idempotent_and_drops_stale_claims
    derge_doc(@tengyur, "derge-tengyur", "toh1127")
    @catalog[:documents].where(urn: "urn:nabu:derge-kangyur:toh1")
                        .update(metadata_json: JSON.generate("persons" => [{ "name" => "stale" }],
                                                             "authors" => ["stale"]))
    run_pass
    first = [metadata_of("urn:nabu:derge-tengyur:toh1127"), @catalog[:document_facets].count]
    run_pass
    assert_equal first, [metadata_of("urn:nabu:derge-tengyur:toh1127"), @catalog[:document_facets].count]
    assert_equal({}, metadata_of("urn:nabu:derge-kangyur:toh1"),
                 "a key no header names any more loses its derived persons")
  end

  def test_absent_e84000_tree_is_a_clean_no_op
    result = Nabu::E84000DergeTitles.new(catalog: @catalog,
                                         canonical_dir: File.join(FIXTURES_ROOT, "nope")).run
    assert_equal 0, result.titled
    assert_nil titles["urn:nabu:derge-kangyur:toh767"]
  end
end
