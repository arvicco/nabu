# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TlaHf adapter tests (P28-2): the TLA's official Hugging Face datasets —
# tla-demotic-v18-premium (13,383 sentences; the only bulk demotic artifact
# anywhere) and tla-late_egyptian-v19-premium (3,606 sentences, with
# hieroglyphs), CC BY-SA 4.0, ONE source with two dataset rows (the
# starling-BASES configuration verdict). The fixtures pin the line-number
# identity (upstream ships no sentence ids), the aligned four-way token
# split (`lemmaID|lemma` pairs — the TLA lemma space), the NFC boundary
# (h + U+0331 precomposes to ẖ U+1E96), the `<g>JSesh</g>` hieroglyph
# fallbacks, the -de German siblings, the gold lemma flow into
# passage_lemmas, and the idempotent double-load. No network: fetch runs
# against WebMock stubs of the two real resolve URLs.
class TlaHfTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("tla-hf")

  DEMOTIC_URL =
    "https://huggingface.co/datasets/thesaurus-linguae-aegyptiae/" \
    "tla-demotic-v18-premium/resolve/main/train.jsonl"
  LATE_URL =
    "https://huggingface.co/datasets/thesaurus-linguae-aegyptiae/" \
    "tla-late_egyptian-v19-premium/resolve/main/train.jsonl"

  DEMOTIC_URN = "urn:nabu:tla-hf:demotic-v18"
  LATE_URN = "urn:nabu:tla-hf:late-egyptian-v19"
  ORIGINAL_URNS = [DEMOTIC_URN, LATE_URN].freeze
  ALL_URNS = [DEMOTIC_URN, "#{DEMOTIC_URN}-de", LATE_URN, "#{LATE_URN}-de"].freeze

  def conformance_adapter
    Nabu::Adapters::TlaHf.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "tla-hf"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_tla_hf_source
    manifest = Nabu::Adapters::TlaHf.manifest
    assert_equal "tla-hf", manifest.id
    assert_match(/CC BY-SA 4\.0/, manifest.license, "the dataset cards' grant, verbatim")
    assert_match(/for required attribution, see citation recommendations/, manifest.license,
                 "the cards' own attribution rider travels with the grant")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://huggingface.co/thesaurus-linguae-aegyptiae", manifest.upstream_url
    assert_equal "tla-jsonl", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_dataset_plus_de_siblings
    refs = Nabu::Adapters::TlaHf.new(translations: true).discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id), "sorted; -de siblings interleave after their originals"
    assert(refs.all? { |r| r.source_id == "tla-hf" })
  end

  def test_discover_without_translations_yields_originals_only
    refs = Nabu::Adapters::TlaHf.new.discover(FIXTURES).to_a
    assert_equal ORIGINAL_URNS, refs.map(&:id)
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::TlaHf.new(translations: true).discover(dir).to_a
    end
  end

  # --- parse: originals -------------------------------------------------------

  def test_parse_mints_one_passage_per_jsonl_line_numbered_from_one
    document = parse_urn(DEMOTIC_URN)
    assert_equal "egy", document.language
    assert_equal 4, document.size
    assert_equal %w[1 2 3 4], document.map { |p| p.urn.split(":").last },
                 "identity is the record's 1-based line number — upstream ships no sentence ids"
    assert_equal (0..3).to_a, document.map(&:sequence)
  end

  def test_demotic_passage_text_is_the_transliteration_nfc
    passage = parse_urn(DEMOTIC_URN).first
    assert_equal "mtw =w tm ḫꜣꜥ ḥwṱ sḥm.t n tꜣy =w mt.t", passage.text
    assert passage.text.unicode_normalized?(:nfc)
  end

  def test_non_nfc_upstream_transliteration_is_normalized_at_the_boundary
    passage = parse_urn(DEMOTIC_URN).to_a[2]
    assert_equal "s-n qšwṱ n ẖr", passage.text,
                 "upstream ships h + U+0331 (decomposed); NFC precomposes to ẖ U+1E96"
    assert passage.text.unicode_normalized?(:nfc)
  end

  def test_tokens_carry_the_four_way_aligned_split_with_tla_lemma_ids
    tokens = parse_urn(DEMOTIC_URN).first.annotations.fetch("tokens")
    assert_equal 10, tokens.length
    assert_equal(
      { "form" => "mtw", "lemma_id" => "d2779", "lemma" => "mtw",
        "upos" => "X", "gloss" => "(undefined)" },
      tokens.first,
      "lemmatization pairs split as <TLA lemma ID>|<lemma transliteration>"
    )
    assert_equal "d5458", tokens[5]["lemma_id"]
    assert_equal "sḥm.t", tokens[5]["lemma"]
  end

  def test_late_egyptian_lemma_ids_are_bare_numbers_in_the_same_space
    tokens = parse_urn(LATE_URN).first.annotations.fetch("tokens")
    assert_equal 19, tokens.length
    assert_equal "851513", tokens.first["lemma_id"],
                 "the hieroglyphic-corpus lemma list uses bare numeric TLA ids"
    assert_equal "ꞽw", tokens.first["lemma"]
  end

  def test_late_egyptian_passages_carry_hieroglyphs_verbatim
    passage = parse_urn(LATE_URN).first
    hieroglyphs = passage.annotations.fetch("hieroglyphs")
    assert hieroglyphs.start_with?("𓇋𓅱 𓅯𓄿"), "the Unicode hieroglyph layer rides in annotations"
    assert_includes hieroglyphs, "<g>Ff101</g>",
                    "not-yet-in-Unicode glyphs ride as JSesh codes in <g>…</g>, verbatim"
  end

  def test_demotic_passages_carry_the_authors_credit_and_late_has_none
    demotic = parse_urn(DEMOTIC_URN).first
    assert_equal "Günter Vittmann;AV Altägyptisches Wörterbuch, AV Wortschatz der ägyptischen Sprache",
                 demotic.annotations.fetch("authors")
    late = parse_urn(LATE_URN).first
    refute late.annotations.key?("authors"), "the late-Egyptian dataset ships no authors field"
    refute demotic.annotations.key?("hieroglyphs"), "the demotic dataset ships no hieroglyphs field"
  end

  def test_document_metadata_carries_the_stage_facet_and_dataset_identity
    document = parse_urn(DEMOTIC_URN)
    assert_equal({ "value" => "demotic", "raw" => "Demotic" },
                 document.metadata.dig("facets", "stage"),
                 "stage rides as a facet, never an invented language subtag (damaskini Norm precedent)")
    assert_equal "tla-demotic-v18-premium", document.metadata["dataset"]
    assert_equal "v18", document.metadata["corpus_version"]

    late = parse_urn(LATE_URN)
    assert_equal({ "value" => "late-egyptian", "raw" => "Late Egyptian" },
                 late.metadata.dig("facets", "stage"))
    assert_equal "v19", late.metadata["corpus_version"]
  end

  # --- parse: -de siblings ----------------------------------------------------

  def test_de_sibling_mints_one_german_passage_per_sentence
    document = parse_urn("#{DEMOTIC_URN}-de")
    assert_equal "deu", document.language
    assert_equal 4, document.size
    first = document.first
    assert_equal "#{DEMOTIC_URN}-de:1", first.urn
    assert_equal "\"so daß kein Mann und keine Frau in ihrer Mitte übriggelassen werden.\"",
                 first.text
  end

  def test_de_citations_align_with_the_original_for_parallel
    original = parse_urn(LATE_URN)
    translation = parse_urn("#{LATE_URN}-de")
    assert_equal original.map { |p| p.urn.split(":").last },
                 translation.map { |p| p.urn.split(":").last },
                 "suffix-for-suffix alignment — the Query::Parallel contract"
  end

  # --- parse: damage is loud --------------------------------------------------

  def test_malformed_json_line_raises_parse_error
    with_broken_dataset("not json\n") do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/line 1/, error.message)
    end
  end

  def test_misaligned_token_fields_raise_parse_error
    record = { "transliteration" => "a b", "lemmatization" => "1|a", "UPOS" => "X X",
               "glossing" => "V V", "translation" => "t",
               "dateNotBefore" => "", "dateNotAfter" => "" }
    with_broken_dataset("#{JSON.generate(record)}\n") do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/misaligned/, error.message,
                   "censused 0 misalignments upstream — a mismatch is damage, never a shrug")
    end
  end

  def test_malformed_lemma_pair_raises_parse_error
    record = { "transliteration" => "a", "lemmatization" => "no-id-here", "UPOS" => "X",
               "glossing" => "V", "translation" => "t",
               "dateNotBefore" => "", "dateNotAfter" => "" }
    with_broken_dataset("#{JSON.generate(record)}\n") do |adapter, ref|
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_both_datasets_via_file_fetch
    stub_datasets
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::TlaHf.new(translations: true)
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/demotic-v18/, report.notes)
      assert_equal ALL_URNS, adapter.discover(workdir).map(&:id),
                   "both files land in place and discover sees the datasets"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, DEMOTIC_URL).to_return(status: 500)
    stub_request(:get, LATE_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::TlaHf.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_heads_both_resolve_urls
    assert_equal :http_zip, Nabu::Adapters::TlaHf.remote_probe_strategy
    targets = Nabu::Adapters::TlaHf.http_probe_targets
    assert_equal [DEMOTIC_URL, LATE_URL], targets.map(&:zip_url)
    assert_equal %w[demotic-v18 late-egyptian-v19], targets.map(&:state_subdir)
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives on the dataset cards, no probe-shaped endpoint")
  end

  # --- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = create_source
    adapter = Nabu::Adapters::TlaHf.new(translations: true)
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 14, catalog[:passages].count, "(4 + 3) originals + (4 + 3) -de siblings"

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 4, catalog[:documents].count
    assert_equal 14, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # --- the gold lemma flow ----------------------------------------------------

  def test_gold_lemmas_reach_the_passage_lemmas_index
    catalog = store_test_db
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Loader.new(db: catalog, source: create_source)
                       .load_from(Nabu::Adapters::TlaHf.new(translations: true),
                                  workdir: FIXTURES, full: true)
    Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

    rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE].where(lemma_raw: "sḥm.t").all
    assert_equal 1, rows.size, "the gold lemma sḥm.t (woman) is indexed"
    assert_equal "sḥm.t", rows[0][:surface_forms], "attested by the pristine surface form"
    assert_equal "gold", rows[0][:tier], "expert-generated lemmatization — the gold default"
    assert_equal "egy", rows[0][:language]
    assert rows[0][:urn].end_with?(":1")
  ensure
    fulltext&.disconnect
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_tla_hf_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["tla-hf"]
    refute_nil entry, "tla-hf must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::TlaHf, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
    assert entry.translations, "translation coverage is 100% — -de siblings ride the same parse"
    assert_equal Nabu::Adapters::TlaHf.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::TlaHf.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def create_source
    Nabu::Store::Source.create(slug: "tla-hf", name: "TLA HF datasets",
                               adapter_class: "Nabu::Adapters::TlaHf",
                               license_class: "attribution")
  end

  # A workdir whose demotic file is +content+; yields the adapter and the
  # demotic ref so damage tests exercise the real discover→parse path.
  def with_broken_dataset(content)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "demotic-v18"))
      File.write(File.join(dir, "demotic-v18", "train.jsonl"), content)
      adapter = Nabu::Adapters::TlaHf.new
      ref = adapter.discover(dir).first
      refute_nil ref
      yield adapter, ref
    end
  end

  def stub_datasets
    { DEMOTIC_URL => "demotic-v18", LATE_URL => "late-egyptian-v19" }.each do |url, subdir|
      stub_request(:get, url).to_return(
        status: 200, body: File.binread(File.join(FIXTURES, subdir, "train.jsonl")),
        headers: { "Content-Type" => "application/json",
                   "Last-Modified" => "Sun, 19 Jan 2025 10:47:31 GMT" }
      )
    end
  end
end
