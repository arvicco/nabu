# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# prakrit-texts (P118-3): the Prakrit Digital Texts Project's TEI tree
# (github.com/aso2101/prakrit_texts) composing the `ollett-tei` family.
# Fixtures (test/fixtures/prakrit-texts/README.md): four trimmed licensed
# files, one trimmed template-comment Āgama (excluded — no grant), the
# trimmed SARIT Sētubandha (excluded — a declared overlap), and, outside
# tei/, the trimmed not-well-formed ācāraniryukti (the quarantine case).
class PrakritTextsTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("prakrit-texts")

  NANDI = "urn:nabu:prakrit-texts:Agam_44_Chuliyaa_01_Moolam_Nandisuyam_003787-s1-3"
  DESINAMAMALA = "urn:nabu:prakrit-texts:DēNāMā-1-2"
  GAUDAVAHO = "urn:nabu:prakrit-texts:GaüḍVa-1-3"
  TARA = "urn:nabu:prakrit-texts:Tārā-1-3"

  STATEMENT = "Prakrit Digital Texts Project. Distributed under a Creative Commons " \
              "Attribution-ShareAlike 4.0 license."

  def conformance_adapter
    Nabu::Adapters::PrakritTexts.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "prakrit-texts"
  end

  def test_manifest
    manifest = Nabu::Adapters::PrakritTexts.manifest
    assert_equal "prakrit-texts", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "ollett-tei", manifest.parser_family
    assert_equal "https://github.com/aso2101/prakrit_texts", manifest.upstream_url
    assert_includes manifest.license, STATEMENT
  end

  def test_discover_admits_only_the_licensed_files
    assert_equal [NANDI, DESINAMAMALA, GAUDAVAHO, TARA], conformance_adapter.discover(FIXTURES).map(&:id)
  end

  def test_exclusions_are_censused_with_reasons_never_silent
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    assert_predicate skips, :clean?
    setu, ayara = skips.notes
    assert_match(%r{\Atei/Pravarasēna/Sētu\.xml: .*urn:nabu:sarit:pravarasena-setubandha}, setu)
    assert_match(%r{\Atei/Śvētāmbarāgama/Agam_01_.*\.xml: no license in the file}, ayara)
  end

  # The exclusion is the grant itself, not the folder: the same template
  # file renamed anywhere under tei/ stays out, and a licensed file moved
  # into the Āgama folder stays in.
  def test_exclusion_follows_the_in_file_grant
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "tei", "Elsewhere"))
      FileUtils.mkdir_p(File.join(root, "tei", "Śvētāmbarāgama"))
      FileUtils.cp(Dir.glob(File.join(FIXTURES, "tei", "Śvētāmbarāgama", "Agam_01_*.xml")).first,
                   File.join(root, "tei", "Elsewhere", "renamed.xml"))
      FileUtils.cp(File.join(FIXTURES, "tei", "Vākpatirāja", "GaüḍVa-1-3.xml"),
                   File.join(root, "tei", "Śvētāmbarāgama", "GaüḍVa-1-3.xml"))
      adapter = conformance_adapter
      assert_equal [GAUDAVAHO], adapter.discover(root).map(&:id)
      assert_equal 1, adapter.discovery_skips(root).skipped_by_rule
    end
  end

  def test_excluded_template_file_also_fails_the_parse_gate
    path = Dir.glob(File.join(FIXTURES, "tei", "Śvētāmbarāgama", "Agam_01_*.xml")).first
    ref = Nabu::DocumentRef.new(source_id: "prakrit-texts", id: "urn:nabu:prakrit-texts:x", path: path, metadata: {})
    error = assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
    assert_match(/license gate/, error.message)
  end

  def test_not_well_formed_upstream_file_quarantines
    path = File.join(FIXTURES, "quarantine", "ācāraniryukti-1-66.xml")
    ref = Nabu::DocumentRef.new(source_id: "prakrit-texts", id: "urn:nabu:prakrit-texts:ācāraniryukti",
                                path: path, metadata: {})
    assert_raises(Nabu::ParseError) { conformance_adapter.parse(ref) }
  end

  def test_every_admitted_file_carries_its_grant_verbatim
    adapter = conformance_adapter
    adapter.discover(FIXTURES).each do |ref|
      doc = adapter.parse(ref)
      assert_equal STATEMENT, doc.metadata["license_statement"], ref.id
      assert_equal "CC BY-SA 4.0", doc.metadata["license"]
      assert_nil doc.metadata["date"], "no composition date is minted for Prakrit works"
    end
  end

  def test_languages_census
    adapter = conformance_adapter
    langs = adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref).language] }
    assert_equal({ NANDI => "pka-Latn", DESINAMAMALA => "pra-Latn", GAUDAVAHO => "pra-Latn", TARA => "pra-Latn" },
                 langs)
  end

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "prakrit-texts", name: "Prakrit Texts",
                                        adapter_class: "Nabu::Adapters::PrakritTexts", license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES,
                                                                                                full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  def test_fetch_sparse_clones_only_the_tei_cone_and_readme
    Dir.mktmpdir("nabu-prakrit-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(FIXTURES, "tei"), upstream)
      File.write(File.join(upstream, "README.md"), "# Prakrit Digital Text Project (PDTP)\n")
      FileUtils.mkdir_p(File.join(upstream, "txt"))
      File.write(File.join(upstream, "txt", "GāSa.txt"), "generated, outside the cone")
      Nabu::Shell.run("git", "init", "-q", upstream)
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")

      adapter = conformance_adapter
      adapter.define_singleton_method(:repo_url) { upstream }
      work = File.join(root, "canonical")
      adapter.fetch(work)
      assert File.file?(File.join(work, "README.md"))
      refute File.exist?(File.join(work, "txt")), "generated txt/ never materializes"
      assert_equal 4, adapter.discover(work).count
      assert_equal 2, adapter.discovery_skips(work).skipped_by_rule
    end
  end

  def test_registered_and_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["prakrit-texts"]
    refute_nil entry
    assert_equal Nabu::Adapters::PrakritTexts, entry.adapter_class
    assert entry.wired, "flipped wired after the verified 2026-10-11 first sync (counts in sources.yml)"
  end
end
