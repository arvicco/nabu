# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::SourceContentIdentity: one source's LIVE derived content
  # named by a digest of its documents' (and dictionary entries') content
  # shas — the member identity a links scope stamp folds in. Content-keyed
  # on purpose (the vectors precedent): a content-neutral code change leaves
  # it alone, any change to what a producer can read moves it.
  class SourceContentIdentityTest < Minitest::Test
    include StoreTestDB

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(slug: "aspr", name: "A", adapter_class: "X", license_class: "open")
      @doc = document("urn:nabu:aspr:1", sha: "a" * 64)
    end

    def document(urn, sha:, withdrawn: false)
      Nabu::Store::Document.create(source_id: @source.id, urn: urn, title: "t", language: "ang",
                                   content_sha256: sha, withdrawn: withdrawn)
    end

    def identity(slugs = ["aspr"]) = Nabu::Store::SourceContentIdentity.for_slugs(@db, slugs)

    def test_identity_is_stable_and_keyed_by_slug
      first = identity
      assert_equal first, identity
      assert_match(/\A\h{64}\z/, first.fetch("aspr"))
    end

    def test_a_document_content_change_moves_the_identity
      before = identity
      @doc.update(content_sha256: "b" * 64)
      refute_equal before, identity
    end

    def test_withdrawn_tombstones_are_not_content
      before = identity
      document("urn:nabu:aspr:gone", sha: "c" * 64, withdrawn: true)
      assert_equal before, identity, "an incremental's tombstone must not differ from a full rebuild's absence"
    end

    def test_license_posture_is_content_a_license_filter_can_read
      before = identity
      @doc.update(license_override: "nc")
      refute_equal before, identity
      @doc.update(license_override: nil)
      @source.update(license_class: "attribution")
      refute_equal before, identity
    end

    def test_dictionary_entries_are_content
      before = identity
      dictionary = @db[:dictionaries].insert(source_id: @source.id, slug: "bt", title: "BT", language: "ang")
      @db[:dictionary_entries].insert(dictionary_id: dictionary, urn: "urn:nabu:bt:1", entry_id: "1",
                                      key_raw: "k", headword: "h", headword_folded: "h", body: "b",
                                      content_sha256: "d" * 64)
      refute_equal before, identity
    end

    def test_an_unknown_slug_reads_absent_not_an_error
      assert_equal "absent", identity(["nope"]).fetch("nope")
    end
  end
end
