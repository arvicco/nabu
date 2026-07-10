# frozen_string_literal: true

require "test_helper"

# The lexica adapter (P11-4): the first DICTIONARY-shaped source. It cannot
# include the shared AdapterConformance suite — that suite is passage-shaped
# (parse returns Nabu::Document) — so this test mirrors its checks for the
# dictionary shape: manifest validity, discover→parse round-trip, id
# uniqueness and stability across independent passes, NFC output, license
# class present.
class LexicaTest < Minitest::Test
  WORKDIR = Nabu::TestSupport.fixtures("lexica")

  def adapter = Nabu::Adapters::Lexica.new

  def test_manifest_is_valid_and_registered_as_lexica
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "lexica", manifest.id
    assert_equal "attribution", manifest.license_class # CC BY-SA 4.0
    assert_equal "lexicon-tei", manifest.parser_family
    assert_includes manifest.upstream_url, "PerseusDL/lexica"
  end

  def test_content_kind_is_dictionary_while_the_base_default_stays_passages
    assert_equal :dictionary, Nabu::Adapters::Lexica.content_kind
    assert_equal :passages, Nabu::Adapter.content_kind
  end

  def test_discover_yields_one_ref_per_lexicon_file_in_stable_order
    refs = adapter.discover(WORKDIR).to_a
    assert_equal %w[
      lexica:lewis-short:lat.ls.perseus-eng2.xml
      lexica:lsj:grc.lsj.perseus-eng12.xml
      lexica:lsj:grc.lsj.perseus-eng13.xml
    ], refs.map(&:id).sort
    refs.each { |ref| assert_equal "lexica", ref.source_id }
  end

  def test_parse_yields_dictionary_documents_with_entries
    adapter.discover(WORKDIR).each do |ref|
      document = adapter.parse(ref)
      assert_kind_of Nabu::DictionaryDocument, document
      refute_empty document.entries, "#{ref.id} parsed to zero entries"
      assert_includes %w[lsj lewis-short], document.slug
    end
  end

  def test_lsj_files_parse_greek_and_lewis_short_latin
    docs = adapter.discover(WORKDIR).map { |ref| adapter.parse(ref) }
    assert_equal({ "lewis-short" => "lat", "lsj" => "grc" },
                 docs.to_h { |doc| [doc.slug, doc.language] })
  end

  def test_entry_output_is_nfc
    adapter.discover(WORKDIR).each do |ref|
      adapter.parse(ref).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  def test_entry_ids_are_unique_within_each_dictionary_across_the_discover_set
    seen = Hash.new { |hash, key| hash[key] = [] }
    adapter.discover(WORKDIR).each do |ref|
      document = adapter.parse(ref)
      document.each { |entry| seen[document.slug] << entry.entry_id }
    end
    seen.each do |slug, ids|
      assert_equal ids.uniq, ids, "duplicate entry ids in #{slug}"
    end
  end

  def test_ids_and_entries_are_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(WORKDIR).map do |ref|
        document = adapter.parse(ref)
        [ref.id, document.slug, document.map(&:entry_id)]
      end
    end
    assert_equal snapshot.call, snapshot.call
  end

  def test_only_the_unicode_lewis_short_variant_is_discovered
    ids = adapter.discover(WORKDIR).map(&:id)
    assert(ids.none? { |id| id.include?("eng1.xml") },
           "the betacode-archival lat.ls.perseus-eng1.xml must never be ingested")
  end
end
