# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::SlounikiNasovic (P117, row 253): Насовіч's 1870 Belarusian
# dictionary from github.com/Belarus/Slouniki-Nasovic — one SlounikPlus XML
# article per file, the library's first `be` shelf. Dictionary-shaped, so it
# mirrors the conformance checks for the dictionary shape (the DillmannTest
# mold): manifest, discover→parse round-trip, id uniqueness/stability, NFC,
# license class, the DictionaryLoader contract, plus the entry pins.
#
# Fixtures (test/fixtures/slouniki-nasovic/data/, README there): four whole
# real articles at upstream commit 0970671c — 00007 «А» (two senses with
# examples), 00873 «БЕЗГОЛО´ВИЦА» (three senses, a <gram> label), 00014
# «АБАКУ´ЛИЦЬ» (a pure "см. {…}" cross-reference, no sense), 01256
# «БЛАЖЕ´Й» (an editor's <comment>).
class SlounikiNasovicTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("slouniki-nasovic")
  Nasovic = Nabu::Adapters::SlounikiNasovic

  def adapter = Nasovic.new

  def entry(stem)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "nasovic:#{stem}" } || flunk("no #{stem}")
    document = adapter.parse(ref)
    assert_equal 1, document.size, "one upstream file IS one article"
    document.first
  end

  def test_manifest_and_content_kind
    manifest = Nasovic.manifest
    assert_equal "slouniki-nasovic", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/Public domain/, manifest.license)
    assert_match(/1870/, manifest.credit)
    assert_equal "slouniki-xml", manifest.parser_family
    assert_equal :dictionary, Nasovic.content_kind
  end

  def test_discover_yields_one_ref_per_article_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[nasovic:00007 nasovic:00014 nasovic:00873 nasovic:01256], refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "slouniki-nasovic" })
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_a_be_dictionary_document
    ref = adapter.discover(FIXTURES).first
    document = adapter.parse(ref)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "nasovic", document.slug
    assert_equal "be", document.language
  end

  def test_entry_ids_are_unique_stable_and_nfc
    snapshot = -> { adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).map(&:entry_id) } }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    adapter.discover(FIXTURES).each do |ref|
      adapter.parse(ref).each do |dictionary_entry|
        assert dictionary_entry.headword.unicode_normalized?(:nfc)
        assert dictionary_entry.body.unicode_normalized?(:nfc)
      end
    end
  end

  def test_the_rich_article_keeps_head_senses_examples_and_the_editors_layer
    article = entry("00873")
    assert_equal "00873", article.entry_id
    assert_equal "БЕЗГОЛО´ВИЦА, -ы, с. ж.", article.key_raw, "the 1870 head rides key_raw verbatim"
    assert_equal "БЕЗГОЛО´ВИЦА", article.headword, "the print's stress mark stays in the display form"
    assert_equal Nabu::Normalize.search_form("БЕЗГОЛОВИЦА", language: "be"), article.headword_folded,
                 "the fold drops the spacing stress mark"
    assert_equal "Несчастіе.", article.gloss
    assert_match(/^3\. \(общ\. р\.\) Глупецъ, безтолковый, безпамятный\.$/, article.body)
    assert_match(/^   — Безголовица споткала!$/, article.body)
    assert_match(/\[Сучасны правапіс: безгало´віца\]/, article.body)
    assert_match(/\[Адпаведнікі: няшчасце, бяспамяцтва/, article.body)
    refute_match(/AAAA/, article.body, "the rtf blob is never ingested")
  end

  def test_a_cross_reference_article_has_a_nil_gloss
    article = entry("00014")
    assert_equal "АБАКУ´ЛИЦЬ", article.headword
    assert_nil article.gloss, "no sense upstream — nil is honest"
    assert_match(/см\. \{Абаку´ливаць\}/, article.body, "the reference rides verbatim, braces and all")
  end

  def test_the_editor_comment_is_labeled
    article = entry("01256")
    assert_equal "БЛАЖЕ´Й", article.headword
    assert_match(/\[Заўвага рэдактара: у ранейшых падобных артыкулах/, article.body)
  end

  def test_a_two_sense_article_numbers_its_senses
    article = entry("00007")
    assert_equal "А", article.headword
    assert_equal "Противоп. какъ и въ Русскомъ языкѣ.", article.gloss
    assert_match(/^2\. Соединит\./, article.body)
  end

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "slouniki-nasovic", name: "Насовіч",
                                        adapter_class: "Nabu::Adapters::SlounikiNasovic", license_class: "open")
    2.times do
      result = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 0, result.errored
      assert_equal 4, db[:dictionary_entries].count
    end
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:nasovic:00873"
  ensure
    db&.disconnect
  end

  def test_fetch_sparse_clones_the_article_cone
    Dir.mktmpdir("nabu-nasovic-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(FIXTURES, "data"), upstream)
      FileUtils.mkdir_p(File.join(upstream, "src"))
      File.write(File.join(upstream, "src", "Prepare.java"), "class Prepare {}")
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      work = File.join(root, "canonical")
      nasovic = adapter
      nasovic.define_singleton_method(:repo_url) { upstream }
      report = nasovic.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "data", "00873.xml"))
      refute File.exist?(File.join(work, "src", "Prepare.java")), "the build scripts stay outside the cone"
      assert_equal 4, nasovic.discover(work).count
    end
  end
end
