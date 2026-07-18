# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::Diorisis (P26-4): the Diorisis Ancient Greek Corpus —
# figshare v1 (2018), one frozen 194,443,428-byte zip (md5
# f3a26efa7e7d2b93d1bcca26900d180a, verified against figshare's published
# metadata at fixture time), 820 XML files / ~10.2M tokenized, lemmatized,
# morphologically analyzed words. THE FIRST SILVER SOURCE: upstream's own
# in-file words are "corpus conversion and automatic annotation" (TreeTagger
# flags, 1/n confidence fractions), so sources.yml declares
# `lemma_tier: silver` and every count downstream renders labeled, never as
# gold attestation.
#
# THE RAHLFS EXCLUSION (02-sources row 44): 53 of the 820 files are the
# Septuagint (tlgAuthor 0527, sourceDesc "Bibliotheca Augustana" — the
# Rahlfs-lineage text the CATSS encumbrance covers; scout text-diffed them
# divergent from our held Swete tlg0527). Excluded BY THE MACHINE-READABLE
# HEADER FIELD — discover skips tlgAuthor 0527 by rule (censused in
# discovery_skips) and parse refuses it belt-and-braces, because a rights
# exclusion deserves both layers.
#
# SECOND-EDITION STANCE: 806 of 809 works are texts the catalog already holds
# (742 Perseus, 102 First1K). Diorisis documents mint as their OWN source's
# documents — provenance-distinct second editions (the MW-beside-kaikki
# precedent); the VALUE is the lemma layer feeding silver counts at scale.
class DiorisisTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  HYMN_URN = "urn:nabu:diorisis:0013:013"
  THUC_URN = "urn:nabu:diorisis:0003:001"
  LXX_FILE = "Septuaginta (0527) - Abdias (040).xml"

  def conformance_adapter
    Nabu::Adapters::Diorisis.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("diorisis")
  end

  def conformance_expected_source_id
    "diorisis"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- manifest / probe -------------------------------------------------------

  def test_manifest_quotes_both_licenses_and_the_in_file_one_governs
    license = Nabu::Adapters::Diorisis.manifest.license
    assert_match(/Attribution-ShareAlike 3\.0 United States/, license,
                 "the in-file declaration (all 820 files) governs")
    assert_match(/CC BY 4\.0/, license, "the figshare page claim is quoted beside it, subordinate")
    assert_equal "attribution", Nabu::Adapters::Diorisis.manifest.license_class
  end

  def test_probe_is_http_zip_against_the_figshare_artifact
    assert_equal :http_zip, Nabu::Adapters::Diorisis.remote_probe_strategy
    targets = Nabu::Adapters::Diorisis.http_probe_targets
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Diorisis::ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "the license lives inside the artifact's files"
  end

  # -- discover + the Rahlfs exclusion ---------------------------------------

  def test_discover_yields_the_non_lxx_files_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [THUC_URN, HYMN_URN], refs.map(&:id),
                 "urn:nabu:diorisis:<tlgAuthor>:<tlgId>, sorted; the LXX file yields no ref"
  end

  def test_the_lxx_files_are_excluded_by_the_machine_readable_header_field
    refs = adapter.discover(workdir).to_a
    assert refs.none? { |ref| ref.path.end_with?(LXX_FILE) },
           "tlgAuthor 0527 (Septuaginta, Rahlfs lineage — 02-sources row 44) is excluded by rule"
    skips = adapter.discovery_skips(workdir)
    assert_equal 1, skips.skipped_by_rule,
                 "the exclusion is censused: 1 fixture file (53 upstream) skipped by rule"
    assert_equal 0, skips.unrecognized
  end

  def test_parse_refuses_an_lxx_ref_belt_and_braces
    ref = Nabu::DocumentRef.new(
      source_id: "diorisis", id: "urn:nabu:diorisis:0527:040",
      path: File.join(workdir, LXX_FILE),
      metadata: { "tlg_author" => "0527", "tlg_id" => "040" }
    )
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/0527/, error.message)
    assert_match(/Rahlfs/, error.message, "the refusal names the lineage, not just a number")
  end

  # -- parse ------------------------------------------------------------------

  def test_parses_the_hymn_with_header_metadata_riding_the_document
    document = adapter.parse(ref_for(HYMN_URN))
    assert_equal "grc", document.language
    assert_equal "Hymns — Hymn 13 To Demeter", document.title
    assert_equal 3, document.count
    metadata = document.metadata
    assert_equal "0013", metadata.fetch("tlg_author")
    assert_equal "013", metadata.fetch("tlg_id")
    assert_equal "Religion", metadata.fetch("genre")
    assert_equal "Hymns", metadata.fetch("subgenre")
    assert_equal "-650", metadata.fetch("creation_date")
    assert_equal "Perseus", metadata.fetch("provenance"),
                 "the per-file sourceDesc provenance (Perseus 752 / Bibliotheca Augustana 60 / " \
                 "Mikros Apoplous 8) rides the document"
    assert_match(%r{github\.com/PerseusDL}, metadata.fetch("provenance_url"))
  end

  def test_parses_thucydides_with_dotted_citations
    document = adapter.parse(ref_for(THUC_URN))
    assert_equal "Thucydides — History", document.title
    assert_equal ["#{THUC_URN}:1", "#{THUC_URN}:2", "#{THUC_URN}:3"], document.map(&:urn)
    assert_equal "1.1.1", document.first.annotations["location"]
    assert document.first.text.start_with?("Θουκυδίδης"),
           "Beta Code decodes at the boundary (got: #{document.first.text[0, 40].inspect})"
  end

  # -- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 6, db[:passages].count, "3 hymn + 3 thucydides sentences"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped, "a byte-identical reload skips every document"
    assert_equal 6, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  # -- the silver tier, end to end on real fixtures ---------------------------

  # THE TIER PIN: Diorisis is registered `lemma_tier: silver` — its rows land
  # in passage_lemmas as tier "silver" and NEVER count as gold anywhere.
  def test_lemma_rows_index_as_silver_tier
    db, fulltext = indexed_store
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count, "the fixture carries lemmatized tokens"
    assert_equal ["silver"], rows.select_map(:tier).uniq,
                 "every Diorisis lemma row carries the silver tier"
    assert_equal ["grc"], rows.select_map(:language).uniq
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # search --lemma over a silver-only index: hits come back LABELED (tier
  # "silver" on every result) and --gold-only excludes them entirely — the
  # never-a-bare-number rule at the search surface, on real corpus bytes.
  def test_lemma_search_labels_silver_hits_and_gold_only_excludes_them
    db, fulltext = indexed_store
    search = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext)
    results = search.run("θεά")
    assert_equal ["#{HYMN_URN}:1", "#{HYMN_URN}:2"], results.map(&:urn),
                 "the automatic lemma layer answers dictionary-form search"
    assert_equal %w[silver silver], results.map(&:tier), "every hit is labeled silver"
    assert_equal %w[θεάν θεά], results.map(&:surface_forms),
                 "surface forms are the decoded pristine inflections"

    assert_empty search.run("θεά", gold_only: true),
                 "--gold-only excludes the automatic layer wholesale"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # ReflexViews on a silver-only attestation: attested_count (the GOLD claim)
  # stays nil — honest absence — while silver_count carries the labeled
  # number. A Diorisis row can never masquerade as verified attestation.
  def test_reflex_views_resolve_silver_counts_beside_a_nil_gold_count
    db, fulltext = indexed_store
    entry_id = seed_reflex_entry(db, [%w[θεά grc]])
    views = Nabu::Query::ReflexViews.new(catalog: db, fulltext: fulltext).for_entry(entry_id)
    thea = views.find { |v| v.word == "θεά" } || flunk("θεά view missing")
    assert_nil thea.attested_count, "no gold rows exist — the gold count must stay nil, never 2"
    assert_equal 2, thea.silver_count, "the silver count carries the Diorisis attestations, labeled"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (WebMock only, no network) ---------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      Dir.glob(File.join(workdir, "*.xml")).each { |xml| FileUtils.cp(xml, dir) }
      zip = File.join(dir, "corpus.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", zip, *Dir.children(dir).grep(/\.xml\z/)) }
      File.binread(zip)
    end
  end

  def stub_figshare(body)
    stub_request(:get, Nabu::Adapters::Diorisis::ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Wed, 02 May 2018 18:27:12 GMT" })
  end

  def test_fetch_pins_the_zip_sha_and_unpacks_the_corpus
    body = zip_body
    stub_figshare(body)
    Dir.mktmpdir do |work|
      report = Nabu::Adapters::Diorisis.new(pin: Digest::SHA256.hexdigest(body)).fetch(work)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.file?(File.join(work, LXX_FILE)),
             "the LXX files land in canonical (the artifact is kept whole) — the exclusion " \
             "is a discovery rule, not a fetch mutilation"
      assert_equal 2, adapter.discover(work).to_a.size
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_pin
    body = zip_body
    stub_figshare(body)
    Dir.mktmpdir do |work|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(work) }
      assert_match(/sha256/, error.message)
      assert_match(/#{Nabu::Adapters::Diorisis::ZIP_SHA256[0, 12]}/, error.message)
      refute File.exist?(File.join(work, LXX_FILE)), "a refused fetch leaves the tree untouched"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, Nabu::Adapters::Diorisis::ZIP_URL).to_return(status: 503)
    Dir.mktmpdir do |work|
      assert_raises(Nabu::FetchError) { adapter.fetch(work) }
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "diorisis", name: "Diorisis", adapter_class: "Nabu::Adapters::Diorisis",
      license_class: "attribution"
    )
  end

  # Load the fixture and index it EXACTLY as sync/rebuild do for a source the
  # registry declares silver: lemma_tiers { "diorisis" => "silver" } threads
  # into Indexer.rebuild! (the P26-0 wire format).
  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                  lemma_tiers: { "diorisis" => "silver" })
    [db, fulltext]
  end

  def seed_reflex_entry(db, words)
    recon = Nabu::Store::Source.create(
      slug: "recon", name: "Recon", adapter_class: "TestAdapter", license_class: "attribution"
    )
    dictionary = Nabu::Store::Dictionary.create(
      source_id: recon.id, slug: "recon-piet", title: "PIE etymology", language: "ine-pro"
    )
    entry = Nabu::Store::DictionaryEntry.create(
      dictionary_id: dictionary.id, urn: "urn:nabu:dict:recon-piet:test", entry_id: "test",
      key_raw: "*test-", headword: "*test-", headword_folded: "test", body: "b",
      content_sha256: "x"
    )
    words.each_with_index do |(word, language), seq|
      db[:dictionary_reflexes].insert(
        dictionary_entry_id: entry.id, seq: seq, lang_code: language, language: language,
        word: word, word_folded: Nabu::Normalize.search_form(word, language: language)
      )
    end
    entry.id
  end
end
