# frozen_string_literal: true

require "test_helper"

# Store::DerivationStamp.derived_languages (P39-1): the honest per-source
# language census behind the fold-digest granularity — the distinct language
# tags across a source's derived rows (documents, passages, dictionaries,
# dictionary reflexes). The asymmetry doctrine applies: nil (unknowable, e.g.
# a pre-migration catalog) makes the fingerprint consult ALL fold modules
# (dirty-more); a missed language would silently under-rebuild (the sin), so
# every language-bearing derived table participates.
class DerivationStampLanguagesTest < Minitest::Test
  include StoreTestDB

  def setup
    @db = store_test_db
  end

  def teardown
    @db.disconnect
  end

  def test_census_unions_documents_passages_and_dictionary_languages
    source_id = insert_source("cjk")
    doc_id = insert_document(source_id, urn: "urn:nabu:cjk:d1", language: "lzh")
    insert_passage(doc_id, urn: "urn:nabu:cjk:d1:1", language: "jpn")
    dict_id = insert_dictionary(source_id, slug: "cjk-dict", language: "och")
    entry_id = insert_entry(dict_id, urn: "urn:nabu:cjk:e1")
    insert_reflex(entry_id, language: "grc")

    assert_equal %w[grc jpn lzh och], languages("cjk")
  end

  def test_census_is_empty_for_a_source_with_no_language_bearing_rows
    insert_source("bare")
    assert_equal [], languages("bare")
  end

  def test_census_is_empty_for_an_unknown_slug
    assert_equal [], languages("never-synced")
  end

  def test_census_ignores_null_languages_and_other_sources
    source_id = insert_source("mine")
    other_id = insert_source("other")
    doc_id = insert_document(source_id, urn: "urn:nabu:mine:d1", language: nil)
    insert_passage(doc_id, urn: "urn:nabu:mine:d1:1", language: "grc")
    other_doc = insert_document(other_id, urn: "urn:nabu:other:d1", language: "jpn")
    insert_passage(other_doc, urn: "urn:nabu:other:d1:1", language: "jpn")

    assert_equal %w[grc], languages("mine")
  end

  def test_census_is_unknowable_on_a_catalog_missing_the_tables
    # Dirty-more: a catalog that cannot answer must return nil so the
    # fingerprint consults every fold module.
    bare = Nabu::Store.connect("sqlite::memory:")
    assert_nil Nabu::Store::DerivationStamp.derived_languages(bare, "any")
  ensure
    bare&.disconnect
  end

  private

  def languages(slug)
    Nabu::Store::DerivationStamp.derived_languages(@db, slug)
  end

  def insert_source(slug)
    @db[:sources].insert(slug: slug, name: slug, adapter_class: "TestAdapter",
                         license_class: "open")
  end

  def insert_document(source_id, urn:, language:)
    @db[:documents].insert(source_id: source_id, urn: urn, language: language,
                           content_sha256: "0" * 64)
  end

  def insert_passage(document_id, urn:, language:)
    @db[:passages].insert(document_id: document_id, urn: urn, sequence: 0,
                          language: language, text: "x", text_normalized: "x",
                          content_sha256: "0" * 64)
  end

  def insert_dictionary(source_id, slug:, language:)
    @db[:dictionaries].insert(source_id: source_id, slug: slug, title: slug, language: language)
  end

  def insert_entry(dictionary_id, urn:)
    @db[:dictionary_entries].insert(dictionary_id: dictionary_id, urn: urn, entry_id: urn,
                                    key_raw: "k", headword: "k", headword_folded: "k",
                                    body: "b", content_sha256: "0" * 64)
  end

  def insert_reflex(entry_id, language:)
    @db[:dictionary_reflexes].insert(dictionary_entry_id: entry_id, seq: 0,
                                     lang_code: language.to_s, language: language, word: "w")
  end
end
