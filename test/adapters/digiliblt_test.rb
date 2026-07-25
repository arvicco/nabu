# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Digiliblt (P45-3): digilibLT — Biblioteca digitale di testi
# latini tardoantichi (Vercelli/UniUPO), via CIRCSE's LiLa-linked CoNLL-U
# repo (github.com/CIRCSE/digilibLT): 373 late-antique secular Latin prose
# texts (2nd–7th c. AD), UDPipe-lemmatized — the classical→medieval
# transition band, and the romance axis's first ancestor shelf.
#
# THE SILVER TIER: the README calls its own linking a "*Bronze* version"
# ("The output of UDPipe still needs checking and disambiguating"), i.e.
# machine annotation → `lemma_tier: silver`, every hit labeled (the GLAUx
# precedent). The fixture's real bytes carry the evidence: dlt000619's
# "rovinciae → rovintia" and "defensaeque → defensaes" are UDPipe inventions
# no hand-checked lemma layer would ship.
#
# Fixture: real bytes from the repo's conllu/part*.tar.gz archives
# (2026-07-25) laid out as the post-fetch extracted tree (texts/part*/).
class DigilibltTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  EUANTIUS_URN = "urn:nabu:digiliblt:dlt000173"
  MACROBIUS_URN = "urn:nabu:digiliblt:dlt000340"
  DECRETUM_URN = "urn:nabu:digiliblt:dlt000619"

  def conformance_adapter = Nabu::Adapters::Digiliblt.new

  def conformance_workdir = Nabu::TestSupport.fixtures("digiliblt")

  def conformance_expected_source_id = "digiliblt"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_extracted_conllu_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [EUANTIUS_URN, MACROBIUS_URN, DECRETUM_URN], refs.map(&:id),
                 "one document per texts/part*/<dlt-id>.xml_linked.conllu, urn " \
                 "urn:nabu:digiliblt:<dlt-id>, sorted"
    assert(refs.all? { |ref| ref.source_id == "digiliblt" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_discover_ignores_files_outside_the_texts_tree
    refute_includes adapter.discover(workdir).to_a.map(&:path),
                    File.join(workdir, "malformed", "dlt000079-head.conllu"),
                    "only the extracted texts/ tree is ingestible"
  end

  # -- parse ------------------------------------------------------------------

  def test_parses_euantius_at_sentence_grain_with_a_known_latin_snippet
    document = adapter.parse(ref_for(EUANTIUS_URN))
    assert_equal "lat", document.language
    assert_equal "Euantius — De comoedia uel de fabula", document.title
    assert_equal 55, document.count
    first = document.first
    assert_equal "#{EUANTIUS_URN}:1", first.urn
    assert_match(/\AInitium tragoediae et comoediae a rebus diuinis est incohatum/, first.text)
    assert_equal "Paragraphus_1,Sentence_1", first.annotations["citation"]
  end

  def test_document_metadata_journals_the_source_edition
    metadata = adapter.parse(ref_for(EUANTIUS_URN)).metadata
    assert_equal "Euantius", metadata["author"]
    assert_equal "dlt000173", metadata["doc_id"]
    assert_match(/Cupaiuolo/, metadata["source_description"])
  end

  def test_no_document_carries_a_license_override
    adapter.discover(workdir).each do |ref|
      assert_nil adapter.parse(ref).license_override,
                 "digilibLT is one license corpus-wide (BY-SA) — no per-document override"
    end
  end

  # -- store: idempotent load + the silver tier end to end ---------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 58, db[:passages].count, "55 Euantius + 2 Macrobius (trim) + 1 Decretum"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 58, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # THE TIER PIN: digilibLT registers `lemma_tier: silver` — its lemma rows
  # land as tier "silver" and never count as gold anywhere.
  def test_lemma_rows_index_as_silver_tier
    db, fulltext = indexed_store
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count, "the fixture carries lemmatized tokens"
    assert_equal ["silver"], rows.select_map(:tier).uniq, "every digilibLT lemma row is silver"
    assert_equal ["lat"], rows.select_map(:language).uniq
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  def test_lemma_search_labels_silver_hits
    db, fulltext = indexed_store
    search = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext)
    results = search.run("tragoedia")
    assert_includes results.map(&:urn), "#{EUANTIUS_URN}:1",
                    "the UDPipe lemma layer answers dictionary search"
    assert_equal ["silver"], results.map(&:tier).uniq, "every hit is labeled silver"
    assert_empty search.run("tragoedia", gold_only: true), "--gold-only excludes the machine layer"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch: sparse git cone + extraction-on-fetch (local git, no network) ----

  def test_fetch_clones_the_conllu_cone_and_extracts_the_archives
    Dir.mktmpdir("nabu-digiliblt-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      digiliblt = adapter
      digiliblt.define_singleton_method(:repo_url) { upstream }
      report = digiliblt.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "conllu", "part1.tar.gz")),
             "the archive cone materializes"
      assert File.file?(File.join(work, "texts", "part1", "dlt000173.xml_linked.conllu")),
             "fetch EXTRACTS the archives into texts/ (extraction-on-fetch, the ZipFetch pattern)"
      refute File.exist?(File.join(work, "ttl")),
             "outside-cone paths (the ~230 MB LiLa TTL lane) must not materialize"
      assert_equal [EUANTIUS_URN, DECRETUM_URN], digiliblt.discover(work).to_a.map(&:id),
                   "the fetched-and-extracted tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "digiliblt", name: "digilibLT", adapter_class: "Nabu::Adapters::Digiliblt",
      license_class: "attribution"
    )
  end

  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                  lemma_tiers: { "digiliblt" => "silver" })
    [db, fulltext]
  end

  # A local upstream repo shaped like CIRCSE/digilibLT: conllu/part*.tar.gz
  # (tarred from the fixture's extracted texts) + README.md in the cone, and
  # a ttl/ tree as outside-cone ballast.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "conllu"))
    %w[part1 part4].each do |part|
      Nabu::Shell.run("tar", "-czf", File.join(upstream, "conllu", "#{part}.tar.gz"),
                      "-C", File.join(workdir, "texts"), part)
    end
    File.write(File.join(upstream, "README.md"), "repo readme (in the cone)")
    FileUtils.mkdir_p(File.join(upstream, "ttl"))
    File.write(File.join(upstream, "ttl", "digilibLTCorpus.ttl"), "outside the cone")
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
