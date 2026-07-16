# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Damaskini adapter tests (P23-1): the Annotated Corpus of Pre-Standardized
# Balkan Slavic Literature 1.1 (CLARIN.SI hdl 11356/1441, CC BY-SA 4.0) —
# 23 gold-annotated damaskini/Balkan Slavic witnesses, 15th–19th c., one
# corpus-wide CoNLL-U file (lemma + msd-bg-dam XPOS + UD deps + text_en)
# plus per-document TSV files whose header block carries the manuscript
# name, place+date, scribe and title. The fixtures pin the newdoc split,
# the corpus-continuous sent numbering → numeric-tail citations, the
# mixed Latin/Cyrillic diplomatic text, the chu/bul language verdicts and
# norm/origin facets (the corpus's own philological classification), the
# -en sibling documents, and the gold lemma flow into passage_lemmas.
# No network: fetch runs against WebMock stubs of the two real bitstreams.
class DamaskiniTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("damaskini")

  CONLLU_ZIP_URL =
    "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1441/Damaskini.CoNNL-U.zip"
  TSV_ZIP_URL =
    "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1441/Damaskini.TSV.zip"

  ORIGINAL_URNS = %w[
    urn:nabu:damaskini:berlinski--slovo-petki
    urn:nabu:damaskini:nedelnik1806--skazanie-paraskevy
    urn:nabu:damaskini:veles--trojanskata
  ].freeze

  ALL_URNS = (ORIGINAL_URNS + ORIGINAL_URNS.map { |u| "#{u}-en" }).sort.freeze

  def conformance_adapter
    Nabu::Adapters::Damaskini.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "damaskini"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_damaskini_source
    manifest = Nabu::Adapters::Damaskini.manifest
    assert_equal "damaskini", manifest.id
    assert_match(/Creative Commons - Attribution-ShareAlike 4\.0 International \(CC BY-SA 4\.0\)/,
                 manifest.license, "the deposit-record grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal CONLLU_ZIP_URL, manifest.upstream_url
    assert_equal "conllu", manifest.parser_family
  end

  # --- the language / classification map (frozen against upstream v1.1) --------

  def test_the_docs_map_classifies_all_23_upstream_newdocs
    docs = Nabu::Adapters::Damaskini::DOCS
    assert_equal 23, docs.size
    assert_equal 3, docs.values.count { |d| d[:language] == "chu" },
                 "Church Slavonic norm: veles, vukovic, kievski (philological description)"
    assert_equal(20, docs.values.count { |d| d[:language] == "bul" })
    assert(docs.values.all? { |d| d[:norm] }, "every witness carries the corpus's own Norm class")
    assert_nil docs.fetch("nbkm370--predislovie")[:origin],
               "NBKM 370 is absent from the description's Origin lists — honest absence"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_newdoc_plus_en_siblings
    refs = Nabu::Adapters::Damaskini.new(translations: true).discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id), "sorted; -en siblings interleave after their originals"
    assert(refs.all? { |r| r.source_id == "damaskini" })
  end

  def test_discover_without_translations_yields_originals_only
    refs = Nabu::Adapters::Damaskini.new.discover(FIXTURES).to_a
    assert_equal ORIGINAL_URNS, refs.map(&:id)
  end

  def test_discover_reads_language_and_tsv_header_metadata
    by_id = Nabu::Adapters::Damaskini.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata] }

    berlinski = by_id.fetch("urn:nabu:damaskini:berlinski--slovo-petki")
    assert_equal "bul", berlinski["language"]
    assert_equal "Slóvo styę prpdbnïę mtre nášīę Pét'kĭ — Berlinski damaskin, 1791",
                 berlinski["title"]

    veles = by_id.fetch("urn:nabu:damaskini:veles--trojanskata")
    assert_equal "chu", veles["language"],
                 "the corpus's own Norm classification: Church Slavonic witness"
    assert_equal "Razkaz za Trojanskata voina - Slovo větxago Aleѯandra — " \
                 "Veleško sborniče (NBKM 667), XV c.", veles["title"]
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::Damaskini.new(translations: true).discover(dir).to_a
    end
  end

  # --- parse: originals ---------------------------------------------------------

  def test_parse_splits_the_corpus_file_at_newdoc_boundaries
    document = parse_urn("urn:nabu:damaskini:berlinski--slovo-petki")
    assert_equal "bul", document.language
    assert_equal 12, document.size
    assert_equal (1..12).map(&:to_s), document.map { |p| p.urn.split(":").last },
                 "citation = the numeric tail of upstream's sent_id (doc id already in the urn)"
  end

  def test_corpus_continuous_sent_numbers_are_kept_verbatim
    document = parse_urn("urn:nabu:damaskini:veles--trojanskata")
    assert_equal "5601", document.first.urn.split(":").last,
                 "upstream numbers sentences corpus-continuously; veles starts at 5601 — " \
                 "the number is upstream's own, never re-minted"
    assert_equal 12, document.size
  end

  def test_known_snippet_carries_real_cyrillic_bytes_nfc
    document = parse_urn("urn:nabu:damaskini:veles--trojanskata")
    passage = document.find { |p| p.urn.end_with?(":5603") }
    assert_equal "bis grad věkъ źělo vъ anaѳoliskoi zemli na msě skamanъdre", passage.text,
                 "the diplomatic layer verbatim: Latin base + real Cyrillic ъ (U+044A), ѳ (U+0473)"
    assert_includes passage.text, "ъ"
    assert_includes passage.text, "ѳ"
    assert passage.text.unicode_normalized?(:nfc)
  end

  def test_gold_tokens_ride_in_annotations
    first = parse_urn("urn:nabu:damaskini:berlinski--slovo-petki").first
    assert_equal "slnce to kolkoto ima světъ", first.text
    tokens = first.annotations.fetch("tokens")
    assert_equal 5, tokens.length
    assert_equal(
      { "id" => "1", "form" => "slnce", "lemma" => "slъnce", "upos" => "NOUN",
        "xpos" => "Nnsnn", "head" => "4", "deprel" => "obj" },
      tokens.first,
      "gold lemma + msd-bg-dam XPOS + UD dependency, FEATS/MISC honestly absent (`_` upstream)"
    )
  end

  def test_document_metadata_carries_the_tsv_header_and_facets
    document = parse_urn("urn:nabu:damaskini:berlinski--slovo-petki")
    assert_equal "Berlinski damaskin", document.metadata["source_name"]
    assert_equal "Pleven?", document.metadata["place"], "upstream's question mark kept verbatim"
    assert_equal "1791", document.metadata["date"]
    assert_equal "pop Georgi", document.metadata["scribe"]
    assert_equal({ "value" => "simple-bulgarian", "raw" => "simple Bulgarian" },
                 document.metadata.dig("facets", "norm"))
    assert_equal({ "value" => "east-bulgaria", "raw" => "East Bulgaria" },
                 document.metadata.dig("facets", "origin"))
  end

  def test_a_scribeless_century_dated_witness_parses_honestly
    document = parse_urn("urn:nabu:damaskini:veles--trojanskata")
    assert_nil document.metadata["scribe"], "veles names no scribe — honest absence"
    assert_nil document.metadata["place"]
    assert_equal "XV c.", document.metadata["date"]
    assert_equal({ "value" => "church-slavonic", "raw" => "Church Slavonic" },
                 document.metadata.dig("facets", "norm"))
    assert_equal({ "value" => "macedonia", "raw" => "Macedonia" },
                 document.metadata.dig("facets", "origin"))
  end

  # --- parse: -en siblings ------------------------------------------------------

  def test_en_sibling_mints_one_english_passage_per_sentence
    document = parse_urn("urn:nabu:damaskini:berlinski--slovo-petki-en")
    assert_equal "eng", document.language
    assert_equal 12, document.size
    first = document.first
    assert_equal "urn:nabu:damaskini:berlinski--slovo-petki-en:1", first.urn
    assert_equal "as (the) world has the sun", first.text
    assert_equal "Slóvo styę prpdbnïę mtre nášīę Pét'kĭ — Berlinski damaskin, 1791 — " \
                 "English translation", document.title
  end

  def test_en_citations_align_with_the_original_for_parallel
    original = parse_urn("urn:nabu:damaskini:veles--trojanskata")
    translation = parse_urn("urn:nabu:damaskini:veles--trojanskata-en")
    assert_equal original.map { |p| p.urn.split(":").last },
                 translation.map { |p| p.urn.split(":").last },
                 "suffix-for-suffix alignment — the Query::Parallel contract"
  end

  # --- parse: damage is loud -----------------------------------------------------

  def test_unclassified_newdoc_id_raises_parse_error
    ref = Nabu::DocumentRef.new(
      source_id: "damaskini", id: "urn:nabu:damaskini:unknown--doc",
      path: File.join(FIXTURES, "conllu", "damaskini.conllu"),
      metadata: { "newdoc" => "unknown--doc" }
    )
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::Damaskini.new.parse(ref) }
    assert_match(/unknown--doc/, error.message)
  end

  def test_missing_tsv_sibling_raises_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "conllu"))
      FileUtils.cp(File.join(FIXTURES, "conllu", "damaskini.conllu"), File.join(dir, "conllu"))
      adapter = Nabu::Adapters::Damaskini.new
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/TSV/, error.message,
                   "a missing TSV sibling is damage (silent metadata loss), never a shrug")
    end
  end

  # --- the gold lemma flow -------------------------------------------------------

  def test_gold_lemmas_reach_the_passage_lemmas_index
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    source = Nabu::Store::Source.create(slug: "damaskini", name: "Damaskini",
                                        adapter_class: "Nabu::Adapters::Damaskini",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(Nabu::Adapters::Damaskini.new(translations: true),
                                  workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_raw: "slъnce").all
    assert_equal 1, rows.size, "the gold lemma slъnce (sun) is indexed"
    assert_equal "slnce", rows[0][:surface_forms], "attested by the pristine diplomatic surface"
    assert rows[0][:urn].end_with?(":1")
  ensure
    fulltext&.disconnect
  end

  # --- the TSV header reader (all shapes the 23 real headers take) ---------------

  def test_header_parses_decades_ranges_centuries_and_post_dates
    reader = Nabu::Adapters::Damaskini::TsvHeader
    assert_equal [1791, 1791], reader.parse_date("1791")
    assert_equal [1580, 1589], reader.parse_date("1580s")
    assert_equal [1650, 1679], reader.parse_date("1650-1670s")
    assert_equal [1601, 1700], reader.parse_date("17th")
    assert_equal [1401, 1500], reader.parse_date("XV c.")
    assert_equal [1817, 1900], reader.parse_date("19th (post 1817)")
    assert_nil reader.parse_date("Evangelie poučitelno")
  end

  def test_header_of_the_century_dated_two_locus_witness
    header = Nabu::Adapters::Damaskini::TsvHeader.read(
      File.join(FIXTURES, "tsv", "veles--trojanskata.txt")
    )
    assert_equal "Veleško sborniče (NBKM 667)", header.source_name
    assert_nil header.place
    assert_equal [1401, 1500], [header.not_before, header.not_after]
    assert_nil header.scribe
    assert_equal "S2: l. 109r-112v, Conev II 1923:180-181 · S1: Močuľskij 1899:377-380",
                 header.notes, "edition/locus lines survive as notes, raw"
  end

  # --- fetch (WebMock only, no network) -------------------------------------------

  def test_fetch_downloads_and_unpacks_both_zips
    stub_zips
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::Damaskini.new(translations: true)
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal [CONLLU_ZIP_URL, TSV_ZIP_URL], report.repos.keys.sort
      assert_equal ALL_URNS, adapter.discover(workdir).map(&:id),
                   "both trees unpack in place and discover sees the corpus"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, CONLLU_ZIP_URL).to_return(status: 500)
    stub_request(:get, TSV_ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Damaskini.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------------

  def test_probe_heads_both_bitstreams
    assert_equal :http_zip, Nabu::Adapters::Damaskini.remote_probe_strategy
    targets = Nabu::Adapters::Damaskini.http_probe_targets
    assert_equal [CONLLU_ZIP_URL, TSV_ZIP_URL], targets.map(&:zip_url)
    assert_equal %w[conllu tsv], targets.map(&:state_subdir)
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives on the record page, no probe-shaped endpoint")
  end

  # --- registry round-trip -------------------------------------------------------------

  def test_registry_resolves_damaskini_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["damaskini"]
    refute_nil entry, "damaskini must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Damaskini, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-16: synced 46 docs, eyeballed, flipped)"
    assert entry.translations, "text_en coverage is 100% — -en siblings ride the same parse"
    assert_equal Nabu::Adapters::Damaskini.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::Damaskini.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  # Zip the checked-in fixture trees under the upstream zips' own top-level
  # dirs (Damaskini.CoNNL-U/ and Damaskini.TSV/ — the upstream filename typo
  # is real) and stub both bitstream URLs.
  def stub_zips
    Dir.mktmpdir do |dir|
      { "Damaskini.CoNNL-U" => File.join(FIXTURES, "conllu"),
        "Damaskini.TSV" => File.join(FIXTURES, "tsv") }.each do |top, tree|
        staging = File.join(dir, top)
        FileUtils.mkdir_p(staging)
        FileUtils.cp_r(Dir.glob(File.join(tree, "*")), staging)
        zip_path = File.join(dir, "#{top}.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, top, chdir: dir)
      end
      stub_request(:get, CONLLU_ZIP_URL).to_return(zip_response(File.join(dir, "Damaskini.CoNNL-U.zip")))
      stub_request(:get, TSV_ZIP_URL).to_return(zip_response(File.join(dir, "Damaskini.TSV.zip")))
    end
  end

  def zip_response(path)
    { status: 200, body: File.binread(path),
      headers: { "Content-Type" => "application/zip",
                 "Last-Modified" => "Fri, 02 Jul 2021 13:21:21 GMT" } }
  end
end
