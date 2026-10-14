# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::OldNubianUd: the Old Nubian Universal Dependencies
# treebank (github.com/Innokentii-Smirnov/OldNubianUDTreebank) — one
# CoNLL-U file, OldNubian.conllu, 124 sentences of medieval Old Nubian in
# Latin transliteration with UD dependency annotation. A thin composition
# of the shared ConlluParser (the old-tibetan mold), git-fetched.
#
# Fixture: ten real sentence blocks, byte-verbatim (README). They carry
# the file's quirks: a decomposed g + combining caron (non-NFC upstream —
# the adapter boundary normalizes tokens as well as text), CorrectForm
# MISC fields, lacuna brackets, Russian and English translation comments,
# and empty translations.
class OldNubianUdTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("old-nubian-ud")
  URN = "urn:nabu:old-nubian-ud:OldNubian"

  def conformance_adapter = Nabu::Adapters::OldNubianUd.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "old-nubian-ud"

  def adapter = conformance_adapter

  def document
    @document ||= adapter.parse(adapter.discover(FIXTURES).first)
  end

  def passage(sent_id) = document.find { |p| p.urn == "#{URN}:#{sent_id}" } || flunk("no sentence #{sent_id}")

  # -- discover ---------------------------------------------------------------

  def test_discovers_the_one_treebank_file_as_one_document
    refs = adapter.discover(FIXTURES).to_a
    assert_equal [URN], refs.map(&:id)
    assert_equal File.expand_path(File.join(FIXTURES, "OldNubian.conllu")), refs.first.path
  end

  def test_only_the_main_conllu_is_discovered_never_the_sidecars
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "OldNubian.conllu"), dir)
      File.write(File.join(dir, "MorphosyntacticWords.tsv"), "MSeg\tlemma\tfeats\tgloss\tupos\tform\n")
      FileUtils.mkdir_p(File.join(dir, "MorphemeSegmentationForUniversalDependencies", "test"))
      FileUtils.cp(File.join(FIXTURES, "OldNubian.conllu"),
                   File.join(dir, "MorphemeSegmentationForUniversalDependencies", "test", "sample.conllu"))
      assert_equal [URN], adapter.discover(dir).map(&:id)
    end
  end

  # -- parse ------------------------------------------------------------------

  def test_the_document_is_old_nubian_cited_by_sent_id
    assert_equal "onw", document.language
    assert_equal "Old Nubian UD Treebank", document.title
    assert_equal 10, document.count, "the ten fixture blocks"
    first = document.first
    assert_equal "#{URN}:0", first.urn
    assert_equal "ṅokkora khristosin martyros-u-ṅiss-u-minana awsa-lo tillin tokinnawėlo amin", first.text
  end

  def test_the_transliteration_text_is_nfc_at_the_boundary
    text = passage(6).text
    assert text.unicode_normalized?(:nfc)
    assert_includes text, "inṅeynǧuriȧ".unicode_normalize(:nfc)
  end

  def test_token_columns_are_nfc_too_so_forms_match_the_text
    tokens = passage(6).annotations["tokens"]
    guria = tokens.find { |t| t["id"] == "3" }
    assert_equal "ǧuriȧ".unicode_normalize(:nfc), guria["form"],
                 "upstream writes g + U+030C; the token must match the NFC passage text"
    assert guria["misc"].unicode_normalized?(:nfc)
    refute(document.any? { |p| JSON.generate(p.annotations).unicode_normalize(:nfc) != JSON.generate(p.annotations) })
  end

  def test_ud_tokens_carry_the_dependency_tree_and_the_morpheme_layer
    tokens = passage(0).annotations["tokens"]
    first = tokens.first
    assert_equal({ "id" => "1", "form" => "ṅokkora", "lemma" => "ṅokkor", "upos" => "NOUN",
                   "feats" => "Case=Abs|Number=Sing", "head" => "0", "deprel" => "root",
                   "misc" => "Gloss=чудо|MGloss=чудо-ABS|MSeg=ṅokkor-a" }, first)
    assert_equal({ "id" => "3-6", "form" => "martyros-u-ṅiss-u-minana" }, tokens.find { |t| t["id"] == "3-6" })
  end

  def test_correct_form_misc_rides_verbatim
    tdir = passage(100).annotations["tokens"].find { |t| t["form"] == "tdir" }
    assert_match(/\ACorrectForm=tril\|/, tdir["misc"], "the annotator's emendation is upstream's MISC, kept")
  end

  def test_translation_comments_ride_in_both_languages_and_empty_ones_mint_nothing
    assert_equal({ "translation" => "Чудо, которое совершил св. мученик Христов Мина. В милости божией, аминь." },
                 passage(0).annotations["translations"])
    assert_equal({ "translation" => "And they called him Emmanuel." }, passage(121).annotations["translations"])
    assert_nil passage(118).annotations["translations"], "an empty `# translation =` is no translation"
  end

  def test_lacuna_brackets_ride_verbatim
    assert_includes passage(75).text, "[*****]titta"
    assert passage(118).text.start_with?("[p]estakol kiriṅi[kon]")
  end

  def test_document_metadata_records_the_treebank_and_its_grant
    meta = document.metadata
    assert_equal "OldNubian.conllu", meta["file"]
    assert_equal "Latn", meta["script"], "measured: a Latin transliteration, no Coptic-block character"
  end

  # -- store ------------------------------------------------------------------

  def test_load_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "old-nubian-ud", name: "Old Nubian UD",
                                        adapter_class: "Nabu::Adapters::OldNubianUd", license_class: "nc")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 1, first.added
    assert_equal 10, db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 1, second.skipped
    assert_equal 10, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # -- fetch: whole-repo git clone (local git, no network) --------------------

  def test_fetch_clones_the_repo_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-old-nubian-ud-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")
      fetcher = adapter
      fetcher.define_singleton_method(:repo_url) { upstream }
      report = fetcher.fetch(work)
      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal [URN], fetcher.discover(work).map(&:id)
    end
  end

  # -- manifest + registry ----------------------------------------------------

  def test_manifest_records_the_author_license_verbatim
    manifest = Nabu::Adapters::OldNubianUd.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license,
                    "The treebank is licensed under the Attribution-NonCommercial-ShareAlike 4.0 International"
    assert_includes manifest.license, "Innokentii Smirnov"
    assert_equal "conllu", manifest.parser_family
  end

  def test_registry_row_is_wired_on_the_africa_desk
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["old-nubian-ud"]
    refute_nil entry, "old-nubian-ud must be registered in config/sources.yml"
    assert_equal "Nabu::Adapters::OldNubianUd", entry.adapter_class_name
    assert entry.wired, "first real sync verified 2026-10-14 (1 doc / 124 passages)"
    assert_equal "manual", entry.sync_policy
    assert_equal ["africa"], entry.axes
  end

  private

  # A local upstream shaped like the real repo: the treebank, the license,
  # and the morpheme-segmentation sidecars.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(upstream)
    FileUtils.cp(File.join(FIXTURES, "OldNubian.conllu"), upstream)
    File.write(File.join(upstream, "LICENSE.txt"),
               "The treebank is licensed under the Attribution-NonCommercial-ShareAlike 4.0 International.\n")
    File.write(File.join(upstream, "MorphosyntacticWords.tsv"), "MSeg\tlemma\tfeats\tgloss\tupos\tform\n")
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
