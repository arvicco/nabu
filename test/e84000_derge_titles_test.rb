# frozen_string_literal: true

require "test_helper"

# Nabu::E84000DergeTitles (P106-5 — the Q78 e84000 lode 2): every 84000
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

  def derge_doc(source_id, shelf, slug)
    @catalog[:documents].insert(source_id: source_id, urn: "urn:nabu:#{shelf}:#{slug}",
                                language: "xct", content_sha256: "x")
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

  def test_absent_e84000_tree_is_a_clean_no_op
    result = Nabu::E84000DergeTitles.new(catalog: @catalog,
                                         canonical_dir: File.join(FIXTURES_ROOT, "nope")).run
    assert_equal 0, result.titled
    assert_nil titles["urn:nabu:derge-kangyur:toh767"]
  end
end
