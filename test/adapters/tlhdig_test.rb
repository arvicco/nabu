# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::Tlhdig (P31-1): the Hittite corpus — TLHdig Beta 0.3 as
# one frozen Zenodo deposit (record 20328284; 74,449,198 bytes, md5
# f9acbc8db3111cc7dd88d82f7819a912 verified against the record's own
# checksum at fixture time, sha256-pinned in the adapter), 23,937
# per-manuscript AOxml files in 826 CTH folders. Identity is the folder
# layout (urn:nabu:tlhdig:<cth>:<project>:<manuscript>); the candidate
# morphology is upstream's own hypothesis layer, so sources.yml registers
# lemma_tier: silver and only the disambiguated subset mints lemma keys.
#
# THE SYNERGY SEAM (measured, promised nothing): TLHdig mrp lemmas vs the
# starling-piet HITT reflex rows — 316 rows mint from the full canonical
# piet.dbf (306 distinct folded keys); 205 = 67.0% join the corpus-wide
# disambiguated TLHdig lemma keys (215 = 70.3% against all candidates).
# The fixture slice proves the seam end-to-end below (ḫūmant- lights a
# silver count through ReflexViews).
class TlhdigTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  MERGED_URN = "urn:nabu:tlhdig:626:hfr:kbo.52.195+"
  DAMAGE_URN = "urn:nabu:tlhdig:433:besrit:kbo.43.277"

  ALL_URNS = [
    "urn:nabu:tlhdig:314:tlh:kub.4.8",
    DAMAGE_URN,
    MERGED_URN,
    "urn:nabu:tlhdig:786:hfr:kbo.20.119"
  ].freeze

  CORPUS_DIR = "TLHbasisONLINE25_1_ZENODO_Beta_03"

  def conformance_adapter
    Nabu::Adapters::Tlhdig.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("tlhdig")
  end

  def conformance_expected_source_id
    "tlhdig"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- manifest / probe -------------------------------------------------------

  def test_manifest_carries_the_prescribed_citation_verbatim
    manifest = Nabu::Adapters::Tlhdig.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license,
                    "Thesaurus Linguarum Hethaeorum digitalis, hethiter.net/: " \
                    "TLHdig – Beta Version 0.3 (2025-11-01)"
    assert_includes manifest.license, "cc-by-4.0"
    assert_equal "aoxml", manifest.parser_family
  end

  def test_probe_is_http_zip_against_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Tlhdig.remote_probe_strategy
    targets = Nabu::Adapters::Tlhdig.http_probe_targets
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Tlhdig::ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url, "the Zenodo API body carries volatile stats"
  end

  # -- discover: the folder layout is the catalog -----------------------------

  def test_discover_derives_identity_from_the_cth_folder_layout
    refs = adapter.discover(workdir).to_a
    assert_equal ALL_URNS, refs.map(&:id), "urn:nabu:tlhdig:<cth>:<project>:<manuscript>, sorted"
    merged = refs.find { |ref| ref.id == MERGED_URN }
    assert_equal({ "cth" => "626", "project" => "HFR" }, merged.metadata)
    refute refs.any? { |ref| ref.path.include?("quarantine") },
           "only 'CTH *' folders are corpus shape"
  end

  def test_discover_yields_nothing_from_a_pre_fetch_workdir
    Dir.mktmpdir do |work|
      assert_empty adapter.discover(work).to_a
      assert_equal 0, adapter.discovery_skips(work).skipped_by_rule
    end
  end

  # The upstream reality this rule exists for: CTH 999_XML_TLH files the
  # byte-identical KUB 46.39+.xml in TWO project bins. First path-sorted
  # copy wins, the twin is censused; a NON-identical collision is damage
  # and raises.
  def test_a_byte_identical_urn_twin_skips_by_rule_censused
    Dir.mktmpdir do |work|
      seed_twin(work, second: fixture_bytes("CTH 433_XML_BESRIT/KBo 43.277.xml"))
      refs = adapter.discover(work).to_a
      assert_equal ["urn:nabu:tlhdig:999:tlh:kub.46.39+"], refs.map(&:id)
      assert refs.first.path.end_with?("BESRIT/KUB 46.39+.xml"), "the first path-sorted copy wins"
      skips = adapter.discovery_skips(work)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
    end
  end

  def test_a_diverging_urn_collision_raises_instead_of_hiding_damage
    Dir.mktmpdir do |work|
      seed_twin(work, second: fixture_bytes("CTH 314_XML_TLH/KUB 4.8.xml"))
      error = assert_raises(Nabu::ParseError) { adapter.discover(work).to_a }
      assert_match(/urn collision/, error.message)
      assert_match(/differ/, error.message)
    end
  end

  # A real sync unpacks the corpus directory BESIDE __MACOSX junk; the
  # fixture dir carries CTH folders at its root. Both roots resolve, and
  # the junk sibling is never scanned.
  def test_corpus_root_resolves_the_real_zip_layout_and_ignores_macosx
    Dir.mktmpdir do |work|
      nested = File.join(work, CORPUS_DIR, "CTH 433_XML_BESRIT")
      FileUtils.mkdir_p(nested)
      FileUtils.cp(File.join(workdir, "CTH 433_XML_BESRIT/KBo 43.277.xml"), nested)
      decoy = File.join(work, "__MACOSX", CORPUS_DIR, "CTH 433_XML_BESRIT")
      FileUtils.mkdir_p(decoy)
      File.write(File.join(decoy, "._KBo 43.277.xml"), "AppleDouble junk")
      refs = adapter.discover(work).to_a
      assert_equal [DAMAGE_URN], refs.map(&:id)
      assert_includes refs.first.path, CORPUS_DIR
    end
  end

  # -- parse: quarantine honesty (the Beta reality) ---------------------------

  def test_parse_quarantines_the_malformed_and_line_less_upstream_shapes
    { "KUB 10.7.xml" => "urn:nabu:tlhdig:612:tlh:kub.10.7",
      "304_e.xml" => "urn:nabu:tlhdig:222:tlh:304_e" }.each do |file, urn|
      ref = Nabu::DocumentRef.new(
        source_id: "tlhdig", id: urn,
        path: File.join(workdir, "quarantine", file),
        metadata: { "cth" => "999", "project" => "TLH" }
      )
      assert_raises(Nabu::ParseError, "#{file} must quarantine") { adapter.parse(ref) }
    end
  end

  def test_parses_the_merged_manuscript_with_header_docid_and_facets
    document = adapter.parse(ref_for(MERGED_URN))
    assert_equal "hit", document.language
    assert_equal "KBo 52.195++ (CTH 626)", document.title
    assert_equal 32, document.count
    assert_equal "626", document.metadata.fetch("cth")
    assert_equal({ "value" => "hfr", "raw" => "HFR" }, document.metadata.dig("facets", "project"))
  end

  # -- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 167, db[:passages].count, "12 + 32 + 27 + 96 tablet lines"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 167, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  # -- the silver tier + the starling-piet seam, end to end -------------------

  def test_lemma_rows_index_as_silver_tier_for_the_disambiguated_subset_only
    db, fulltext = indexed_store
    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
    refute_equal 0, rows.count, "the disambiguated subset mints lemma rows"
    assert_equal ["silver"], rows.select_map(:tier).uniq,
                 "every TLHdig lemma row carries the silver tier — never gold"
    refute rows.where(lemma_folded: "tarna").any?,
           "the unresolved multi-candidate tarn=a-/tarn=aḫḫ- word minted nothing"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  def test_lemma_search_answers_the_citation_form_labeled_silver
    db, fulltext = indexed_store
    search = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext)
    results = search.run("ḫūmant")
    assert_equal ["#{MERGED_URN}:17", "#{MERGED_URN}:9"], results.map(&:urn),
                 "both attestations (ḫumantuš ACC.PL + ḫumantaš D/L.PL, each digit-selected) " \
                 "answer the dictionary form — ḫ folds to h, the stem hyphen is off"
    assert_equal ["silver"], results.map(&:tier).uniq, "every hit is labeled"
    assert_empty search.run("ḫūmant", gold_only: true),
                 "--gold-only excludes the automatic layer wholesale"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # The measured seam: a starling-piet HITT reflex row (Hittite and
  # Tokharian reflexes are S. Starostin's own additions to piet) resolves
  # a SILVER count against TLHdig — and the gold count honestly stays nil.
  def test_a_piet_hitt_reflex_lights_a_silver_count_through_reflex_views
    db, fulltext = indexed_store
    entry_id = seed_reflex_entry(db, [["ḫūmant-", "hit"]])
    views = Nabu::Query::ReflexViews.new(catalog: db, fulltext: fulltext).for_entry(entry_id)
    view = views.find { |v| v.word == "ḫūmant-" } || flunk("ḫūmant- view missing")
    assert_nil view.attested_count, "no gold rows exist — the gold claim stays honestly absent"
    assert_equal 2, view.silver_count, "both TLHdig attestations answer, labeled silver"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (WebMock only, no network) ---------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      corpus = File.join(dir, CORPUS_DIR)
      Dir.glob(File.join(workdir, "CTH *")).each do |folder|
        FileUtils.mkdir_p(File.join(corpus, File.basename(folder)))
        FileUtils.cp_r(Dir.glob(File.join(folder, "*")), File.join(corpus, File.basename(folder)))
      end
      FileUtils.mkdir_p(File.join(dir, "__MACOSX", CORPUS_DIR))
      File.write(File.join(dir, "__MACOSX", CORPUS_DIR, "._junk"), "AppleDouble junk")
      zip = File.join(dir, "corpus.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, CORPUS_DIR, "__MACOSX") }
      File.binread(zip)
    end
  end

  def stub_zenodo(body)
    stub_request(:get, Nabu::Adapters::Tlhdig::ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Thu, 21 May 2026 00:00:00 GMT" })
  end

  def test_fetch_pins_the_zip_sha_and_unpacks_the_corpus_beside_the_junk
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |work|
      report = Nabu::Adapters::Tlhdig.new(pin: Digest::SHA256.hexdigest(body)).fetch(work)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.directory?(File.join(work, "__MACOSX")),
             "the artifact lands whole — junk exclusion is a discovery rule, not a fetch mutilation"
      assert_equal ALL_URNS, adapter.discover(work).to_a.map(&:id)
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_pin
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |work|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(work) }
      assert_match(/sha256/, error.message)
      assert_match(/#{Nabu::Adapters::Tlhdig::ZIP_SHA256[0, 12]}/, error.message)
      assert_empty adapter.discover(work).to_a, "a refused fetch leaves the tree untouched"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, Nabu::Adapters::Tlhdig::ZIP_URL).to_return(status: 503)
    Dir.mktmpdir do |work|
      assert_raises(Nabu::FetchError) { adapter.fetch(work) }
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def fixture_bytes(relative)
    File.binread(File.join(workdir, relative))
  end

  def seed_twin(work, second:)
    twin = fixture_bytes("CTH 433_XML_BESRIT/KBo 43.277.xml")
    %w[BESRIT TLH].zip([twin, second]).each do |bin, bytes|
      dir = File.join(work, "CTH 999_XML_TLH", bin)
      FileUtils.mkdir_p(dir)
      File.binwrite(File.join(dir, "KUB 46.39+.xml"), bytes)
    end
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "tlhdig", name: "TLHdig", adapter_class: "Nabu::Adapters::Tlhdig",
      license_class: "attribution"
    )
  end

  # Load the fixtures and index EXACTLY as sync/rebuild do for a source
  # the registry declares silver (the P26-0 wire format).
  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                  lemma_tiers: { "tlhdig" => "silver" })
    [db, fulltext]
  end

  # A dictionary entry with reflex rows folded the starling way (member
  # fold: parens + trailing stem hyphen off before the language fold) —
  # the same word_folded the real piet shelf mints for its HITT column.
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
      folded = Nabu::Normalize.search_form(word.delete("()⁽⁾").sub(/-\z/, ""), language: language)
      db[:dictionary_reflexes].insert(
        dictionary_entry_id: entry.id, seq: seq, lang_code: "HITT", language: language,
        word: word, word_folded: folded
      )
    end
    entry.id
  end
end
