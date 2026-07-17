# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# SARIT adapter tests (P26-2). The adapter composes SaritParser (the sibling
# rung-strategy TEI family) with the flat corpus repo layout: discover globs
# the top-level *.xml, skipping the teiCorpus wrapper and the header template
# by rule; parse delegates to SaritParser (per-file license gate, Devanagari
# search transcode); fetch clones/pulls the single upstream repo. Includes
# the shared AdapterConformance suite, double-load idempotency, and the
# both-scripts folded-lookup proof (one IAST query landing on the IAST and
# the Devanagari shelves alike).
class SaritTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("sarit")

  ASTAVAKRA = "urn:nabu:sarit:astavakragita"
  SAMANYA = "urn:nabu:sarit:samanyadusana"
  NYAYA = "urn:nabu:sarit:vatsyayana-nyayabhasya-s1-2"
  MBH = "urn:nabu:sarit:mahabharata-devanagari-adi1-svarga1"

  ALL_FIXTURES = [ASTAVAKRA, MBH, SAMANYA, NYAYA].freeze # discover order (sorted by urn)

  # --- AdapterConformance hooks --------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Sarit.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "sarit"
  end

  # Devanagari editions mint text_normalized from the documented Deva→IAST
  # transcode of the pristine text (conventions §9 / the ccmh-txt
  # documented-derivation precedent) — recomputable from the stored passage
  # alone via its language tag.
  def conformance_search_source(passage)
    passage.language.split("-").include?("Deva") ? Nabu::Deva.to_iast(passage.text) : passage.text
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Sarit.manifest
    assert_equal "sarit", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/MIT/, manifest.license)
    assert_equal "https://github.com/sarit/SARIT-corpus", manifest.upstream_url
    assert_equal "sarit", manifest.parser_family
  end

  # --- discover -------------------------------------------------------------

  def test_discover_mints_literal_filename_slugs_with_language_and_title
    refs = Nabu::Adapters::Sarit.new.discover(FIXTURES).to_a
    assert_equal ALL_FIXTURES.sort, refs.map(&:id)
    refs.each do |ref|
      assert_equal "sarit", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      refute_nil ref.metadata["title"]
    end
    by_id = refs.to_h { |ref| [ref.id, ref] }
    assert_equal "san-Latn", by_id[ASTAVAKRA].metadata["language"]
    assert_equal "san-Deva", by_id[SAMANYA].metadata["language"]
    assert_equal "san-Deva", by_id[MBH].metadata["language"]
    assert_equal "Aṣṭāvakragītā", by_id[ASTAVAKRA].metadata["title"]
  end

  def test_discover_skips_the_corpus_wrapper_and_template_by_rule
    Dir.mktmpdir do |root|
      FileUtils.cp(File.join(FIXTURES, "astavakragita.xml"), root)
      File.write(File.join(root, "saritcorpus.xml"),
                 "<teiCorpus xmlns=\"http://www.tei-c.org/ns/1.0\"><teiHeader/></teiCorpus>\n")
      File.write(File.join(root, "00-sarit-tei-header-template.xml"), "<TEI><teiHeader/></TEI>\n")
      adapter = Nabu::Adapters::Sarit.new
      assert_equal [ASTAVAKRA], adapter.discover(root).to_a.map(&:id)
      assert_equal 2, adapter.discovery_skips(root).skipped_by_rule
      assert_predicate adapter.discovery_skips(root), :clean?
    end
  end

  # The six real corpus files that declare NO language anywhere get the
  # script sniff: first body text in Devanagari → san-Deva, else san-Latn.
  def test_discover_sniffs_script_for_undeclared_language_editions
    Dir.mktmpdir do |root|
      base = File.read(File.join(FIXTURES, "samanyadusana.xml"))
      File.write(File.join(root, "undeclared-deva.xml"), base.sub(' xml:lang="sa-Deva"', ""))
      latn = File.read(File.join(FIXTURES, "astavakragita.xml"))
                 .sub(' xml:lang="sa-Latn"', "").sub(' xml:id="aṣṭāvakragītā"', "")
      File.write(File.join(root, "undeclared-latn.xml"), latn)
      refs = Nabu::Adapters::Sarit.new.discover(root).to_a.to_h { |r| [r.id.split(":").last, r] }
      assert_equal "san-Deva", refs["undeclared-deva"].metadata["language"]
      assert_equal "san-Latn", refs["undeclared-latn"].metadata["language"]
    end
  end

  # --- parse round-trip + per-document license -------------------------------

  def test_parse_carries_the_per_document_grant
    adapter = Nabu::Adapters::Sarit.new
    licenses = adapter.discover(FIXTURES).to_h do |ref|
      [ref.id, adapter.parse(ref).metadata["license"]]
    end
    assert_equal "CC BY-SA 3.0", licenses[ASTAVAKRA]
    assert_equal "CC BY-SA 4.0", licenses[SAMANYA]
    assert_equal "CC BY-SA 3.0", licenses[NYAYA]
    assert_equal "CC BY-SA 3.0", licenses[MBH]
  end

  # --- load: idempotency (the house double-load rule) ------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = sarit_source
    loader = Nabu::Store::Loader.new(db: catalog, source: source)
    first = loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored

    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                 "an unchanged corpus must not fake content revisions"
  end

  # --- the both-scripts folded lookup (the packet's script verdict, proven) --

  def test_one_iast_query_lands_on_both_scripts
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Loader.new(db: catalog, source: sarit_source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    # Aṣṭāvakragītā 1.1 spells it in IAST; the same folded form must ALSO be
    # findable where the surface is Devanagari.
    search = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)
    iast_hits = search.run("kathaṃ jñānamavāpnoti", limit: 10)
    assert(iast_hits.any? { |hit| hit.urn == "#{ASTAVAKRA}:1.1" },
           "IAST query must find the IAST surface (got #{iast_hits.map(&:urn).inspect})")

    # The MBh invocation, surface नारायणं नमस्कृत्य — found by its IAST spelling.
    deva_hits = search.run("nārāyaṇaṃ namaskṛtya", limit: 10)
    assert(deva_hits.any? { |hit| hit.urn == "#{MBH}:1-1-1" },
           "IAST query must find the Devanagari surface (got #{deva_hits.map(&:urn).inspect})")
    hit = deva_hits.find { |h| h.urn == "#{MBH}:1-1-1" }
    assert_includes hit.text, "नारायणं", "display text keeps the native Devanagari surface"

    # And an unaccented ASCII-ish query folds onto the Devanagari shelf too.
    ascii_hits = search.run("vyapakam nityamekam", limit: 10)
    assert(ascii_hits.any? { |hit| hit.urn == "#{SAMANYA}:v1" },
           "bare-ASCII query must fold onto the Devanagari surface (got #{ascii_hits.map(&:urn).inspect})")
  ensure
    fulltext&.disconnect
  end

  # --- fetch (local git only, no network) ------------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = sarit_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = sarit_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_sarit_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["sarit"]
    refute_nil entry, "sarit must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Sarit, entry.adapter_class
    assert_equal "manual", entry.sync_policy
    refute entry.enabled, "sarit stays enabled: false until the owner-fired first real sync"
  end

  private

  def sarit_source
    Nabu::Store::Source.create(
      slug: "sarit", name: "SARIT", adapter_class: "Nabu::Adapters::Sarit",
      license_class: "attribution"
    )
  end

  def sarit_pointing_at(upstream)
    adapter = Nabu::Adapters::Sarit.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "dummy.xml"), "<TEI/>\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
